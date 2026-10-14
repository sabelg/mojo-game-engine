#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
base="$repo/.deps/blender-source"
sdk="$base/lib/linux_arm64"
mkdir -p "$repo/.deps/usd-tools/bin"
for tool in inspect stage; do
"$base/compiler/usr/bin/g++-14" -std=c++17 -O2 \
  -I"$sdk/opencolorio/include" -I"$sdk/usd/include" -I"$sdk/tbb/include" -I"$sdk/python/include/python3.13" \
  "$repo/scripts/usd-$tool.cc" -L"$base/build/bin/lib" \
  -Wl,-rpath,"$base/build/bin/lib" -Wl,-rpath-link,"$base/build/bin/lib" \
  -Wl,--export-dynamic -lusd_ms -ltbb -lOpenColorIO "$sdk/python/lib/libpython3.13.a" \
  -ldl -lpthread -lm -lutil -o "$repo/.deps/usd-tools/bin/atlas-usd-$tool.tmp"
mv "$repo/.deps/usd-tools/bin/atlas-usd-$tool.tmp" "$repo/.deps/usd-tools/bin/atlas-usd-$tool"
done
