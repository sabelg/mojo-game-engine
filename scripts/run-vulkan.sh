#!/usr/bin/env bash
# Optional project-local SDK/driver; system installations work without .deps.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
export LD_LIBRARY_PATH="$root/.deps/sdl3/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
local_sdk="$root/.deps/vulkan/usr"
# Optional validation layers must match the native architecture, including ARM64.
native_validation="$root/.deps/validation/usr"
native_lib="$native_validation/lib/$(uname -m)-linux-gnu"
if [[ -f "$native_lib/libVkLayer_khronos_validation.so" ]]; then
    export LD_LIBRARY_PATH="$native_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [[ -z "${VK_LAYER_PATH:-}" ]]; then
        export VK_LAYER_PATH="$native_validation/share/vulkan/explicit_layer.d"
    fi
fi
# The optional downloaded SDK contains x86-64 binaries. ARM64 targets use
# their native system loader and drivers; never preload the bundled libraries.
if [[ "$(uname -m)" != x86_64 || "${MOJO_VK_SYSTEM:-0}" == 1 ]]; then
    exec "$@"
fi
if [[ -d "$local_sdk/lib" ]]; then
    export LD_LIBRARY_PATH="$local_sdk/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
if [[ "${MOJO_VK_SOFTWARE:-0}" == 1 && -z "${VK_DRIVER_FILES:-}" && -f "$local_sdk/share/vulkan/icd.d/lvp_icd.json" ]]; then
    export VK_DRIVER_FILES="$local_sdk/share/vulkan/icd.d/lvp_icd.json"
fi
# Add the local software ICD as a fallback without hiding hardware drivers.
if [[ -z "${VK_DRIVER_FILES:-}" && -f "$local_sdk/share/vulkan/icd.d/lvp_icd.json" ]]; then
    export VK_ADD_DRIVER_FILES="$local_sdk/share/vulkan/icd.d/lvp_icd.json${VK_ADD_DRIVER_FILES:+:$VK_ADD_DRIVER_FILES}"
fi
if [[ -z "${VK_LAYER_PATH:-}" && -d "$local_sdk/share/vulkan/explicit_layer.d" ]]; then
    export VK_LAYER_PATH="$local_sdk/share/vulkan/explicit_layer.d${VK_LAYER_PATH:+:$VK_LAYER_PATH}"
fi
exec "$@"
