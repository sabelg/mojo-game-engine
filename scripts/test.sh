#!/usr/bin/env bash
set -euo pipefail
build/vector_rotation-test
build/axis_normalization-test
build/core-test
build/rigidbody3d-test
build/rigidbody-integration-test
build/world3d-test
env SDL_VIDEO_DRIVER=dummy SDL_AUDIO_DRIVER=dummy bash scripts/smoke.sh
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/graphics3d-test
cmp build/gpu-cinematic-0.bmp build/gpu-cinematic-2.bmp
cmp build/gpu-cinematic-0.bmp build/gpu-cinematic-3.bmp
cmp build/gpu-origin.bmp build/gpu-far.bmp
cmp build/gpu-crossfade.bmp build/gpu-crossfade-reference.bmp
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/open-world --smoke
python3 scripts/check_render.py
for samples in 1 4; do
    env MOJO_VK_MSAA="$samples" MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/msaa-test
done
python3 scripts/check-msaa.py

python3 - <<'PYWAV'
import math,struct,wave
with wave.open('build/media-tone.wav','wb') as w:
    w.setnchannels(2);w.setsampwidth(2);w.setframerate(22050)
    w.writeframes(b''.join(struct.pack('<hh',int(math.sin(i*.1)*10000),int(math.sin(i*.1)*5000)) for i in range(2205)))
PYWAV
env SDL_AUDIO_DRIVER=dummy build/media-test

build/input-test
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/sdl3-events-test
env SDL_VIDEO_DRIVER=dummy build/controller-test

python3 tests/cook_assets.py
python3 tests/morph_animation.py
build/morph_animation-test
if [[ -x "${ATLAS_USD_INSPECT:-.deps/usd-tools/bin/atlas-usd-inspect}" && -x "${ATLAS_BLENDER:-.deps/blender-source/build/bin/blender}" ]]; then
    if [[ -x "${ATLAS_USD_STAGE:-.deps/usd-tools/bin/atlas-usd-stage}" ]]; then
        python3 scripts/qualify-usd.py
    else
        echo 'USD qualification needs the native stage tool: run pixi run usd-setup.'
    fi
else
    echo 'USD integration tests skipped: run pixi run usd-setup to install optional authoring tools.'
fi
build/binary_assets-test
build/triangle_collision-test
build/gameplay3d-test
python3 tests/benchmark_reports.py
build/atlas_systems-test
build/world_recovery-test
build/terrain_authoring-test
build/project3d-test
build/editor_commands-test
python3 tests/project_workflow.py
build/scheduler-test
env MOJO_VK_DEVICE_LOCAL_MESH=1 MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/uploads-test
cmp build/atlas-upload-updated.bmp build/atlas-upload-reference.bmp
for frames in 1 2; do
    env MOJO_VK_FRAMES_IN_FLIGHT="$frames" MOJO_VK_PROFILE=1 MOJO_VK_DEVICE_LOCAL_MESH=1 MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/frames-test
done
cmp build/atlas-frames-1.bmp build/atlas-frames-2.bmp
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/atlas_render-test
cmp build/atlas-instance-reference.bmp build/atlas-instance.bmp
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/atlas-world --smoke
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/atlas-character --smoke

env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/gpu_skin-test
python3 scripts/check-skin.py

env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/textures-test

env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/terrain_stream-test
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/visibility3d-test
cmp build/atlas-visibility-linear.bmp build/atlas-visibility-hierarchical.bmp
for frames in 1 2; do
    env MOJO_VK_FRAMES_IN_FLIGHT="$frames" MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/cascades-test
done
python3 scripts/check-cascades.py

for samples in 1 4; do
    for frames in 1 2; do
        env MOJO_VK_MSAA="$samples" MOJO_VK_FRAMES_IN_FLIGHT="$frames" MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/hdr-test
    done
done
python3 scripts/check-hdr.py

for frames in 1 2; do
    env MOJO_VK_FRAMES_IN_FLIGHT="$frames" MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/cascades-test --hdr
done
python3 scripts/check-cascades.py --hdr

for frames in 1 2; do
    env MOJO_VK_FRAMES_IN_FLIGHT="$frames" MOJO_VK_PROFILE=1 MOJO_VK_DEVICE_LOCAL_MESH=1 MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/frames-test --hdr
done
cmp build/atlas-frames-hdr-1.bmp build/atlas-frames-hdr-2.bmp

env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/preview3d-test
cmp build/atlas-preview-overrides.bmp build/atlas-preview-committed.bmp

for samples in 1 4; do
    for frames in 1 2; do
        env MOJO_VK_MSAA="$samples" MOJO_VK_FRAMES_IN_FLIGHT="$frames" MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/lod3d-test
        python3 scripts/check-lod.py
    done
done
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/hlod3d-test
python3 scripts/check-hlod.py
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/foliage3d-test
cmp build/atlas-foliage-0.bmp build/atlas-foliage-1.bmp
env MOJO_VK_SOFTWARE=1 bash scripts/run-vulkan.sh build/terrain_fade-test

python3 scripts/evaluate-temporal.py
