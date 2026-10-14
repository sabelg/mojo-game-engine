#!/usr/bin/env bash
# Rebuild the pinned native Blender source checkout and local dependencies.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
base="$repo/.deps/blender-source"
cmake -S "$base/blender" -B "$base/build" \
  -DCMAKE_C_COMPILER="$base/compiler/usr/bin/gcc-14" \
  -DCMAKE_CXX_COMPILER="$base/compiler/usr/bin/g++-14" \
  -DCMAKE_BUILD_TYPE=Release -DLIBDIR="$base/lib/linux_arm64" \
  -DWITH_LIBS_PRECOMPILED=ON -DWITH_CYCLES_DEVICE_CUDA=ON \
  -DWITH_CYCLES_DEVICE_OPTIX=ON -DOPTIX_ROOT_DIR="$base/optix" \
  -DWITH_CYCLES_CUDA_BINARIES=ON -DCYCLES_CUDA_BINARIES_ARCH=sm_121 \
  -DWITH_CYCLES_DEVICE_HIP=OFF -DWITH_CYCLES_DEVICE_ONEAPI=OFF \
  -DWITH_GHOST_WAYLAND=OFF -DWITH_GTESTS=OFF
cmake --build "$base/build" --parallel "${BLENDER_BUILD_JOBS:-16}"
cmake --install "$base/build"
