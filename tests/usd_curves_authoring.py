"""Editing a composed scalar curve preserves its weaker-layer keys."""
import importlib.util,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('stage',ROOT/'scripts/usd-session.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
def curve(stage,time=12):
    result=stage.request('curves',path='/Camera',time=time)
    return next(c for c in result['curves'] if c['name']=='focalLength')
with tempfile.TemporaryDirectory(prefix='usd-keyframes-',dir=ROOT/'build') as tmp:
    work=Path(tmp);source=work/'source.usda'
    source.write_text('''#usda 1.0
def Camera "Camera" {
 float focalLength.timeSamples = {0:40,24:80}
 uniform float constant = 7
}
''')
    before=source.read_bytes()
    with api.StageSession() as stage:
        opened=stage.request('open',source=str(source))
        original=curve(stage)
        assert original['value']==60 and not any(k['session'] for k in original['keys'])
        assert not next(c for c in stage.request('curves',path='/Camera')['curves'] if c['name']=='constant')['editable']
        assert stage.request('snapshot')==opened,'Inspection changed authoring state'
        try:stage.request('clear_sample',path='/Camera',name='focalLength',time=0)
        except ValueError:pass
        else:raise AssertionError('Source key deleted without a session override')
        assert stage.request('snapshot')==opened
        stage.request('attribute',path='/Camera',name='focalLength',value=70,time=12)
        edited=curve(stage)
        assert [(k['time'],k['value']) for k in edited['keys']]==[(0,40),(12,70),(24,80)]
        assert all(k['session'] for k in edited['keys'])
        assert curve(stage,6)['value']==55
        stage.request('clear_sample',path='/Camera',name='focalLength',time=12)
        assert curve(stage)['value']==60
        stage.request('undo');assert curve(stage)['value']==70
        snapshot=stage.request('snapshot')
        try:stage.request('attribute',path='/Camera',name='focalLength',value=-1,time=6)
        except ValueError:pass
        else:raise AssertionError('Invalid optics accepted')
        assert stage.request('snapshot')==snapshot
        stage.request('save',destination=str(work/'edited.usda'))
        stage.request('undo');assert curve(stage)==original
        stage.request('redo');assert curve(stage)['value']==70
    with api.StageSession() as stage:
        stage.request('open',source=str(work/'edited.usda'))
        assert curve(stage)['value']==70 and len(curve(stage)['keys'])==3
    assert source.read_bytes()==before
print('USD curve authoring passed: composed-key preservation, interpolation, deletion, rollback, undo/redo and save/reopen')

(ROOT/'build/usd-keyframes-source.usda').write_text('''#usda 1.0
(metersPerUnit = 1
 upAxis = "Y"
 startTimeCode = 1
 endTimeCode = 5
 timeCodesPerSecond = 24)
def Camera "Shot" {
 float focalLength.timeSamples = {1:35,5:70}
 float horizontalAperture = 36
 float verticalAperture = 24
 float2 clippingRange = (0.1,100)
 double3 xformOp:translate = (0,0,5)
 uniform token[] xformOpOrder = ["xformOp:translate"]
}
def Mesh "Triangle" {
 uniform token subdivisionScheme = "none"
 point3f[] points = [(-1,-1,0),(1,-1,0),(0,1,0)]
 int[] faceVertexCounts = [3]
 int[] faceVertexIndices = [0,1,2]
}
def DomeLight "Sky" {
 float inputs:intensity = 1
}
''')
