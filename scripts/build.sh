#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 scripts/embed_shaders.py
vulkan_include=()
if [[ -n "${VULKAN_INCLUDE_DIR:-}" ]]; then
    vulkan_include=(-I "$VULKAN_INCLUDE_DIR")
elif [[ -f .deps/vulkan/usr/include/vulkan/vulkan.h ]]; then
    vulkan_include=(-I "$PWD/.deps/vulkan/usr/include")
fi
cc "${vulkan_include[@]}" -std=c11 -O2 -Wall -Wextra -Werror -Ibuild -c native/graphics.c -o build/graphics.o
ar rcs build/libmojo_graphics.a build/graphics.o
cc -std=c11 -O2 -Wall -Wextra -Werror tests/vulkan_window.c build/graphics.o -lSDL2 -lvulkan -o build/vulkan-window-test
mojo precompile mojo_game -o build/mojo_game.mojoc
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
# Both examples compile outside the source tree against the packaged API.
cp examples/orb_collector.mojo "$staging/collector.mojo"
cp examples/open_world.mojo "$staging/world.mojo"
link=(-I "$PWD/build" -Xlinker "$PWD/build/libmojo_graphics.a" -Xlinker -lSDL2 -Xlinker -lvulkan)
mojo build "$staging/collector.mojo" "${link[@]}" -o build/orb-collector
mojo build "$staging/world.mojo" "${link[@]}" -o build/open-world
for test in core platform world3d graphics3d; do
    mojo build "tests/$test.mojo" "${link[@]}" -o "build/$test-test"
done
tar --exclude=assets/yofrankie --exclude=assets/yofrankie-realistic -czf build/mojo-game-source.tar.gz mojo_game examples tests scripts native shaders assets docs pixi.toml pixi.lock README.md
