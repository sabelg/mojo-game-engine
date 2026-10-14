"""Static point placement, prototype transform, masks and stable occurrence IDs."""
import importlib.util,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('cook',ROOT/'scripts/cook-assets.py');cook=importlib.util.module_from_spec(spec);spec.loader.exec_module(cook)
spec=importlib.util.spec_from_file_location('session',ROOT/'scripts/usd-session.py');session=importlib.util.module_from_spec(spec);spec.loader.exec_module(session)
work=Path(tempfile.mkdtemp(prefix='usd-points-',dir=ROOT/'build'));source=work/'source.usda'
text='''#usda 1.0
(metersPerUnit = 1)
def PointInstancer "Scatter" {
 int[] protoIndices = [0,0,0]
 point3f[] positions = [(0,0,0),(4,0,0),(8,0,0)]
 int64[] ids = [101,202,303]
 int64[] invisibleIds = [202]
 rel prototypes = </Scatter/Prototypes/Triangle>
 def Scope "Prototypes" {
  def Mesh "Triangle" {
   uniform token subdivisionScheme = "none"
   point3f[] points = [(0,0,0),(1,0,0),(0,1,0)]
   int[] faceVertexCounts = [3]
   int[] faceVertexIndices = [0,1,2]
   double3 xformOp:translate = (0,2,0)
   uniform token[] xformOpOrder = ["xformOp:translate"]
  }
 }
}
'''
source.write_text(text)
inspector=os.environ.get('ATLAS_USD_INSPECT',str(ROOT/'.deps/usd-tools/bin/atlas-usd-inspect'))
report=json.loads(subprocess.check_output([inspector,source,work/'expanded.usda']))
assert report['meshes']==2 and report['point_instancers'][0]['visible_occurrences']==2,report
with session.StageSession() as stage:
 snapshot=stage.request('open',source=str(work/'expanded.usda'))
 points={p['stable_id']:p for p in snapshot['prims'] if p.get('stable_id','').startswith('/Scatter/point/')}
 assert set(points)=={'/Scatter/point/101','/Scatter/point/303'},points
 for identity,x in [('/Scatter/point/101',0),('/Scatter/point/303',8)]:
  matrix=points[identity]['world_transform_row_major'];assert matrix[12:15]==[x,2,0],matrix
assert cook.cook(source,work/'cooked','scatter')=='cooked'
scene=(work/'cooked/scatter-scene.scene').read_text();assert '/Scatter/point/101' in scene and '/Scatter/point/303' in scene
assert source.read_text()==text
before=(work/'cooked/scatter-cook.json').read_bytes()
for invalid in [text.replace(' int[] protoIndices', ' vector3f[] velocities = [(1,0,0),(0,0,0),(0,0,0)]\n int[] protoIndices'),text.replace('[101,202,303]','[101,101,303]'),text.replace('int[] protoIndices = [0,0,0]','int[] protoIndices = [0,4,0]'),text.replace('point3f[] positions = [(0,0,0),(4,0,0),(8,0,0)]','point3f[] positions.timeSamples = {1:[(0,0,0),(4,0,0),(8,0,0)],2:[(1,0,0),(4,0,0),(8,0,0)]}')]:
 source.write_text(invalid)
 try:cook.cook(source,work/'cooked','scatter')
 except ValueError:pass
 else:raise AssertionError('Unsupported/invalid instancer accepted')
 assert (work/'cooked/scatter-cook.json').read_bytes()==before
print('Point instancers passed: static transforms, prototype placement, masks, stable IDs, complete cook and atomic rejection')
