# Atlas — Mojo 3D Engine

A modular Linux desktop engine and world editor written in Mojo, with a small
SDL3/Vulkan backend also written in Mojo. It now includes camera-relative 3D rendering, lit
materials and shadows, imported meshes, streamed terrain, persistent world
cells, scene editing and sphere physics. Instanced batches, asynchronous terrain/cell
workers, stable asset manifests, capsule movement and skeletal clip blending
extend the 3D API. The earlier 2D library remains usable.

The reusable engine is independent of its game projects. `mojo_game/`, `native/`, `shaders/`, engine examples and engine regression tests belong to Atlas. Game-specific code, art, audio, saves, reports and release tooling live in [games/yo-frankie](games/yo-frankie/README.md). Game projects import the compiled API and link the engine archive; engine builds and SDK packages contain no Yo Frankie content.

```sh
python3 scripts/new-game.py /path/to/new-game
# Build Atlas once, then use the new project's pixi run build/play tasks.
```

Root Yo Frankie commands remain compatibility launchers. New projects can live outside this repository and select the engine with `ATLAS_ENGINE_ROOT`. See [project boundaries](docs/PROJECT_LAYOUT.md).

See the [Atlas roadmap](docs/ROADMAP.md), [implemented upgrades](docs/ATLAS_UPGRADES.md),
[native SDL3 setup and acceptance](docs/SDL3_MIGRATION.md),
[migration and known limits](docs/ATLAS_MIGRATION.md),
[qualified animation authoring](docs/USD_TYPED_CURVES.md), and [qualification evidence](docs/VALIDATION.md).

![Open-world editor](docs/open-world.png)

## Run

This repository uses **Git LFS** for Blender projects, meshes, textures and audio.
Install Git LFS before cloning, or run `git lfs install` and `git lfs pull` after
cloning to download the full assets. Dependency caches and build outputs are
excluded; the build scripts reproduce them locally.

```sh
pixi run world-demo       # open the partition-aware 3D world editor
pixi run character-demo   # skeletal clip blending and dynamic mesh updates
pixi run library-test     # build and run all CPU, SDL and Vulkan tests
pixi run world-smoke      # render a world headlessly; saves build/atlas-world.bmp
pixi run library-demo    # original 2D collector game
```

Build requirements: CMake, Pixi, a C11 compiler, `ar`, Python 3 (offline tools and shader embedding only),
project-local SDL3 3.4.18 ([patch verification](docs/SDL3_UPGRADE.md)), Vulkan loader/linker libraries, and `glslc` (SPIR-V shader compiler). The Pixi lockfile pins
Mojo `1.2.0.dev2026092905`. Runtime games use native Mojo, SDL3 and Vulkan;
all project-owned CPU runtime code is Mojo. SDL3 is pinned from official source under `.deps/sdl3`; the Vulkan loader and GPU drivers
remain external system libraries; GPU programs remain GLSL compiled to SPIR-V.
The C compiler builds only independent ABI regression harnesses. There is no
Python runtime dependency. See [Mojo runtime and migration checks](docs/MOJO_RUNTIME.md). The 3D backend requires Vulkan 1.1 and an installed Vulkan ICD.

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
project-local dependencies. See the production notes for dated GB10 evidence and
the limits of those measurements.

See [the Atlas upgrades and their limits](docs/ATLAS_UPGRADES.md) for asset cooking,
partition authoring, worker ownership, instancing and character APIs.

## World editor controls

| Input | Action |
| --- | --- |
| WASD / Q,E | Fly forward/sideways / down,up |
| Right mouse drag / IJKL | Look around |
| Shift | Move faster |
| Left click / drag | Select object / move axis gizmo / place asset from browser |
| Arrows / Page Up,Down | Move selected object horizontally / vertically |
| R / +,- | Rotate / scale selected object |
| B / X | Duplicate / delete selected object |
| Z / Y | Undo / redo (32 edits) |
| F5 / F9 | Queue dirty world-cell saves / flush and reload cells |
| C / Space | Toggle fly/capsule walk / jump while walking |
| T | Travel one billion world units to exercise world streaming |
| Escape | Exit |

The partition editor starts with procedural terrain and a primitive asset browser.
Its default cells are saved in `build/atlas-world-project`; use `--project` for a
durable world directory and `--assets` for a cooked asset manifest. The earlier
single-scene editor remains available as `build/open-world`.

## Implemented systems

- **3D rendering:** indexed GPU meshes, configurable/resizable viewport,
  perspective camera, frustum culling, inverse-transpose normals, GGX metallic/
  roughness lighting, directional shadow map with PCF, fog, tone mapping,
  gamma output, BMP textures with mipmaps, and batched overlay UI.
- **Large worlds:** Float64 scene transforms, camera-relative GPU upload,
  seeded height terrain, three mesh LODs with skirts, near-first chunk loading,
  bounded uploads per update, GPU eviction, and generational resource handles.
  Asynchronous preparation adds cancellation, bounded reservations and soft
  upload-time budgets; rendering uses instanced batches and reusable mesh pools.
- **Authored content:** OBJ positions/normals/UVs and convex polygon triangulation,
  mesh cache, hierarchical scene transforms, scene validation, atomic file
  replacement, and disk-backed cells that save dirty content before eviction.
  Stable manifest keys and an incremental OBJ/glTF/GLB cooker connect imported
  scenes, materials, skeletons and clips to partition authoring.
- **Simulation and tools:** fixed-step lifecycle, 3D sphere/terrain contact,
  sphere broad phase and impulses, ray queries, camera navigation, scene
  selection/transforms, undo/redo, snapshots, and draw/triangle statistics.
  Capsule sweeps add stepping, jumping and platform motion; skeletal clips use
  quaternion blending and CPU skinning into persistent GPU meshes.
- **Existing 2D systems:** entity/components, events, animation, AABB physics,
  sprites, font rendering, procedural audio, and the software 3D renderer.

See [3D API and architecture](docs/OPEN_WORLD.md),
[validation and limitations](docs/VALIDATION.md), and the
[2D API guide](mojo_game/README.md).

## Reuse the library

`pixi run library-build` creates:

- `build/mojo_game.mojoc` — version-specific Mojo package.
- `build/libmojo_graphics.a` — compiled Mojo runtime, with embedded shaders.
- `build/atlas-world`, `build/atlas-character`, `build/open-world` and
  `build/orb-collector` — standalone example executables.
- `build/mojo-game-source.tar.gz` — library, backend, assets, examples and tests.

Compile a 3D game against the package:

```sh
pixi run mojo build main.mojo -I build \
  -Xlinker build/libmojo_graphics.a -Xlinker -lSDL3 -Xlinker -lvulkan -o my-game
```

Use [the open-world example](examples/open_world.mojo) for render-pass and
streaming integration. `Game3D` / `Engine3D` provide the reusable fixed-step
lifecycle; the editor demonstrates a custom loop for variable-rate navigation.
The source archive is the portable distribution format across Mojo upgrades.

## Maturity

This is a tested 3D engine foundation, not a production-complete shipping engine.
The new workers and upload budgets do not guarantee frame deadlines. Skeletal
animation currently skins on the CPU; glTF import supports a documented subset.
Physics includes spheres and an upright capsule/box controller, with no angular
rigid-body dynamics. A general job scheduler, GPU skinning, triangle collision,
navigation mesh, networking, terrain sculpting and a broader driver/platform
acceptance suite remain future work. See [the roadmap](docs/ROADMAP.md).

## Optional FFmpeg media tools

Atlas can use pinned stable FFmpeg 9.0.2 CLI tools in a separate, versioned ARM64
conda-forge environment. Run `pixi run ffmpeg-setup`, then `pixi run ffmpeg-check`
and `pixi run ffmpeg-test`; invoke `pixi run ffmpeg` or `pixi run ffprobe` with
your arguments. See [setup, codec checks, synthetic tests and rollback](docs/FFMPEG.md).
The media environment is separate from Atlas's SDL3 runtime and root Pixi lock.
