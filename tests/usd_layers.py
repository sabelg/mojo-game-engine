"""Local edit targets: strength, history, rollback, reload and delivery isolation."""
import importlib.util,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('stage',ROOT/'scripts/usd-session.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
def focal(s):
    return next(c for c in s.request('curves',path='/Camera',time=12)['curves'] if c['name']=='focalLength')
def edit(s,n):s.request('attribute',path='/Camera',name='focalLength',value=n,time=12)
def rejected(s,op,**args):
    before=s.request('snapshot')
    try:s.request(op,**args)
    except ValueError:pass
    else:raise AssertionError('Accepted invalid '+op)
    assert s.request('snapshot')==before,'Failed request changed authoring state'
with tempfile.TemporaryDirectory(prefix='usd-layers-',dir=ROOT/'build') as tmp:
    root=Path(tmp);source=root/'source.usda'
    source.write_text('#usda 1.0\ndef Camera "Camera" {\n float focalLength.timeSamples = {0:40,24:80}\n}\n')
    original=source.read_bytes()
    with api.StageSession() as s:
        s.request('open',source=str(source))
        rejected(s,'select_layer',name=str(source))
        rejected(s,'create_layer',name='../source')
        s.request('create_layer',name='animation');edit(s,70)
        assert focal(s)['value']==70
        assert all(k['authored_in_target'] and not k['session'] for k in focal(s)['keys'])
        assert [(k['time'],k['value']) for k in focal(s)['keys']]==[(0,40),(12,70),(24,80)]
        s.request('create_layer',name='shot');edit(s,90)
        rejected(s,'create_layer',name='shot')
        assert focal(s)['value']==90
        rejected(s,'attribute',path='/Camera',name='focalLength',value=-1,time=12)
        s.request('select_layer',name='animation');edit(s,65)
        assert focal(s)['value']==90,'A weaker layer unexpectedly overrode the stronger shot layer'
        s.request('select_layer',name='shot');s.request('clear_layer')
        assert focal(s)['value']==65
        s.request('undo');assert focal(s)['value']==90
        s.request('redo');assert focal(s)['value']==65
        s.request('select_layer',name='session')
        rejected(s,'clear_sample',path='/Camera',name='focalLength',time=12)
        edit(s,100)
        assert all(k['session'] and k['authored_in_target'] for k in focal(s)['keys'])
        s.request('clear_layer');assert focal(s)['value']==65
        assert len([l for l in s.request('snapshot')['layers'] if l['editable']])==3
        s.request('select_layer',name='animation')
        rejected(s,'timeline',start=0,end=24,time_codes_per_second=24)
        s.request('reload');assert focal(s)['value']==65
        assert s.request('snapshot')['edit_target']=='animation'
        for op,ext in [('save','usda'),('flatten','usdc'),('package','usdz')]:
            s.request(op,destination=str(root/('result.'+ext)))
            rejected(s,op,destination=str(root/('result.'+ext)))
        s.request('reset');assert focal(s)['value']==60
        s.request('undo');assert focal(s)['value']==65
        assert s.request('snapshot')['edit_target']=='animation'
        s.request('redo');assert focal(s)['value']==60
        for i in range(8):s.request('create_layer',name='layer'+str(i))
        rejected(s,'create_layer',name='overflow')
        s.request('undo');assert len([l for l in s.request('snapshot')['layers'] if l['editable']])==8
        s.request('redo');assert len([l for l in s.request('snapshot')['layers'] if l['editable']])==9
        rejected(s,'open',source=str(root/'missing.usda'))
    assert source.read_bytes()==original
    for ext in ['usda','usdc','usdz']:
        if ext=='usdz':source.rename(root/'hidden.usda')
        with api.StageSession() as s:
            s.request('open',source=str(root/('result.'+ext)))
            assert focal(s)['value']==65
            assert [(k['time'],k['value']) for k in focal(s)['keys']]==[(0,40),(12,65),(24,80)]
print('USD local layers passed: target selection, strength, rollback, history, limits, reload, export and portable package')
