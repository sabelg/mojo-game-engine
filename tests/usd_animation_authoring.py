"""Scalar spline values/tangents, finite bake error and owned graph retiming."""
import importlib.util
import math
from pathlib import Path
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('session',ROOT/'scripts/usd-session.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)

def curve(stage,path='/Camera',name='curve',time=0):
    return next(c for c in stage.request('curves',path=path,time=time)['curves'] if c['name']==name)

def rejected(stage,op,**fields):
    before=stage.request('snapshot',time=2.5)
    try:stage.request(op,**fields)
    except ValueError:pass
    else:raise AssertionError('Accepted unsupported '+op)
    assert stage.request('snapshot',time=2.5)==before

with tempfile.TemporaryDirectory(prefix='usd-animation-authoring-',dir=ROOT/'build') as tmp:
    root=Path(tmp);source=root/'source.usda';asset=root/'asset.usda';sub=root/'sub.usda'
    asset.write_text('''#usda 1.0
(defaultPrim="Camera"
timeCodesPerSecond=24
framesPerSecond=24)
def Camera "Camera" {
 float curve.timeSamples={0:40,10:80}
}
''')
    sub.write_text('''#usda 1.0
(timeCodesPerSecond=24)
def Xform "Offset" {
 double3 xformOp:translate.timeSamples={0:(0,0,0),10:(10,0,0)}
 uniform token[] xformOpOrder=["xformOp:translate"]
}
''')
    source.write_text('''#usda 1.0
(startTimeCode=0
endTimeCode=30
timeCodesPerSecond=24
framesPerSecond=24
 subLayers=[@sub.usda@ (offset=1.5;scale=2)])
def Camera "Camera" {
 float curve.timeSamples={0:0,10:20}
}
def Camera "Ref" (prepend references=@asset.usda@</Camera> (offset=10;scale=2)) {}
def Camera "Payload" (prepend payload=@asset.usda@</Camera> (offset=3;scale=1.5)) {}
''')
    originals={p:p.read_bytes() for p in [source,asset,sub]};fields=dict(path='/Camera',name='curve')
    with api.StageSession() as stage:
        stage.request('open',source=str(source));stage.request('load',path='/Payload')
        rejected(stage,'convert_frame_rate',rate=48)
        stage.request('set_interpolation',mode='bezier',**fields)
        for i in range(21):
            u=i/20;expected=20*(3*u*u-2*u*u*u)
            assert math.isclose(curve(stage,time=10*u)['value'],expected,abs_tol=2e-5)
        info=stage.request('spline',**fields);assert len(info['knots'])==2
        stage.request('set_tangent',time=0,side='out',slope=2,width=10/3,**fields)
        edited_info=stage.request('spline',**fields)
        expected=lambda t:(1-t/10)**2*(t/10)*20+3*(1-t/10)*(t/10)**2*20+(t/10)**3*20
        for t in [1.25,2.5,5,7.5]:assert math.isclose(curve(stage,time=t)['value'],expected(t),abs_tol=2e-5)
        rejected(stage,'set_tangent',time=0,side='out',slope=2,width=-1,**fields)
        rejected(stage,'set_tangent',time=0,side='out',slope=2,width=9,**fields)
        rejected(stage,'set_tangent',time=.5,side='out',slope=2,width=1,**fields)
        stage.request('save_workspace',destination=str(root/'spline-workspace'))
        rejected(stage,'preview',destination=str(root/'unsupported-preview.usdc'),animated=True)
        stage.request('preview',destination=str(root/'static-preview.usda'),time=2.5)
        stage.request('bake_curve',start=0,end=10,step=2,max_error=.001,**fields)
        assert len(curve(stage)['keys'])>6
        max_error=max(abs(curve(stage,time=i/100)['value']-expected(i/100)) for i in range(1001))
        assert max_error<=.001,max_error
        stage.request('undo');assert stage.request('spline',**fields)['knots']==edited_info['knots']
        stage.request('set_interpolation',mode='held',**fields)
        assert curve(stage,time=5)['value']==0
        rejected(stage,'bake_curve',start=0,end=10,step=1,max_error=.1,**fields)
        stage.request('undo')
        stage.request('begin_source_editing');stage.request('select_layer',name='session')
        poses={p:curve(stage,path=p,time=t)['value'] for p,t in [('/Camera',2.5),('/Ref',15),('/Payload',6.75)]}
        matrix=next(p for p in stage.request('snapshot',time=6.5)['prims'] if p['id']=='/Offset')['world_transform_row_major']
        state=stage.request('convert_frame_rate',rate=48)
        assert state['time_codes_per_second']==48 and state['end']==60,state
        for p,t in [('/Camera',5),('/Ref',30),('/Payload',13.5)]:assert math.isclose(curve(stage,path=p,time=t)['value'],poses[p],abs_tol=2e-5),(p,poses[p])
        assert next(p for p in stage.request('snapshot',time=13)['prims'] if p['id']=='/Offset')['world_transform_row_major']==matrix
        tangents=stage.request('spline',**fields)['knots'];assert math.isclose(tangents[0]['out_slope'],1) and math.isclose(tangents[0]['out_width'],20/3)
        stage.request('undo');assert curve(stage,time=2.5)['value']==poses['/Camera']
        stage.request('redo');stage.request('save_workspace',destination=str(root/'retimed-workspace'))
        stage.request('save',destination=str(root/'delivery.usda'));stage.request('package',destination=str(root/'delivery.usdz'))
    for destination in [root/'retimed-workspace',root/'delivery.usda',root/'delivery.usdz']:
        with api.StageSession() as stage:
            stage.request('open_workspace' if destination.is_dir() else 'open',source=str(destination));stage.request('load',path='/Payload')
            assert math.isclose(curve(stage,time=5)['value'],poses['/Camera'],abs_tol=2e-5)
            assert math.isclose(curve(stage,path='/Ref',time=30)['value'],poses['/Ref'],abs_tol=2e-5)
    with api.StageSession() as stage:
        stage.request('open_workspace',source=str(root/'spline-workspace'))
        assert math.isclose(curve(stage,time=2.5)['value'],expected(2.5),abs_tol=2e-5)
    for p,data in originals.items():assert p.read_bytes()==data
    # Rate conversion failures restore every owned layer and timeline.
    for metadata in ['timeCodesPerSecond=30','clips={string unsupported="fixture"}']:
        bad=root/'bad.usda'
        bad.write_text('#usda 1.0\n'+('('+metadata+')\ndef Xform "Bad" {}\n' if metadata.startswith('time') else 'def Xform "Bad" ('+metadata+') {}\n'))
        mixed=root/'mixed.usda';mixed.write_text('#usda 1.0\n(timeCodesPerSecond=24\nsubLayers=[@bad.usda@])\n')
        with api.StageSession() as stage:
            stage.request('open',source=str(mixed));stage.request('begin_source_editing');rejected(stage,'convert_frame_rate',rate=48)

print('Scalar animation authoring passed: analytic Bezier/held sampling, tangents, '
      'finite bake error, atomic rejection, physical-time preserving owned retiming, '
      'reference/payload/sublayer offsets, undo and workspace/USD/USDZ restart')
