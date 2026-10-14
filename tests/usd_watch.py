"""Live layer reload preserves local overrides and recovers after invalid edits."""
import importlib.util,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('usd_session',ROOT/'scripts/usd-session.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def wait_for(stage,predicate):
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
        event=stage.events.get(timeout=max(.01,deadline-time.monotonic()))
        if predicate(event):return event
    raise AssertionError('Watcher did not publish expected change')
with tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='usd-watch-') as directory:
    directory=Path(directory);source=directory/'stage.usda';base=directory/'base.usda'
    original='#usda 1.0\ndef Camera "Camera" {\n float focalLength = 40\n float horizontalAperture = 36\n}\n'
    base.write_text(original)
    source.write_text('#usda 1.0\n(subLayers = [@base.usda@])\n')
    with module.WatchedStageSession(interval=.05) as stage:
        stage.request('open',source=str(source))
        local=stage.request('attribute',path='/Camera',name='focalLength',value=55)
        assert str(base) in local['used_layers']
        base.write_text(original.replace('= 36','= 42'))
        wait_for(stage,lambda e:e['operation']=='reload' and 'error' not in e)
        row=stage.snapshot['prims'][0]
        assert row['attributes']['focalLength']==55 and row['attributes']['horizontalAperture']==42
        last=stage.snapshot['revision']
        base.write_text('invalid USD syntax')
        wait_for(stage,lambda e:'error' in e)
        assert stage.snapshot['revision']==last
        base.write_text(original.replace('= 36','= 48'))
        wait_for(stage,lambda e:e['operation']=='reload' and 'error' not in e)
        row=stage.snapshot['prims'][0]
        assert row['attributes']['focalLength']==55 and row['attributes']['horizontalAperture']==48
    assert not stage.thread.is_alive()
print('USD watcher passed: referenced layer changes, local overrides, error notification, recovery and shutdown')
