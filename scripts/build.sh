#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
sdl_prefix="$PWD/.deps/sdl3"
if [[ ! -f "$sdl_prefix/lib/libSDL3.so" ]]; then
    echo 'Run bash scripts/setup-sdl3.sh before building Atlas.' >&2; exit 1
fi
export CPATH="$sdl_prefix/include${CPATH:+:$CPATH}"
export LIBRARY_PATH="$sdl_prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
sdl_link=(-Xlinker -L -Xlinker "$sdl_prefix/lib" -Xlinker -rpath -Xlinker '$ORIGIN/../.deps/sdl3/lib' -Xlinker -lSDL3)
python3 tests/sdl3_abi.py
python3 scripts/check-engine-boundary.py
python3 scripts/embed_shaders.py
python3 scripts/engine-build-state.py begin
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" tests/native_abi.mojo -I . -o build/native-abi-test
build/native-abi-test
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" tests/rigidbody3d.mojo -I . -o build/rigidbody3d-test
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" tests/rigidbody_integration.mojo -I . -o build/rigidbody-integration-test
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" tests/media.mojo -I . "${sdl_link[@]}" -Xlinker -lvulkan -Xlinker -lm -o build/media-test
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" native/mojo/runtime.mojo -I . --emit object -o build/mojo-runtime.o
# Recreate the archive so an old C object cannot remain as an extra member.
rm -f build/libmojo_graphics.a
ar rcs build/libmojo_graphics.a build/mojo-runtime.o
# C programs here are independent ABI test harnesses, not game runtime code.
mojo_executable=$(command -v mojo)
mojo_runtime_lib=$(cd "$(dirname "$mojo_executable")/../lib" && pwd)
cc -std=c11 -O2 -Wall -Wextra -Werror tests/vulkan_window.c build/libmojo_graphics.a \
    -L "$mojo_runtime_lib" -Wl,-rpath,"$mojo_runtime_lib" -lKGENCompilerRTShared -L "$sdl_prefix/lib" -Wl,-rpath,'$ORIGIN/../.deps/sdl3/lib' -lSDL3 -lvulkan -lm -o build/vulkan-window-test
for harness in input controller; do
    cc -std=c11 -O2 -Wall -Wextra -Werror "tests/$harness.c" build/libmojo_graphics.a -L "$mojo_runtime_lib" -Wl,-rpath,"$mojo_runtime_lib" -lKGENCompilerRTShared -L "$sdl_prefix/lib" -Wl,-rpath,'$ORIGIN/../.deps/sdl3/lib' -lSDL3 -lvulkan -lm -o "build/$harness-test"
done
mojo precompile mojo_game -o build/mojo_game.mojoc
cc -std=c11 -O2 -Wall -Wextra -Werror tests/sdl3_events.c -c -o build/sdl3-events-oracle.o
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" tests/sdl3_events.mojo -I build -Xlinker build/sdl3-events-oracle.o -Xlinker build/libmojo_graphics.a "${sdl_link[@]}" -Xlinker -lvulkan -Xlinker -lm -o build/sdl3-events-test
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
# Both examples compile outside the source tree against the packaged API.
cp examples/orb_collector.mojo "$staging/collector.mojo"
cp examples/open_world.mojo "$staging/world.mojo"
cp examples/atlas_world.mojo "$staging/atlas_world.mojo"
cp examples/animated_character.mojo "$staging/animated_character.mojo"
link=(-I "$PWD/build" -Xlinker "$PWD/build/libmojo_graphics.a" "${sdl_link[@]}" -Xlinker -lvulkan -Xlinker -lm)
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" "$staging/collector.mojo" "${link[@]}" -o build/orb-collector
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" "$staging/world.mojo" "${link[@]}" -o build/open-world
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" "$staging/atlas_world.mojo" "${link[@]}" -o build/atlas-world
mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" "$staging/animated_character.mojo" "${link[@]}" -o build/atlas-character
for test in vector_rotation axis_normalization core platform world3d graphics3d atlas_systems atlas_render world_recovery scheduler uploads frames binary_assets triangle_collision gpu_skin gameplay3d textures terrain_authoring terrain_stream project3d editor_commands visibility3d cascades hdr preview3d lod3d hlod3d foliage3d terrain_fade usd_camera usd_camera_animation usd_light_animation local_lighting morph_animation morph_render visibility_animation preview_playback usd_animation_render; do
    mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" "tests/$test.mojo" "${link[@]}" -o "build/$test-test"
done

mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" tests/msaa.mojo -I . -Xlinker build/libmojo_graphics.a "${sdl_link[@]}" -Xlinker -lvulkan -Xlinker -lm -o build/msaa-test



mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" examples/usd_scene.mojo "${link[@]}" -o build/atlas-usd-scene

mojo build --num-threads "${ATLAS_BUILD_JOBS:-1}" examples/usd_editor.mojo "${link[@]}" -o build/atlas-usd-editor

python3 scripts/engine-build-state.py write
python3 scripts/package-atlas.py
