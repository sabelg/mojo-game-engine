"""Portable USDZ import and bounded archive rejection without publication changes."""
import importlib.util,zipfile,json,warnings
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
cook=module('cook','cook-assets.py');session=module('session','usd-session.py')
work=ROOT/'build/usdz-cook-test';work.mkdir(parents=True,exist_ok=True)
source=work/'source.usda';source.write_text('''#usda 1.0
(metersPerUnit = 1)
def Mesh "Triangle" {
 uniform token subdivisionScheme = "none"
 point3f[] points = [(0,0,0),(1,0,0),(0,1,0)]
 int[] faceVertexCounts = [3]
 int[] faceVertexIndices = [0,1,2]
}
''')
package=work/'portable.usdz'
if package.exists():package.unlink()
with session.StageSession() as stage:
 stage.request('open',source=str(source));stage.request('package',destination=str(package))
original=source.read_bytes();source.unlink()
try:
 assert cook.cook(package,work/'cooked','portable') in ('cooked','cached')
 assert cook.cook(package,work/'cooked','portable')=='cached'
 report=json.loads((work/'cooked/portable-source.json').read_text())
 assert report['source']==str(package) and str(package) in report['dependencies']
finally:source.write_bytes(original)
before=(work/'cooked/portable-cook.json').read_bytes()
for name,entries,compression in [('traversal',[('../escape.usda',original)],0),('duplicate',[('scene.usda',original),('scene.usda',original)],0),('compressed',[('scene.usda',original)],8),('root',[('texture.png',b'abc')],0),('missing',[('scene.usda',b'#usda 1.0\n(subLayers = [@missing.usda@])\n')],0)]:
 bad=work/(name+'.usdz')
 with warnings.catch_warnings():
  warnings.simplefilter('ignore')
  with zipfile.ZipFile(bad,'w',compression=compression) as archive:
   for path,data in entries:archive.writestr(path,data)
 try:cook.cook(bad,work/'cooked','portable')
 except ValueError:pass
 else:raise AssertionError('Accepted '+name)
 assert before==(work/'cooked/portable-cook.json').read_bytes()
assert not (ROOT/'build/usd-packages/escape.usda').exists()
print('USDZ cooker passed: portable import, cache, provenance, archive bounds and atomic rejection')

corrupt=work/'crc.usdz'
with zipfile.ZipFile(corrupt,'w') as archive:archive.writestr('scene.usda',original)
data=bytearray(corrupt.read_bytes());at=data.index(original);data[at]^=1;corrupt.write_bytes(data)
try:cook.cook(corrupt,work/'cooked','portable')
except ValueError:pass
else:raise AssertionError('Accepted bad archive CRC')
assert before==(work/'cooked/portable-cook.json').read_bytes()
print('USDZ CRC rejection passed')
