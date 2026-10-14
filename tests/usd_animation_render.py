"""Prepare native authored cameras and an independent analytic lens reference."""
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
api=module('api','usd-session.py');usd=module('usd','cook-usd.py')
source=ROOT/'build/usd-m03-render-source.usda'
source.write_text('''#usda 1.0
(metersPerUnit=1
 upAxis="Y"
 startTimeCode=0
 endTimeCode=10
 timeCodesPerSecond=24)
def Camera "Camera" {
 float focalLength.timeSamples={0:40,10:80}
 float horizontalAperture=36
 float verticalAperture=24
 float2 clippingRange=(0.1,100)
 double3 xformOp:translate=(0,0,5)
 uniform token[] xformOpOrder=["xformOp:translate"]
}
''')
original=source.read_bytes();actual=[];expected=[]
with api.StageSession() as stage:
    stage.request('open',source=str(source));stage.request('set_interpolation',path='/Camera',name='focalLength',mode='bezier')
    for i,time in enumerate([0,2.5,7.5,10]):
        camera=next(p for p in stage.request('snapshot',time=time)['prims'] if p['id']=='/Camera')['atlas_camera']
        camera['id']='/Camera-'+str(i);actual.append(camera)
        u=time/10;focal=40+40*(3*u*u-2*u*u*u)
        projection=[0.0]*16;projection[0]=2*focal/36;projection[5]=2*focal/24
        projection[10]=-(100+.1)/(100-.1);projection[11]=-1;projection[14]=-2*100*.1/(100-.1)
        world=[1.0,0,0,0,0,1.0,0,0,0,0,1.0,0,0,0,5.0,1.0]
        reference={'id':'/Expected-'+str(i),'projection':projection,'world':world,'exposure_scale':1}
        assert max(abs(a-b) for a,b in zip(camera['projection'],projection))<1e-6
        assert camera['world']==world
        expected.append(reference)
for name,values in [('actual',actual),('expected',expected)]:
    (ROOT/('build/usd-m03-render-'+name+'.atlascameras')).write_text(usd.camera_assets({'cameras':values})['cameras.atlascameras'])
assert source.read_bytes()==original
print('Prepared four native spline camera samples and independent analytic projections at keys/between keys')
