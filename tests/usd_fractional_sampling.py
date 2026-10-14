"""Fractional rig/morph/camera keys survive the bounded conversion frame grid."""
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
FIXTURE='''#usda 1.0
(metersPerUnit=1
 upAxis="Y"
 startTimeCode=0
 endTimeCode=5
 timeCodesPerSecond=24)
def SkelRoot "Rig" {
 def Skeleton "Skeleton" (prepend apiSchemas=["SkelBindingAPI"]) {
  uniform token[] joints=["root"]
  uniform matrix4d[] bindTransforms=[((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,0,0,1))]
  uniform matrix4d[] restTransforms=[((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,0,0,1))]
  rel skel:animationSource=</Rig/Animation>
 }
 def SkelAnimation "Animation" {
  uniform token[] joints=["root"]
  float3[] translations.timeSamples={0:[(0,0,0)],1.25:[(3,0,0)],3.5:[(1,0,0)],5:[(2,0,0)]}
  quatf[] rotations.timeSamples={0:[(1,0,0,0)],1.25:[(0.70710678,0,0,0.70710678)],3.5:[(1,0,0,0)],5:[(0,0,0,1)]}
  half3[] scales.timeSamples={0:[(1,1,1)],1.25:[(1,2,1)],3.5:[(1,1,1)],5:[(1,1,1)]}
  uniform token[] blendShapes=["Smile"]
  float[] blendShapeWeights.timeSamples={0:[0],1.25:[0.75],3.5:[0.25],5:[1]}
 }
 def Mesh "Mesh" (prepend apiSchemas=["SkelBindingAPI"]) {
  uniform token subdivisionScheme="none"
  point3f[] points=[(0,0,0),(1,0,0),(0,0,1)]
  int[] faceVertexCounts=[3]
  int[] faceVertexIndices=[0,1,2]
  rel skel:skeleton=</Rig/Skeleton>
  int[] primvars:skel:jointIndices=[0,0,0] (interpolation="vertex";elementSize=1)
  float[] primvars:skel:jointWeights=[1,1,1] (interpolation="vertex";elementSize=1)
  uniform token[] skel:blendShapes=["Smile"]
  rel skel:blendShapeTargets=[</Rig/Smile>]
 }
 def BlendShape "Smile" {
  uniform int[] pointIndices=[0,1,2]
  vector3f[] offsets=[(0,0.5,0),(0,0.5,0),(0,0.5,0)]
 }
}
def Camera "Camera" {
 float focalLength.timeSamples={0:40,1.25:65,3.5:55,5:80}
 float horizontalAperture=36
 float verticalAperture=24
 float2 clippingRange=(0.1,100)
 double3 xformOp:translate=(0,0,5)
 uniform token[] xformOpOrder=["xformOp:translate"]
}
'''
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def main():
    api=module('api','usd-session.py');usd=module('usd','cook-usd.py')
    inspector=ROOT/'.deps/usd-tools/bin/atlas-usd-inspect';oracle=ROOT/'build/usd-pose-oracle'
    if not oracle.is_file():
        base=ROOT/'.deps/blender-source';sdk=base/'lib/linux_arm64'
        subprocess.run([str(base/'compiler/usr/bin/g++-14'),'-std=c++17','-O1',str(ROOT/'tests/usd_pose_oracle.cc'),
         '-I'+str(sdk/'usd/include'),'-I'+str(sdk/'tbb/include'),'-I'+str(sdk/'python/include/python3.13'),
         '-L'+str(base/'build/bin/lib'),'-Wl,-rpath,'+str(base/'build/bin/lib'),'-Wl,-rpath-link,'+str(base/'build/bin/lib'),
         '-lusd_ms','-ltbb',str(sdk/'python/lib/libpython3.13.a'),'-ldl','-lpthread','-lm','-lutil','-o',str(oracle)],check=True)
    source=ROOT/'build/usd-fractional-rig-source.usda';source.write_text(FIXTURE);original=source.read_bytes()
    with tempfile.TemporaryDirectory(prefix='usd-fractional-sampling-',dir=ROOT/'build') as tmp:
        root=Path(tmp);converted=root/'converted.usdc'
        report=json.loads(subprocess.check_output([str(inspector),str(source),str(converted)],text=True))
        assert report['conversion_grid_factor']==4 and report['conversion_time_codes_per_second']==96
        assert report['meshes']==1 and report['skeletons']==1
        times=[s['seconds']*24 for s in report['camera_tracks'][0]['samples']]
        assert 1.25 in times and 3.5 in times,times
        samples=report['camera_tracks'][0]['samples']
        assert math.isclose(next(s for s in samples if s['seconds']*24==1.25)['projection'][0],130/36,abs_tol=1e-5)
        for time in [0,.5,.625,1.25,2.25,3.5,4.5,5]:
            before=json.loads(subprocess.check_output([str(oracle),str(source),str(time)],text=True))
            after=json.loads(subprocess.check_output([str(oracle),str(converted),str(time*4)],text=True))
            assert len(before)==len(after)==1
            assert max(abs(x-y) for a,b in zip(before[0]['joint_matrices'],after[0]['joint_matrices']) for x,y in zip(a,b))<1e-5,(time,before,after)
            assert max(abs(x-y) for x,y in zip(before[0]['weights'],after[0]['weights']))<1e-6
        with api.StageSession() as stage:
            state=stage.request('open',source=str(converted));assert state['time_codes_per_second']==96 and state['end']==20
            curve=next(c for c in stage.request('curves',path='/Rig/Animation',time=5)['curves'] if c['name']=='blendShapeWeights')
            assert [k['time'] for k in curve['keys']]==list(range(21))
        # Nonzero fractional start keeps the physical duration and starts at the
        # exact source pose, rather than truncating Blender's integer range.
        shifted=root/'shifted.usda';shifted.write_text(FIXTURE.replace('startTimeCode=0','startTimeCode=1.25'))
        shifted_report=json.loads(subprocess.check_output([str(inspector),str(shifted),str(root/'shifted.usdc')],text=True))
        assert shifted_report['conversion_start']==5 and shifted_report['conversion_end']==20
        assert shifted_report['camera_tracks'][0]['samples'][0]['seconds']==0
        bad=root/'bad.usda';bad.write_text(FIXTURE.replace('1.25:','1.123456789:'))
        failure=subprocess.run([str(inspector),str(bad),str(root/'bad.usdc')],capture_output=True,text=True)
        assert failure.returncode and '64 conversion samples' in failure.stderr and not (root/'bad.usdc').exists()
        for start,end in [(-1,5),(1048570,1048575)]:
            outside=root/'outside.usda';outside.write_text(FIXTURE.replace('startTimeCode=0',f'startTimeCode={start}').replace('endTimeCode=5',f'endTimeCode={end}'))
            failure=subprocess.run([str(inspector),str(outside),str(root/'outside.usdc')],capture_output=True,text=True)
            assert failure.returncode and 'outside Blender profile' in failure.stderr and not (root/'outside.usdc').exists()
        # Persist companion tracks for a real runtime sample check.
        (ROOT/'build/usd-fractional-camera.atlascameratracks').write_text(usd.camera_track_assets(report)['camera-tracks.atlascameratracks'])
    assert source.read_bytes()==original
    print('Fractional conversion sampling passed: exact authored times, independent '
          'USD Skel poses/morph weights at/between keys, camera tracks, physical '
          'duration, nonzero start and explicit fine-grid rejection')

if __name__=='__main__':main()
