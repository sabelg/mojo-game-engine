"""Named joint/morph channels preserve typed arrays and actual USD skeleton poses."""
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('session',ROOT/'scripts/usd-session.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
base=ROOT/'.deps/blender-source';sdk=base/'lib/linux_arm64';binary=ROOT/'build/usd-pose-oracle'
subprocess.run([str(base/'compiler/usr/bin/g++-14'),'-std=c++17','-O1',str(ROOT/'tests/usd_pose_oracle.cc'),
 '-I'+str(sdk/'usd/include'),'-I'+str(sdk/'tbb/include'),'-I'+str(sdk/'python/include/python3.13'),
 '-L'+str(base/'build/bin/lib'),'-Wl,-rpath,'+str(base/'build/bin/lib'),'-Wl,-rpath-link,'+str(base/'build/bin/lib'),
 '-lusd_ms','-ltbb',str(sdk/'python/lib/libpython3.13.a'),'-ldl','-lpthread','-lm','-lutil','-o',str(binary)],check=True)

IDENTITY='((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,0,0,1))'
CHILD='((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,1,0,1))'
def pose(source,time):return json.loads(subprocess.check_output([str(binary),str(source),str(time)],text=True))
def values(stage,path,name,time):return [c['value'] for c in stage.request('curves',path=path,time=time)['curves'] if c['name']==name]
def rejected(stage,op,**fields):
    before=stage.request('snapshot',time=5)
    try:stage.request(op,**fields)
    except ValueError:pass
    else:raise AssertionError('Accepted unsupported '+op)
    assert stage.request('snapshot',time=5)==before

with tempfile.TemporaryDirectory(prefix='usd-skel-authoring-',dir=ROOT/'build') as tmp:
    root=Path(tmp);asset=root/'rig.usda';source=root/'source.usda';workspace=root/'workspace'
    asset.write_text('''#usda 1.0
(defaultPrim="Rig")
def SkelRoot "Rig" {
 def Skeleton "Skeleton" (prepend apiSchemas=["SkelBindingAPI"]) {
  uniform token[] joints=["root","root/child"]
  uniform matrix4d[] bindTransforms=['''+IDENTITY+','+CHILD+''']
  uniform matrix4d[] restTransforms=['''+IDENTITY+','+CHILD+''']
  rel skel:animationSource=</Rig/Animation>
 }
 def SkelAnimation "Animation" {
  uniform token[] joints=["root","root/child"]
  float3[] translations.timeSamples={0:[(0,0,0),(0,1,0)],10:[(2,0,0),(0,1,0)]}
  quatf[] rotations.timeSamples={0:[(1,0,0,0),(1,0,0,0)],10:[(1,0,0,0),(0,0,0,1)]}
  half3[] scales.timeSamples={0:[(1,1,1),(1,1,1)],10:[(1,1,1),(1,1,1)]}
  uniform token[] blendShapes=["Smile"]
  float[] blendShapeWeights.timeSamples={0:[0],10:[1]}
 }
}
''')
    source.write_text('''#usda 1.0
(startTimeCode=0
 endTimeCode=30
 timeCodesPerSecond=24)
def SkelRoot "A" (prepend references=@rig.usda@</Rig> (offset=10;scale=2)) {}
def SkelRoot "B" (prepend references=@rig.usda@</Rig>) {}
''')
    originals={p:p.read_bytes() for p in [asset,source]};path='/A/Animation'
    with api.StageSession() as stage:
        stage.request('open',source=str(source));stage.request('begin_source_editing')
        target=next(t for t in stage.request('source_targets',path=path)['targets'] if t['source']==str(asset))
        stage.request('select_source_layer',name=target['name'],context=path,node=target['node'])
        rows=stage.request('curves',path=path,time=20)['curves']
        assert any(c['label']=='translations[root/child].y' for c in rows)
        assert any(c['label']=='blendShapeWeights[Smile]' for c in rows)
        stage.request('set_channel',path=path,name='translations',channel=0,value=3,time=20)
        assert values(stage,path,'translations',20)==[3,0,0,0,1,0]
        stage.request('set_channel',path=path,name='rotations',channel=4,value=0,time=20)
        q=values(stage,path,'rotations',20)[4:];assert math.isclose(q[2],math.sqrt(.5),abs_tol=1e-6) and math.isclose(q[3],math.sqrt(.5),abs_tol=1e-6),q
        stage.request('set_channel',path=path,name='scales',channel=4,value=2,time=20)
        assert values(stage,path,'scales',20)==[1,1,1,1,2,1]
        stage.request('set_channel',path=path,name='blendShapeWeights',channel=0,value=.75,time=20)
        assert values(stage,'/B/Animation','blendShapeWeights',5)==[.75]
        rejected(stage,'set_channel',path=path,name='scales',channel=0,value=1e10,time=20)
        rejected(stage,'attribute',path=path,name='rotations',value=[0]*8,time=20)
        stage.request('copy_key',path=path,name='translations',from_time=20,time=23)
        stage.request('move_key',path=path,name='translations',from_time=23,time=25)
        stage.request('clear_sample',path=path,name='translations',time=25);stage.request('undo')
        stage.request('save_workspace',destination=str(workspace))
        stage.request('save',destination=str(root/'delivery.usda'));stage.request('package',destination=str(root/'delivery.usdz'))
    # Evaluate edited hierarchy through an independent USD Skel query.
    for destination in [root/'delivery.usda',root/'delivery.usdz']:
        actual={p['path']:p for p in pose(destination,20)};a=actual['/A/Skeleton']
        assert math.isclose(a['joint_matrices'][0][12],3,abs_tol=1e-6)
        assert math.isclose(a['joint_matrices'][1][12],3,abs_tol=1e-6)
        assert math.isclose(a['joint_matrices'][1][13],1,abs_tol=1e-6)
        assert math.isclose(a['joint_matrices'][1][0],0,abs_tol=1e-6)
        assert math.isclose(a['joint_matrices'][1][1],1,abs_tol=1e-6)
        assert math.isclose(a['joint_matrices'][1][4],-2,abs_tol=1e-6)
        assert a['weights']==[.75]
        between={p['path']:p for p in pose(destination,15)}['/A/Skeleton']
        assert math.isclose(between['joint_matrices'][0][12],1.5,abs_tol=1e-6)
        assert math.isclose(between['weights'][0],.375,abs_tol=1e-6)
    with api.StageSession() as stage:
        stage.request('open_workspace',source=str(workspace));assert values(stage,path,'translations',25)==[3,0,0,0,1,0]
    for p,data in originals.items():assert p.read_bytes()==data

print('Skeleton/morph authoring passed: named typed arrays, sibling preservation, '
      'per-joint slerp/normalization, half precision, mapped tuple keys, independent '
      'USD Skel joint poses and weights at/between keys, workspace/USD/USDZ restart')
