# Validation

Run `pixi run library-test` to compile the package, native bridge, examples and
all tests, then run the full suite. The native bridge builds with
`-Wall -Wextra -Werror`. Both examples compile from a temporary directory against
the precompiled package rather than local source imports.

## Automated coverage

- Original core and platform regressions, plus mouse button edges/focus loss.
- Quaternion rotation, transform composition, projection rejection and
  camera-relative conversion at one-billion-unit coordinates.
- Frustum inclusion/exclusion, slab ray intersection and camera center rays.
- OBJ negative indices, polygon triangulation, generated normals and bad indices.
- Hierarchy composition, cycle rejection, scene round trips and undo/redo.
- Adjacent terrain seam heights and reduced triangle counts at distant LOD.
- Sphere bounce, nearest ray queries and terrain contact.
- World-cell dirty save, eviction and reload.
- Vulkan device, SPIR-V pipelines, shadow/color passes, BMP textures,
  resource retirement, stale handle rejection and repeated close.
- Asset-cache deduplication, bounds picking and the reusable 3D lifecycle.
- Chunk upload budgets, bounded residency and eviction after a billion-unit move.
- Pixel-identical snapshots before/after a billion-unit world translation,
  using an odd-sized framebuffer to exercise pixel-row alignment.
- Offscreen render-target resize and rejection of meshes retired after queueing.
- Optional virtual-display swapchain acquisition, presentation and repeated resize.
- Full 24-frame world smoke: 81 resident chunks, culled scene rendering, and
  image-content checks that reject empty output.

`build/open-world.bmp` is the captured world frame. The test script uses only
Python's standard library to validate BMP content. `build/gpu-origin.bmp` and
`build/gpu-far.bmp` must be byte-identical.

## What these tests do not establish

The current graphics validation uses Mesa lavapipe, a software Vulkan driver.
It establishes renderer correctness on that driver, not hardware performance or
cross-vendor compatibility. No framerate, maximum-world-size, production-readiness,
or shipping-platform claims follow from these smoke tests. Vulkan and synchronization validation pass for both offscreen rendering and an
Xvfb-backed SDL swapchain, including resizing. Resource ownership has behavioral
tests and validation checks, not a full sanitizer/driver leak audit. Terrain and cell
loading have count budgets, not guaranteed frame-time deadlines.

`pixi run vulkan-test` requires `VK_LAYER_KHRONOS_validation` and enables
synchronization validation. Validation errors fail frame rendering.
`pixi run vulkan-window-test` uses Xvfb to exercise actual SDL Vulkan surfaces,
swapchain acquisition/presentation and recreation without a desktop window.
The window test is separate because sandbox environments may prohibit its socket.
