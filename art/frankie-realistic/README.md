# Blender authoring library

Generated with Blender 5.2.1 LTS. This is a procedural remaster of the original
YoFrankie! media, retaining character shapes and baked mesh animation poses.

- The twelve `level_*.blend` / `minilevel_*.blend` files contain environments,
  actor/prop placement previews, materials, sun and a preview camera.
- `frankie_*.blend`, `ram_*.blend`, `rat_*.blend`, and `sheep_cute_*.blend` contain
  action poses, arranged as named collections. Only the first pose is visible.
- `props.blend` contains the remaining exported prefabs in named collections.
- Textures are shared through relative paths into `../../assets/yofrankie-realistic/`.
  Keep both directories together when moving this library.

Open a file directly in Blender. Export saved geometry edits with:

```sh
bash scripts/remake-frankie.sh --export-blend art/frankie-realistic/level_1_home__island.blend
python3 scripts/check-frankie-realistic.py
```

Full regeneration overwrites generated files. Save manual work separately first.
See [workflow and limitations](../../docs/FRANKIE_REALISTIC_REMAKE.md).

YoFrankie! (c) 2008 Blender Foundation, www.blender.org. Original and derivative
media are attributed under CC-BY 3.0; see
[attribution](../../assets/yofrankie-realistic/ATTRIBUTION.txt) and
[license](../../assets/yofrankie-realistic/CC-BY3.0).
