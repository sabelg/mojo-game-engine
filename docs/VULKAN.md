# Vulkan backend

The 3D backend uses Vulkan 1.1 exclusively. There is no OpenGL renderer or
OpenGL linkage in the 3D build. The engine's existing 2D SDL renderer remains
separate. The public `Graphics3D` scene, mesh, material and draw interfaces are
preserved, with `resize(width,height)` and `validation_errors()` added.

## Dependencies

Build: the Vulkan loader/linker library, SDL2 development files,
a C11 compiler, `ar`, Python 3 and `glslc`. `spirv-val`, when installed, checks all
compiled shader modules. Set `GLSLC` to override shader compiler discovery. The CPU backend is Mojo;
the C compiler is used only for independent regression harnesses.
Shaders are compiled to Vulkan 1.1 SPIR-V and embedded as static Mojo UInt32 arrays;
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
`MOJO_VK_SOFTWARE=1` now filters for CPU Vulkan devices on every architecture,
including ARM64; a native software ICD must be installed. Explicit
`VK_DRIVER_FILES` selection remains respected. `MOJO_VK_REQUIRE_HARDWARE=1`
requires a discrete, integrated or virtual GPU and rejects CPU fallback. Setting
both flags is an error. `build/yo-frankie --gpu-check` prints the selected Vulkan
device without loading game assets. Optional native validation layers under
`.deps/validation/usr` are supported independently of the x86-only local SDK.

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
   There is no per-frame queue-idle wait after presentation: reacquiring an image
   and waiting on its acquire semaphore makes reuse of that image's present
   semaphore safe ([Khronos guide](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html)).

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
`triplanar(albedo, tiles_per_unit)` enables object-local three-axis projection
for opaque albedo materials; zero restores atlas UVs. The albedo, normal and ORM
maps share the projection and fourth-power normal weights. The last pose push
constant carries the scale, leaving animation's three blend factors unchanged.
Local vertex positions anchor the material through floating-origin changes.
Normals are blended as tangent slopes and transformed with the model's inverse
transpose. Transparent albedos are rejected so the UV-based shadow alpha test
remains consistent. Projected materials use three samples per map; they add no
render targets or passes. The original material path remains the default.

`foliage(albedo, transmission)` enables viewer-facing normals on both sides of a
leaf card and a shadowed reverse-light term. Strength is in [0, 1]; zero disables
the mode. Foliage and projection modes are exclusive and share the final pose
scalar. Alpha testing and shadow cutouts remain unchanged. No extra light or
shadow-map samples are needed. `slope_tint(albedo)` treats `Material.color` as
the steep-face multiplier, blending from white on level faces using the local
normal. It accepts opaque non-foliage materials and adds no texture samples.

Frankie material manifests accept an optional seventh column for triplanar scale
(0 disables it; maximum 64 tiles per local unit), following the ORM column. An
eighth column sets foliage transmission. An optional ninth column, `slope`,
enables terrain tint and requires zero foliage transmission. Five- and six-column
manifests retain their original behavior.
`draw_morph` binds a second position/normal stream and interpolates compatible
mesh poses in color and shadow passes. Both source and target handles are checked
again before command recording; a released target cannot remain in a draw queue.
Overlay quads support smooth-alpha font atlas sampling and derivative-smoothed
circle edges. Legacy rectangle and bitmap-font callers remain supported.
The 4096-square shadow pass supports alpha-cutout textures through
`shadow_material`. Anisotropic filtering is enabled only when supported,
capped at 16 or the device limit. Textures use generated
mipmaps where Vulkan format capabilities support linear blits, otherwise one
level. Uniform/overlay and readback buffers reuse coherent mappings. Mesh buffers
use pooled slices with fence-delayed reuse; coherent pages are the default and
`MOJO_VK_DEVICE_LOCAL_MESH=1` selects staged device-local pages. Ownership and
completion fences ensure eviction cannot free in-flight GPU resources.
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

The Atlas instancing, pool-reuse, dynamic-mesh and staged-upload tests passed on
NVIDIA GB10 with synchronization validation. Headless dense-scene and sustained
streaming benchmarks are recorded under `build/atlas-benchmark`; see
[Atlas upgrades](ATLAS_UPGRADES.md) for methodology and limits. One serialized
frame and the extra presentation blit remain throughput limits. Multiple frames
in flight have not been enabled.

Implementation references: [Khronos synchronization examples](https://docs.vulkan.org/guide/latest/synchronization_examples.html)
and [swapchain recreation](https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/04_Swap_chain_recreation.html).

`Graphics3D(..., fullscreen=True)` creates a desktop fullscreen window. Use `fullscreen(enabled)` to change modes and `is_fullscreen()` to query the applied state. The legacy native `mg_open` entry point remains windowed; `mg_open_mode` accepts the additional fullscreen flag.

### Cross-clip animation

`draw_crossfade` blends two pairs of compatible poses in both lit and shadow
passes: `mix(mix(a,b,blend), mix(c,d,target_blend), fade)`. All weights must be
finite and within [0,1]. All four handles must be live and share vertex counts
and index topology; queued handles are checked again before submission. Callers
must preserve vertex correspondence, UVs and material assignments across clips.
The pipeline uses four vertex streams and retains the 112-byte push constants.
The graphics regression compares a crossfade against equivalent static geometry
bit-for-bit, including shadows, and rejects invalid weights/layouts/stale targets.
Target-hardware animation performance has not been measured.

### Foliage wind

`wind_material(albedo)` opts a foliage material into object-local vertex
deformation. `wind(seconds, amplitude=0.12)` sets the field after `shadow_begin`;
the next `shadow_begin` resets it. The color and shadow passes share the same
deformation function, and normals use its analytic inverse transpose. Bounds
must expand by `amplitude * (0.8, 0.12, 0.6)` in local axes before transforming
them into world space. Amplitude is limited to 0.25; zero restores static geometry.
The frame uniform gains one vec4; mesh formats and 112-byte push constants remain
unchanged. GPU images test CPU-reference shadow parity, disabled/reset behavior,
long clocks and floating origins. See [the game integration](../art/frankie-canopy/WIND.md).
