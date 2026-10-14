"""Typed channel edits preserve transform stacks, tuples, offsets and precision."""
import importlib.util
import math
from pathlib import Path
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('session',ROOT/'scripts/usd-session.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)

def channels(stage,path,name,time=1.25):
    return [c for c in stage.request('curves',path=path,time=time)['curves'] if c['name']==name]

def tuple_value(stage,path,name,time=1.25):return [c['value'] for c in channels(stage,path,name,time)]

def rejected(stage,op,**fields):
    before=stage.request('snapshot',time=1.25)
    try:stage.request(op,**fields)
    except ValueError:pass
    else:raise AssertionError('Accepted invalid '+op)
    assert stage.request('snapshot',time=1.25)==before,'Rejected edit changed current state'

with tempfile.TemporaryDirectory(prefix='usd-typed-curves-',dir=ROOT/'build') as tmp:
    root=Path(tmp);asset=root/'asset.usda';source=root/'source.usda';workspace=root/'workspace'
    asset.write_text('''#usda 1.0
(defaultPrim="Rig")
def Xform "Rig" {
 double3 xformOp:translate.timeSamples={0:(0,10,20),10:(10,30,40)}
 double3 xformOp:translate:pivot=(2,3,4)
 float3 xformOp:rotateXYZ=(0,0,0)
 float3 xformOp:scale=(1,1,1)
 uniform token[] xformOpOrder=["!resetXformStack!","xformOp:translate","xformOp:translate:pivot","xformOp:rotateXYZ","xformOp:scale","!invert!xformOp:translate:pivot"]
 def Xform "Orient" {
  quatd xformOp:orient.timeSamples={0:(1,0,0,0),10:(0,0,0,1)}
  uniform token[] xformOpOrder=["xformOp:orient"]
 }
 def Camera "Camera" {
  float focalLength.timeSamples={0:40,10:80}
  float2 clippingRange=(0.1,100)
  uniform float constant=7
 }
}
''')
    source.write_text('''#usda 1.0
(startTimeCode=0
 endTimeCode=30
 timeCodesPerSecond=24)
def Xform "World" {
 double3 xformOp:translate=(100,0,0)
 uniform token[] xformOpOrder=["xformOp:translate"]
 def Xform "A" (prepend references=@asset.usda@</Rig> (offset=10;scale=2)) {}
def Xform "B" (prepend references=@asset.usda@</Rig>) {}
def Xform "Proxy" (prepend references=@asset.usda@</Rig>;instanceable=true) {}
}
''')
    originals={p:p.read_bytes() for p in [asset,source]}
    with api.StageSession() as stage:
        stage.request('open',source=str(source))
        assert [c['label'] for c in channels(stage,'/World/A','xformOp:translate')]==['xformOp:translate[x]','xformOp:translate[y]','xformOp:translate[z]']
        # Local override preserves other channels and inherited endpoint keys.
        stage.request('set_channel',path='/World/B',name='xformOp:translate',channel=0,value=5.25,time=1.25)
        assert tuple_value(stage,'/World/B','xformOp:translate')==[5.25,12.5,22.5]
        assert [k['time'] for k in channels(stage,'/World/B','xformOp:translate')[0]['keys']]==[0,1.25,10]
        stage.request('copy_key',path='/World/B',name='xformOp:translate',from_time=1.25,time=2.75)
        assert tuple_value(stage,'/World/B','xformOp:translate',2.75)==[5.25,12.5,22.5]
        rejected(stage,'move_key',path='/World/B',name='xformOp:translate',from_time=1.25,time=2.75)
        stage.request('move_key',path='/World/B',name='xformOp:translate',from_time=2.75,time=3.5)
        assert [k['time'] for k in channels(stage,'/World/B','xformOp:translate')[0]['keys']]==[0,1.25,3.5,10]
        stage.request('clear_sample',path='/World/B',name='xformOp:translate',time=3.5)
        stage.request('undo');assert tuple_value(stage,'/World/B','xformOp:translate',3.5)==[5.25,12.5,22.5]
        stage.request('redo')
        for fields in [dict(channel=.5,value=2),dict(channel=3,value=2),dict(channel=0,value=1e100)]:
            name='xformOp:scale' if fields['value']==1e100 else 'xformOp:translate'
            rejected(stage,'set_channel',path='/World/B',name=name,time=1.25,**fields)
        rejected(stage,'set_channel',path='/World/Proxy/Orient',name='xformOp:orient',channel=0,value=1,time=0)
        rejected(stage,'set_channel',path='/World/B/Camera',name='constant',channel=0,value=1,time=0)
        # Owned reference edits use source tuples even when a stronger tuple masks them.
        stage.request('begin_source_editing')
        targets=stage.request('source_targets',path='/World/A')['targets']
        target=next(t for t in targets if t['source']==str(asset))
        stage.request('select_layer',name='session')
        stage.request('attribute',path='/World/A',name='xformOp:translate',value=[999,888,777],time=12.5)
        stage.request('select_source_layer',name=target['name'],context='/World/A',node=target['node'])
        edited=stage.request('set_channel',path='/World/A',name='xformOp:translate',channel=0,value=6.25,time=12.5)
        assert edited['edit_feedback']=='masked_by_stronger_layer'
        assert math.isclose(edited['authored_layer_time'],1.25)
        stage.request('select_layer',name='session');stage.request('clear_layer')
        assert tuple_value(stage,'/World/A','xformOp:translate',12.5)==[6.25,12.5,22.5]
        assert tuple_value(stage,'/World/B','xformOp:translate',1.25)==[6.25,12.5,22.5]
        stage.request('select_source_layer',name=target['name'],context='/World/A',node=target['node'])
        stage.request('copy_key',path='/World/A',name='xformOp:translate',from_time=12.5,time=15.5)
        stage.request('move_key',path='/World/A',name='xformOp:translate',from_time=15.5,time=17)
        assert tuple_value(stage,'/World/B','xformOp:translate',3.5)==[6.25,12.5,22.5]
        # Editing Euler/scale channels must not replace pivots or xformOpOrder.
        stage.request('set_channel',path='/World/A',name='xformOp:rotateXYZ',channel=2,value=90,time=12.5)
        stage.request('set_channel',path='/World/A',name='xformOp:scale',channel=1,value=2,time=12.5)
        pivoted=next(c for c in stage.request('snapshot',time=12.5)['prims'] if c['id']=='/World/A')['world_transform_row_major']
        assert math.isclose(pivoted[12],14.25) and math.isclose(pivoted[13],13.5) and math.isclose(pivoted[14],22.5),pivoted
        # Orientation interpolation is quaternion slerp, not component lerp.
        orient=next(t for t in stage.request('source_targets',path='/World/A/Orient')['targets'] if t['source']==str(asset))
        stage.request('select_source_layer',name=orient['name'],context='/World/A/Orient',node=orient['node'])
        stage.request('set_channel',path='/World/A/Orient',name='xformOp:orient',channel=0,value=0,time=20)
        q=tuple_value(stage,'/World/A/Orient','xformOp:orient',20)
        assert math.isclose(q[2],math.sqrt(.5)) and math.isclose(q[3],math.sqrt(.5)),q
        rejected(stage,'attribute',path='/World/A/Orient',name='xformOp:orient',value=[0,0,0,0],time=20)
        stage.request('save_workspace',destination=str(workspace))
        stage.request('save',destination=str(root/'delivery.usda'))
        stage.request('package',destination=str(root/'delivery.usdz'))
    for p,data in originals.items():assert p.read_bytes()==data
    for destination in [workspace,root/'delivery.usda',root/'delivery.usdz']:
        with api.StageSession() as stage:
            stage.request('open_workspace' if destination.is_dir() else 'open',source=str(destination))
            assert tuple_value(stage,'/World/B','xformOp:translate',3.5)==[6.25,12.5,22.5]
            assert tuple_value(stage,'/World/A','xformOp:rotateXYZ',12.5)==[0,0,90]
            assert tuple_value(stage,'/World/A','xformOp:scale',12.5)==[1,2,1]
            q=tuple_value(stage,'/World/A/Orient','xformOp:orient',20)
            assert math.isclose(sum(v*v for v in q),1)

print('Typed USD curves passed: vector precision, sibling channels, mapped offsets, '
      'fractional tuple key move/copy/delete, pivots/Euler/scale, quaternion interpolation, '
      'masking, rollback, undo, workspace and USD/USDZ restart; source files unchanged')
