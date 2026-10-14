import importlib.util,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('usd_session',ROOT/'scripts/usd-session.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='usd-identity-') as work:
    work=Path(work);source=work/'source.usda'
    source.write_text('#usda 1.0\ndef Xform "Original" {}\n')
    with module.StageSession() as stage:
        stage.request('open',source=str(source))
        assigned=stage.request('assign_ids')['prims'][0]['stable_id']
        assert stage.request('assign_ids')['prims'][0]['stable_id']==assigned
        stage.request('flatten',destination=str(work/'portable.usda'))
    renamed=work/'renamed.usda'
    renamed.write_text((work/'portable.usda').read_text().replace('"Original"','"Renamed"'))
    with module.StageSession() as stage:
        row=stage.request('open',source=str(renamed))['prims'][0]
        assert row['id']=='/Renamed' and row['stable_id']==assigned
    assert 'atlas' not in source.read_text()
print('USD identities passed: assignment, persistence, namespace rename and unchanged original source')
