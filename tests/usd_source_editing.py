"""Working-copy source edits: offsets, references, variants, conflicts and restart."""
import importlib.util
import json
import math
from pathlib import Path
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('session',ROOT/'scripts/usd-session.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)

def curve(stage,path,time=20):
    return next(c for c in stage.request('curves',path=path,time=time)['curves'] if c['name']=='focalLength')

def rejected(stage,op,**fields):
    before=stage.request('snapshot')
    try:stage.request(op,**fields)
    except ValueError:pass
    else:raise AssertionError('Accepted invalid '+op)
    assert stage.request('snapshot')==before,'Failed operation changed current workspace'

with tempfile.TemporaryDirectory(prefix='usd-source-editing-',dir=ROOT/'build') as tmp:
    root=Path(tmp);art=root/'art';art.mkdir();source=art/'root.usda';sub=art/'sub.usda';asset=art/'asset.usda'
    sub.write_text('#usda 1.0\ndef Camera "Local" {\n float focalLength.timeSamples={0:40,10:80}\n}\n')
    asset.write_text('''#usda 1.0
(defaultPrim="Asset")
def Xform "Asset" (
 prepend variantSets="lens"
 variants={string lens="wide"}
) {
 def Camera "Camera" {
  float focalLength.timeSamples={0:30,10:60}
 }
 variantSet "lens"={
  "wide" {
   over "Camera" {
    float horizontalAperture=36
   }
  }
  "close" {
   over "Camera" {
    float horizontalAperture=24
   }
  }
 }
}
''')
    source.write_text('''#usda 1.0
(subLayers=[@sub.usda@ (offset=10;scale=2)])
def Xform "World" {
 def Xform "A" (prepend references=@asset.usda@</Asset> (offset=100;scale=3)) {}
 def Xform "B" (prepend references=@asset.usda@</Asset>) {}
 def Xform "Instance" (prepend references=@asset.usda@</Asset>;instanceable=true) {}
}
''')
    originals={p:p.read_bytes() for p in [source,sub,asset]};workspace=root/'workspace'
    with api.StageSession() as stage:
        stage.request('open',source=str(source))
        assert [k['time'] for k in curve(stage,'/Local')['keys']]==[10,30]
        state=stage.request('begin_source_editing')
        assert len(state['working_layers'])==3 and state['edit_target']=='working:0'
        stage.request('undo');assert not stage.request('snapshot')['working_layers']
        stage.request('redo');assert len(stage.request('snapshot')['working_layers'])==3
        stage.request('select_source_layer',name=str(sub))
        rejected(stage,'select_source_layer',name=str(sub),node=1e100)
        rejected(stage,'select_source_layer',name=str(sub),node=.5)
        edited=stage.request('attribute',path='/Local',name='focalLength',time=20,value=55)
        assert edited['authored_layer_time']==5 and edited['authored_spec_path']=='/Local.focalLength'
        assert curve(stage,'/Local')['value']==55
        assert [k['time'] for k in curve(stage,'/Local')['keys']]==[10,20,30]
        stage.request('clear_sample',path='/Local',name='focalLength',time=20)
        assert curve(stage,'/Local')['value']==60
        stage.request('undo');assert curve(stage,'/Local')['value']==55
        targets=stage.request('source_targets',path='/World/A/Camera')['targets']
        candidates=[t for t in targets if t['source']==str(asset)]
        assert any(t['spec_path']=='/Asset/Camera' and t['time_offset']==100 and t['time_scale']==3 for t in candidates)
        reference=next(t for t in candidates if t['spec_path']=='/Asset/Camera')
        stage.request('select_source_layer',name=str(asset),context='/World/A/Camera',node=reference['node'])
        edited=stage.request('attribute',path='/World/A/Camera',name='focalLength',time=115,value=45)
        assert math.isclose(edited['authored_layer_time'],5) and edited['authored_spec_path']=='/Asset/Camera.focalLength'
        assert curve(stage,'/World/A/Camera',115)['value']==45
        assert curve(stage,'/World/B/Camera',5)['value']==45,'Shared source edit did not affect its other occurrence'
        rejected(stage,'attribute',path='/Local',name='focalLength',value=20)
        rejected(stage,'select_source_layer',name=str(asset),context='/World/Instance/Camera')
        variant=next(t for t in candidates if '{lens=wide}' in t['spec_path'])
        stage.request('select_source_layer',name=str(asset),context='/World/A/Camera',node=variant['node'])
        edited=stage.request('attribute',path='/World/A/Camera',name='horizontalAperture',value=38)
        assert '{lens=wide}' in edited['authored_spec_path']
        stage.request('select_layer',name='session')
        stage.request('attribute',path='/Local',name='focalLength',time=20,value=99)
        stage.request('select_source_layer',name=str(sub))
        edited=stage.request('attribute',path='/Local',name='focalLength',time=20,value=56)
        assert edited['edit_feedback']=='masked_by_stronger_layer'
        stage.request('save_workspace',destination=str(workspace))
        assert json.loads((workspace/'workspace.json').read_text())['version']==2
        manifest=workspace/'workspace.json';committed=manifest.read_text()
        invalid=json.loads(committed);invalid['working_sources'][1]['original']['path']=str(asset)
        manifest.write_text(json.dumps(invalid))
        try:rejected(stage,'open_workspace',source=str(workspace))
        finally:manifest.write_text(committed)
        for op,ext in [('save','usda'),('package','usdz')]:stage.request(op,destination=str(root/('delivery.'+ext)))
    for p,data in originals.items():assert p.read_bytes()==data
    with api.StageSession() as stage:
        state=stage.request('open_workspace',source=str(workspace))
        assert state['edit_target']==next(w['name'] for w in state['working_layers'] if w['source']==str(sub))
        assert curve(stage,'/Local')['value']==99
        stage.request('select_layer',name='session');stage.request('clear_layer')
        assert curve(stage,'/Local')['value']==56
        assert curve(stage,'/World/A/Camera',115)['value']==45
        assert not state['unsaved_changes']
        # Source changes become explicit conflicts and preserve all owned edits.
        sub.write_text(sub.read_text().replace('0:40','0:42'))
        assert stage.request('snapshot')['source_conflicts']
        rejected(stage,'reload');rejected(stage,'save_workspace',destination=str(workspace))
        stage.request('resolve_sources',action='keep_working')
        assert not stage.request('snapshot')['source_conflicts']
        assert stage.request('snapshot')['unsaved_changes'],'Accepting new source fingerprints must require saving'
        assert curve(stage,'/Local')['value']==56
        stage.request('save_workspace',destination=str(workspace))
        stage.request('resolve_sources',action='reload')
        assert curve(stage,'/Local',10)['value']==42
        stage.request('undo');assert curve(stage,'/Local')['value']==56
        # New source arcs require reimport rather than silently changing membership.
        extra=art/'extra.usda';extra.write_text('#usda 1.0\ndef Xform "Extra" {}\n')
        source.write_text(source.read_text().replace('@sub.usda@ (offset=10;scale=2)', '@sub.usda@ (offset=10;scale=2),@extra.usda@'))
        rejected(stage,'resolve_sources',action='keep_working')
        source.write_bytes(originals[source])
    # Relocate the project and verify owned references and sublayer offsets survive.
    moved=root.parent/(root.name+'-moved');root.rename(moved)
    try:
        with api.StageSession() as stage:
            stage.request('open_workspace',source=str(moved/'workspace'))
            stage.request('select_layer',name='session')
            assert curve(stage,'/World/A/Camera',115)['value']==45
            assert curve(stage,'/Local')['value']==56
        for ext in ['usda','usdz']:
            with api.StageSession() as stage:
                stage.request('open',source=str(moved/('delivery.'+ext)))
                assert curve(stage,'/Local')['value']==99
                assert curve(stage,'/World/A/Camera',115)['value']==45
    finally:moved.rename(root)

print('USD source editing passed: owned root/sublayer/reference/variant copies, '
      'path/time mapping, shared occurrences, proxy rejection, masked diagnostics, '
      'undo, workspace/delivery restart, relocation and explicit source conflicts')
