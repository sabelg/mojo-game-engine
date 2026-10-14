"""Native stage service regression: editable composition and portable packaging."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import zipfile
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('usd_session', ROOT / 'scripts/usd-session.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
StageSession = module.StageSession

def rejected(stage, op, **fields):
    try:
        stage.request(op, **fields)
    except ValueError:
        return
    raise AssertionError('Expected rejection: ' + op)

def rows(snapshot):
    return {p['id']: p for p in snapshot['prims']}

with tempfile.TemporaryDirectory(prefix='usd-stage-', dir=ROOT / 'build') as work:
    work = Path(work)
    (work / 'base.usda').write_bytes((ROOT / 'assets/usd/base.usda').read_bytes())
    source = work / 'scene.usda'
    text = (ROOT / 'assets/usd/scene.usda').read_text()
    # Independent camera/light and deferred-payload source fixture.
    text += '''
def Camera "Camera" {
    float focalLength = 40
    float horizontalAperture = 36
    float verticalAperture = 24
    float2 clippingRange = (0.1, 1000)
    double3 xformOp:translate = (0, -5, 2)
    uniform token[] xformOpOrder = ["xformOp:translate"]
}
def SphereLight "Key" {
    float inputs:intensity = 10
    float inputs:exposure = 2
    color3f inputs:color = (1, 0.8, 0.6)
}
def Xform "Deferred" (prepend payload = @payload.usda@</Contents>) {}
'''
    source.write_text(text)
    (work / 'payload.usda').write_text('#usda 1.0\ndef Xform "Contents" {\n def Xform "Child" {}\n}\n')
    originals = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in work.glob('*.usda')}
    started = time.monotonic()
    with StageSession() as stage:
        initial = stage.request('open', source=str(source))
        assert initial['openusd_version'] == 2603
        assert '/Deferred/Child' not in rows(initial)
        assert rows(initial)['/Camera']['attributes']['focalLength'] == 40
        assert rows(initial)['/Key']['attributes']['inputs:exposure'] == 2
        assert initial['up_axis'] == 'Z' and initial['meters_per_unit'] == 1
        loaded = stage.request('load', path='/Deferred')
        assert '/Deferred/Child' in rows(loaded)
        stage.request('unload', path='/Deferred')
        selected = stage.request('variant', path='/World/Placed', set='size', value='small')
        assert rows(selected)['/World/Placed']['variants']['size']['selected'] == 'small'
        matrix = [1,0,0,0, 0,1,0,0, 0,0,1,0, 7,8,9,1]
        edited = stage.request('transform', path='/World/Placed', matrix=matrix)
        assert rows(edited)['/World/Placed']['world_transform_row_major'] == matrix
        edited = stage.request('attribute', path='/Camera', name='focalLength', value=55)
        assert rows(edited)['/Camera']['attributes']['focalLength'] == 55
        edited = stage.request('attribute', path='/Key', name='inputs:color', value=[.2,.4,.8])
        rejected(stage, 'attribute', path='/Camera', name='focalLength', value=1e100)
        rejected(stage, 'variant', path='/World/Placed', set='size', value='missing')
        rejected(stage, 'transform', path='/World/Placed', matrix=[0]*16)
        rejected(stage, 'open', source=str(source), prim_limit=1)
        current = stage.request('snapshot')
        assert current['revision'] == edited['revision']
        assert rows(current)['/Camera']['attributes']['focalLength'] == 55
        stage.request('visibility', path='/World/Placed', value='invisible')
        overlay = work / 'edited.usda'
        stage.request('save', destination=str(overlay))
        assert 'subLayers' in overlay.read_text() and 'base.usda' not in overlay.read_text()
        rejected(stage, 'save', destination=str(overlay))
        package = work / 'portable.usdz'
        stage.request('package', destination=str(package))
        assert package.is_file()
        rejected(stage, 'flatten', destination=str(work / 'flat.usdc'))
        stage.request('load', path='/Deferred')
        stage.request('flatten', destination=str(work / 'flat.usdc'))
        # External reload retains session opinions and exposes the modified source.
        source.write_text(text.replace('float horizontalAperture = 36', 'float horizontalAperture = 42'))
        reloaded = stage.request('reload')
        assert rows(reloaded)['/Camera']['attributes']['focalLength'] == 55
        assert rows(reloaded)['/Camera']['attributes']['horizontalAperture'] == 42
        source.write_text(text)
        stage.request('reload')
        stage.request('reset')
        assert rows(stage.request('snapshot'))['/Camera']['attributes']['focalLength'] == 40
    for path, digest in originals.items():
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, path
    with StageSession() as stage:
        reopened = stage.request('open', source=str(overlay))
        assert rows(reopened)['/Camera']['attributes']['focalLength'] == 55
        assert rows(reopened)['/World/Placed']['variants']['size']['selected'] == 'small'
        assert reopened['up_axis'] == 'Z' and reopened['meters_per_unit'] == 1
    # Hide all original input layers: packaged references/payloads must be internal.
    for path in list(originals) + [overlay]:
        path.rename(path.with_suffix('.hidden'))
    with StageSession() as stage:
        reopened = stage.request('open', source=str(package))
        assert rows(reopened)['/Camera']['attributes']['focalLength'] == 55
        assert '/Deferred/Child' in rows(stage.request('load', path='/Deferred'))
    with zipfile.ZipFile(package) as archive:
        assert len(archive.namelist()) >= 4
    # A selective load that exceeds the prim count rolls back its load rules.
    source = work / 'limited.usda'
    source.write_text('#usda 1.0\ndef Xform "Deferred" (prepend payload = @big.usda@</Contents>) {}\n')
    (work / 'big.usda').write_text('#usda 1.0\ndef Xform "Contents" {\n' + '\n'.join(f'def Xform "N{i}" {{}}' for i in range(20)) + '\n}\n')
    with StageSession() as stage:
        before = stage.request('open', source=str(source), prim_limit=10)
        rejected(stage, 'load', path='/Deferred')
        after = stage.request('snapshot')
        assert after['revision'] == before['revision'] and len(after['prims']) == 1
    project = work / 'project'
    subprocess.run([sys.executable, str(ROOT/'scripts/atlas-project.py'), 'create', '--project', str(project)], check=True, capture_output=True)
    command_file = work/'operations.json'
    command_file.write_text(json.dumps([{'op':'load','path':'/Deferred'}]))
    subprocess.run([sys.executable, str(ROOT/'scripts/atlas-project.py'), 'usd-author', '--project', str(project), '--source', str(source), '--commands', str(command_file), '--destination', str(work/'project-overlay.usda')], check=True, capture_output=True)
    with module.BackgroundStageSession(capacity=2) as background:
        background.request('open', source=str(source)).result(timeout=10)
        loaded = background.request('load', path='/Deferred').result(timeout=10)
        assert len(loaded['prims']) == 21
        # Hold the serial request lock to exercise cancellation and queue pressure deterministically.
        background.stage.lock.acquire()
        try:
            first = background.request('snapshot')
            queued = background.request('snapshot')
            try:
                background.request('snapshot')
            except ValueError:
                pass
            else:
                raise AssertionError('Background queue did not enforce its capacity')
            assert queued.cancel()
        finally:
            background.stage.lock.release()
        first.result(timeout=10)
        background.request('unload', path='/Deferred').result(timeout=10)
        memory = next(row for row in Path(f'/proc/{background.stage.process.pid}/status').read_text().splitlines() if row.startswith('VmHWM:'))
    report = {'peak_native_memory': memory, 'openusd_version': 2603, 'elapsed_seconds': time.monotonic()-started,
        'checks': ['variants', 'transform override', 'camera/light attributes', 'reload',
                   'source immutability', 'failed-edit rollback', 'payload load/unload',
                   'payload count rollback', 'overlay reopen', 'portable USDZ', 'flatten']}
    (ROOT / 'build/usd-stage-test.json').write_text(json.dumps(report, indent=2)+'\n')
print('USD native stage tests passed: edits, reload, payloads, rollback, overlay, portable USDZ')
