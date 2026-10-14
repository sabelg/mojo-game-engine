"""Visibility on mesh and ancestor with fractional source time boundaries."""
import importlib.util,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('cook',ROOT/'scripts/cook-assets.py');cook=importlib.util.module_from_spec(spec);spec.loader.exec_module(cook)
work=ROOT/'build/usd-visibility-test';work.mkdir(parents=True,exist_ok=True)
source=work/'visibility.usda';source.write_text('''#usda 1.0
(startTimeCode = 1
endTimeCode = 25
timeCodesPerSecond = 24
metersPerUnit = 1)
def Xform "Parent" {
 token visibility.timeSamples = {1:"invisible", 7.5:"inherited", 20:"invisible"}
 def Mesh "Triangle" {
  uniform token subdivisionScheme = "none"
  point3f[] points = [(-1,-1,0),(1,-1,0),(0,1,0)]
  int[] faceVertexCounts = [3]
  int[] faceVertexIndices = [0,1,2]
  token visibility.timeSamples = {1:"inherited", 15:"invisible", 17:"inherited"}
 }
}
''')
assert cook.cook(source,work/'cooked','visible') in ('cooked','cached')
rows=(work/'cooked/visible-visibility.atlasvisibility').read_text().splitlines()[1:]
assert [int(row.split('\t')[2]) for row in rows]==[0,1,0,1,0,0],rows
assert abs(float(rows[1].split('\t')[1])-6.5/24)<1e-9
report=json.loads((work/'cooked/visible-source.json').read_text())
assert report['conversion']['mesh_objects']==1
print('USD visibility passed: hidden initial geometry retained, composed ancestry, fractional held keys and stable binding')
