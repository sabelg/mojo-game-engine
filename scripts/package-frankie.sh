#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Retain editable originals and their licenses alongside every converted asset.
tar -czf build/yofrankie-vulkan-source.tar.gz frankie games mojo_game native shaders scripts tests \
    assets art/frankie-realistic third_party/yofrankie docs saves/.gitkeep README.md pixi.toml pixi.lock
