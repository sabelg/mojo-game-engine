"""Qualify an independently extracted SDK and generated game; retain phase logs."""
import argparse, hashlib, json, os, shutil, signal, subprocess, tarfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    parser.add_argument('--pixi', default='pixi')
    parser.add_argument('--window', action='store_true')
    args = parser.parse_args()
    output = (args.output or ROOT/'build/atlas-sdk-qualification'/time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())).resolve()
    if output.exists():
        raise SystemExit('Choose a new qualification directory; existing evidence is preserved.')
    env = os.environ.copy()
    env.update(MOJO_VK_SOFTWARE='1', MOJO_VK_VALIDATION='1', VK_LAYER_VALIDATE_SYNC='1', MOJO_VK_FRAMES_IN_FLIGHT='2', SDL_VIDEO_DRIVER='dummy', SDL_AUDIO_DRIVER='dummy')
    if env.get('MOJO_VK_REQUIRE_HARDWARE') not in (None, '0'):
        raise SystemExit('This SDK suite selects lavapipe; use qualify-atlas.py for hardware runs.')
    output.mkdir(parents=True)
    phases = []
    report = {'passed': False, 'phases': phases, 'window_requested': args.window}
    def phase(name, command, cwd, timeout=1800):
        started = time.monotonic()
        with (output/(name+'.log')).open('w') as log:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = 124
        phases.append({'name': name, 'exit_code': code, 'elapsed_seconds': time.monotonic()-started, 'command': command, 'cwd': str(cwd)})
        print(name, 'exit', code, flush=True)
        if code:
            raise RuntimeError('Phase failed: '+name+'; inspect '+str(output/(name+'.log')))
    def pixi(command, manifest):
        return [args.pixi, 'run', '--manifest-path', str(manifest), '--locked', *command]
    try:
        phase('source-check', ['python3', 'scripts/engine-build-state.py', 'check'], ROOT, 60)
        phase('package', ['python3', 'scripts/package-atlas.py'], ROOT, 60)
        archive = output/'mojo-game-source.tar.gz'
        shutil.copy2(ROOT/'build/mojo-game-source.tar.gz', archive)
        sdk = output/'sdk'
        with tarfile.open(archive) as bundle:
            bundle.extractall(sdk, filter='data')
        manifest = json.loads((sdk/'ENGINE-MANIFEST.json').read_text())
        for name, entry in manifest['files'].items():
            assert digest(sdk/name) == entry['sha256'], name
        report.update(source_package_sha256=digest(archive), source_files=len(manifest['files']), root_engine=json.loads((ROOT/'build/atlas-build-state.json').read_text()))
        phase('sdk-build', pixi(['bash', 'scripts/build.sh'], sdk/'pixi.toml'), sdk)
        phase('sdk-suite', pixi(['bash', 'scripts/test.sh'], sdk/'pixi.toml'), sdk)
        phase('sdk-source-check', ['python3', 'scripts/engine-build-state.py', 'check'], sdk, 60)
        report['sdk_engine'] = json.loads((sdk/'build/atlas-build-state.json').read_text())
        assert report['root_engine']['engine_source_sha256'] == report['sdk_engine']['engine_source_sha256']
        if args.window:
            for name, option in [('window', []), ('hdr-window', ['--hdr'])]:
                phase(name, pixi(['bash', 'scripts/test-vulkan-window.sh', *option], sdk/'pixi.toml'), sdk, 120)
        starter = output/'starter'
        phase('starter-create', ['python3', str(sdk/'scripts/new-game.py'), str(starter)], sdk, 60)
        phase('starter-build', pixi(['bash', 'scripts/build.sh'], sdk/'pixi.toml'), starter)
        phase('starter-smoke', [str(starter/'build/game'), '--smoke'], starter, 60)
        report['starter_sha256'] = digest(starter/'build/game')
        report['passed'] = True
    except (OSError, ValueError, AssertionError, RuntimeError) as error:
        report['error'] = str(error)
    finally:
        (output/'summary.json').write_text(json.dumps(report, indent=2)+'\n')
        files = [f for f in output.iterdir() if f.is_file() and f.name != 'SHA256SUMS']
        (output/'SHA256SUMS').write_text(''.join(digest(f)+'  '+f.name+'\n' for f in sorted(files)))
    print('SDK qualification:', output, 'passed:', report['passed'])
    raise SystemExit(0 if report['passed'] else 1)

if __name__ == '__main__':
    main()
