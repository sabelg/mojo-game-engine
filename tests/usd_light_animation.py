import importlib.util,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('usd',ROOT/'scripts/cook-usd.py')
usd=importlib.util.module_from_spec(spec);spec.loader.exec_module(usd)
source=ROOT/'build/usd-light-animation.usda'
source.write_text('''#usda 1.0
(
 metersPerUnit = 1
 upAxis = "Y"
 startTimeCode = 1
 endTimeCode = 25
 timeCodesPerSecond = 24
)
def DistantLight "Sun" {
 bool inputs:normalize = true
 float inputs:intensity.timeSamples = {1: 2, 25: 6}
 float inputs:exposure = 1
 float xformOp:rotateY.timeSamples = {1: 0, 25: 90}
 uniform token[] xformOpOrder = ["xformOp:rotateY"]
}
def DomeLight "Fill" {
 float inputs:intensity.timeSamples = {1: 0.1, 25: 0.3}
}
''')
inspector=os.environ.get('ATLAS_USD_INSPECT',str(ROOT/'.deps/usd-tools/bin/atlas-usd-inspect'))
report=json.loads(subprocess.check_output([inspector,source]))
assert len(report['light_tracks'])==2
assert abs(report['light_tracks'][0]['samples'][12]['rgb'][0]-8)<1e-5
(ROOT/'build/usd-light-animation.atlaslighttracks').write_text(usd.light_track_assets(report)['light-tracks.atlaslighttracks'])
(ROOT/'build/usd-light-animation.atlaslights').write_text(usd.light_assets(report)['lights.atlaslights'])
print('USD light animation fixture passed: light rotation, exposure and intensity')
