#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
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
if [[ "${1:-}" == --frankie ]]; then test_command=(build/yo-frankie --window-test --windowed); fi
env SDL_AUDIODRIVER=dummy DISPLAY=":$display" SDL_VIDEODRIVER=x11 MOJO_VK_SOFTWARE=1 MOJO_VK_VALIDATION="${MOJO_VK_VALIDATION:-1}" VK_LAYER_VALIDATE_SYNC=1 \
    timeout 30 bash scripts/run-vulkan.sh "${test_command[@]}"
