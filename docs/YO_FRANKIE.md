# Yo Frankie! — Vulkan port

A playable **work-in-progress remake of the original Blender Game Engine edition**,
built on this repository's native Mojo/SDL2/Vulkan engine. This replaces the
abandoned original-level "Acorn Trail" draft. It is **not yet a complete,
behavior-identical remake** and is not an official Blender Foundation release.

## Play

```sh
pixi run play                 # build and launch the procedural remaster
pixi run frankie              # original art
pixi run world-demo           # engine world editor remains available
```

For the already-built executable, avoiding a rebuild:

```sh
bash scripts/run-vulkan.sh build/yo-frankie
```

Run from the repository root. Linux x86-64; Vulkan 1.1 and SDL2 required.
`MOJO_VK_SOFTWARE=1` selects the locally installed Mesa software driver.
Missing audio devices do not stop the game. The game runs natively without
Blender or Python; those are asset-authoring tools only.

The [Blender 5 procedural remaster](FRANKIE_REALISTIC_REMAKE.md) supplies a separate
art pack for all scenes. Launch it with `pixi run play`, or add `--realistic` to
the built executable. The visual-upgrade details below describe the original
art pack selected by `pixi run frankie`.

## Visual upgrade

[View the 4K capture](yo-frankie-hd.png).

The game opens in **desktop fullscreen** at your display resolution, with scaled HUD/menus. Press **F11** to toggle fullscreen, or pass `--windowed` to start in a window (1920×1080 by default). Resolution flags below set the windowed or capture size. Audio is enabled by default, with original title/gameplay music and sound effects; **M** toggles mute and saves that preference.
Choose another output size directly:

```sh
bash scripts/run-vulkan.sh build/yo-frankie --720p
bash scripts/run-vulkan.sh build/yo-frankie --1440p
bash scripts/run-vulkan.sh build/yo-frankie --4k
```

- 62 albedo textures restored from editable sources, capped at 4096 pixels without
  upscaling. Two actually exceed the old 1024 cap: the 2048×512 sky and
  2560×2560 watermap. Lower-resolution original textures retain their native size.
- 19 original normal maps, sampled in linear space with derivative tangent frames,
  add surface relief to bark, stone, props, and characters.
- Up to 16× anisotropic filtering, limited to the Vulkan device's supported value.
- 4096×4096 filtered sun shadows from scene geometry and actors, including
  alpha-cutout foliage. Sky, clouds, effects, and water do not cast solid shadows.
- Material-specific roughness, rust metallic response, lava emission, and filmic
  highlight roll-off replace the previous uniform material settings.
- One Catmull–Clark subdivision level on skinned characters, baked through all
  existing animation poses. Frankie now has 19,624 triangles per pose.

Original layouts, UVs, character identity, and gameplay collision remain intact.
This preserves the original stylized art direction. It does not invent detail
by enlarging small source images. The converted asset set is approximately
571 MB; preloaded subdivided animation poses increase graphics memory use.
Hardware frame rates have not been measured.

`--capture --4k` renders a settled, headless 4K frame to
`build/yofrankie-capture-3840x2160.bmp`. `python3 scripts/upgrade-frankie-materials.py` rebuilds
textures and `materials.tsv` from originals without re-exporting geometry.
Full `export-frankie.sh` also runs this material step and validates the output.

## Controls

| Input | Action |
| --- | --- |
| WASD / arrows | Camera-relative movement |
| Space; Space again | Jump; double jump |
| Hold Space after double jump | Glide while descending |
| E | Tail whip |
| C | Pick up nearby sheep |
| F | Throw carried sheep, or bones/acorns |
| Q / R; right mouse drag | Orbit camera |
| Right mouse drag vertically | Tilt camera |
| Page Up / Page Down | Move camera closer / farther |
| Escape | Pause / resume |
| R while paused | Restart current scene |
| Tab while paused | Main menu |
| M | Mute / unmute |
| F11 | Fullscreen / windowed |
| Arrows + Enter; mouse click | Navigate main menu / scene selection |

Apricots restore two health units, up to the original maximum of 13.
Acorns and bones provide ammunition. Boost pickups double the baseline running
speed (3 to 6 units/second) for 10 seconds. Death or a water/lava contact returns
Frankie to the scene's original spawn. The original island ending portal leads
to a completion screen. Scene choice, best collectible count, completion count,
and audio preference are saved atomically to `saves/yofrankie.save`.
Inventory and entity state are not saved across application restarts.

## Content and fidelity

The source assets were obtained from the [BlenderVR mirror of the original
Yo Frankie repository](https://github.com/BlenderVR/yofrankie).
The editable upstream files are retained in `third_party/yofrankie`.
See its `PROVENANCE.json` for the archive URL, retrieval date, and SHA-256.

| Area | Implemented / remaining |
| --- | --- |
| Original maps | 12 exported scenes: home island and lavaland; lighthouse; nut; two selectors; underworld; five mini-levels |
| Models and textures | Actual original geometry, UV textures, characters, collectibles, and placement; no replacement procedural campaign |
| Animation | 12 original Frankie action clips baked to 12 poses each; idle/run/hit clips for sheep, rams and rats baked to 8 poses each |
| Collision | Static triangle terrain, walls, step support, camera obstruction, and exact hazard surfaces |
| Movement | Running, double jump and simplified glide; original wall-running, ledge hanging/shimmy/climbing and glide pitch physics remain unported |
| Combat | Tail whip, ammunition projectiles, sheep carrying/throwing, simple enemy patrol/chase, damage and respawn; original AI/state-machine parity remains unverified |
| Portals | Authored blend/scene/marker destinations, generated selector portals, home-island completion; no invented campaign gate requirements |
| Level machinery | Imported at initial pose; moving platforms, switches, destructible scenery, and bespoke mini-game scripts remain unported |
| Audio | Original effects, forest ambience, cave music; mute toggle; full original positional audio behavior remains unported |
| Presentation | New title/pause/help/credits/scene menus and HUD; original BGE shaders, cutscenes, original menu composition and split-screen are not reproduced |
| Missing upstream content | `Untitled.tga`, `ivory.png`, and the nut level's `../levels2/level_mine.blend` destination are absent from this mirror; unresolved portal destinations are reported in-game |

Exporting every scene does **not** establish that every original challenge is
completable. A complete manual play-through and the remaining gameplay systems
are required before calling this a full faithful remake. All scenes are exposed
in the menu so current content can be explored without false unlock promises.

## Rebuild assets

The converted files in `assets/yofrankie` are already supplied. Re-export only
when changing upstream assets or the exporter:

```sh
BLENDER_LEGACY=/path/to/blender-2.79b/blender bash scripts/export-frankie.sh
```

Requires Blender **2.79b** and ImageMagick's `magick`. Modern Blender 5 discards
pre-2.50 animation data. The project-local converter, if installed, is at
`.deps/blender279/blender`; it does not replace system Blender.
Exporter failures use `--python-exit-code 1` so they fail the build.

The exporter changes coordinates from Blender Z-up to engine Y-up, triangulates
meshes, preserves scene positions/portal properties, converts textures to BMP
(maximum 4096 pixels per dimension, alpha retained), and bakes subdivided character animation poses.
Water uses a blue material instead of displaying the legacy shader's normal map
as an albedo texture. Legacy object hide tracks are disabled during enemy pose baking; actor bounds
are validated to prevent off-level poses. Original source files are not modified.

## Tests and limits

```sh
pixi run frankie-test
pixi run frankie-window-test  # Xvfb required; local display socket access
```

Tests cover control-driven movement and collection, double jump/glide/landing,
wall blocking, spring-box bounce, hazard surface proximity, damage immunity, healing, projectiles,
sheep carrying/throwing, save round-trips/rejection, every original spawn,
scene portal resolution, and the original ending trigger. Vulkan tests render
all 12 scenes with synchronization validation and a 60-frame simulation.
The window test injects SDL events into this application's own queue to check
movement, jumping, pause/resume, 1024x640 resize, audio setup, and presentation.

These are automated integration tests, **not** a full original-game play-through.
Rendering was tested with Mesa llvmpipe; hardware GPU performance is unmeasured.

## Attribution and redistribution

**YoFrankie! (c) 2008, Blender Foundation, www.blender.org**

Original media: **Creative Commons Attribution 3.0**. Original gameplay scripts:
**GPL version 2 or later**. The `frankie` gameplay port is GPL-2.0-or-later;
see `frankie/LICENSE`. Preserve `third_party/yofrankie/COPYING`, `CC-BY3.0`,
`GPL-2`, and original editable assets alongside converted media. In-game credits
attribute the original project and key contributors; upstream source retains
its own detailed notices. This does not change licensing of unrelated engine code.

Original contributors include Campbell Barton, Christopher Plush, Pablo Vazquez,
Moraes Junior, Claire Fitch, Dariusz Dawidowski, Frank Richter, Pablo Martin,
Brecht van Lommel, Margreet Riphagen, Ton Roosendaal, and the Apricot team.
See the [original project team page](https://apricot.blender.org/team/).

`bash scripts/package-frankie.sh` creates a source distribution containing the
converted assets, original editable files, code, and licenses. The engine-only
source archive excludes Yo Frankie media to keep the engine package independent.

Fullscreen verification on a desktop with a window manager: `bash scripts/run-vulkan.sh build/yo-frankie --window-test`. This briefly opens the game, checks fullscreen entry and F11 exit, exercises input, and opens the default audio device. The Xvfb regression uses `--windowed` because the virtual display has no window manager.
