# Atlas — Mojo 3D Engine

A modular Linux desktop engine and world editor written in Mojo, with a small
SDL2/Vulkan C backend. It now includes camera-relative 3D rendering, lit
materials and shadows, imported meshes, streamed terrain, persistent world
cells, scene editing, and sphere physics. The earlier 2D library remains usable.

The repository also includes a playable **Yo Frankie Vulkan port in progress**,
using the original Blender Foundation assets and 12 original scenes.
The visual upgrade adds 1080p–4K output, original normal maps, subdivided characters,
4K environment shadows, and anisotropic filtering.
Run `pixi run play`. Movement, combat, portals, menus, audio, and scene selection
are implemented; full original gameplay parity is still unfinished.
See [controls, attribution, tests, and remaining fidelity work](docs/YO_FRANKIE.md).

`pixi run play` selects the **stylized remaster**: Blender 5 art for all 12 scenes,
curved foliage/flowers, smooth GPU animation blending, scene lighting, camera and
action feedback, and a smooth-font HUD. Original models and baked poses remain
the basis. See the [presentation pass and its limits](docs/FRANKIE_POLISH.md).
Use `pixi run frankie` for the original art. See the
[Blender workflow and remaster limitations](docs/FRANKIE_REALISTIC_REMAKE.md).

The campaign target is all 12 scenes on **DGX Spark**, retaining Mojo/Vulkan.
See [production gates and ARM64 build/performance instructions](docs/FRANKIE_PRODUCTION.md).
`pixi run frankie-benchmark` measures every scene; Spark performance is not yet verified.

![Open-world editor](docs/open-world.png)

## Run

This repository uses **Git LFS** for Blender projects, meshes, textures and audio.
Install Git LFS before cloning, or run `git lfs install` and `git lfs pull` after
cloning to download the full assets. Dependency caches and build outputs are
excluded; the build scripts reproduce them locally.

```sh
pixi run world-demo       # open the 3D world editor
pixi run library-test     # build and run all CPU, SDL and Vulkan tests
pixi run world-smoke      # render a world headlessly; saves build/open-world.bmp
pixi run library-demo    # original 2D collector game
```

Build requirements: Pixi, a C11 compiler, `ar`, Python 3 (shader embedding only),
SDL2, Vulkan headers/loader, and `glslc` (SPIR-V shader compiler). The Pixi lockfile pins
Mojo `1.2.0.dev2026092905`. Runtime games use native Mojo, SDL2 and Vulkan;
there is no Python runtime dependency. The 3D backend requires Vulkan 1.1 and an installed Vulkan ICD.

The headless graphics tests use offscreen Vulkan images and Mesa lavapipe, with
no display server or SDL video driver required. `MOJO_VK_SOFTWARE=1` selects the
project-local software ICD when available. The existing 2D SDL tests still use
the `dummy` video driver.

```sh
pixi run vulkan-test         # full suite with Vulkan + synchronization validation
pixi run vulkan-window-test  # swapchain/resize regression on Xvfb
```

These extra checks require Khronos validation layers and, for window tests,
Xvfb. See [Vulkan setup and backend details](docs/VULKAN.md), including optional
project-local dependencies. Hardware GPU performance has not been validated.

## World editor controls

| Input | Action |
| --- | --- |
| WASD / Q,E | Fly forward/sideways / down,up |
| Right mouse drag / IJKL | Look around |
| Shift | Move faster |
| Left click / Tab / F | Pick object or outliner row / next object / center-ray pick |
| Arrows / Page Up,Down | Move selected object horizontally / vertically |
| R / +,- | Rotate / scale selected object |
| B / X | Duplicate / delete selected object |
| Z / Y | Undo / redo (32 edits) |
| F5 / F9 | Save / load `assets/world.scene` |
| Space | Throw a bouncing physics sphere |
| T | Travel one billion world units to exercise world streaming |
| Escape | Exit |

The editor starts with a procedural landscape and imported landmark meshes.
The scene file stores authored objects; terrain is regenerated from its seed.
The reusable `WorldPartition` API separately stores authored scenes by region.
The editor's F5/F9 workflow edits one scene rather than an entire partition.

## Implemented systems

- **3D rendering:** indexed GPU meshes, configurable/resizable viewport,
  perspective camera, frustum culling, inverse-transpose normals, GGX metallic/
  roughness lighting, directional shadow map with PCF, fog, tone mapping,
  gamma output, BMP textures with mipmaps, and batched overlay UI.
- **Large worlds:** Float64 scene transforms, camera-relative GPU upload,
  seeded height terrain, three mesh LODs with skirts, near-first chunk loading,
  bounded uploads per update, GPU eviction, and generational resource handles.
- **Authored content:** OBJ positions/normals/UVs and convex polygon triangulation,
  mesh cache, hierarchical scene transforms, scene validation, atomic file
  replacement, and disk-backed cells that save dirty content before eviction.
- **Simulation and tools:** fixed-step lifecycle, 3D sphere/terrain contact,
  sphere broad phase and impulses, ray queries, camera navigation, scene
  selection/transforms, undo/redo, snapshots, and draw/triangle statistics.
- **Existing 2D systems:** entity/components, events, animation, AABB physics,
  sprites, font rendering, procedural audio, and the software 3D renderer.

See [3D API and architecture](docs/OPEN_WORLD.md),
[validation and limitations](docs/VALIDATION.md), and the
[2D API guide](mojo_game/README.md).

## Reuse the library

`pixi run library-build` creates:

- `build/mojo_game.mojoc` — version-specific Mojo package.
- `build/libmojo_graphics.a` — native graphics backend, with embedded shaders.
- `build/open-world` and `build/orb-collector` — standalone example executables.
- `build/mojo-game-source.tar.gz` — library, backend, assets, examples and tests.

Compile a 3D game against the package:

```sh
pixi run mojo build main.mojo -I build \
  -Xlinker build/libmojo_graphics.a -Xlinker -lSDL2 -Xlinker -lvulkan -o my-game
```

Use [the open-world example](examples/open_world.mojo) for render-pass and
streaming integration. `Game3D` / `Engine3D` provide the reusable fixed-step
lifecycle; the editor demonstrates a custom loop for variable-rate navigation.
The source archive is the portable distribution format across Mojo upgrades.

## Maturity

This is a tested 3D engine foundation for open-world development, **not a
production-complete professional engine**. Terrain and cell loading are
synchronous with per-update budgets; there is no background job system. The
physics system is sphere-based and has no rigid-body angular dynamics or CCD.
There is no skeletal animation, glTF pipeline, navigation mesh, networking,
terrain sculpting, automatic world-cell migration, or shipping-platform suite.
Those requirements, with concrete acceptance criteria, are listed in
[the roadmap](docs/ROADMAP.md).
