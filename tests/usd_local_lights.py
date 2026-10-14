import importlib.util,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('usd',ROOT/'scripts/cook-usd.py')
usd=importlib.util.module_from_spec(spec);spec.loader.exec_module(usd)
source=ROOT/'build/usd-local-light.usda'
source.write_text('''#usda 1.0
(metersPerUnit = 0.01)
def SphereLight "Point" {
 bool treatAsPoint = true
 bool inputs:normalize = true
 float inputs:intensity = 32
 double3 xformOp:translate = (0,0,200)
 uniform token[] xformOpOrder = ["xformOp:translate"]
}
''')
inspector=os.environ.get('ATLAS_USD_INSPECT',str(ROOT/'.deps/usd-tools/bin/atlas-usd-inspect'))
report=json.loads(subprocess.check_output([inspector,source]))
assert len(report['local_lights'])==1
assert report['local_lights'][0]['position']==[0,0,2]
assert report['local_lights'][0]['intensity']==[8,8,8]
(ROOT/'build/usd-local-light.atlaslocallights').write_text(usd.local_light_assets(report)['local-lights.atlaslocallights'])
print('USD local light fixture passed: point hint, normalized spherical emission and centimetre conversion')

# Equal axis lengths alone do not establish isotropic scale: reject shear too.
sheared=ROOT/'build/usd-local-light-shear.usda'
sheared.write_text(source.read_text().replace('double3 xformOp:translate = (0,0,200)',
    'matrix4d xformOp:transform = ((1,0,0,0),(0.6,0.8,0,0),(0,0,1,0),(0,0,200,1))').replace('"xformOp:translate"','"xformOp:transform"'))
assert json.loads(subprocess.check_output([inspector,sheared]))['local_lights']==[], 'Sheared sphere must remain authoring-only'
print('USD local light shear exclusion passed')
