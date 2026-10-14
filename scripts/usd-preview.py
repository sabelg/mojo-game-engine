"""Revisioned, disposable static scene previews for the native USD editor."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]

def atomic(path, text):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(text)
    temporary.replace(path)

class PreviewCooker:
    def __init__(self, work, animated=False):
        self.animated = animated
        self.work = Path(work)
        self.root = self.work/'previews'
        self.root.mkdir()
        self.job = None
        self.log = None
        self.pending = None
        self.serial = 0
        self.revision = -1
        self.last_revision = -1
        self.started = 0

    def publish(self, status, revision, prefix='', message=''):
        message = str(message).replace('\n',' ').replace('\r',' ').replace('\t',' ')[:512]
        atomic(self.work/'preview.tsv', f'{status}\t{revision}\t{prefix}\t{message}\n')

    def cancel(self):
        if self.job is not None:
            # Blender and the cooker are one owned process group.
            try:os.killpg(self.job.pid, signal.SIGTERM)
            except ProcessLookupError:pass
            try:self.job.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(self.job.pid, signal.SIGKILL)
                self.job.wait(timeout=2)
            self.log.close()
            self.job = self.log = None
            shutil.rmtree(self.directory, ignore_errors=True)

    def schedule(self, snapshot):
        revision = snapshot['revision']
        if revision == self.last_revision:return
        self.last_revision = revision
        self.cancel()
        self.pending = (revision, snapshot['start'], time.monotonic()+.2)
        self.publish('PENDING', revision, message='Preparing loaded content at stage start time')

    def tick(self, stage):
        ack = self.work/'preview-ack.txt'
        if ack.exists():
            serial = int(ack.read_text())
            for directory in self.root.iterdir():
                if directory.is_dir() and int(directory.name) < serial:
                    shutil.rmtree(directory)
        if self.job is not None:
            code = self.job.poll()
            if code is None and time.monotonic()-self.started > 180:
                revision = self.revision
                self.cancel()
                self.publish('ERROR', revision, message='Preview exceeded 180 seconds; previous view retained')
            elif code is not None:
                self.log.close()
                self.job = self.log = None
                if code == 0:
                    self.publish('READY', self.revision, str(self.directory/'preview'), str(self.serial))
                else:
                    log = (self.directory/'cook.log').read_text(errors='replace')[-2000:]
                    self.publish('ERROR', self.revision, message=log)
                    shutil.rmtree(self.directory)
        if self.job is None and self.pending and time.monotonic() >= self.pending[2]:
            # Bound unacknowledged publications. The newest revision stays queued.
            if len(list(self.root.iterdir())) >= 4:return
            revision, sample, _ = self.pending
            self.pending = None
            self.serial += 1
            self.directory = self.root/str(self.serial)
            self.directory.mkdir()
            try:
                exported = stage.request('preview', destination=str(self.directory/'sample.usdc'), time=sample, animated=self.animated)
                self.revision = exported['revision']
                self.log = (self.directory/'cook.log').open('w')
                self.job = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--cook', str(self.directory)],
                    stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True,
                    env={**os.environ, 'ATLAS_USD_CACHE_DIR':str(self.directory/'cache')})
                self.started = time.monotonic()
                self.publish('COOKING', self.revision, message='Background preview cook; previous view retained')
            except Exception as error:
                if self.log:self.log.close()
                self.log = None
                shutil.rmtree(self.directory, ignore_errors=True)
                self.publish('ERROR', revision, message=error)

    def close(self):
        self.cancel()
        shutil.rmtree(self.root, ignore_errors=True)
        for name in ('preview.tsv','preview-ack.txt'):
            (self.work/name).unlink(missing_ok=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cook', type=Path, required=True)
    args = parser.parse_args()
    directory = args.cook.resolve()
    inspector=os.environ.get('ATLAS_USD_INSPECT',str(ROOT/'.deps/usd-tools/bin/atlas-usd-inspect'))
    inspected=subprocess.run([inspector,str(directory/'sample.usdc')],check=True,capture_output=True,text=True,timeout=60)
    report=json.loads(inspected.stdout)
    if report['unsupported'] or report['unresolved']:
        raise ValueError('Preview requires supported geometry: '+str(report['unsupported']+report['unresolved']))
    (directory/'preview-timing.atlastiming').write_text('ATLAS_PREVIEW_TIME_1\n'+str((report['end']-report['start'])/report['time_codes_per_second'])+'\n'+str(report['time_codes_per_second'])+'\n')
    source=directory/'sample.usdc'
    if not report['meshes']:
        # Empty loaded stages are valid editor states, not conversion failures.
        source=directory/'empty.gltf'
        source.write_text(json.dumps({'asset':{'version':'2.0'},'scenes':[{'nodes':[]}],'scene':0,'nodes':[]}))
        # Camera/light authoring still has a runtime preview without mesh import.
        def module(name,file):
            spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
            value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
        assets=module('atlas_preview_assets','cook-assets.py');usd=module('atlas_preview_usd','cook-usd.py')
        auxiliary={**usd.camera_assets(report),**usd.camera_track_assets(report),**usd.light_assets(report),
                   **usd.light_track_assets(report),**usd.local_light_assets(report)}
        assets._cook(source,directory,'preview',0,8,0,auxiliary=auxiliary)
        return
    # The flattened copy resolves authored dependencies to their absolute paths.
    # The normal USD dependency/byte/geometry budgets still apply.
    subprocess.run([sys.executable, str(ROOT/'scripts/cook-assets.py'), str(source),
                    '--output', str(directory), '--id', 'preview', '--usd-root', '/'], check=True)

if __name__ == '__main__':main()
