"""Native session undo/redo, payload rules, failure atomicity and bounded history."""
import importlib.util,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('session',ROOT/'scripts/usd-session.py');session=importlib.util.module_from_spec(spec);spec.loader.exec_module(session)
def focal(snapshot):return next(p for p in snapshot['prims'] if p['id']=='/Camera')['attributes']['focalLength']
def rejected(stage,op,**kwargs):
 before=stage.request('snapshot')
 assert before['used_layers']==sorted(set(before['used_layers'])),'Layer paths must be sorted and unique'
 try:stage.request(op,**kwargs)
 except ValueError:pass
 else:raise AssertionError('Expected rejection: '+op)
 after=stage.request('snapshot')
 assert after['used_layers']==sorted(set(after['used_layers'])),'Rollback changed canonical layer ordering'
 assert after==before,'Failed operation changed session/history'
with tempfile.TemporaryDirectory(prefix='usd-history-',dir=ROOT/'build') as tmp:
 work=Path(tmp);source=work/'source.usda'
 text='#usda 1.0\ndef Camera "Camera" {\n float focalLength = 40\n}\ndef Xform "Deferred" (prepend payload = @payload.usda@</Root>) {}\n'
 source.write_text(text);(work/'payload.usda').write_text('#usda 1.0\ndef Xform "Root" {\n def Xform "Child" {}\n}\n')
 bad=work/'bad.usda';bad.write_text('#usda 1.0\ndef Camera "Bad" {\n float exposure:fStop = 0\n}\n')
 with session.StageSession() as stage:
  assert stage.request('open',source=str(source))['undo_count']==0
  edited=stage.request('attribute',path='/Camera',name='focalLength',value=55);assert edited['undo_count']==1
  assert focal(stage.request('undo'))==40
  assert focal(stage.request('redo'))==55
  rejected(stage,'attribute',path='/Camera',name='exposure:fStop',value=0)
  stage.request('undo');stage.request('attribute',path='/Camera',name='focalLength',value=60);rejected(stage,'redo')
  loaded=stage.request('load',path='/Deferred');assert any(p['id']=='/Deferred/Child' for p in loaded['prims'])
  assert loaded['used_layers']==sorted([str(source),str(work/'payload.usda')])
  assert not any(p['id']=='/Deferred/Child' for p in stage.request('undo')['prims'])
  assert any(p['id']=='/Deferred/Child' for p in stage.request('redo')['prims'])
  rejected(stage,'open',source=str(bad))
  stage.request('reload');assert stage.request('snapshot')['undo_count']==0
  for i in range(40):stage.request('attribute',path='/Camera',name='focalLength',value=100+i)
  assert stage.request('snapshot')['undo_count']==32
  for _ in range(32):state=stage.request('undo')
  assert focal(state)==107;rejected(stage,'undo')
  stage.request('reload');assert stage.request('snapshot')['redo_count']==0
 assert source.read_text()==text
print('USD history passed: edits, branching, payload rules, failed-open preservation, 32-step limit and source protection')
