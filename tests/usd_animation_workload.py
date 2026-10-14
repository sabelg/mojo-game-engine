"""Bounded real mesh/rig edit-to-preview acceptance, separate from endurance."""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shutil
import statistics
import time

ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value

def array(items):return '['+','.join(items)+']'
def vector(x,y,z):return f'({x:.7g},{y:.7g},{z:.7g})'
def matrix(y):return f'((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,{y:.7g},0,1))'
def fixture():
    side=100;count=side*side
    points=[vector((x/(side-1)-.5)*4,0,(z/(side-1)-.5)*4) for z in range(side) for x in range(side)]
    faces=[]
    for z in range(side-1):
        for x in range(side-1):
            a=z*side+x;faces.extend([a,a+side,a+1,a+1,a+side,a+side+1])
    indices=[];weights=[]
    for z in range(side):
        joint=min(30,z*31//side)
        for _ in range(side):indices.extend([joint,joint+1]);weights.extend(['0.75','0.25'])
    names=['"root"']+['"root/j'+str(i)+'"' for i in range(1,32)]
    times=[0,1.25,12.5,24]
    translations=[];rotations=[];scales=[]
    for t in times:
        phase=t/24;translations.append(f'{t}:'+array(vector(.5*math.sin(phase*math.pi),i*.02,0) if i==0 else vector(0,i*.02,0) for i in range(32)))
        rotations.append(f'{t}:'+array(f'({math.cos(.12*math.sin(phase*math.pi+i*.1)):.7g},0,0,{math.sin(.12*math.sin(phase*math.pi+i*.1)):.7g})' for i in range(32)))
        scales.append(f'{t}:'+array('(1,1,1)' for _ in range(32)))
    wave=[vector(0,.15*math.sin(x*.12)*math.cos(z*.12),0) for z in range(side) for x in range(side)]
    bend=[vector(0,0,.1*(x/(side-1)-.5)) for z in range(side) for x in range(side)]
    return '''#usda 1.0
(metersPerUnit=1; upAxis="Y";startTimeCode=0;endTimeCode=24;timeCodesPerSecond=24)
def SkelRoot "Rig" {
 def Skeleton "Skeleton" (prepend apiSchemas=["SkelBindingAPI"]) {
 uniform token[] joints='''+array(names)+'''
 uniform matrix4d[] bindTransforms='''+array(matrix(i*.02) for i in range(32))+'''
 uniform matrix4d[] restTransforms='''+array(matrix(i*.02) for i in range(32))+'''
 rel skel:animationSource=</Rig/Animation>
 }
 def SkelAnimation "Animation" {
 uniform token[] joints='''+array(names)+'''
 float3[] translations.timeSamples={'''+','.join(translations)+'''}
 quatf[] rotations.timeSamples={'''+','.join(rotations)+'''}
 half3[] scales.timeSamples={'''+','.join(scales)+'''}
 uniform token[] blendShapes=["Wave","Bend"]
 float[] blendShapeWeights.timeSamples={0:[0,0],1.25:[0.2,0.5],12.5:[0.8,0.4],24:[0.1,0.9]}
 }
 def Mesh "Mesh" (prepend apiSchemas=["SkelBindingAPI"]) {
 uniform token subdivisionScheme="none"
 point3f[] points='''+array(points)+'''
 int[] faceVertexCounts='''+array('3' for _ in range(len(faces)//3))+'''
 int[] faceVertexIndices='''+array(str(i) for i in faces)+'''
 rel skel:skeleton=</Rig/Skeleton>
 int[] primvars:skel:jointIndices='''+array(str(i) for i in indices)+''' (interpolation="vertex";elementSize=2)
 float[] primvars:skel:jointWeights='''+array(weights)+''' (interpolation="vertex";elementSize=2)
 uniform token[] skel:blendShapes=["Wave","Bend"]
 rel skel:blendShapeTargets=[</Rig/Wave>,</Rig/Bend>]
 }
 def BlendShape "Wave" {
 uniform int[] pointIndices='''+array(str(i) for i in range(count))+'''
 vector3f[] offsets='''+array(wave)+'''
 }
 def BlendShape "Bend" {
 uniform int[] pointIndices='''+array(str(i) for i in range(count))+'''
 vector3f[] offsets='''+array(bend)+'''
 }
}
def Camera "Camera" {
 float focalLength.timeSamples={0:40,1.25:55,12.5:65,24:50}
 double3 xformOp:translate=(0,3,6)
 uniform token[] xformOpOrder=["xformOp:translate"]
}
'''

def owned_rss(pid):
    """Sample only the owned cook process and descendants, without command lines."""
    pending=[pid];seen=set();total=0
    while pending:
        current=pending.pop()
        if current in seen:continue
        seen.add(current)
        try:
            status=Path(f'/proc/{current}/status').read_text()
            total+=next((int(line.split()[1])*1024 for line in status.splitlines() if line.startswith('VmRSS:')),0)
            pending.extend(int(x) for x in Path(f'/proc/{current}/task/{current}/children').read_text().split())
        except (OSError,ValueError):pass
    return total

api=module('workload_api','usd-session.py');preview=module('workload_preview','usd-preview.py')
work=ROOT/'build/usd-m03-workload';shutil.rmtree(work,ignore_errors=True);work.mkdir()
source=work/'source.usda';source.write_text(fixture());original=source.read_bytes();samples=[];peak=0
with api.StageSession() as stage:
    snapshot=stage.request('open',source=str(source));cooker=preview.PreviewCooker(work,animated=True)
    def ready(snapshot,started):
        global peak
        deadline=started+30
        while time.monotonic()<deadline:
            cooker.tick(stage)
            if cooker.job:peak=max(peak,owned_rss(cooker.job.pid))
            fields=(work/'preview.tsv').read_text().strip().split('\t')
            if fields[0]=='ERROR':raise AssertionError(fields)
            if fields[0]=='READY':
                assert int(fields[1])==snapshot['revision'];return Path(fields[2])
            time.sleep(.01)
        raise AssertionError('Representative mesh preview exceeded 30-second acceptance bound')
    try:
        for name,channel,value,timecode in [('translations',0,.7,12.5),('blendShapeWeights',0,.6,12.5),('rotations',3,.15,1.25)]:
            started=time.monotonic();snapshot=stage.request('set_channel',path='/Rig/Animation',name=name,channel=channel,value=value,time=timecode)
            edited=time.monotonic();cooker.schedule(snapshot);prefix=ready(snapshot,started)
            rows=(prefix.with_name(prefix.name+'-playback.atlasplayback')).read_text()
            assert all('\n'+kind+'\t' in rows for kind in ('skin','clip','weights'))
            provenance=json.loads(prefix.with_name(prefix.name+'-source.json').read_text())
            assert provenance['conversion']['conversion_timing']['conversion_grid_factor']==4
            samples.append({'attribute':name,'revision':snapshot['revision'],'edit_ms':(edited-started)*1000,'edit_to_ready_ms':(time.monotonic()-started)*1000})
            (work/'preview-ack.txt').write_text(str(cooker.serial))
        # Cancel a running owned conversion and publish only the later revision.
        snapshot=stage.request('set_channel',path='/Rig/Animation',name='translations',channel=0,value=.9,time=12.5)
        cooker.schedule(snapshot);time.sleep(.21);cooker.tick(stage);assert cooker.job is not None
        cancelled_pid=cooker.job.pid;cancelled_directory=cooker.directory;started=time.monotonic()
        latest=stage.request('set_channel',path='/Rig/Animation',name='translations',channel=0,value=1.1,time=12.5)
        cooker.schedule(latest);assert cooker.job is None and not cancelled_directory.exists()
        prefix=ready(latest,started);assert not Path(f'/proc/{cancelled_pid}').exists()
        assert len(list(cooker.root.iterdir()))<=4
        publication=work/'accepted';shutil.copytree(prefix.parent,publication)
        files=list(publication.rglob('*'));bundle=sum(p.stat().st_size for p in files if p.is_file())
        assert bundle<64*1024*1024 and peak<768*1024*1024,(bundle,peak)
    finally:cooker.close()
assert source.read_bytes()==original
report={'passed':True,'scope':'Synthetic representative bounded fixture; 10000 source vertices, 19602 triangles, 32 joints, two morphs and animated camera; not production art or endurance',
        'source_sha256':hashlib.sha256(original).hexdigest(),'samples':samples,
        'median_edit_ms':statistics.median(x['edit_ms'] for x in samples),'median_edit_to_ready_ms':statistics.median(x['edit_to_ready_ms'] for x in samples),
        'peak_sampled_owned_cook_rss_bytes':peak,'published_directory_bytes':bundle,
        'limits':{'edit_to_ready_seconds':30,'sampled_owned_rss_bytes':768*1024*1024,'published_directory_bytes':64*1024*1024,'unacknowledged_publications':4},
        'running_revision_cancelled':True,'latest_revision_published':True,'source_unchanged':True}
(ROOT/'build/usd-animation-workload.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
