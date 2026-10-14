"""Independent authored Atlas hierarchy -> USD -> native stage and Blender recook."""
import importlib.util,json,math,tempfile,hashlib
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
exporter=module('usd_export','export-usd.py');cook=module('cook','cook-assets.py');session=module('session','usd-session.py')
work=Path(tempfile.mkdtemp(prefix='usd-export-',dir=ROOT/'build'))
obj=work/'source.obj';obj.write_text('v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0 0\nvt 1 0\nvt 0 1\nf 1/1 2/2 3/3\n')
cook.cook(obj,work/'assets','tri')
Image.new('RGBA',(2,2),(128,64,32,255)).save(work/'assets/color.bmp')
Image.new('RGBA',(2,2),(128,128,255,255)).save(work/'assets/normal.bmp')
Image.new('RGBA',(2,2),(255,128,64,255)).save(work/'assets/orm.bmp')
manifest=work/'assets/tri-assets.atlas'
manifest.write_text(manifest.read_text()+'material\tpaint\tcolor.bmp\t.8\t.6\t.4\t.4\t.2\t0\tnormal.bmp\torm.bmp\t10497\t10497\t9987\t9729\t10497\t10497\t9987\t9729\t10497\t10497\t9987\t9729\t1\t.5\n')
def row(i,name,parent,identity,asset='',mat='',position=(0,0,0),rotation=(0,0,0,1),scale=(1,1,1),color=(.2,.3,.4)):
 return '\t'.join(map(str,[i,name,parent,-1,1,*position,*rotation,*scale,*color,.35,.6,0,-1,asset,mat,identity]))
scene=work/'authored.scene'
scene.write_text('MOJO_SCENE_3\n'+row(0,'Parent',-1,'parent-id',position=(10,20,30),rotation=(0,0,math.sqrt(.5),math.sqrt(.5)))+'\n'+row(1,'Child',0,'child-id','tri/mesh','paint',position=(2,0,0))+'\n'+row(2,'Reuse',-1,'reuse-id','tri/mesh','paint',position=(-3,0,0))+'\n'+row(3,'Cube',-1,'cube-id','atlas/cube',scale=(2,1,3))+'\n')
before=scene.read_bytes();destination=work/'exported'
report=exporter.export_scene(scene,[manifest],destination)
assert report['geometry_definitions']==2 and report['mesh_occurrences']==3,report
assert scene.read_bytes()==before
with session.StageSession() as stage:
 snap=stage.request('open',source=str(destination/'scene.usda'))
 prims={p.get('stable_id'):p for p in snap['prims'] if p.get('stable_id')}
 assert set(prims)=={'parent-id','child-id','reuse-id','cube-id'},prims
 world=prims['child-id']['world_transform_row_major']
 assert all(abs(world[i]-v)<1e-8 for i,v in zip([12,13,14],[10,22,30])),world
# The delivery must not depend on its originating textures or meshes.
for path in (work/'assets').rglob('*'):
 if path.is_file():path.rename(path.with_name(path.name+'.hidden'))
assert cook.cook(destination/'scene.usda',work/'roundtrip','roundtrip')=='cooked'
assert json.loads((work/'roundtrip/roundtrip-source.json').read_text())['stage']['meshes']==3
try:exporter.export_scene(scene,[],destination)
except ValueError as error:assert 'already exists' in str(error)
else:raise AssertionError('Existing delivery was overwritten')
assert before==scene.read_bytes()
# Unsupported sources fail without publishing a directory.
bad=work/'bad.scene';bad.write_text('MOJO_SCENE_3\n'+row(0,'Unknown',-1,'bad-id','missing/mesh')+'\n')
try:exporter.export_scene(bad,[],work/'bad-delivery')
except ValueError:pass
else:raise AssertionError('Missing asset accepted')
assert not (work/'bad-delivery').exists()
print('USD snapshot export passed: hierarchy, transforms, persistent IDs, shared geometry, portable textures, native reopen and Blender recook:',work)
