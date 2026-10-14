"""Persistent native USD authoring client and batch command runner.

A session owns a native process. Source documents are never edited in place.
Timeouts terminate the process; reopen the last committed workspace or delivery.
"""
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time
import threading
import queue
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[1]

class StageSession:
    def __init__(self, timeout=60, memory_mib=4096):
        if not 256 <= memory_mib <= 16384:
            raise ValueError("USD process memory limit must be 256..16384 MiB")
        self.lock = threading.Lock()
        binary = Path(os.environ.get('ATLAS_USD_STAGE', ROOT / '.deps/usd-tools/bin/atlas-usd-stage'))
        self.log = tempfile.TemporaryFile(mode='w+b')
        try:
            self.process = subprocess.Popen(['prlimit', f'--as={memory_mib*1024**2}', '--', str(binary)], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=self.log, bufsize=0,
                # OpenUSD otherwise defaults its package scratch files to /var/tmp.
                # Respect the caller's temp policy, including restricted workspaces.
                env={**os.environ, 'PXR_WORK_THREAD_LIMIT': '4',
                     'TMPDIR': os.environ.get('TMPDIR', tempfile.gettempdir())})
        except OSError:
            self.log.close()
            raise
        self.timeout = timeout
        self.pending = bytearray()
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)

    def request(self, op, **fields):
        with self.lock:
            return self._request(op, **fields)

    def _request(self, op, **fields):
        data = (json.dumps(dict(op=op, **fields), allow_nan=False) + '\n').encode()
        if len(data) > 1024 * 1024:
            raise ValueError('USD request exceeds 1 MiB')
        deadline = time.monotonic() + self.timeout
        view = memoryview(data)
        while view:
            written = self.process.stdin.write(view)
            if not written:
                raise RuntimeError("USD stage service closed its input")
            view = view[written:]
        while b'\n' not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not self.selector.select(remaining):
                self.close()
                raise TimeoutError('USD stage operation timed out; reopen the session')
            part = os.read(self.process.stdout.fileno(), 65536)
            if not part:
                raise RuntimeError('USD stage service exited unexpectedly')
            self.pending.extend(part)
            if len(self.pending) > 64 * 1024 * 1024:
                self.close()
                raise ValueError('USD stage response exceeds 64 MiB')
        line, _, rest = self.pending.partition(b'\n')
        self.pending = bytearray(rest)
        result = json.loads(line)
        if not result['ok']:
            raise ValueError(result['error'])
        return result['result']

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.selector.close()
        self.process.stdin.close()
        self.process.stdout.close()
        self.log.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

class WatchedStageSession(StageSession):
    """Reload changed composed layers, preserving session edits.

    Notifications use a bounded queue. Invalid external edits leave the last
    successful snapshot available and emit an error; fixing the file retries.
    Texture/GPU reload is outside this authoring-layer watcher.
    """
    def __init__(self, timeout=60, memory_mib=4096, interval=.25):
        if not .05 <= interval <= 60:
            raise ValueError('USD watch interval must be .05..60 seconds')
        super().__init__(timeout, memory_mib)
        self.events = queue.Queue(maxsize=64)
        self.snapshot = None
        self.files = {}
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._watch, args=(interval,), daemon=True,
                                       name='atlas-usd-watch')
        self.thread.start()

    @staticmethod
    def _signature(path):
        try:
            stat = Path(path).stat()
            return stat.st_mtime_ns, stat.st_size, stat.st_ino
        except OSError:
            return None

    def _event(self, event):
        try:
            self.events.put_nowait(event)
        except queue.Full:
            try:
                self.events.get_nowait()
            except queue.Empty:
                pass
            self.events.put_nowait(event)

    def _request(self, op, **fields):
        result = super()._request(op, **fields)
        if isinstance(result, dict) and 'used_layers' in result:
            self.snapshot = result
            self.files = {path:self._signature(path) for path in result['used_layers'] if path}
            self._event({'operation':op, 'revision':result['revision']})
        return result

    def _watch(self, interval):
        while not self.stop.wait(interval):
            with self.lock:
                current = {path:self._signature(path) for path in self.files}
                if current == self.files:
                    continue
                self.files = current
                try:
                    self._request('reload')
                except Exception as error:
                    if not self.stop.is_set():
                        self._event({'operation':'reload', 'error':str(error)})

    def close(self):
        self.stop.set()
        super().close()
        if threading.current_thread() is not self.thread:
            self.thread.join(timeout=3)

class BackgroundStageSession:
    """Serialized worker operations with a bounded pending queue.

    request() returns a Future immediately. Cancelled queued futures do not reach
    OpenUSD. In-flight operations finish or hit the StageSession timeout.
    """
    def __init__(self, timeout=60, memory_mib=4096, capacity=8):
        if not 1 <= capacity <= 64:
            raise ValueError('USD operation capacity must be 1..64')
        self.stage = StageSession(timeout, memory_mib)
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix='atlas-usd')
        self.pending = threading.BoundedSemaphore(capacity)

    def request(self, op, **fields):
        if not self.pending.acquire(blocking=False):
            raise ValueError('USD background operation queue is full')
        try:
            future = self.executor.submit(self.stage.request, op, **fields)
        except BaseException:
            self.pending.release()
            raise
        future.add_done_callback(lambda _: self.pending.release())
        return future

    def close(self):
        self.executor.shutdown(wait=True, cancel_futures=True)
        self.stage.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='USD source file or durable workspace directory')
    parser.add_argument('--commands', type=Path, help='JSON array of stage operations')
    parser.add_argument('--output', type=Path, help='Write final snapshot JSON')
    args = parser.parse_args()
    commands = []
    if args.commands:
        if args.commands.stat().st_size > 1024 * 1024:
            parser.error('Commands file exceeds 1 MiB')
        commands = json.loads(args.commands.read_text())
        if not isinstance(commands, list) or len(commands) > 1000:
            parser.error('Expected at most 1000 commands')
    with StageSession() as stage:
        stage.request('open_workspace' if args.source.is_dir() else 'open', source=str(args.source.resolve()))
        for command in commands:
            stage.request(**command)
        result = json.dumps(stage.request('snapshot'), indent=2) + '\n'
        if args.output:
            with args.output.open('x') as stream:
                stream.write(result)
        else:
            print(result, end='')

if __name__ == '__main__':
    main()
