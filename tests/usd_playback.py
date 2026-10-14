"""Independent rig/morph/camera/light fixture with a nonzero USD start frame."""
import importlib.util,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
blender=os.environ.get('ATLAS_BLENDER',str(ROOT/'.deps/blender-source/build/bin/blender'))
rig=ROOT/'build/usd-playback-rig.usdc'
subprocess.run([blender,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
               '--python',str(ROOT/'tests/usd_rig_fixture.py'),'--',str(rig)],check=True,stdout=subprocess.DEVNULL)
source=ROOT/'build/usd-playback.usda'
source.write_text('''#usda 1.0
(metersPerUnit = 1
 upAxis = "Z"
 startTimeCode = 1
 endTimeCode = 5
 timeCodesPerSecond = 24
 subLayers = [@usd-playback-rig.usdc@])
def Camera "Shot" {
 float focalLength = 35
 float horizontalAperture = 36
 float verticalAperture = 24
 float2 clippingRange = (0.1,100)
 double3 xformOp:translate.timeSamples = {1:(1,-6,2),5:(1.3,-6,2)}
 float3 xformOp:rotateXYZ = (75,0,0)
 uniform token[] xformOpOrder = ["xformOp:translate","xformOp:rotateXYZ"]
}
def DomeLight "Sky" {
 float inputs:intensity.timeSamples = {1:1,5:2}
 color3f inputs:color = (0.8,0.9,1)
}
''')
spec=importlib.util.spec_from_file_location('cook',ROOT/'scripts/cook-assets.py')
cook=importlib.util.module_from_spec(spec);spec.loader.exec_module(cook)
output=ROOT/'build/usd-playback-cooked'
cook.cook(source,output,'preview')
manifest=(output/'preview-playback.atlasplayback').read_text()
assert all('\n'+kind+'\t' in manifest for kind in ('skin','clip','weights'))
times=[float(line.split()[4]) for line in (output/'preview-animation-0.atlasclip').read_text().splitlines()[1:]]
assert min(times)==0 and abs(max(times)-4/24)<1e-6,times
weights=[float(line.split('\t')[3]) for line in next(output.glob('preview-animation-*.atlasmorphclip')).read_text().splitlines()[1:]]
assert min(weights)==0 and abs(max(weights)-4/24)<1e-6,weights
camera=(output/'preview-camera-tracks.atlascameratracks').read_text().splitlines()
assert float(camera[1].split('\t')[1])==0
assert abs(float(camera[-1].split('\t')[1])-max(times))<1e-6
print('USD playback fixture passed: shared zero-based clock, skin/morph bindings and authored camera/light tracks')
