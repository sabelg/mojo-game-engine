"""Occurrence identities remain reserved while payloads and proxies are hidden."""
import importlib.util
from pathlib import Path
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('session',ROOT/'scripts/usd-session.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)

def ids(stage):return {row['path']:row for row in stage.request('identities')['identities']}

with tempfile.TemporaryDirectory(prefix='usd-identity-payloads-',dir=ROOT/'build') as tmp:
    root=Path(tmp);asset=root/'asset.usda';source=root/'source.usda';workspace=root/'workspace'
    asset.write_text('''#usda 1.0
(defaultPrim="Asset")
def Xform "Asset" {
 def Camera "Camera" (
  customData={dictionary atlas={string uuid="shared-child"}}
 ) {}
}
''')
    source.write_text('''#usda 1.0
def Xform "A" (prepend payload=@asset.usda@</Asset>) {}
def Xform "B" (prepend payload=@asset.usda@</Asset>) {}
def Xform "I1" (prepend references=@asset.usda@</Asset>;instanceable=true) {}
def Xform "I2" (prepend references=@asset.usda@</Asset>;instanceable=true) {}
''')
    original=source.read_bytes();asset_original=asset.read_bytes()
    with api.StageSession() as stage:
        stage.request('open',source=str(source))
        stage.request('begin_source_editing')
        stage.request('load',path='/A');stage.request('repair_ids')
        first=ids(stage);child=first['/A/Camera']['stable_id']
        assert first['/I1/Camera']['stable_id']!=first['/I2/Camera']['stable_id']
        assert not first['/I1/Camera']['writable']
        try:stage.request('attribute',path='/I1/Camera',name='focalLength',value=10)
        except ValueError:pass
        else:raise AssertionError('Proxy was directly editable')
        stage.request('unload',path='/A');stage.request('load',path='/B')
        stage.request('repair_ids');hidden=ids(stage)
        assert hidden['/A/Camera']['stable_id']==child and not hidden['/A/Camera']['loaded']
        assert hidden['/B/Camera']['stable_id']!=child,'Loaded duplicate reused a hidden occurrence ID'
        stage.request('load',path='/A');stage.request('repair_ids')
        final=ids(stage)
        assert final['/A/Camera']['stable_id']==child
        assert final['/I1/Camera']['stable_id']==first['/I1/Camera']['stable_id']
        before=stage.request('snapshot');stage.request('repair_ids')
        assert stage.request('snapshot')['undo_count']==before['undo_count'],'Reconciliation is not idempotent'
        stage.request('save_workspace',destination=str(workspace))
    with api.StageSession() as stage:
        stage.request('open_workspace',source=str(workspace))
        assert ids(stage)==final
        stage.request('repair_ids');assert ids(stage)==final
        stage.request('unload',path='/B');stage.request('repair_ids');stage.request('undo')
        assert ids(stage)['/B/Camera']['stable_id']==final['/B/Camera']['stable_id']
    assert source.read_bytes()==original and asset.read_bytes()==asset_original

print('USD payload identities passed: hidden IDs reserved, duplicate loaded '
      'occurrences repaired, distinct stable read-only proxies, undo and workspace restart')
