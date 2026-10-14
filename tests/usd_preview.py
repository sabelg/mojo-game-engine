"""Static loaded-stage previews, revision cancellation and failure preservation."""
import importlib.util
from pathlib import Path
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
session=module('stage','usd-session.py')
preview=module('preview','usd-preview.py')

def wait(cooker,stage,status):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        cooker.tick(stage)
        fields=(cooker.work/'preview.tsv').read_text().rstrip('\n').split('\t')
        if fields[0]==status:return fields
        if fields[0]=='ERROR':raise AssertionError(fields)
        time.sleep(.025)
    raise AssertionError('Preview timeout')

with tempfile.TemporaryDirectory(prefix='usd-preview-',dir=ROOT/'build') as tmp:
    work=Path(tmp).resolve()
    source=work/'source.usda'
    original=(ROOT/'assets/usd/scene.usda').read_text()
    source.write_text(original+'\ndef Xform "Deferred" (prepend payload = @payload.usda@</Root>) {}\n')
    (work/'base.usda').write_bytes((ROOT/'assets/usd/base.usda').read_bytes())
    (work/'payload.usda').write_text('#usda 1.0\ndef Xform "Root" {\n def Xform "HiddenChild" {}\n}\n')
    originals={path:path.read_bytes() for path in work.glob('*.usda')}
    with session.StageSession() as stage:
        before=stage.request('open',source=str(source))
        target=work/'sample.usdc'
        exported=stage.request('preview',destination=str(target),time=3)
        assert exported['revision']==before['revision']
        assert stage.request('snapshot')==before
        with session.StageSession() as sampled:
            opened=sampled.request('open',source=str(target))
            assert not opened['payloads']
            assert not any(p['id']=='/Deferred/HiddenChild' for p in opened['prims'])
            a=sampled.request('snapshot',time=0)['prims']
            b=sampled.request('snapshot',time=100)['prims']
            assert a==b
            placed=next(p for p in a if p['id']=='/World/Placed')
            assert placed['world_transform_row_major'][12]==1
        cooker=preview.PreviewCooker(work)
        try:
            cooker.schedule(before)
            ready=wait(cooker,stage,'READY')
            prefix=Path(ready[2]);assert prefix.with_name('preview-scene.sceneb').exists()
            assert (prefix.parent/'cache').is_dir()
            preview.atomic(work/'preview-ack.txt',ready[3]+'\n')
            changed=stage.request('variant',path='/World/Placed',set='size',value='small')
            cooker.schedule(changed)
            time.sleep(.21);cooker.tick(stage)
            stale=cooker.job;assert stale is not None
            newest=stage.request('undo');cooker.schedule(newest)
            assert stale.poll() is not None
            latest=wait(cooker,stage,'READY')
            assert int(latest[1])==newest['revision']
            last_prefix=Path(latest[2]);assert last_prefix.with_name('preview-scene.sceneb').exists()
            # Unsupported shading fails without replacing published geometry.
            bad=stage.request('attribute',path='/World/Placed/Paint/Surface',name='info:id',value='UnsupportedShader')
            cooker.schedule(bad)
            failure=wait(cooker,stage,'ERROR')
            assert int(failure[1])==bad['revision']
            assert last_prefix.with_name('preview-scene.sceneb').exists()
            repaired=stage.request('undo');cooker.schedule(repaired)
            recovered=wait(cooker,stage,'READY')
            preview.atomic(work/'preview-ack.txt',recovered[3]+'\n')
            cooker.tick(stage)
            assert len(list(cooker.root.iterdir()))==1
            empty=stage.request('active',path='/World/Placed',value=False)
            cooker.schedule(empty)
            empty_ready=wait(cooker,stage,'READY')
            assert Path(empty_ready[2]+'-scene.scene').read_text()=='MOJO_SCENE_3\n'
        finally:cooker.close()
        assert not (work/'previews').exists()
    for path,data in originals.items():assert path.read_bytes()==data
print('USD previews passed: static sampling, unloaded payload exclusion, cancellation, failure retention, recovery and owned cleanup')
