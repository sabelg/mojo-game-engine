# Yo Frankie realistic remake — production brief

Status: an implemented **stylized remaster** on the existing Mojo/Vulkan engine.
See the subsequent [presentation and animation pass](FRANKIE_POLISH.md).
Blender 5.2.1 LTS produced editable files for all 12 scenes and 22 prop/animation
libraries. Original character anatomy, environment silhouettes and baked poses
remain; this is not a fully resculpted photorealistic remake.

## Play and inspect

![Mojo/Vulkan remaster capture](yo-frankie-polished.png)

```sh
pixi run play                 # procedural remaster
pixi run frankie              # original art
pixi run frankie-realistic-test
```

Open `art/frankie-realistic/level_1_home__island.blend` in Blender to inspect the
home island. Every scene includes placed actors/pickups, a preview camera, sun,
and editable node materials. The other files contain all baked character poses
and props; pose collections are named after their runtime manifest, with only
one collection initially visible. These are baked mesh poses, not new armature rigs.

Generated runtime art is in `assets/yofrankie-realistic/`. Original files in
`assets/yofrankie/` and `third_party/yofrankie/` are preserved. The remaster uses
original gameplay metadata, collision, portals and audio. Geometry edits do not
automatically update gameplay collision.

## Implemented art pass

- Reconstructed and re-exported all 794 original mesh files through modern
  Blender, removing zero-area triangles before normal generation.
- Reauthored procedural stone, soil, grass and bark tiles, with metre-scaled
  terrain UVs. Atlas-based characters and props retain their original color
  layouts with added surface detail. Signs, sky graphics and effects retain
  their authored imagery.
- Added short geometric fur fibers to character/tail surfaces and seeded grass
  geometry to every scene. These are lightweight static meshes carried by the
  existing baked poses; there is no groom simulation or wind animation.
- Added 64 material sets: base color, tangent-space normal, and packed linear
  occlusion/roughness/metallic (ORM). Original alpha masks remain supported.
- Extended the Vulkan renderer with an ORM texture binding and full-strength
  remaster normals; the five-column original material format still works.

Textures retain native dimensions up to a configurable cap (1024 by default).
Procedural detail is synthesized, not recovered photographic detail. Occlusion
maps contain only procedural micro-occlusion, not a scene-wide light bake.
The runtime does not reproduce Blender Cycles lighting or render settings.

## Rebuild and edit

The installed Blender reports 5.2.1 LTS. The [official release page](https://www.blender.org/releases/) listed 5.2.2
when checked, but the download server returned HTTP 403. Override the executable
with `BLENDER_MODERN=/path/to/blender` to use another compatible Blender 5 build.

The system Blender needed project-local Python dependencies:

```sh
uv pip install --python /usr/bin/python3 --target .deps/blender-python numpy cattrs requests
bash scripts/remake-frankie.sh
python3 scripts/check-frankie-realistic.py
```

`bash scripts/remake-frankie.sh --texture-size 2048 --grass-budget 12000` changes
the authoring budgets. Full regeneration overwrites the generated `.blend` files
and runtime pack, so preserve manual edits in separate copies before regenerating.

To export saved geometry edits without regenerating the art:

```sh
bash scripts/remake-frankie.sh --export-blend art/frankie-realistic/level_1_home__island.blend
python3 scripts/check-frankie-realistic.py
```

Edit the `Environment` collection for levels or the named pose collections for
characters. The exporter applies transforms and evaluated modifiers, preserves
UVs/normals, and supports one registered runtime material per object. Split
multi-material objects before export. Material nodes are authoring previews:
new shader networks must be baked to BMP maps and registered in `materials.tsv`
before runtime export. Actor placement edits in level `.blend` files are previews;
the game continues to use its original `.entities` files.

The generator is deterministic by asset name. Exported topology may change only
by removing zero-area legacy triangles and adding explicitly reported detail.
`remake-report.json` records per-mesh treatment, triangle counts, source texture
hashes and scene coverage. Original attribution and licenses accompany the pack.

The sections below remain production targets for a fully rebuilt realistic game,
beyond this procedural pass.

## Validation of this pass

The completed pack has **1,181 mesh files, 64 materials and 192 surface texture maps**,
with 34 editable Blender files (12 scenes and 22 prop/action libraries).
Its runtime art occupies about 866 MiB; the Blender library about 255 MiB.
The 6.35 million triangles in the manifest total include every animation pose
and every scene; they are not all drawn in a frame.

Asset-reference, finite-vertex, normal, actor-bound and material-budget checks
pass. Gameplay metadata matches the original export byte for byte. The original
gameplay/save tests, engine suite, and isolated ORM image regressions pass.
The 60-frame remaster smoke test and full 12-scene Vulkan tour report zero
validation errors using Mesa llvmpipe. Hardware frame rates are unmeasured.

The home island was reopened and exported from its saved Blender file; every
nondegenerate original triangle position survived that round trip exactly.
This does not establish full campaign gameplay parity or test every possible
manual Blender edit. The original gameplay limitations still apply.

## Art direction

Keep Frankie's recognizable silhouette, expressive face, tail and gliding membrane,
with believable fur, anatomy, eyes and movement. Preserve readable platforming
distances and collectible silhouettes. Use natural materials, weathering and
consistent scale throughout the environments. Realism should not obscure hazards
or make traversable surfaces hard to recognize.

Produce a home-island playable sample before replacing the entire campaign:
Frankie, one sheep, one tree, rock/cliff kit, ground materials, water and collectibles.
Validate appearance in motion and on the intended hardware before mass production.

## Replacement deliverables

| Group | Required work |
| --- | --- |
| Frankie | Sculpt, retopology, UVs, fur cards or groom, eyes, teeth, membrane, rig, animation, collision and LODs |
| Sheep, ram, rat | Separate anatomical models, wool/fur, rigs, animation and readable attack poses |
| Collectibles and interactables | Acorn, apricot, bone, spring box and every exported prop; retain gameplay dimensions |
| Vegetation | Bark and leaf materials, tree/branch/root kits, foliage, wind response and LODs |
| Terrain and architecture | Cliffs, ground, cave, volcanic and building kits; preserve original routes and collision alignment |
| Materials | Authored base color, normal, roughness, metallic and optional AO/height; emission for lava/effects |
| Presentation | Water, atmosphere, particles, lighting, audio placement and UI readability |

The machine-readable [inventory](frankie-remake-inventory.json) enumerates every
exported parts manifest and its mesh/material references. Regenerate it with
`python3 scripts/inventory-frankie-remake.py`. Baked animation poses count as
separate manifests, not separate characters. An additional Blender source-object
audit is needed to split combined environment meshes into reusable authored kits.

## Scene coverage

These are proposed visual treatments, not claims about completed new scenarios.
Original layouts and authored portal destinations remain the gameplay baseline.

| Exported scene | Proposed realistic treatment |
| --- | --- |
| Home island | Coastal woodland, weathered tree home, exposed roots, mossy stone, clear water |
| Home lavaland | Fractured basalt, cooled lava crust, glowing fissures, ash and heat haze |
| Lighthouse island | Salt-weathered masonry, coastal grass, surf and maritime haze |
| Nut level | Woodland rock and timber kit, readable vertical routes and collectible placement |
| Selector island | Natural hub with clear paths, landmarks and legible destination signs |
| Other selector island | Related hub materials with distinct landmarks and lighting |
| Underworld | Damp cave stone, mineral seams, localized mist and guided lighting |
| Demo arena 3 | Weathered arena surfaces with clear combat sightlines |
| Lava Falls | Volcanic cliffs, flowing emissive lava and readable safe ledges |
| Ratpack | Worn ground and cover materials; keep enemies visible |
| Release Demo | Shared woodland kit with consistent scale and material detail |
| The Arena | Cohesive stone/ground kit with clear boundaries and hazards |

## Rendering and integration

The current Vulkan renderer has normal maps, textured and scalar metallic/roughness,
directional shadows and tone mapping. Further realism requires skeletal animation,
broader asset import, animated foliage and lighting improvements. Ray tracing, temporal upscaling, groom rendering and virtualized
geometry are not implemented here. Choose technologies against measured hardware
budgets rather than assuming every feature is necessary.

Author editable source models and lossless texture masters. Proposed interchange:
glTF for meshes/materials/animation, with engine-specific extensions handled by
the selected importer. Base color is color data; normal/roughness/metallic are
linear data. Texture resolution and geometry budgets depend on screen coverage,
memory and the target GPU. Generated concept images do not replace rigged 3D assets
or physically consistent material maps.

## Acceptance

Each replacement must pass material/mesh reference validation, animation review,
collision alignment, scene traversal and portal checks. Capture matched before/after
views and measure GPU time, frame pacing and memory on target hardware. Complete
an actual play-through of all scenes; existing automated tests do not establish
campaign completeness. Preserve original attribution and record provenance for
every new asset. Track original gameplay gaps separately in [the port notes](YO_FRANKIE.md).
