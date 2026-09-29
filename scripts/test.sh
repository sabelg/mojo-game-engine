#!/usr/bin/env bash
set -euo pipefail
build/core-test
build/world3d-test
env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy bash scripts/smoke.sh
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/graphics3d-test
cmp build/gpu-origin.bmp build/gpu-far.bmp
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/open-world --smoke
python3 scripts/check_render.py
