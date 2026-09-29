"""Inventory existing exported content for a realistic remake; no assets modified."""
from pathlib import Path
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/yofrankie'
DEST = ROOT / 'docs/frankie-remake-inventory.json'


def main():
    scenes = []
    for line in (ASSETS / 'levels.tsv').read_text().splitlines():
        key, source, scene, spawn = line.split('\t')
        scenes.append(dict(id=key, source=source, scene=scene,
                           spawn=[float(v) for v in spawn.split()]))
    scene_ids = {scene['id'] for scene in scenes}
    manifests = []
    meshes = set()
    textures = set()
    for path in sorted(ASSETS.glob('*.parts')):
        parts = []
        for line in path.read_text().splitlines():
            mesh, texture, color = line.split('\t')
            mesh_path = ASSETS / mesh
            with mesh_path.open('rb') as stream:
                magic, vertices = struct.unpack('<II', stream.read(8))
            if magic != 0x314D4659 or vertices % 3 or mesh_path.stat().st_size != 8 + vertices * 32:
                raise ValueError(f'Invalid mesh: {mesh}')
            if texture != '-':
                if not (ASSETS / texture).is_file():
                    raise FileNotFoundError(texture)
                textures.add(texture)
            meshes.add(mesh)
            parts.append(dict(mesh=mesh, albedo=None if texture == '-' else texture,
                              color=[float(v) for v in color.split()], triangles=vertices // 3))
        manifests.append(dict(id=path.stem, kind='environment' if path.stem in scene_ids else 'actor_pose_or_prop',
                              replacement_status='original_art', parts=parts))
    materials = []
    for line in (ASSETS / 'materials.tsv').read_text().splitlines():
        albedo, normal, roughness, metallic, emission = line.split('\t')
        materials.append(dict(albedo=albedo, normal=None if normal == '-' else normal,
                              roughness=float(roughness), metallic=float(metallic), emission=float(emission),
                              replacement_status='original_art'))
    report = dict(schema_version=1, scope='Exported runtime content; poses are not unique character models. Source blend objects are not individually inventoried.',
                  counts=dict(scenes=len(scenes), manifests=len(manifests), mesh_files=len(meshes),
                              referenced_albedos=len(textures), materials=len(materials)),
                  scenes=scenes, materials=materials, manifests=manifests)
    DEST.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['counts'], indent=2))
    print(DEST)


if __name__ == '__main__':
    main()
