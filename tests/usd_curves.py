"""Finite tube geometry from independently authored USD curve control points."""
import importlib.util,json,os,subprocess,tempfile,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
cook=module('cook','cook-assets.py');exporter=module('exporter','export-usd.py')
work=Path(tempfile.mkdtemp(prefix='usd-curves-',dir=ROOT/'build'));source=work/'curves.usda'
text='''#usda 1.0
(metersPerUnit = 1)
def BasisCurves "Wire" {
 uniform token type = "linear"
 uniform token wrap = "nonperiodic"
 int[] curveVertexCounts = [2]
 point3f[] points = [(0,0,0),(0,2,0)]
 float[] widths = [.4] (interpolation = "constant")
 custom int userProperties:atlas_curve_sides = 8
}
def BasisCurves "Bezier" {
 uniform token type = "cubic"
 uniform token basis = "bezier"
 uniform token wrap = "nonperiodic"
 int[] curveVertexCounts = [4]
 point3f[] points = [(2,0,0),(2,1,0),(3,1,0),(3,0,0)]
 float[] widths = [.2] (interpolation = "constant")
 custom int userProperties:atlas_curve_sides = 8
 custom int userProperties:atlas_curve_steps = 8
}
'''
source.write_text(text);inspector=os.environ.get('ATLAS_USD_INSPECT',str(ROOT/'.deps/usd-tools/bin/atlas-usd-inspect'))
report=json.loads(subprocess.check_output([inspector,source]))
assert report['meshes']==2 and len(report['curve_bakes'])==2,report
assert report['curve_bakes'][0]['vertices']==38 and report['curve_bakes'][0]['triangles']==32
assert cook.cook(source,work/'cooked','curves')=='cooked'
meshes=[exporter.mesh(p.read_bytes()) for p in sorted((work/'cooked').glob('*.atlasmeshb'))]
wire=next(m for m in meshes if min(v[0] for v in m[0])<0)
vertices,indices,_=wire
assert abs(min(v[0] for v in vertices)+.2)<1e-6 and abs(max(v[0] for v in vertices)-.2)<1e-6
# Blender may rotate mesh-local axes and compensate in its scene node.
scene_rows=[r.split('\t') for r in (work/'cooked/curves-scene.scene').read_text().splitlines()[1:]]
node=next(r for r in scene_rows if r[1]=='Wire');q=list(map(float,node[8:12]));length=math.sqrt(sum(v*v for v in q));x,y,z,w=[v/length for v in q]
def rotate(v):
    cross=[y*v[2]-z*v[1],z*v[0]-x*v[2],x*v[1]-y*v[0]]
    cross2=[y*cross[2]-z*cross[1],z*cross[0]-x*cross[2],x*cross[1]-y*cross[0]]
    return [v[i]+2*(w*cross[i]+cross2[i]) for i in range(3)]
world=[rotate(v[:3]) for v in vertices]
assert abs(min(v[1] for v in world))<1e-6 and abs(max(v[1] for v in world)-2)<1e-6
for i in range(0,len(indices),3):
 a,b,c=[vertices[indices[i+j]] for j in range(3)];u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
 n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
 assert sum(n[j]*a[j+3] for j in range(3))>1e-8,'Tube winding disagrees with normals'
assert source.read_text()==text
before=(work/'cooked/curves-cook.json').read_bytes()
for invalid in [text.replace('"nonperiodic"','"periodic"'),text.replace('= 8','= 99'),text.replace('widths = [.4]','widths = [-1]'),text.replace('type = "linear"','type = "cubic"')]:
 source.write_text(invalid)
 try:cook.cook(source,work/'cooked','curves')
 except ValueError:pass
 else:raise AssertionError('Invalid/out-of-profile curves accepted')
 assert before==(work/'cooked/curves-cook.json').read_bytes()
print('USD curves passed: linear/Bezier tubes, radius/endpoints, caps/winding, complete cooking and atomic rejection')
