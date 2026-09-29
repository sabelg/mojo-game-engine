# Vulkan backend

The 3D backend uses Vulkan 1.1 exclusively. There is no OpenGL renderer or
OpenGL linkage in the 3D build. The engine's existing 2D SDL renderer remains
separate. The public `Graphics3D` scene, mesh, material and draw interfaces are
preserved, with `resize(width,height)` and `validation_errors()` added.

## Dependencies

Build: Vulkan headers, the Vulkan loader/linker library, SDL2 development files,
a C11 compiler, `ar`, Python 3 and `glslc`. `spirv-val`, when installed, checks all
compiled shader modules. Set `VULKAN_INCLUDE_DIR` or `GLSLC` to override discovery.
Shaders are compiled to Vulkan 1.1 SPIR-V and embedded as aligned uint32 arrays;
applications need no shader compiler or shader source at runtime.

Runtime: the Vulkan loader, an installed compatible hardware or software ICD,
and SDL2. Visible windows need an SDL Vulkan-capable video driver (X11/Wayland).
`hidden=True` uses Vulkan images without a window, surface or swapchain. It does
not require a display or the SDL offscreen video driver.

Optional validation: `VK_LAYER_KHRONOS_validation`. Set `MOJO_VK_VALIDATION=1`
to enable it explicitly; unavailable requested layers cause initialization to
fail instead of silently skipping validation. `VK_LAYER_VALIDATE_SYNC=1` adds
synchronization validation. Errors are printed and fail frame rendering.

Optional window regression: Xvfb, selected by `XVFB`, a project-local installation,
or PATH. The test starts a disposable virtual display and cleans it up on exit.
Local display sockets must be permitted by the environment.

## Project-local dependencies

This workspace's missing development/test dependencies were extracted under
`.deps/vulkan/usr` from these Arch/Omarchy packages, without changing system
packages:

- `vulkan-headers` 1:1.4.357.0-1
- `vulkan-swrast` 1:26.2.2-1 (Mesa lavapipe)
- `vulkan-validation-layers` 1.4.357.0-1
- `vulkan-tools` 1.4.357.0-1
- `xorg-server-xvfb` 21.1.24-1

`.deps/` is ignored and excluded from the source archive. On another machine,
install equivalent system development/runtime packages or provide compatible
SDK files. The downloaded binaries are distro-specific, not portable assets.
`scripts/build.sh` discovers local headers if present. `scripts/run-vulkan.sh`
adds the local library/layer paths and offers the local software ICD as a fallback
alongside system hardware ICDs. Explicit `VK_DRIVER_FILES` selection is respected.
`MOJO_VK_SOFTWARE=1` selects the local lavapipe ICD for reproducible tests when
that ICD exists; with system-only installations, set `VK_DRIVER_FILES` yourself
if deterministic software-driver selection is required.

## Render and presentation model

The backend uses one graphics queue and one synchronous frame in flight:

1. Queue shadow and color draws and overlay rectangles through the Mojo API.
2. Validate queued generational mesh handles before command recording.
3. Record the depth-only shadow pass and transition its image for sampling.
4. Record the lit color pass and blended overlay into an RGBA8 offscreen target.
5. Transition the color image for transfer and submit with a completion fence.
6. For snapshots, copy to a coherent readback buffer and save a top-oriented BMP.
7. For windows, acquire a swapchain image, blit the color image, transition it for
   presentation and present. Completion semaphores are indexed by swapchain image.

Resize recreates offscreen color/depth/readback resources. Window resize,
suboptimal surfaces and out-of-date acquisition/presentation recreate the
swapchain after device-idle synchronization. Zero-sized drawable surfaces skip
presentation. A graphics queue that also supports the surface is required.
The presentation surface must support transfer destination usage and an RGBA8
or BGRA8 UNORM format in the nonlinear sRGB color space.

Frame data uses a uniform buffer, including configurable hemisphere/sun/haze
lighting. Per-object matrices/materials and pose blend use 112-byte push
constants. Descriptor sets bind frame data, the depth shadow image, an sRGB albedo
texture (a default white texture for untextured draws), an optional linear
normal map, and an optional linear ORM map. `normal_texture` uploads UNORM data;
`normal_map(albedo, normal)` and `orm_map(albedo, packed)` bind those maps to an
albedo material. ORM stores occlusion in R, roughness in G, and metallic in B;
occlusion affects ambient light only. Its channels replace scalar roughness and
metallic values. Tangent frames are reconstructed from derivatives. Original
materials retain their attenuated normal strength; ORM-enabled remaster materials
use full-strength OpenGL normal maps, with V adjusted for exported texture UVs.
`draw_morph` binds a second position/normal stream and interpolates compatible
mesh poses in color and shadow passes. Both source and target handles are checked
again before command recording; a released target cannot remain in a draw queue.
Overlay quads support smooth-alpha font atlas sampling and derivative-smoothed
circle edges. Legacy rectangle and bitmap-font callers remain supported.
The 4096-square shadow pass supports alpha-cutout textures through
`shadow_material`. Anisotropic filtering is enabled only when supported,
capped at 16 or the device limit. Textures use generated
mipmaps where Vulkan format capabilities support linear blits, otherwise one
level. Vertex/index buffers are coherent host-visible allocations. Ownership and
synchronous completion ensure eviction cannot free in-flight GPU resources.
A mesh released after CPU queueing is rejected before recording commands.

CPU projection matrices retain the existing [-1,1] clip-depth convention.
Vertex shaders remap depth to Vulkan's [0,1] range and invert clip-space Y.
Shadow sampling adjusts its vertical coordinate consistently. UI coordinates
remain top-left based. Floating-origin conversion still happens in Float64
before GPU Float32 upload.

## Validation and limits

Run `pixi run vulkan-test` and `pixi run vulkan-window-test`. The tests cover
SPIR-V, resource reuse, shadow/color/overlay passes, textures, odd-width readback,
resize, CPU-queued retirement, terrain streaming, billion-unit render identity,
and real swapchain presentation on a virtual display. Validation and
synchronization checks passed on Mesa lavapipe in this workspace.

No hardware-GPU benchmark has been performed. One serialized frame, individual
host-visible mesh allocations, and the extra presentation blit limit throughput.
Staged device-local uploads, memory suballocation and multiple frames in flight
are future optimizations; the current backend does not claim those capabilities.

Implementation references: [Khronos synchronization examples](https://docs.vulkan.org/guide/latest/synchronization_examples.html)
and [swapchain recreation](https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/04_Swap_chain_recreation.html).

`Graphics3D(..., fullscreen=True)` creates a desktop fullscreen window. Use `fullscreen(enabled)` to change modes and `is_fullscreen()` to query the applied state. The legacy native `mg_open` entry point remains windowed; `mg_open_mode` accepts the additional fullscreen flag.
