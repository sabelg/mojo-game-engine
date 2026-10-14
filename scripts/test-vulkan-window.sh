#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CPATH="$PWD/.deps/sdl3/include${CPATH:+:$CPATH}"
export LIBRARY_PATH="$PWD/.deps/sdl3/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
xvfb=${XVFB:-}
if [[ -z "$xvfb" && -x .deps/vulkan/usr/bin/Xvfb ]]; then xvfb="$PWD/.deps/vulkan/usr/bin/Xvfb"; fi
if [[ -z "$xvfb" ]]; then xvfb=$(command -v Xvfb) || { echo 'Install Xvfb or set XVFB for the window regression' >&2; exit 1; }; fi
scratch=$(mktemp -d)
server=
cleanup() {
    if [[ -n "$server" ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi
    rm -rf "$scratch"
}
trap cleanup EXIT
"$xvfb" -displayfd 3 -screen 0 800x600x24 -nolisten tcp -noreset 3>"$scratch/display" >"$scratch/server.log" 2>&1 &
server=$!
for _ in {1..50}; do
    if [[ -s "$scratch/display" ]]; then break; fi
    if ! kill -0 "$server" 2>/dev/null; then tail -40 "$scratch/server.log" >&2; exit 1; fi
    sleep 0.1
done
if [[ ! -s "$scratch/display" ]]; then tail -40 "$scratch/server.log" >&2; exit 1; fi
read -r display < "$scratch/display"
test_command=(build/vulkan-window-test)
if [[ "${1:-}" == --hdr || "${1:-}" == --sdl3 ]]; then
    harness=vulkan_hdr_window
    binary=vulkan-hdr-window-test
    if [[ "${1:-}" == --sdl3 ]]; then harness=sdl3_window; binary=sdl3-window-test; fi
    mojo_executable=$(command -v mojo)
    mojo_runtime_lib=$(cd "$(dirname "$mojo_executable")/../lib" && pwd)
    cc -std=c11 -O2 -Wall -Wextra -Werror "tests/$harness.c" build/libmojo_graphics.a \
        -L "$mojo_runtime_lib" -Wl,-rpath,"$mojo_runtime_lib" -lKGENCompilerRTShared -Wl,-rpath,'$ORIGIN/../.deps/sdl3/lib' -lSDL3 -lvulkan -lm -o "build/$binary"
    test_command=("build/$binary")
fi
if [[ "${1:-}" == --frankie ]]; then test_command=(bash "$PWD/games/yo-frankie/scripts/run-vulkan.sh" build/yo-frankie --window-test --windowed --polished); fi
env SDL_AUDIO_DRIVER=dummy DISPLAY=":$display" SDL_VIDEO_DRIVER=x11 MOJO_VK_SOFTWARE="${MOJO_VK_SOFTWARE:-1}" MOJO_VK_VALIDATION="${MOJO_VK_VALIDATION:-1}" VK_LAYER_VALIDATE_SYNC=1 \
    timeout 30 bash scripts/run-vulkan.sh "${test_command[@]}"
