#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-frankie-realistic.py
build/frankie-test
env MOJO_VK_SOFTWARE=1 MOJO_VK_VALIDATION=1 VK_LAYER_VALIDATE_SYNC=1 \
    bash scripts/run-vulkan.sh build/yo-frankie --realistic --smoke
env MOJO_VK_SOFTWARE=1 MOJO_VK_VALIDATION=1 VK_LAYER_VALIDATE_SYNC=1 \
    bash scripts/run-vulkan.sh build/yo-frankie --realistic --tour
env MOJO_VK_SOFTWARE=1 MOJO_VK_VALIDATION=1 VK_LAYER_VALIDATE_SYNC=1 \
    bash scripts/run-vulkan.sh build/yo-frankie --realistic --action-test
