"""Independent camera-parent movement and changing lens fixture."""
import importlib.util,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('usd',ROOT/'scripts/cook-usd.py')
usd=importlib.util.module_from_spec(spec);spec.loader.exec_module(usd)
source=ROOT/'build/usd-camera-animation.usda'
source.write_text('''#usda 1.0
(
 metersPerUnit = 1
 upAxis = "Y"
 startTimeCode = 1
 endTimeCode = 25
 timeCodesPerSecond = 24
)
def Xform "Dolly" {
 double3 xformOp:translate.timeSamples = {1: (0,0,5), 25: (4,0,5)}
 uniform token[] xformOpOrder = ["xformOp:translate"]
 def Camera "Camera" {
  float horizontalAperture = 36
  float verticalAperture = 24
  float exposure.timeSamples = {1: 0, 25: 2}
  float exposure:iso = 200
  float exposure:time = 0.25
  float exposure:fStop = 2
  float exposure:responsivity = 4
  float focalLength.timeSamples = {1: 40, 25: 80}
  float2 clippingRange = (0.1, 100)
 }
}
''')
inspector=os.environ.get('ATLAS_USD_INSPECT',str(ROOT/'.deps/usd-tools/bin/atlas-usd-inspect'))
report=json.loads(subprocess.check_output([inspector,source]))
samples=report['camera_tracks'][0]['samples']
assert len(samples)==25 and samples[-1]['seconds']==1
assert samples[12]['world'][12]==2
assert abs(samples[12]['projection'][0]-120/36)<1e-5
(ROOT/'build/usd-camera-animation.atlascameratracks').write_text(usd.camera_track_assets(report)['camera-tracks.atlascameratracks'])
print('USD camera animation fixture passed: parent motion, focal length, timing and sample budget')

assert abs(samples[0]['exposure_scale']-.5)<1e-6
assert abs(samples[12]['exposure_scale']-1)<1e-6
assert abs(samples[24]['exposure_scale']-2)<1e-6
lines=(ROOT/'build/usd-camera-animation.atlascameratracks').read_text().splitlines()
(ROOT/'build/usd-camera-legacy.atlascameratracks').write_text('ATLAS_CAMERA_TRACKS_1\n'+'\n'.join('\t'.join(row.split('\t')[:-1]) for row in lines[1:])+'\n')
invalid=ROOT/'build/usd-camera-bad-exposure.usda';invalid.write_text(source.read_text().replace('exposure:fStop = 2','exposure:fStop = 0'))
assert subprocess.run([inspector,invalid],capture_output=True).returncode!=0
print('Physical camera exposure passed: ISO/time/f-stop/responsivity/EV and invalid aperture rejection')
