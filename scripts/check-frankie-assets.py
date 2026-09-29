"""Validate converted asset references, binary layouts and actor-local bounds."""
from pathlib import Path
import math
import struct

root = Path('assets/yofrankie')
parts = list(root.glob('*.parts'))
assert parts, 'No converted Yo Frankie assets'
for manifest in parts:
    actor = manifest.name.startswith(('frankie_', 'ram_', 'rat_', 'sheep_cute_'))
    for line in manifest.read_text().splitlines():
        mesh, texture, color = line.split('\t')
        data = (root / mesh).read_bytes()
        magic, count = struct.unpack_from('<II', data)
        assert magic == 0x314D4659 and count > 0 and count % 3 == 0, mesh
        assert len(data) == 8 + count * 32, mesh
        assert len(color.split()) == 3, manifest
        if texture != '-':
            assert (root / texture).is_file(), texture
        if actor:
            for vertex in struct.iter_unpack('<8f', data[8:]):
                assert all(math.isfinite(v) for v in vertex), mesh
                # BGE object IPOs can hide actors thousands of units away.
                # Those tracks must never leak into skeletal animation baking.
                assert max(map(abs, vertex[:3])) < 10, ('Non-local actor pose', mesh)
assert len((root / 'levels.tsv').read_text().splitlines()) == 12
print('Yo Frankie asset manifests and animation bounds passed:', len(parts))

# Material assets are required by the HD runtime; normal maps remain linear data.
import json
report=json.loads((root/'material-upgrade.json').read_text())
assert report['upscaled'] is False
for row in (root/'materials.tsv').read_text().splitlines():
    albedo, normal, roughness, metallic, emission=row.split('\t')
    assert (root/albedo).exists(), albedo
    assert 0.045<=float(roughness)<=1 and 0<=float(metallic)<=1 and float(emission)>=0
    if normal!='-':assert (root/normal).exists(),normal
for material in report['materials']:
    data=(root/material['albedo']).read_bytes()
    w,h=struct.unpack_from('<ii',data,18)
    assert (w,abs(h))==(material['width'],material['height'])
    assert max(w,abs(h))<=4096
print('HD material references, native dimensions and normal maps passed')
