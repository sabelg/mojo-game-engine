"""Create independent camera optics fixtures for the Mojo/runtime regression."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('usd_cook', ROOT / 'scripts/cook-usd.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = ROOT / 'build/usd-camera-fixture.usda'
source.write_text('''#usda 1.0
(metersPerUnit = 0.01; upAxis = "Z")
def Camera "Perspective" {
    float horizontalAperture = 36
    float verticalAperture = 24
    float horizontalApertureOffset = 3.6
    float focalLength = 40
    float2 clippingRange = (10, 10000)
    matrix4d xformOp:transform = ((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,-500,0,1))
    uniform token[] xformOpOrder = ["xformOp:transform"]
}
def Camera "Orthographic" {
    token projection = "orthographic"
    float horizontalAperture = 3600
    float verticalAperture = 2400
    float2 clippingRange = (10, 10000)
    matrix4d xformOp:transform = ((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,-500,0,1))
    uniform token[] xformOpOrder = ["xformOp:transform"]
}
'''.replace('; upAxis', '\n upAxis'))
inspector = os.environ.get('ATLAS_USD_INSPECT', str(ROOT / '.deps/usd-tools/bin/atlas-usd-inspect'))
report = json.loads(subprocess.check_output([inspector, str(source)]))
assert len(report['cameras']) == 2
(ROOT / 'build/usd-camera-fixture.atlascameras').write_text(module.camera_assets(report)['cameras.atlascameras'])
print('USD camera fixture prepared: centimetres, Z-up, lens shift, perspective and orthographic')

# The complete cooker must publish camera samples into its immutable generation.
spec = importlib.util.spec_from_file_location('asset_cook', ROOT / 'scripts/cook-assets.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
mesh_source = ROOT / 'build/usd-camera-mesh.usda'
mesh_source.write_text(source.read_text()+'''
def DistantLight "Sun" {
    float inputs:intensity = 3
    float inputs:exposure = 1
    bool inputs:normalize = true
    color3f inputs:color = (1,0.5,0.25)
}
def DomeLight "Fill" {
    float inputs:intensity = 0.2
    color3f inputs:color = (0.5,0.5,0.5)
}

def Mesh "Triangle" {
    uniform token subdivisionScheme = "none"
    point3f[] points = [(0,0,0),(100,0,0),(0,100,0)]
    int[] faceVertexCounts = [3]
    int[] faceVertexIndices = [0,1,2]
}''')
output = ROOT/'build/usd-camera-cooked'
api.cook(mesh_source, output, 'camera')
state = json.loads((output/'camera-cook.json').read_text())
camera_file = output/'camera-cameras.atlascameras'
assert camera_file.read_bytes() == (output/state['generation']/camera_file.name).read_bytes()
assert api.cook(mesh_source, output, 'camera') == 'cached'
print('USD camera cooker passed: immutable publication and repeated-import cache')

(ROOT/'build/usd-light-fixture.atlaslights').write_bytes((output/'camera-lights.atlaslights').read_bytes())

rows=(ROOT/'build/usd-camera-fixture.atlascameras').read_text().splitlines()
(ROOT/'build/usd-camera-legacy.atlascameras').write_text('ATLAS_CAMERAS_1\n'+'\n'.join('\t'.join(row.split('\t')[:-1]) for row in rows[1:])+'\n')
