# Yo Frankie — stylized presentation pass

The requested quality reference is [Donkey Kong Bananza](https://www.nintendo.com/us/gaming-systems/switch-2/featured-games/donkey-kong-bananza/).
This pass moves the existing game toward colorful, readable platformer presentation.
It does **not** establish equivalent production quality, and it does not implement
Bananza's terrain destruction or replace Frankie's original character design.

![Actual Mojo/Vulkan capture](yo-frankie-polished.png)

## Play

```sh
pixi run play
# Already built:
bash scripts/run-vulkan.sh build/yo-frankie --polished
```

`--realistic` remains an alias for the same asset pack. `pixi run frankie` loads
the original art. Right mouse drag now orbits and tilts the camera; Page Up/Down
changes follow distance. Existing movement/combat controls are retained.

## Implemented

- Rebalanced terrain, bark and stone colors and reduced excessive surface noise.
  New curved broad-leaf plants and rounded flower petals are authored in Blender
  for all 12 scenes. Grass uses upward-facing shading normals to avoid black spikes.
  Fur fibers follow the skin normals, and the old bright stippled tail colors
  are replaced with a continuous warm fur tone while retaining the alpha mask.
- Scene-specific hemisphere, sunlight and haze colors distinguish outdoor,
  underground and volcanic levels. A subtle rim contribution helps silhouettes.
- Vulkan interpolates adjacent baked mesh poses for Frankie and enemies in both
  color and shadow passes. All 888 adjacent animated part pairs have compatible
  vertex counts; incompatible handles/layouts are rejected by the backend.
  This is pose interpolation, not a new skeletal animation system.
- Camera smoothing uses elapsed time, includes motion look-ahead and retains
  collision checks. The closer default framing and slightly larger visual model
  make Frankie easier to read; gameplay collision dimensions remain unchanged.
- Landing squash, jump/footstep dust, tail-whip bursts, pickup sparkles, pickup
  counter bounce and restrained damage shake provide action feedback. Visual
  particles are capped at 96 and freeze while paused.
- A smooth-alpha Liberation Sans font atlas, rounded panels, clear health pips,
  separated ammunition counters, scene labels and temporary control hints replace
  the remaster's bitmap HUD. The font license ships with the atlas.

The pack contains **1,181 runtime meshes, 64 surface materials and 192 surface
texture maps**, plus the UI font atlas. The 34 editable Blender files remain in
`art/frankie-realistic/`; runtime art remains in `assets/yofrankie-realistic/`.
See [authoring and geometry export](FRANKIE_REALISTIC_REMAKE.md).

## Verification and limits

The engine suite includes exact-image comparison of a half-blended GPU pose
against the equivalent static geometry, including shadows. It also checks stale
morph targets, incompatible mesh layouts, scene lighting, smooth font rendering,
round UI shapes and the existing ORM/normal map paths. Gameplay tests cover
feedback lifetime, pause behavior, particle limits and the existing game systems.

```sh
pixi run vulkan-test
pixi run frankie-realistic-test
```

The latter runs asset validation, gameplay tests, a 60-frame smoke test, every
scene, and a scripted jump/double-jump/attack/pickup/damage sequence. These are
software Vulkan checks, not measured hardware performance or a full manual
campaign play-through.

The engine suite, gameplay/feedback tests, full scene tour and scripted action
sequence passed with zero Vulkan validation errors on Mesa llvmpipe. The final
camera framing was also checked across all 12 scenes.

The remaining quality gap includes newly authored character models and rigs,
more expressive animations, bespoke environment composition, richer audio and
interaction, complete gameplay systems, anti-aliasing/post-processing work, and
hardware profiling. The current version still uses the original base models,
routes and gameplay data.

To rebuild the shared UI atlas with the installed Liberation fonts:

```sh
python3 scripts/build-frankie-font.py
```
