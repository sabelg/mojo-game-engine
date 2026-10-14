"""Reused-asset identity repair and time-sampled authoring round trips."""
import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('session', ROOT/'scripts/usd-session.py')
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)

def rows(snapshot):
    return {row['id']: row for row in snapshot['prims']}

def rejected(stage, op, **fields):
    before = stage.request('snapshot', time=12)
    try:
        stage.request(op, **fields)
    except ValueError:
        pass
    else:
        raise AssertionError('Expected failure: '+op)
    assert stage.request('snapshot', time=12) == before

def check_samples(stage):
    middle = rows(stage.request('snapshot', time=12))
    assert middle['/Camera']['attributes']['focalLength'] == 60
    assert middle['/Camera']['world_transform_row_major'][12:15] == [12, 0, 0]
    assert middle['/Camera']['visibility'] == 'inherited'
    end = rows(stage.request('snapshot', time=24))
    assert end['/Camera']['attributes']['focalLength'] == 80
    assert end['/Camera']['visibility'] == 'invisible'

with tempfile.TemporaryDirectory(prefix='usd-authoring-', dir=ROOT/'build') as tmp:
    work = Path(tmp)
    asset = work/'asset.usda'
    asset.write_text('''#usda 1.0
def Xform "Root" (customData = { dictionary atlas = { string uuid = "shared-root" } }) {
    def Xform "Child" (customData = { dictionary atlas = { string uuid = "shared-child" } }) {}
}
''')
    source = work/'source.usda'
    source.write_text('''#usda 1.0
(startTimeCode = 0
 endTimeCode = 24
 timeCodesPerSecond = 24)
def Xform "B" (prepend references = @asset.usda@</Root>) {}
def Xform "A" (prepend references = @asset.usda@</Root>) {}
def Xform "NativeB" (prepend references = @asset.usda@</Root>
 instanceable = true) {}
def Xform "NativeA" (prepend references = @asset.usda@</Root>
 instanceable = true) {}
def Xform "Invalid" (customData = { dictionary atlas = { int uuid = 7 } }) {}
def Camera "Camera" {
 float focalLength = 40
 uniform float customConstant = 3
}
''')
    originals = {p: p.read_bytes() for p in (source, asset)}
    with session.StageSession() as stage:
        initial = stage.request('open', source=str(source))
        assert len(initial['identity_issues']) == 3
        rejected(stage, 'assign_ids')
        repaired = stage.request('repair_ids')
        assert not repaired['identity_issues']
        ids = {path: row['stable_id'] for path, row in rows(repaired).items()}
        assert len(set(ids.values())) == len(ids)
        assert ids['/A'] == 'shared-root' and ids['/A/Child'] == 'shared-child'
        assert rows(repaired)['/NativeA']['instance'] and rows(repaired)['/NativeB']['instance']
        assert stage.request('undo')['identity_issues'] == initial['identity_issues']
        assert {p: r['stable_id'] for p, r in rows(stage.request('redo')).items()} == ids
        count = stage.request('snapshot')['undo_count']
        assert stage.request('repair_ids')['undo_count'] == count
        for time, focal, x in ((0, 40, 0), (24, 80, 24)):
            stage.request('attribute', path='/Camera', name='focalLength', value=focal, time=time)
            matrix = [1,0,0,0, 0,1,0,0, 0,0,1,0, x,0,0,1]
            stage.request('transform', path='/Camera', matrix=matrix, time=time)
            stage.request('visibility', path='/Camera', value='inherited' if time == 0 else 'invisible', time=time)
        check_samples(stage)
        stage.request('timeline', start=0, end=48, time_codes_per_second=48)
        assert stage.request('snapshot')['end'] == 48
        assert stage.request('snapshot')['time_codes_per_second'] == 48
        stage.request('undo')
        assert stage.request('snapshot')['end'] == 24
        rejected(stage, 'timeline', start=24, end=0, time_codes_per_second=24)
        stage.request('attribute', path='/Camera', name='focalLength', value=66, time=12)
        assert rows(stage.request('snapshot', time=12))['/Camera']['attributes']['focalLength'] == 66
        stage.request('clear_sample', path='/Camera', name='focalLength', time=12)
        check_samples(stage)
        stage.request('undo')
        assert rows(stage.request('snapshot', time=12))['/Camera']['attributes']['focalLength'] == 66
        stage.request('redo')
        check_samples(stage)
        rejected(stage, 'clear_sample', path='/Camera', name='focalLength', time=12)
        rejected(stage, 'attribute', path='/Camera', name='exposure:fStop', value=0, time=12)
        rejected(stage, 'attribute', path='/Camera', name='customConstant', value=4, time=12)
        rejected(stage, 'visibility', path='/Camera', value='invisible', time=1e10)
        rejected(stage, 'repair_ids', time=12)
        stage.request('save', destination=str(work/'edited.usda'))
        stage.request('flatten', destination=str(work/'flat.usdc'))
        stage.request('package', destination=str(work/'portable.usdz'))
    for path, data in originals.items():
        assert path.read_bytes() == data
    for target in ('edited.usda', 'flat.usdc', 'portable.usdz'):
        with session.StageSession() as stage:
            opened = stage.request('open', source=str(work/target))
            assert not opened['identity_issues'], (target, opened['identity_issues'], [(r['id'], r.get('identity_status')) for r in opened['prims']])
            assert {p: rows(opened)[p]['stable_id'] for p in ids} == ids
            check_samples(stage)
    for path in originals:
        path.rename(path.with_suffix('.hidden'))
    with session.StageSession() as stage:
        stage.request('open', source=str(work/'portable.usdz'))
        check_samples(stage)

print('USD authoring passed: reused-reference/instance ID repair, undo, keyframes, interpolation, atomic failures and portable round trips')
