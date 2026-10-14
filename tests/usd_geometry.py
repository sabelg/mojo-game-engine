"""Explicit subdivision bakes and stable identities of repeated USD instances."""
import importlib.util
import json
from pathlib import Path
import tempfile
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('asset_cook',ROOT/'scripts/cook-assets.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
with tempfile.TemporaryDirectory(prefix='usd-geometry-',dir=ROOT/'build') as work:
    work = Path(work)
    source = work/'subdivision.usda'
    source.write_text('''#usda 1.0
(metersPerUnit = 1)
def Mesh "Quad" {
    uniform token subdivisionScheme = "catmullClark"
    custom int userProperties:atlas_subdivision_level = 2
    point3f[] points = [(-1,-1,0),(1,-1,0),(1,1,0),(-1,1,0)]
    int[] faceVertexCounts = [4]
    int[] faceVertexIndices = [0,1,2,3]
}
''')
    output = work/'cooked'
    api.cook(source,output,'surface')
    report = json.loads((output/'surface-source.json').read_text())
    assert report['conversion']['geometry_bakes'][0]['level']==2
    manifest = (output/'surface-assets.atlas').read_text()
    mesh_name = next(row.split('\t')[2] for row in manifest.splitlines() if row.startswith('mesh\t'))
    data = next(output.glob('surface-*.atlasmesh')).read_text().splitlines()
    assert len(data)>20, data
    base = work/'base.usda'
    base.write_text('''#usda 1.0
(defaultPrim = "Asset")
def Xform "Asset" {
 def Mesh "Shape" {
    uniform token subdivisionScheme = "none"
    point3f[] points = [(0,0,0),(1,0,0),(0,1,0)]
    int[] faceVertexCounts = [3]
    int[] faceVertexIndices = [0,1,2]
 }
}
''')
    source = work/'instances.usda'
    source.write_text('''#usda 1.0
(metersPerUnit = 1)
def Xform "World" {
 def Xform "One" (instanceable = true; prepend references = @base.usda@) {}
 def Xform "Two" (instanceable = true; prepend references = @base.usda@) {
    double3 xformOp:translate = (3,0,0)
    uniform token[] xformOpOrder = ["xformOp:translate"]
 }
}
'''.replace('; prepend', '\n prepend'))
    api.cook(source,output,'instances')
    text = (output/'instances-scene.scene').read_text()
    # Blender merges each single-mesh parent transform; occurrence IDs remain distinct.
    assert '/World/One' in text and '/World/Two' in text, text
    report = json.loads((output/'instances-source.json').read_text())
    assert report['stage']['meshes']==report['conversion']['mesh_objects']==2
print('USD geometry tests passed: explicit subdivision bake and repeated-instance path identities')
