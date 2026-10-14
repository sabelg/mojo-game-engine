"""Export an Atlas scene snapshot to a portable USD directory, without overwrites.

Static mesh/transform/material snapshot. Animation, procedural terrain and foliage
simulation require baking or separate authoring export and are rejected explicitly.
"""
import argparse,ctypes,hashlib,importlib.util,io,json,math,os,shutil,struct,tempfile
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
project=module('atlas_project_export','atlas-project.py')
usd=module('atlas_usd_cook_export','cook-usd.py')
def num(value):
 if not math.isfinite(value):raise ValueError('Non-finite export value')
 return format(value,'.17g')
def vec(values):return '('+', '.join(num(v) for v in values)+')'
def array(values):return '['+', '.join(values)+']'
def quoted(value):return json.dumps(value,ensure_ascii=False)
def checksum(data):
 value=14695981039346656037
 for byte in data:value=((value^byte)*1099511628211)&0xffffffffffffffff
 return value
class Reader:
 def __init__(self,data,kind):
  if len(data)<36 or data[:8]!=b'ATLASB2\0' or struct.unpack_from('<II',data,8)!=(2,kind) or struct.unpack_from('<Q',data,16)[0]!=len(data)-32 or struct.unpack_from('<Q',data,24)[0]!=checksum(data[32:]):raise ValueError('Invalid binary export input')
  self.data=data;self.at=32
  if self.take('I')[0]!=0:raise ValueError('Mesh export does not accept embedded dependencies')
 def take(self,fmt):
  size=struct.calcsize('<'+fmt)
  if self.at+size>len(self.data):raise ValueError('Truncated mesh input')
  result=struct.unpack_from('<'+fmt,self.data,self.at);self.at+=size
  return result

def mesh(data):
 source=Reader(data,1);nv,ni=source.take('II')
 if not 1<=nv<=250000 or not 3<=ni<=750000 or ni%3:raise ValueError('Export mesh exceeds geometry profile')
 vertices=[list(source.take('8f')) for _ in range(nv)];indices=source.take('I'*ni);colors=[]
 if any(i>=nv for i in indices):raise ValueError('Invalid export mesh index')
 if source.at<len(data):
  magic,tangents,targets=source.take('III')
  if magic!=0x47454f31 or tangents>1 or targets>64:raise ValueError('Unknown geometry extension')
  if targets:raise ValueError('Morph geometry must be baked to a mesh snapshot before USD export')
  # USD reconstructs tangent frames from authored normals and UVs.
  if tangents:source.take('f'*(nv*4))
  if source.at<len(data):
   if source.take('I')[0]!=0x434f4c31:raise ValueError('Unknown mesh color extension')
   colors=[source.take('4f') for _ in range(nv)]
 if source.at!=len(data) or any(not math.isfinite(v) for row in vertices+colors for v in row):raise ValueError('Invalid mesh data/trailing bytes')
 if colors and any(v<0 or v>1 for row in colors for v in row):raise ValueError('Invalid vertex colors')
 return vertices,indices,colors

def builtin(key):
 vertices=[];indices=[]
 if key=='atlas/cube':
  points=[(-.5,-.5,-.5),(.5,-.5,-.5),(.5,.5,-.5),(-.5,.5,-.5),(-.5,-.5,.5),(.5,-.5,.5),(.5,.5,.5),(-.5,.5,.5)]
  faces=[0,3,2,1,4,5,6,7,0,1,5,4,3,7,6,2,0,4,7,3,1,2,6,5]
  for i in range(0,24,4):
   for triangle in [(faces[i],faces[i+1],faces[i+2]),(faces[i],faces[i+2],faces[i+3])]:
    a,b,c=[points[j] for j in triangle];u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)];n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
    for p,uv in zip((a,b,c),((0,0),(1,0),(1,1))):indices.append(len(vertices));vertices.append([*p,*n,*uv])
 elif key=='atlas/sphere':
  for j in range(13):
   latitude=j*math.pi/12
   for i in range(25):
    longitude=i*2*math.pi/24;n=[math.sin(latitude)*math.cos(longitude),math.cos(latitude),math.sin(latitude)*math.sin(longitude)]
    vertices.append([*n,*n,i/24,j/12])
  for j in range(12):
   for i in range(24):
    a=j*25+i;b=a+25;indices.extend([a,a+1,b,a+1,b+1,b])
 else:raise ValueError('Unresolved mesh asset '+key)
 return vertices,indices,[]

def export_scene(scene,manifests,destination):
 scene=scene.resolve();destination=destination.resolve()
 if destination.exists():raise ValueError('Export destination already exists')
 inputs={};meshes={};materials={};total=0
 def read(path):
  nonlocal total
  path=path.resolve()
  if path not in inputs:
   data=project.read(path);total+=len(data)
   if total>256*1024*1024 or len(inputs)>=4096:raise ValueError('Export dependency budget exceeded')
   inputs[path]=data
  return inputs[path]
 for manifest in manifests:
  manifest=manifest.resolve();rows=read(manifest).decode().splitlines()
  if not rows or rows[0]!='ATLAS_ASSETS_1':raise ValueError('Export requires text asset manifests')
  for line in rows[1:]:
   f=line.split('\t')
   if len(f)<3:raise ValueError('Invalid manifest record')
   if f[0]=='mesh':
    if len(f)!=3 or f[1] in meshes:raise ValueError('Duplicate or invalid mesh record')
    path=project.path_in(manifest.parent,f[2])
    meshes[f[1]]=path
   elif f[0]=='material':
    if f[1] in materials or len(f) not in (9,11,25,28):raise ValueError('Duplicate or invalid material record')
    materials[f[1]]=(f,manifest.parent)
   elif f[0]!='collision':raise ValueError('Unknown manifest record')
 data=read(scene);project.scene_check(data,set(meshes)|{'atlas/cube','atlas/sphere'},set(materials))
 lines=data.decode().splitlines()
 if lines[0]!='MOJO_SCENE_3':raise ValueError('Export requires MOJO_SCENE_3 persistent identities')
 records=[line.split('\t') for line in lines[1:] if line]
 if any(r[1]=='ATLAS_TERRAIN_1' for r in records):raise ValueError('Procedural terrain must be baked before USD export')
 if len(records)>10000:raise ValueError('USD scene export supports at most 10000 nodes')

 children={};paths={};used_ids=set()
 for i,r in enumerate(records):
  if r[4]!='1':continue
  if not r[24] or len(r[24].encode())>128:raise ValueError('Invalid persistent identity')
  children.setdefault(int(r[2]),[]).append(i)
  if r[3]!='-1' and not r[22]:raise ValueError('Mesh table indices need stable asset keys for USD export')
  q=list(map(float,r[8:12]))
  if abs(sum(v*v for v in q)-1)>1e-5:raise ValueError('Scene quaternion is not normalized')
 destination.parent.mkdir(parents=True,exist_ok=True)
 temporary=Path(tempfile.mkdtemp(prefix='.atlas-usd-export-',dir=destination.parent))
 try:
  out=['#usda 1.0','(defaultPrim = "Atlas"\n metersPerUnit = 1\n upAxis = "Y")','def Xform "Atlas" {']
  material_cache={};geometry_cache={};texture_cache={};material_defs=[];geometry_defs=[];policies=[];vertex_count=0
  def texture(path):
   raw=read(path);key=hashlib.sha256(raw).hexdigest();name='textures/'+key+'.png'
   if key not in texture_cache:
    with Image.open(io.BytesIO(raw)) as image:
     if image.width*image.height>16777216:raise ValueError('Export texture exceeds pixel budget')
     target=temporary/name;target.parent.mkdir(exist_ok=True);image.convert('RGBA').save(target)
    texture_cache[key]=name
   return name
  def material(r):
   if r[23]:fields,base=materials[r[23]]
   else:
    if r[21]!='-1':raise ValueError('Inline texture handles need authored material assets')
    fields=['material','inline','-',*r[15:21]];base=scene.parent
   if len(fields)==28 and (float(fields[25])!=0 or int(fields[26])!=0):raise ValueError('Foliage transmission/wind cannot be preserved by static USD export')
   values=list(map(float,fields[3:9]))
   if len(values)!=6 or any(not math.isfinite(v) for v in values) or any(v<0 or v>1 for v in values[:5]) or values[5]<0:raise ValueError('Invalid exported material factor')
   identity=json.dumps([fields,str(base)]);key=hashlib.sha256(identity.encode()).hexdigest()[:24];path='/Atlas/Materials/m'+key
   if key in material_cache:return path
   material_cache[key]=path;rgb=values[:3];roughness=max(.045,values[3]);metal=values[4];emission=values[5]
   if emission and fields[2]!='-':raise ValueError('Textured emission requires a baked emission map before USD export')
   body=['def Material "m'+key+'" {','token outputs:surface.connect = <'+path+'/Surface.outputs:surface>']
   connections={}
   slots=[(2,'Albedo','sRGB',(*rgb,1),(0,0,0,0)),(9,'Normal','raw',(2,2,2,1),(-1,-1,-1,0)),(10,'ORM','raw',(1,roughness,metal,1),(0,0,0,0))]
   for column,name,space,scale,bias in slots:
    if column>=len(fields) or fields[column]=='-':continue
    image=texture(project.path_in(base,fields[column]));offset=11 if column==2 else 15 if column==9 else 19
    sampler=list(map(int,fields[offset:offset+4])) if len(fields)>=25 else [10497,10497,9987,9729]
    if sampler[0] not in (10497,33071,33648) or sampler[1] not in (10497,33071,33648):raise ValueError('Invalid export texture wrap')
    wraps={10497:'repeat',33071:'clamp',33648:'mirror'}
    if sampler[2:]!=[9987,9729]:policies.append('Texture filtering is renderer-defined in UsdUVTexture: '+name)
    tex=path+'/'+name
    body += ['def Shader "'+name+'" {','uniform token info:id = "UsdUVTexture"','asset inputs:file = @'+image+'@','token inputs:sourceColorSpace = '+quoted(space),'float2 inputs:st.connect = <'+path+'/UV.outputs:result>','float4 inputs:scale = '+vec(scale),'float4 inputs:bias = '+vec(bias),'token inputs:wrapS = '+quoted(wraps[sampler[0]]),'token inputs:wrapT = '+quoted(wraps[sampler[1]]),'float3 outputs:rgb','float outputs:r','float outputs:g','float outputs:b','float outputs:a','}']
    if name=='Albedo':
     connections['diffuseColor']=('color3f',tex+'.outputs:rgb')
     mode=int(fields[23]) if len(fields)>=25 else 0
     if mode not in (0,1,2):raise ValueError('Invalid alpha policy')
     if mode==2 or mode==0:connections['opacity']=('float',tex+'.outputs:a')
    elif name=='Normal':connections['normal']=('normal3f',tex+'.outputs:rgb')
    else:connections.update(roughness=('float',tex+'.outputs:g'),metallic=('float',tex+'.outputs:b'),occlusion=('float',tex+'.outputs:r'))
   body += ['def Shader "UV" {','uniform token info:id = "UsdPrimvarReader_float2"','token inputs:varname = "st"','float2 outputs:result','}', 'def Shader "Surface" {','uniform token info:id = "UsdPreviewSurface"','token outputs:surface']
   constants={'diffuseColor':('color3f',vec(rgb)),'roughness':('float',num(roughness)),'metallic':('float',num(metal)),'emissiveColor':('color3f',vec([v*emission for v in rgb]))}
   for name,(kind,value) in constants.items():
    if name not in connections:body.append(kind+' inputs:'+name+' = '+value)
   for name,(kind,value) in connections.items():body.append(kind+' inputs:'+name+'.connect = <'+value+'>')
   if 'opacity' in connections:body.append('float inputs:opacityThreshold = '+(fields[24] if len(fields)>=25 else '.5'))
   body+=['}','}'];material_defs.extend(body)
   return path
  def geometry(asset):
   nonlocal vertex_count
   if asset in geometry_cache:return geometry_cache[asset]
   if asset in meshes:
    path=meshes[asset]
    if path.with_suffix('.atlasskinb').exists():raise ValueError('Skinned geometry must be baked before static USD export')
    vertices,indices,colors=mesh(read(path))
   else:vertices,indices,colors=builtin(asset)
   vertex_count+=len(vertices)
   if vertex_count>1000000:raise ValueError('USD export exceeds one million source vertices')
   if colors and any(any(abs(v-1)>1e-6 for v in row) for row in colors):raise ValueError('Vertex colors require material baking before USD snapshot export')
   key='g'+hashlib.sha256(asset.encode()).hexdigest()[:24];path='/Atlas/Geometry/'+key;geometry_cache[asset]=path
   geometry_defs.extend(['class Mesh "'+key+'" {','uniform token subdivisionScheme = "none"','bool doubleSided = true','point3f[] points = '+array(vec(v[:3]) for v in vertices),'normal3f[] normals = '+array(vec(v[3:6]) for v in vertices)+' (interpolation = "vertex")','texCoord2f[] primvars:st = '+array(vec((v[6],1-v[7])) for v in vertices)+' (interpolation = "vertex")','int[] faceVertexCounts = '+array('3' for _ in range(len(indices)//3)),'int[] faceVertexIndices = '+array(str(i) for i in indices),'}'])
   return path
  # Iterative hierarchy writing avoids recursion on imported scene graphs.
  stack=[('node',i,0) for i in reversed(children.get(-1,[]))]
  while stack:
   action,i,depth=stack.pop()
   if action=='close':out.append('}');continue
   if depth>256:raise ValueError('USD export hierarchy exceeds depth 256')
   r=records[i];parent=int(r[2]);path=(paths[parent] if parent!=-1 else '/Atlas')+'/n'+str(i);paths[i]=path
   used_ids.add(r[24]);q=list(map(float,r[8:12]))
   out += ['def Xform "n'+str(i)+'" (displayName = '+quoted(r[1])+'\n customData = { dictionary atlas = { string uuid = '+quoted(r[24])+' } }) {','double3 xformOp:translate = '+vec(map(float,r[5:8])),'quatd xformOp:orient = '+vec((q[3],*q[:3])),'double3 xformOp:scale = '+vec(map(float,r[12:15])),'uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:orient", "xformOp:scale"]']
   if r[22]:
    geo=geometry(r[22]);mat=material(r)
    out+=['def Mesh "Shape" (prepend references = <'+geo+'>\n prepend apiSchemas = ["MaterialBindingAPI"]) {','rel material:binding = <'+mat+'>','}']
   stack.append(('close',i,depth))
   stack.extend(('node',child,depth+1) for child in reversed(children.get(i,[])))
  out+=['def Scope "Materials" {',*material_defs,'}','def Scope "Geometry" {',*geometry_defs,'}','}']
  encoded=('\n'.join(out)+'\n').encode()
  if len(encoded)>64*1024*1024:raise ValueError('USD output exceeds 64 MiB')
  stage=temporary/'scene.usda';project.atomic(stage,encoded)
  inspector=usd.executable('ATLAS_USD_INSPECT',ROOT/'.deps/usd-tools/bin/atlas-usd-inspect')
  report=json.loads(usd.run([inspector,stage]))
  if report['unresolved'] or report['unsupported']:raise ValueError('Export failed native USD validation: '+str(report['unsupported']+report['unresolved']))
  for path,data in inputs.items():
   if project.read(path)!=data:raise ValueError('Source changed during USD export; retry')
  state={'format':'atlas-usd-export-1','scene':str(scene),'snapshot_only':True,'source_sha256':{str(p):hashlib.sha256(d).hexdigest() for p,d in inputs.items()},'persistent_ids':sorted(used_ids),'geometry_definitions':len(geometry_cache),'mesh_occurrences':report['meshes'],'policies':sorted(set(policies))+['Static opaque/masked PBR snapshot; tangent frames reconstructed from normals/UVs','Animation, skins, morphs, procedural terrain, nonwhite vertex colors and foliage require baking']}
  project.atomic(temporary/'export.json',(json.dumps(state,indent=2)+'\n').encode())
  libc=ctypes.CDLL(None,use_errno=True)
  rename=libc.renameat2;rename.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint];rename.restype=ctypes.c_int
  if rename(-100,os.fsencode(temporary),-100,os.fsencode(destination),1)!=0:
   code=ctypes.get_errno();raise OSError(code,os.strerror(code),str(destination))
  fd=os.open(destination.parent,os.O_RDONLY|os.O_DIRECTORY)
  try:os.fsync(fd)
  finally:os.close(fd)
  return state
 finally:
  if temporary.exists():shutil.rmtree(temporary)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--scene',type=Path,required=True);p.add_argument('--manifest',type=Path,action='append',default=[]);p.add_argument('--destination',type=Path,required=True);args=p.parse_args()
 try:
  report=export_scene(args.scene,args.manifest,args.destination)
  print('USD scene snapshot exported:',report['mesh_occurrences'],'mesh occurrences;',report['geometry_definitions'],'geometry definitions')
 except (OSError,ValueError,KeyError,IndexError,TypeError,struct.error) as error:raise SystemExit('USD export failed: '+str(error))
if __name__=='__main__':main()
