"""Finite G01 qualification; requires an explicitly available exclusive GPU slot.

No installs, root lock updates, toolchain upgrades, driver or H3 changes.
Matching official max-core is isolated under .deps/physics-gpu-g01.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
GPU_ENV = ROOT / '.deps/physics-gpu-g01/.pixi/envs/default'
OUT = ROOT / 'build/physics-g01'
MEMORY_RESERVE_KB = 32 * 1024 * 1024

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def sample():
    memory = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    sensors = {}
    for root in Path('/sys/class/thermal').glob('thermal_zone*'):
        sensors[root.name] = int((root / 'temp').read_text()) / 1000
    gpu = subprocess.check_output(['nvidia-smi', '--query-gpu=temperature.gpu,utilization.gpu', '--format=csv,noheader,nounits'], text=True, timeout=5).strip()
    temperature, utilization = (int(value.strip()) for value in gpu.split(','))
    return {'available_kB': int(memory['MemAvailable'].split()[0]), 'GPU_C': temperature, 'GPU_utilization': utilization, 'sensors_C': sensors}

def stage(name, command, seconds, env, cwd=ROOT):
    first = sample()
    if first['available_kB'] < MEMORY_RESERVE_KB:
        raise SystemExit('32 GiB memory reserve unavailable; stage not launched')
    competing = subprocess.check_output(['nvidia-smi', '--query-compute-apps=pid,process_name', '--format=csv,noheader'], text=True, timeout=5).strip()
    if competing:
        raise SystemExit('GPU compute already active; stage not launched: ' + competing)
    started = time.monotonic()
    samples = [first]
    fault = None
    process = None
    log = OUT / (name + '.log')
    try:
        with log.open('w') as output:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            while process.poll() is None:
                if time.monotonic() - started >= seconds:
                    fault = 'deadline exceeded'
                    break
                observation = sample()
                samples.append(observation)
                if observation['available_kB'] < MEMORY_RESERVE_KB:
                    fault = '32 GiB memory reserve breached'
                    break
                time.sleep(.5)
    except Exception as error:
        fault = repr(error)
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
        result = {'stage': name, 'command': command, 'deadline_s': seconds,
                  'elapsed_s': round(time.monotonic()-started, 3),
                  'returncode': process.returncode if process else None,
                  'fault': fault, 'samples': samples}
        (OUT / (name + '-telemetry.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(log.read_text(errors='replace'), end='')
    if fault or process is None or process.returncode:
        raise SystemExit('G01 stage failed; preserved log: ' + str(log))
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['capability', 'test', 'demo'])
    parser.add_argument('--slot-confirmed', action='store_true', help='confirm exclusive CPU/GPU slot; do not run alongside H3')
    parser.add_argument('--build', action='store_true', help='recompile this selected finite target')
    args = parser.parse_args()
    if not args.slot_confirmed:
        parser.error('Confirm the exclusive compute slot before passing --slot-confirmed')
    for pattern, version in [('mojo-compiler-*.json', '1.2.0.dev2026092905'), ('max-core-*.json', '26.7.0.dev2026092905')]:
        records = list((GPU_ENV / 'conda-meta').glob(pattern))
        if len(records) != 1 or json.loads(records[0].read_text())['version'] != version:
            raise SystemExit('Matching isolated GPU environment required; see experimental/physics_gpu/README.md. No automatic install performed.')
    env = os.environ.copy()
    env['PATH'] = str(GPU_ENV / 'bin') + ':' + env['PATH']
    env['CONDA_PREFIX'] = str(GPU_ENV)
    env['MODULAR_HOME'] = str(GPU_ENV / 'share/max')
    env['LD_LIBRARY_PATH'] = str(GPU_ENV / 'lib') + ':' + str(ROOT / '.deps/sdl3/lib') + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
    OUT.mkdir(parents=True, exist_ok=True)
    sources = sorted((ROOT / 'experimental/physics_gpu').glob('*.mojo'))
    sources += [ROOT / 'mojo_game' / name for name in ['rigidbody3d.mojo', 'math3d.mojo', 'transform3d.mojo']]
    target = ROOT / 'experimental/physics_gpu' / ('capability.mojo' if args.mode == 'capability' else 'test.mojo')
    command = [str(GPU_ENV / 'bin/mojo'), 'build', '--num-threads', '1', str(target), '-I', str(ROOT)]
    cwd = ROOT
    if args.mode == 'demo':
        game = ROOT / 'games/yo-frankie'
        target = game / 'examples/gpu_physics_review.mojo'
        sources += sorted((game / 'frankie').glob('*.mojo')) + [target, ROOT / 'build/libmojo_graphics.a', ROOT / '.deps/sdl3/lib/libSDL3.so']
        subprocess.run(['python3', str(ROOT / 'scripts/engine-build-state.py'), 'check'], check=True, timeout=10)
        command = [str(GPU_ENV / 'bin/mojo'), 'build', '--num-threads', '1', str(target), '-I', str(ROOT), '-I', str(game),
                   '-Xlinker', str(ROOT / 'build/libmojo_graphics.a'), '-Xlinker', '-L', '-Xlinker', str(ROOT / '.deps/sdl3/lib'),
                   '-Xlinker', '-rpath', '-Xlinker', str(ROOT / '.deps/sdl3/lib'), '-Xlinker', '-lSDL3', '-Xlinker', '-lvulkan', '-Xlinker', '-lm']
        cwd = game
        env.update({'VK_DRIVER_FILES': '/usr/share/vulkan/icd.d/nvidia_icd.json', 'MOJO_VK_SOFTWARE': '0', 'MOJO_VK_REQUIRE_HARDWARE': '1',
                    'MOJO_VK_VALIDATION': '1', 'VK_LAYER_VALIDATE_SYNC': '1', 'SDL_AUDIO_DRIVER': 'dummy'})
    fingerprint = {str(p.relative_to(ROOT)): digest(p) for p in sources}
    fingerprint['GPU_ENV/pixi.lock'] = digest(GPU_ENV.parents[2] / 'pixi.lock')
    executable = OUT / args.mode
    state_path = OUT / (args.mode + '-build.json')
    try:
        previous = json.loads(state_path.read_text())
        valid = previous['sources'] == fingerprint and previous['executable_sha256'] == digest(executable)
    except (OSError, KeyError, ValueError):
        valid = False
    if args.build or not valid:
        command += ['-o', str(executable)]
        stage(args.mode + '-compile', command, 180, env)
        state_path.write_text(json.dumps({'sources': fingerprint, 'executable_sha256': digest(executable)}, indent=2) + '\n')
    seconds = 10 if args.mode == 'capability' else 30
    run_command = [str(executable)]
    if args.mode == 'demo':
        run_command = ['bash', str(ROOT / 'games/yo-frankie/scripts/run-vulkan.sh'), str(executable)]
    result = stage(args.mode + '-run', run_command, seconds, env, cwd)
    receipt = {'status': 'passed', 'mode': args.mode, 'build': json.loads(state_path.read_text()),
               'run': result, 'precision': 'Float64 correctness profile', 'CPU_fallback': False,
               'explicit_buffer_budget_MiB': 16, 'max_bodies': 256,
               'unsupported': ['contacts', 'friction', 'joints', 'CCD', 'direct CUDA-Vulkan interop']}
    (OUT / (args.mode + '-qualification.json')).write_text(json.dumps(receipt, indent=2) + '\n')
    print('G01 passed:', args.mode, '; receipt:', OUT / (args.mode + '-qualification.json'))

if __name__ == '__main__':
    main()
