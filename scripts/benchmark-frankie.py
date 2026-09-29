"""Measure all campaign scenes; host frame latency, not GPU timestamp timings."""
import argparse
import json
import math
from pathlib import Path
import platform
import statistics
import subprocess
import time


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resolution', choices=['720p', '1080p', '1440p', '4k'], default='1080p')
    parser.add_argument('--quick', action='store_true', help='Harness check only; too few samples for performance conclusions')
    parser.add_argument('--output', type=Path, default=Path('build/frankie-performance.json'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    expected = [line.split('\t')[0] for line in (root / 'assets/yofrankie/levels.tsv').read_text().splitlines() if line]
    command = ['bash', 'scripts/run-vulkan.sh', 'build/yo-frankie',
               '--benchmark-quick' if args.quick else '--benchmark', '--' + args.resolution]
    scenes = {}
    driver = None
    resolution = None
    started = time.time()
    result = subprocess.run(command, cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.with_suffix('.log').write_text(result.stdout)
    if result.returncode:
        raise SystemExit(f'Benchmark failed ({result.returncode}); see {args.output.with_suffix(".log")}')
    for line in result.stdout.splitlines():
        fields = line.split()
        if line.startswith('Yo Frankie Vulkan:'):
            driver = line.partition(':')[2].strip()
        elif fields and fields[0] == 'BENCH_RESOLUTION':
            resolution = [int(v) for v in fields[1:]]
        elif fields and fields[0] == 'BENCH_LOAD':
            scenes[fields[1]] = {'load_ms': float(fields[2]), 'samples': [], 'triangles': []}
        elif fields and fields[0] == 'BENCH_FRAME':
            scenes[fields[1]]['samples'].append(float(fields[2]))
            scenes[fields[1]]['triangles'].append(int(fields[3]))
    count = 6 if args.quick else 180
    if set(scenes) != set(expected) or any(len(s['samples']) != count for s in scenes.values()):
        raise SystemExit('Incomplete campaign sweep; no performance report written')
    if not driver or not resolution or 'Vulkan validation errors: 0' not in result.stdout:
        raise SystemExit('Missing device, resolution, or successful validation status')
    for scene in scenes.values():
        values = scene['samples']
        if any(not math.isfinite(v) or v <= 0 for v in values):
            raise SystemExit('Invalid frame timing')
        scene.update(mean_ms=statistics.mean(values), p50_ms=percentile(values, .5),
                     p95_ms=percentile(values, .95), p99_ms=percentile(values, .99),
                     max_ms=max(values), frames_over_16_67_ms=sum(v > 1000 / 60 for v in values))
    report = dict(driver=driver, architecture=platform.machine(), resolution=resolution,
                  quick_check=args.quick, elapsed_seconds=time.time() - started,
                  measurement='Headless synchronous frame wall time, including game update and render; excludes load and warmup. Camera orbits spawn. Does not measure window presentation or full-level traversal.',
                  scenes=scenes)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    for name, scene in scenes.items():
        print(f'{name}: p95 {scene["p95_ms"]:.2f} ms; load {scene["load_ms"]:.0f} ms')
    print(f'Report: {args.output} ({driver})')


if __name__ == '__main__':
    main()
