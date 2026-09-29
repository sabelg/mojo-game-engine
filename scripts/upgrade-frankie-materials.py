"""Restore source-resolution albedo and original tangent-space normal maps.
No invented upscaling: images retain native detail, capped at 4096 per side.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess

root=Path('third_party/yofrankie')
out=Path('assets/yofrankie')
safe=lambda name: re.sub(r'[^a-zA-Z0-9_-]', '_', name)
sources={}
for path in sorted(root.rglob('*')):
    if path.suffix.lower() in {'.png','.jpg','.jpeg','.tga'}:
        sources.setdefault(safe(path.name)+'.bmp',path)
used=set()
for manifest in out.glob('*.parts'):
    for line in manifest.read_text().splitlines():
        used.add(line.split('\t')[1])
rows=[]
audit=[]
for name in sorted(used-{'-'}):
    source=sources.get(name)
    if not source:raise RuntimeError('No editable source for '+name)
    subprocess.run(['magick',str(source),'-resize','4096x4096>','BMP:'+str(out/name)],check=True)
    normal=None
    if '_col' in source.stem:
        candidate=source.with_name(source.name.replace('_col','_nor'))
        if candidate.exists():normal=candidate
    normal_name='-'
    if normal:
        normal_name=safe(normal.name)+'.bmp'
        subprocess.run(['magick',str(normal),'-resize','4096x4096>','BMP:'+str(out/normal_name)],check=True)
    low=source.name.lower()
    roughness=0.86
    metallic=0.0
    emission=0.0
    if 'rock' in low or 'stone' in low:roughness=0.78
    if 'bark' in low or 'wood' in low or 'log' in low:roughness=0.9
    if 'skin' in low or 'char_' in low:roughness=0.8
    if 'rust' in low:roughness=0.65;metallic=0.25
    if 'lava' in low:emission=0.7
    rows.append(f'{name}\t{normal_name}\t{roughness}\t{metallic}\t{emission}')
    dims=subprocess.check_output(['magick','identify','-format','%w %h',str(out/name)],text=True).split()
    audit.append({'albedo':name,'source':str(source),'width':int(dims[0]),'height':int(dims[1]),'normal':normal_name,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
(out/'materials.tsv').write_text('\n'.join(rows)+'\n')
(out/'material-upgrade.json').write_text(json.dumps({'max_texture_dimension':4096,'upscaled':False,'materials':audit},indent=2)+'\n')
print('Restored',len(rows),'source textures;',sum(a['normal']!='-' for a in audit),'normal maps;',sum(max(a['width'],a['height'])>1024 for a in audit),'textures above the old 1024 cap')
