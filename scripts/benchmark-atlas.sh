#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/atlas-benchmark
mode=${1:-current}
case "$mode" in baseline|current|instanced|streaming) ;; *) echo 'Usage: benchmark-atlas.sh baseline|current|instanced|streaming' >&2; exit 2 ;; esac
if [[ "$mode" == baseline && -f build/atlas-benchmark/baseline.json ]]; then
    echo 'Historical baseline already exists; use current, instanced or streaming.' >&2
    exit 2
fi
mojo build examples/atlas_benchmark.mojo -I build -Xlinker build/libmojo_graphics.a -Xlinker -L -Xlinker "$PWD/.deps/sdl3/lib" -Xlinker -rpath -Xlinker "$PWD/.deps/sdl3/lib" -Xlinker -lSDL3 -Xlinker -lvulkan -Xlinker -lm -o "build/atlas-benchmark/$mode"
options=()
if [[ "$mode" == instanced ]]; then options+=(--instanced); fi
if [[ "$mode" == streaming ]]; then options+=(--streaming); fi
env MOJO_VK_REQUIRE_HARDWARE=1 MOJO_VK_PROFILE=1 MOJO_VK_VALIDATION="${MOJO_VK_VALIDATION:-0}" VK_LAYER_VALIDATE_SYNC=1 bash scripts/run-vulkan.sh "build/atlas-benchmark/$mode" "${options[@]}" > "build/atlas-benchmark/$mode.tsv"
python3 scripts/report-atlas-benchmark.py "$mode"
