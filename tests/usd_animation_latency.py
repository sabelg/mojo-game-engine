"""Bounded edit/publication measurements for a camera-rich scene without meshes."""
import importlib.util
import json
from pathlib import Path
import statistics
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
api=module('api','usd-session.py');preview=module('preview','usd-preview.py')
measurements=[]
with tempfile.TemporaryDirectory(prefix='usd-animation-latency-',dir=ROOT/'build') as tmp:
    work=Path(tmp);source=work/'source.usda'
    source.write_text('#usda 1.0\n(metersPerUnit=1\nupAxis="Y"\nstartTimeCode=0\nendTimeCode=24\ntimeCodesPerSecond=24)\n'+
      ''.join('def Camera "Camera'+str(i)+'" {\nfloat focalLength.timeSamples={0:40,24:80}\n}\n' for i in range(36))+
      ''.join('def Xform "Node'+str(i)+'" {\ndouble3 xformOp:translate.timeSamples={0:(0,0,0),24:(1,2,3)}\nuniform token[] xformOpOrder=["xformOp:translate"]\n}\n' for i in range(128)))
    with api.StageSession() as stage:
        snapshot=stage.request('open',source=str(source));cooker=preview.PreviewCooker(work,animated=True)
        try:
            for i in range(4):
                started=time.monotonic();snapshot=stage.request('set_channel',path='/Camera0',name='focalLength',channel=0,value=50+i,time=12.5)
                edit_done=time.monotonic();cooker.schedule(snapshot);deadline=started+30
                while time.monotonic()<deadline:
                    cooker.tick(stage);fields=(work/'preview.tsv').read_text().strip().split('\t')
                    if fields[0]=='ERROR':raise AssertionError(fields)
                    if fields[0]=='READY':break
                    time.sleep(.01)
                else:raise AssertionError('Preview latency exceeded 30-second test bound')
                assert int(fields[1])==snapshot['revision']
                prefix=Path(fields[2]);assert prefix.with_name(prefix.name+'-cameras.atlascameras').is_file()
                assert prefix.with_name(prefix.name+'-camera-tracks.atlascameratracks').is_file()
                measurements.append({'edit_ms':(edit_done-started)*1000,'edit_to_ready_ms':(time.monotonic()-started)*1000,'revision':snapshot['revision']})
                (work/'preview-ack.txt').write_text(str(cooker.serial))
            # Only the latest queued revision may be published.
            first=stage.request('attribute',path='/Camera0',name='focalLength',value=71,time=12.5);cooker.schedule(first)
            last=stage.request('attribute',path='/Camera0',name='focalLength',value=73,time=12.5);cooker.schedule(last)
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                cooker.tick(stage);fields=(work/'preview.tsv').read_text().strip().split('\t')
                if fields[0]=='ERROR':raise AssertionError(fields)
                if fields[0]=='READY':assert int(fields[1])==last['revision'];break
                time.sleep(.01)
            else:raise AssertionError('Latest revision was not published')
        finally:cooker.close()
report={'scope':'36 animated cameras and 128 animated transform prims; no mesh conversion or GPU upload latency claim',
        'samples':measurements,'median_edit_ms':statistics.median(m['edit_ms'] for m in measurements),
        'median_edit_to_ready_ms':statistics.median(m['edit_to_ready_ms'] for m in measurements),
        'latest_revision_publication':True,'passed':True}
(ROOT/'build/usd-animation-latency.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
