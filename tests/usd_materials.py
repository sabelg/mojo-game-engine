"""Constant opaque MaterialX factors, source immutability and failure atomicity."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('asset_cook', ROOT/'scripts/cook-assets.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
source_text = '''#usda 1.0
(metersPerUnit = 1)
def Xform "World" {
 def Mesh "Triangle" {
  uniform token subdivisionScheme = "none"
  point3f[] points = [(0,0,0),(1,0,0),(0,1,0)]
  int[] faceVertexCounts = [3]
  int[] faceVertexIndices = [0,1,2]
  rel material:binding = </World/Paint>
 }
 def Material "Paint" {
  token outputs:mtlx:surface.connect = </World/Paint/Surface.outputs:out>
  def Shader "Surface" {
   uniform token info:id = "SHADER"
   color3f inputs:base_color = (0.2, 0.3, 0.4)
   float inputs:METAL = 0.25
   float inputs:specular_roughness = 0.6
   token outputs:out
  }
 }
}
'''
with tempfile.TemporaryDirectory(prefix='usd-materials-', dir=ROOT/'build') as work:
    work = Path(work)
    for shader, metal in [('ND_standard_surface_surfaceshader','metalness'),
                          ('ND_open_pbr_surface_surfaceshader','base_metalness')]:
        source = work/(shader+'.usda')
        text = source_text.replace('SHADER',shader).replace('METAL',metal)
        source.write_text(text)
        original = hashlib.sha256(source.read_bytes()).hexdigest()
        output = work/shader
        api.cook(source,output,'material')
        assert hashlib.sha256(source.read_bytes()).hexdigest() == original
        manifest = output/'material-assets.atlas'
        data = manifest.read_bytes()
        material = next(line.split('\t') for line in data.decode().splitlines() if line.startswith('material\t'))
        for actual, expected in zip(map(float,material[3:8]),[.2,.3,.4,.6,.25]):
            assert abs(actual-expected)<1e-5,material
        provenance = json.loads((output/'material-source.json').read_text())
        assert provenance['stage']['material_translations'][0]['source']==shader
        # Unsupported layered effects must fail before changing the active asset.
        bad_name = 'coat_weight' if 'open_pbr' in shader else 'coat'
        source.write_text(text.replace('token outputs:out',f'float inputs:{bad_name} = 0.5\n   token outputs:out'))
        try:
            api.cook(source,output,'material')
        except ValueError as error:
            assert 'unsupported MaterialX input' in str(error),error
        else:
            raise AssertionError('Unsupported coat was silently discarded')
        assert manifest.read_bytes()==data
    # Color-space metadata must be converted, not merely stripped.
    source=work/'srgb.usda'
    source.write_text(source_text.replace('SHADER','ND_open_pbr_surface_surfaceshader').replace('METAL','base_metalness').replace('(0.2, 0.3, 0.4)', '(0.5, 0.5, 0.5) (colorSpace = "srgb_texture")'))
    output=work/'srgb'
    api.cook(source,output,'color')
    row=next(line.split('\t') for line in (output/'color-assets.atlas').read_text().splitlines() if line.startswith('material\t'))
    assert abs(float(row[3])-.21404114)<1e-5,row
print('USD MaterialX profile passed: Standard Surface/OpenPBR factors, immutable sources, unsupported-effect rejection')
