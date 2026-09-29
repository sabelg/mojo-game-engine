"""Validate every remaster reference and preserve the original gameplay contract."""
from pathlib import Path
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/yofrankie'
OUT = ROOT / 'assets/yofrankie-realistic'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    report = json.loads((OUT / 'remake-report.json').read_text())
    levels = [line.split('\t')[0] for line in (SOURCE / 'levels.tsv').read_text().splitlines()]
    require({s['id'] for s in report['scenes']} == set(levels), 'Incomplete scene coverage')
    for scene in report['scenes']:
        require((ROOT / scene['blend']).is_file(), 'Missing editable scene: ' + scene['id'])
    for path in SOURCE.iterdir():
        if path.suffix in ('.collision', '.hazards', '.entities', '.triggers', '.markers') or path.name == 'levels.tsv':
            require((OUT / path.name).read_bytes() == path.read_bytes(), 'Gameplay data changed: ' + path.name)
    materials = {}
    textures = set()
    for line in (OUT / 'materials.tsv').read_text().splitlines():
        albedo, normal, roughness, metallic, emission, orm = line.split('\t')
        require(albedo not in materials, 'Duplicate material: ' + albedo)
        require(.045 <= float(roughness) <= 1 and 0 <= float(metallic) <= 1 and float(emission) >= 0, 'Invalid material factors')
        dimensions = []
        for name in (albedo, normal, orm):
            data = (OUT / name).read_bytes()
            require(data[:2] == b'BM', name + ': invalid BMP')
            w, h = struct.unpack_from('<ii', data, 18)
            require(0 < w <= 4096 and 0 < h <= 4096, name + ': invalid dimensions')
            offset = struct.unpack_from('<I', data, 10)[0]
            require(len(data) == offset + w * h * 4, name + ': truncated pixels')
            dimensions.append((w, h))
            textures.add(name)
        require(len(set(dimensions)) == 1, albedo + ': map dimensions differ')
        materials[albedo] = line
    require(len(textures) <= 256, 'Runtime texture budget exceeded')
    triangles = 0
    mesh_names = set()
    for source in SOURCE.glob('*.parts'):
        manifest = OUT / source.name
        require(manifest.is_file(), 'Missing manifest: ' + source.name)
        for line in manifest.read_text().splitlines():
            mesh, texture, color = line.split('\t')
            require(texture == '-' or texture in materials, 'Unknown material: ' + texture)
            require(len(color.split()) == 3, 'Invalid color')
            data = (OUT / mesh).read_bytes()
            magic, count = struct.unpack_from('<II', data)
            require(magic == 0x314d4659 and count > 0 and count % 3 == 0, 'Invalid mesh header: ' + mesh)
            require(len(data) == 8 + count * 32, 'Invalid mesh length: ' + mesh)
            actor = manifest.stem.startswith(('frankie_', 'ram_', 'rat_', 'sheep_cute_'))
            for vertex in struct.iter_unpack('<8f', data[8:]):
                require(all(math.isfinite(v) for v in vertex), 'Nonfinite vertex: ' + mesh)
                require(.8 < sum(v * v for v in vertex[3:6]) < 1.2, 'Invalid normal: ' + mesh)
                if actor: require(max(map(abs, vertex[:3])) < 10, 'Nonlocal actor: ' + mesh)
            triangles += count // 3
            mesh_names.add(mesh)
    require(mesh_names == {m['file'] for m in report['meshes']}, 'Mesh report is incomplete')
    print(f'Remaster passed: {len(levels)} scenes, {len(mesh_names)} meshes, {len(materials)} materials, {len(textures)} textures, {triangles:,} triangles across all poses/scenes')
    print('Collision, hazards, entities, portals and spawn data match the original export.')


if __name__ == '__main__':
    main()
