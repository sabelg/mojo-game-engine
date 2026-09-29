#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-frankie-assets.py
build/frankie-input-test
build/frankie-test
env MOJO_VK_SOFTWARE=1 MOJO_VK_VALIDATION=1 VK_LAYER_VALIDATE_SYNC=1 bash scripts/run-vulkan.sh build/yo-frankie --smoke
env MOJO_VK_SOFTWARE=1 MOJO_VK_VALIDATION=1 VK_LAYER_VALIDATE_SYNC=1 bash scripts/run-vulkan.sh build/yo-frankie --tour
