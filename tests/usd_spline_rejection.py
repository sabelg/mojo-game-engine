"""Existing Ts tangents remain intact when time-sample editing is unsupported."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('session',ROOT/'scripts/usd-session.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
base=ROOT/'.deps/blender-source';sdk=base/'lib/linux_arm64';binary=ROOT/'build/usd-spline-fixture'
command=[str(base/'compiler/usr/bin/g++-14'),'-std=c++17','-O1',str(ROOT/'tests/usd_spline_fixture.cc'),
         '-I'+str(sdk/'usd/include'),'-I'+str(sdk/'tbb/include'),'-I'+str(sdk/'python/include/python3.13'),
         '-L'+str(base/'build/bin/lib'),'-Wl,-rpath,'+str(base/'build/bin/lib'),
         '-Wl,-rpath-link,'+str(base/'build/bin/lib'),'-lusd_ms','-ltbb',str(sdk/'python/lib/libpython3.13.a'),
         '-ldl','-lpthread','-lm','-lutil','-o',str(binary)]
subprocess.run(command,check=True)
with tempfile.TemporaryDirectory(prefix='usd-spline-rejection-',dir=ROOT/'build') as tmp:
    root=Path(tmp);source=root/'source.usda';workspace=root/'workspace'
    subprocess.run([str(binary),str(source)],check=True);original=source.read_bytes()
    with api.StageSession() as stage:
        stage.request('open',source=str(source));before=stage.request('snapshot',time=5)
        curve=next(c for c in stage.request('curves',path='/Animated',time=5)['curves'] if c['name']=='curve')
        assert not curve['editable'] and 'Spline' in curve['read_only_reason']
        for op,fields in [('set_channel',dict(channel=0,value=3)),('attribute',dict(value=3)),
                          ('move_key',dict(from_time=0)),('copy_key',dict(from_time=0))]:
            try:stage.request(op,path='/Animated',name='curve',time=5,**fields)
            except ValueError as e:assert 'Spline' in str(e)
            else:raise AssertionError('Spline silently converted by '+op)
            assert stage.request('snapshot',time=5)==before
        stage.request('begin_source_editing');stage.request('save_workspace',destination=str(workspace))
    with api.StageSession() as stage:
        stage.request('open_workspace',source=str(workspace))
        reopened=stage.request('curves',path='/Animated',time=5)['curves'][0]
        assert reopened['value']==curve['value'] and reopened['spline'] and reopened['spline_editable']
        knots=stage.request('spline',path='/Animated',name='curve')['knots']
        assert [k['time'] for k in knots]==[0,10] and all(k['in_width']==2 and k['out_width']==2 for k in knots)
    assert source.read_bytes()==original
print('Real USD spline rejection passed: time-sample editing remains guarded, '
      'channel/key/time-sample edits reject atomically, workspace preserves source splines')
