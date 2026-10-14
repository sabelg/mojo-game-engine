"""Deterministic offline OBJ/glTF/GLB/USD cooking into the native Atlas formats.

Standard library for mesh/rig cooking; Pillow is needed only for PNG/JPEG images.
Unsupported glTF features fail explicitly rather than producing partial assets.
"""
import argparse,base64,hashlib,io,json,math,os,re,struct,uuid
from pathlib import Path

MAX_FILE=64*1024*1024
MAX_BUNDLE=256*1024*1024
MAX_IMPORT_WORK=512*1024*1024
MAX_JSON=16*1024*1024
MAX_VERTICES=250_000
MAX_INDICES=750_000

class ImportBudget:
 """Conservative cumulative work estimates, separate from retained file bytes."""
 def __init__(self):self.used=0
 def reserve(self,size):
  if size<0 or size>MAX_IMPORT_WORK-self.used:raise ValueError('Import exceeds 512 MiB estimated work budget')
  self.used+=size

class Payloads(dict):
 def __init__(self):super().__init__();self.bytes=0
 def __setitem__(self,name,data):
  size=len(data);total=self.bytes-len(self.get(name,b''))+size
  if size>MAX_FILE:raise ValueError('Cooked file exceeds 64 MiB limit')
  if total>MAX_BUNDLE:raise ValueError('Cooked bundle exceeds 256 MiB limit')
  super().__setitem__(name,data);self.bytes=total

def parse_gltf_json(data):
 if len(data)>MAX_JSON:raise ValueError('glTF JSON exceeds 16 MiB limit')
 depth=0;tokens=0;string=False;escaped=False
 # Bound parser allocations and recursion before Python creates the document.
 for byte in data:
  if string:
   if escaped:escaped=False
   elif byte==92:escaped=True
   elif byte==34:string=False
   continue
  if byte==34:string=True;tokens+=1
  elif byte in (123,91):depth+=1;tokens+=1
  elif byte in (125,93):depth-=1
  elif byte in (44,58):tokens+=1
  if depth>64 or tokens>1_000_000:raise ValueError('glTF JSON exceeds nesting/token budget')
 return json.loads(data)

def reserve_gltf_work(doc,budget):
 """Inspect counts before decoding any accessor or expanding mesh instances."""
 generated=0
 def accessor_cost(index):
  a=doc['accessors'][index];return a['count']*(96+64*WIDTH[a['type']])
 for node in doc.get('nodes',[]):
  if 'mesh' not in node:continue
  for primitive in doc['meshes'][node['mesh']]['primitives']:
   generated+=1
   if generated+len(doc.get('nodes',[]))>100_000:raise ValueError('Generated scene exceeds 100000 nodes')
   attrs=primitive['attributes'];n=doc['accessors'][attrs['POSITION']]['count']
   indices=doc['accessors'][primitive['indices']]['count'] if 'indices' in primitive else n
   if n>MAX_VERTICES or indices>MAX_INDICES:raise ValueError('Primitive exceeds 250000 vertex/750000 index limits')
   targets=primitive.get('targets',[])
   if not isinstance(targets,list) or len(targets)>64:raise ValueError('Too many or invalid morph targets')
   # Covers default attributes, text/binary serialization, collision scratch,
   # skin mapping and retained morph channels in addition to decoded accessors.
   budget.reserve(n*(1200+len(targets)*9*80)+indices*144)
   for index in attrs.values():budget.reserve(accessor_cost(index))
   if 'indices' in primitive:budget.reserve(accessor_cost(primitive['indices']))
   for target in targets:
    if not isinstance(target,dict):raise ValueError('Invalid morph target')
    for index in target.values():
     if type(index)!=int or not 0<=index<len(doc.get('accessors',[])):raise ValueError('Invalid morph accessor')
     budget.reserve(accessor_cost(index))
 for skin in doc.get('skins',[]):
  budget.reserve(len(doc.get('nodes',[]))*4096)
  if 'inverseBindMatrices' in skin:budget.reserve(accessor_cost(skin['inverseBindMatrices']))
 for animation in doc.get('animations',[]):
  for channel in animation['channels']:
   sampler=animation['samplers'][channel['sampler']]
   budget.reserve(accessor_cost(sampler['input'])+accessor_cost(sampler['output']))
   budget.reserve(doc['accessors'][sampler['input']]['count']*2048)

VERSION=2
COMPONENT={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
IDENTITY=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]

def number(v):
 if not math.isfinite(v):raise ValueError('Non-finite asset value')
 return format(v,'.17g')
def record(values):return ' '.join(map(number,values))
def checksum(data):
 value=14695981039346656037
 for byte in data:value=((value^byte)*1099511628211)&0xffffffffffffffff
 return value
def binary_text(value):
 data=value.encode('utf-8')
 if len(data)>1024*1024 or b'\0' in data:raise ValueError('Invalid binary asset string')
 return struct.pack('<I',len(data))+data
def envelope(kind,payload,dependencies=()):
 if len(dependencies)>4096:raise ValueError('Too many binary dependencies')
 table_size=4+sum(12+len(name.encode('utf-8')) for name,_ in dependencies)
 if len(payload)+table_size>MAX_FILE-32:raise ValueError('Binary asset exceeds 64 MiB limit')
 table=struct.pack('<I',len(dependencies))+b''.join(binary_text(name)+struct.pack('<Q',checksum(data)) for name,data in dependencies)
 body=table+payload
 if len(body)>64*1024*1024-32:raise ValueError('Binary asset exceeds 64 MiB limit')
 return struct.pack('<8sIIQQ',b'ATLASB2\0',2,kind,len(body),checksum(body))+body
def collision_payload(vertices,indices,channels=None):
 if len(vertices)>MAX_VERTICES or len(indices)>MAX_INDICES:raise ValueError('Collision geometry exceeds cooking limits')
 positions=[list(struct.unpack('<3f',struct.pack('<3f',*v[:3]))) for v in vertices]
 if channels:
  _,targets,weights=channels[:3]
  for i,p in enumerate(positions):
   for target,weight in zip(targets,weights):
    for axis in range(3):p[axis]+=struct.unpack('<f',struct.pack('<f',target[i][axis]))[0]*weight
   positions[i]=list(struct.unpack('<3f',struct.pack('<3f',*p)))
 triangles=[]
 for offset in range(0,len(indices),3):
  triangle=[positions[i] for i in indices[offset:offset+3]]
  if sum(v*v for v in cross([b-a for a,b in zip(triangle[0],triangle[1])],[b-a for a,b in zip(triangle[0],triangle[2])]))<1e-24:continue
  triangles.append(triangle)
 if not triangles:return None
 if len(triangles)>1000000:raise ValueError('Collision triangle limit exceeded')
 order=list(range(len(triangles)));nodes=[]
 def bounds(start,count):
  points=[p for index in order[start:start+count] for p in triangles[index]]
  return [min(p[axis] for p in points) for axis in range(3)]+[max(p[axis] for p in points) for axis in range(3)]
 def build(start,count,depth=0):
  box=bounds(start,count);index=len(nodes);nodes.append([box,-1,-1,start,count])
  if count<=8 or depth==32:return index
  axis=max(range(3),key=lambda axis:box[axis+3]-box[axis]);split=(box[axis]+box[axis+3])*.5
  left=[];right=[]
  for slot in order[start:start+count]:
   (left if sum(p[axis] for p in triangles[slot])/3<split else right).append(slot)
  middle=start+len(left) if left and right else start+count//2
  if left and right:order[start:start+count]=left+right
  nodes[index][1:]=[build(start,middle-start,depth+1),build(middle,start+count-middle,depth+1),start,0]
  return index
 build(0,len(triangles))
 return struct.pack('<II',len(triangles),len(nodes))+b''.join(struct.pack('<9f',*(v for p in triangle for v in p)) for triangle in triangles)+struct.pack('<'+'I'*len(order),*order)+b''.join(struct.pack('<6d4i',*box,left,right,start,count) for box,left,right,start,count in nodes)
def binary_outputs(payloads,geometry_channels=None):
 """Emit typed binary counterparts and retain the existing migration formats."""
 pending=[]
 for name,data in list(payloads.items()):
  if name.endswith('.bmp'):continue
  lines=data.decode().splitlines();kind=0;body=b'';dependencies=[]
  if name.endswith('.atlasmesh'):
   kind=1;vertices=[list(map(float,row.split()[1:])) for row in lines[1:] if row.startswith('v ')];indices=[int(v) for row in lines[1:] if row.startswith('i ') for v in row.split()[1:]]
   body=struct.pack('<II',len(vertices),len(indices))+b''.join(struct.pack('<8f',*v) for v in vertices)+struct.pack('<'+'I'*len(indices),*indices)
   channels=(geometry_channels or {}).get(name)
   if channels:
    tangents,targets,weights=channels[:3]
    body+=struct.pack('<III',0x47454f31,int(bool(tangents)),len(targets))
    if tangents:body+=b''.join(struct.pack('<4f',*value) for value in tangents)
    for target,weight in zip(targets,weights):body+=struct.pack('<d',weight)+b''.join(struct.pack('<9f',*value) for value in target)
    if len(channels)>3 and channels[3]:body+=struct.pack('<I',0x434f4c31)+b''.join(struct.pack('<4f',*value) for value in channels[3])
  elif name.endswith('.scene'):
   kind=2;records=[row.split('\t') for row in lines[1:] if row];body=struct.pack('<I',len(records))
   for row in records:body+=binary_text(row[1])+struct.pack('<iiI16di',int(row[2]),int(row[3]),int(row[4]),*map(float,row[5:21]),int(row[21]))+b''.join(binary_text(v) for v in row[22:25])
  elif name.endswith('.atlasskeleton'):
   kind=4;records=[row.split() for row in lines[1:] if row];body=struct.pack('<I',len(records))
   for row in records:body+=struct.pack('<i26d',int(row[1]),*map(float,row[2:]))
  elif name.endswith('.atlasclip'):
   kind=5;tracks={}
   for row in lines[1:]:
    values=row.split()
    if values:tracks.setdefault(int(values[0]),[]).append(values)
   body=struct.pack('<I',len(tracks))
   for records in tracks.values():
    body+=struct.pack('<iiII',*map(int,records[0][1:4]),len(records))
    for row in records:
     body+=struct.pack('<5d',*map(float,row[4:9]))
     if int(row[3])==2:body+=struct.pack('<8d',*map(float,row[9:17]))
  elif name.endswith('.atlasskin'):
   kind=6;records=[row.split() for row in lines[2:] if row];body=struct.pack('<iI',int(lines[1]),len(records))
   for row in records:body+=struct.pack('<4i4d',*map(int,row[:4]),*map(float,row[4:]))
   dependencies=[name.removesuffix('.atlasskin')+'.atlasmeshb']
  if kind:
   if dependencies:pending.append((name+'b',kind,body,dependencies))
   else:
    payloads[name+'b']=envelope(kind,body)
    if kind==1:
     collision=collision_payload(vertices,indices,channels)
     if collision is not None:payloads[name.removesuffix('.atlasmesh')+'.atlascollisionb']=envelope(7,collision,[(name+'b',payloads[name+'b'])])
 for name,kind,body,dependencies in pending:payloads[name]=envelope(kind,body,[(key,payloads[key]) for key in dependencies])
 for name,data in list(payloads.items()):
  if not name.endswith('.atlas'):continue
  rows=[row.split('\t') for row in data.decode().splitlines()[1:] if row];extra=[]
  for row in rows:
   if row[0]=='mesh':
    collision=row[2].removesuffix('.atlasmesh')+'.atlascollisionb'
    if collision in payloads:extra.append(['collision',row[1],collision])
  rows+=extra;body=struct.pack('<I',len(rows));dependencies=set()
  for row in rows:
   if row[0]=='mesh':
    row[2]+='b';body+=struct.pack('<I',1)+binary_text(row[1])+binary_text(row[2]);dependencies.add(row[2])
   elif row[0]=='material':
    maps=row[9:11] if len(row)>=11 else ['-','-'];body+=struct.pack('<I',5 if len(row)==28 else 4 if len(row)==25 else 2)+binary_text(row[1])+binary_text(row[2])+struct.pack('<6d',*map(float,row[3:9]))+b''.join(binary_text(v) for v in maps)
    if len(row)>=25:body+=struct.pack('<12IId',*map(int,row[11:24]),float(row[24]))
    if len(row)==28:body+=struct.pack('<dId',float(row[25]),int(row[26]),float(row[27]))
    dependencies.update(value for value in [row[2],*maps] if value!='-')
   elif row[0]=='collision':body+=struct.pack('<I',3)+binary_text(row[1])+binary_text(row[2]);dependencies.add(row[2])
   else:raise ValueError('Invalid binary manifest row')
  payloads[name+'b']=envelope(3,body,[(key,payloads[key]) for key in sorted(dependencies)])
  payloads[name]=('ATLAS_ASSETS_1\n'+''.join('\t'.join(row)+'\n' for row in rows)).encode()
def bounded_read(path):
 with path.open('rb') as stream:
  data=stream.read(MAX_FILE+1)
 if len(data)>MAX_FILE:raise ValueError('Source dependency exceeds 64 MiB limit')
 return data
def sync_directory(path):
 fd=os.open(path,os.O_RDONLY|os.O_DIRECTORY)
 try:os.fsync(fd)
 finally:os.close(fd)
def atomic(path,data):
 path.parent.mkdir(parents=True,exist_ok=True)
 temporary=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
 try:
  with temporary.open('xb') as stream:
   stream.write(data if isinstance(data,bytes) else data.encode());stream.flush();os.fsync(stream.fileno())
  temporary.replace(path);sync_directory(path.parent)
 finally:temporary.unlink(missing_ok=True)
def generation_manifest(data,payloads,directory):
 rows=[row.split('\t') for row in data.decode().splitlines()[1:] if row]
 body=struct.pack('<I',len(rows));dependencies={}
 for row in rows:
  kind={'mesh':1,'material':5 if len(row)==28 else 4 if len(row)==25 else 2,'collision':3}[row[0]]
  columns=[2]+([9,10] if kind in (2,4,5) and len(row)>=11 else [])
  for column in columns:
   if row[column]=='-':continue
   original=row[column];row[column]=directory+'/'+original;dependencies[row[column]]=payloads[original]
  body+=struct.pack('<I',kind)+binary_text(row[1])+binary_text(row[2])
  if kind in (2,4,5):
   body+=struct.pack('<6d',*map(float,row[3:9]))+b''.join(binary_text(v) for v in (row[9:11] if len(row)>=11 else ['-','-']))
   if kind in (4,5):body+=struct.pack('<12IId',*map(int,row[11:24]),float(row[24]))
   if kind==5:body+=struct.pack('<dId',float(row[25]),int(row[26]),float(row[27]))
 return ('ATLAS_ASSETS_1\n'+''.join('\t'.join(row)+'\n' for row in rows)).encode(),envelope(3,body,sorted(dependencies.items()))
def unit(v):
 if len(v)!=3 or any(not math.isfinite(x) for x in v):raise ValueError('Invalid normal vector')
 length=math.hypot(*v)
 return [x/length for x in v] if length>1e-12 else [0,1,0]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def cooked_mesh(vertices,indices):
 if not vertices or not indices or len(indices)%3:raise ValueError('Empty/nontriangular mesh')
 if any(i<0 or i>=len(vertices) for i in indices):raise ValueError('Mesh index outside vertex array')
 if len(vertices)>MAX_VERTICES or len(indices)>MAX_INDICES:raise ValueError('Mesh exceeds cooking limits')
 data=bytearray(b'ATLAS_MESH_1\n')
 for v in vertices:
  row=('v '+record(v)+'\n').encode()
  if len(data)+len(row)>MAX_FILE:raise ValueError('Cooked mesh exceeds 64 MiB limit')
  data.extend(row)
 for i in range(0,len(indices),3):
  row=('i '+record(indices[i:i+3])+'\n').encode()
  if len(data)+len(row)>MAX_FILE:raise ValueError('Cooked mesh exceeds 64 MiB limit')
  data.extend(row)
 return data.decode()
def obj_mesh(path):
 positions=[];normals=[];uvs=[];vertices=[];indices=[];cache={};budget=ImportBudget()
 def index(s,values):
  n=int(s);n=n-1 if n>0 else len(values)+n
  if not s or int(s)==0 or not 0<=n<len(values):raise ValueError('Invalid OBJ index')
  return n
 for line in io.StringIO(bounded_read(path).decode('utf-8')):
  if len(line)>1024*1024:raise ValueError('OBJ line exceeds 1 MiB limit')
  f=line.split('#',1)[0].split(maxsplit=65536)
  if len(f)>65536:raise ValueError('OBJ face/token budget exceeded')
  if not f:continue
  if f[0] in ('v','vn','vt'):budget.reserve(256)
  if f[0]=='v':positions.append(list(map(float,f[1:4])))
  elif f[0]=='vn':normals.append(unit(list(map(float,f[1:4]))))
  elif f[0]=='vt':uvs.append(list(map(float,f[1:3])))
  elif f[0]=='f':
   budget.reserve(len(f)*256)
   corners=[]
   for token in f[1:]:
    p=token.split('/');corners.append((index(p[0],positions),index(p[1],uvs) if len(p)>1 and p[1] else -1,index(p[2],normals) if len(p)>2 and p[2] else -1))
   if len(corners)<3:raise ValueError('Invalid OBJ face')
   for i in range(1,len(corners)-1):
    tri=[corners[0],corners[i],corners[i+1]];p=[positions[c[0]] for c in tri]
    normal=unit(cross([b-a for a,b in zip(p[0],p[1])],[b-a for a,b in zip(p[0],p[2])]))
    for position,uv,n in tri:
     vertex=positions[position]+(normals[n] if n>=0 else normal)+(uvs[uv] if uv>=0 else [0,0]);key=tuple(vertex)
     if key not in cache:
      if len(vertices)>=MAX_VERTICES:raise ValueError('OBJ vertex limit exceeded')
      budget.reserve(512);cache[key]=len(vertices);vertices.append(vertex)
     if len(indices)>=MAX_INDICES:raise ValueError('OBJ index limit exceeded')
     budget.reserve(16)
     indices.append(cache[key])
 return vertices,indices

def gltf_schema(doc):
 if not isinstance(doc,dict):raise ValueError('glTF document must be an object')
 # Inspect ignored extras/extensions as well: parser recursion limits vary by
 # Python version, so enforce our own depth and value-count budget.
 pending=[(doc,0)];values=0
 while pending:
  value,depth=pending.pop();values+=1
  if depth>64 or values>1_000_000:raise ValueError('glTF document exceeds nesting/value budget')
  if isinstance(value,(dict,list)):
   if len(value)>1_000_000-values-len(pending):raise ValueError('glTF document exceeds value budget')
   pending.extend((v,depth+1) for v in (value.values() if isinstance(value,dict) else value))
 for name in ['buffers','bufferViews','accessors','meshes','nodes','materials','textures','images','samplers','skins','animations','scenes']:
  entries=doc.get(name,[])
  if not isinstance(entries,list) or len(entries)>4096 or any(not isinstance(entry,dict) for entry in entries):raise ValueError('Invalid or oversized glTF '+name)
 def index(value,name):
  if type(value)!=int or not 0<=value<len(doc.get(name,[])):raise ValueError('Invalid '+name+' reference')
 def integer(value,lower=0,upper=MAX_FILE):
  if type(value)!=int or not lower<=value<=upper:raise ValueError('Invalid glTF integer')
 def vector(value,width):
  if not isinstance(value,list) or len(value)!=width or any(type(v) not in (int,float) or not math.isfinite(v) for v in value):raise ValueError('Invalid glTF vector')
 for buffer in doc.get('buffers',[]):integer(buffer['byteLength'])
 for view in doc.get('bufferViews',[]):
  index(view['buffer'],'buffers');integer(view['byteLength']);integer(view.get('byteOffset',0))
  if 'byteStride' in view:integer(view['byteStride'],4,252)
 for accessor in doc.get('accessors',[]):
  if accessor['type'] not in WIDTH or accessor['componentType'] not in COMPONENT:raise ValueError('Unsupported accessor layout')
  integer(accessor['count'],1,2_000_000);integer(accessor.get('byteOffset',0))
  if 'bufferView' in accessor:index(accessor['bufferView'],'bufferViews')
  if 'sparse' in accessor:
   sparse=accessor['sparse'];integer(sparse['count'],1,accessor['count'])
   for part in ['indices','values']:
    index(sparse[part]['bufferView'],'bufferViews');integer(sparse[part].get('byteOffset',0))
 for texture in doc.get('textures',[]):
  index(texture['source'],'images')
  if 'sampler' in texture:index(texture['sampler'],'samplers')
 for image in doc.get('images',[]):
  if 'bufferView' in image:index(image['bufferView'],'bufferViews')
 for node in doc.get('nodes',[]):
  for field,array in [('mesh','meshes'),('skin','skins')]:
   if field in node:index(node[field],array)
  for child in node.get('children',[]):index(child,'nodes')
  for field,width in [('matrix',16),('translation',3),('rotation',4),('scale',3)]:
   if field in node:vector(node[field],width)
  if 'matrix' in node and any(field in node for field in ['translation','rotation','scale']):raise ValueError('Node matrix and TRS are mutually exclusive')
  if 'matrix' in node and (any(node['matrix'][i]!=0 for i in [3,7,11]) or node['matrix'][15]!=1):raise ValueError('Non-affine node matrix')
  if 'rotation' in node and abs(sum(v*v for v in node['rotation'])-1)>1e-4:raise ValueError('Node quaternion must be normalized')
  if 'scale' in node and any(abs(v)<1e-12 for v in node['scale']):raise ValueError('Singular node scale')
 for skin in doc.get('skins',[]):
  joints=skin['joints']
  if not isinstance(joints,list) or not joints or len(joints)>4096 or len(set(joints))!=len(joints):raise ValueError('Invalid skin joint list')
  for joint in joints:index(joint,'nodes')
  if 'inverseBindMatrices' in skin:index(skin['inverseBindMatrices'],'accessors')
 for mesh in doc.get('meshes',[]):
  primitives=mesh['primitives']
  if not isinstance(primitives,list) or not primitives or len(primitives)>4096:raise ValueError('Invalid primitive list')
  for primitive in primitives:
   attrs=primitive['attributes']
   if not isinstance(attrs,dict) or 'POSITION' not in attrs or set(attrs)-{'POSITION','NORMAL','TEXCOORD_0','COLOR_0','TANGENT','JOINTS_0','WEIGHTS_0'}:raise ValueError('Unsupported primitive attributes')
   for value in attrs.values():index(value,'accessors')
   if 'indices' in primitive:index(primitive['indices'],'accessors')
   if 'material' in primitive:index(primitive['material'],'materials')
 for animation in doc.get('animations',[]):
  if not isinstance(animation['samplers'],list) or not isinstance(animation['channels'],list) or len(animation['samplers'])>4096 or len(animation['channels'])>4096:raise ValueError('Invalid animation size')
  for sampler in animation['samplers']:
   index(sampler['input'],'accessors');index(sampler['output'],'accessors')
  for channel in animation['channels']:
   integer(channel['sampler'],0,len(animation['samplers'])-1);index(channel['target']['node'],'nodes')
 for scene in doc.get('scenes',[]):
  for node in scene.get('nodes',[]):index(node,'nodes')
 if 'scene' in doc:index(doc['scene'],'scenes')

def load_image(data,mode,budget=None):
 from PIL import Image
 image=Image.open(io.BytesIO(data));w,h=image.size
 if w<1 or h<1 or w>4096 or h>4096 or w*h*4>MAX_FILE-122:raise ValueError('Image exceeds cooked texture budget')
 if budget is not None:budget.reserve(w*h*16)
 return image.convert(mode)

class Gltf:
 def __init__(self,path):
  self.path=path;data=bounded_read(path);self.dependencies={str(path):data};self.budget=ImportBudget();self.budget.reserve(len(data)*4);self.uri_cache={};binary=None
  if path.suffix.lower()=='.glb':
   magic,version,length=struct.unpack_from('<III',data)
   if magic!=0x46546c67 or version!=2 or length!=len(data):raise ValueError('Invalid GLB header')
   chunks={};offset=12
   while offset<len(data):
    size,kind=struct.unpack_from('<II',data,offset);offset+=8
    if offset+size>len(data) or kind in chunks:raise ValueError('Invalid GLB chunk')
    chunks[kind]=data[offset:offset+size];offset+=size
   self.doc=parse_gltf_json(chunks[0x4e4f534a]);binary=chunks.get(0x004e4942)
  else:self.doc=parse_gltf_json(data)
  gltf_schema(self.doc)
  reserve_gltf_work(self.doc,self.budget)
  if self.doc.get('asset',{}).get('version')!='2.0':raise ValueError('Only glTF 2.0 is supported')
  if self.doc.get('extensionsRequired'):raise ValueError('Required glTF extensions are unsupported')
  self.buffers=[]
  for b in self.doc.get('buffers',[]):
   payload=self.uri(b['uri']) if 'uri' in b else binary
   if payload is None or len(payload)<b['byteLength']:raise ValueError('Truncated glTF buffer')
   self.buffers.append(payload)
  self.parents=[-1]*len(self.doc.get('nodes',[]))
  for i,node in enumerate(self.doc.get('nodes',[])):
   for child in node.get('children',[]):
    if not 0<=child<len(self.parents) or self.parents[child]!=-1:raise ValueError('Invalid/multiply-parented glTF node')
    self.parents[child]=i
  states=[0]*len(self.parents)
  for i in range(len(self.parents)):
   chain=[];j=i
   while j!=-1 and states[j]!=2:
    if states[j]==1:raise ValueError('glTF hierarchy cycle')
    states[j]=1;chain.append(j);j=self.parents[j]
   for j in chain:states[j]=2
 def uri(self,uri):
  if uri in self.uri_cache:return self.uri_cache[uri]
  if uri.startswith('data:'):
   header,payload=uri.split(',',1)
   if ';base64' not in header:raise ValueError('Only base64 data URIs are supported')
   if len(payload)>MAX_FILE*4//3+4:raise ValueError('Embedded dependency exceeds 64 MiB limit')
   self.budget.reserve(len(payload)*3//4+3)
   data=base64.b64decode(payload,validate=True)
   self.uri_cache[uri]=data
   return data
  if '://' in uri or uri.startswith('/'):raise ValueError('Asset URI must be local and relative')
  from urllib.parse import unquote
  path=(self.path.parent/unquote(uri)).resolve()
  if not path.is_relative_to(self.path.parent.resolve()):raise ValueError('Asset URI escapes source directory')
  if str(path) in self.dependencies:return self.dependencies[str(path)]
  self.budget.reserve(path.stat().st_size)
  data=bounded_read(path);self.dependencies[str(path)]=data
  self.uri_cache[uri]=data
  if sum(map(len,self.dependencies.values()))>MAX_BUNDLE:raise ValueError('Source dependencies exceed 256 MiB limit')
  return data
 def accessor(self,index):
  if not isinstance(index,int) or not 0<=index<len(self.doc.get('accessors',[])):raise ValueError('Invalid accessor index')
  a=self.doc['accessors'][index]
  width=WIDTH[a['type']];fmt,size=COMPONENT[a['componentType']];count=a['count']
  if not isinstance(count,int) or count<1 or count*width>2_000_000:raise ValueError('Invalid accessor count or allocation budget')
  def read(view_index,relative,count,fmt,size,width,tight=False):
   if not 0<=view_index<len(self.doc['bufferViews']):raise ValueError('Invalid buffer view index')
   view=self.doc['bufferViews'][view_index]
   if not 0<=view['buffer']<len(self.buffers):raise ValueError('Invalid buffer index')
   data=self.buffers[view['buffer']];offset=view.get('byteOffset',0)+relative;stride=view.get('byteStride',width*size)
   if tight and ('byteStride' in view or 'target' in view):raise ValueError('Sparse views must be tightly packed without a target')
   if relative<0 or offset%size or stride%size or stride<width*size or (count and relative+(count-1)*stride+width*size>view['byteLength']):raise ValueError('Accessor exceeds/misaligns buffer view')
   if offset<0 or view.get('byteOffset',0)<0 or view.get('byteOffset',0)+view['byteLength']>len(data):raise ValueError('View exceeds buffer')
   return [list(struct.unpack_from('<'+fmt*width,data,offset+i*stride)) for i in range(count)]
  result=read(a['bufferView'],a.get('byteOffset',0),count,fmt,size,width) if 'bufferView' in a else [[0]*width for _ in range(count)]
  if 'sparse' in a:
   sparse=a['sparse'];length=sparse['count'];indices=sparse['indices'];values=sparse['values']
   if not isinstance(length,int) or not 1<=length<=count or indices['componentType'] not in (5121,5123,5125):raise ValueError('Invalid sparse accessor count/indices')
   index_fmt,index_size=COMPONENT[indices['componentType']]
   slots=[row[0] for row in read(indices['bufferView'],indices.get('byteOffset',0),length,index_fmt,index_size,1,True)]
   substitutions=read(values['bufferView'],values.get('byteOffset',0),length,fmt,size,width,True)
   if slots[-1]>=count or any(a>=b for a,b in zip(slots,slots[1:])):raise ValueError('Sparse indices must increase within accessor bounds')
   for slot,values in zip(slots,substitutions):result[slot]=values
  for i,values in enumerate(result):
   if a.get('normalized'):
    limits={5120:127,5121:255,5122:32767,5123:65535}
    if a['componentType'] not in limits:raise ValueError('Invalid normalized accessor')
    values=[max(-1,v/limits[a['componentType']]) for v in values]
   if any(not math.isfinite(v) for v in values):raise ValueError('Non-finite accessor')
   result[i]=values
  return result
 def transform(self,node):
  if 'matrix' in node:
   m=node['matrix'];scale=[math.sqrt(sum(m[c*4+r]**2 for r in range(3))) for c in range(3)]
   if len(m)!=16 or any(s<1e-12 for s in scale):raise ValueError('Invalid node matrix')
   cols=[[m[c*4+r]/scale[c] for r in range(3)] for c in range(3)]
   if any(abs(sum(cols[a][r]*cols[b][r] for r in range(3)))>1e-6 for a,b in [(0,1),(0,2),(1,2)]):raise ValueError('Sheared node matrix is unsupported')
   if sum(cross(cols[0],cols[1])[i]*cols[2][i] for i in range(3))<0:
    scale[0]=-scale[0];cols[0]=[-v for v in cols[0]]
   r=[[cols[c][j] for c in range(3)] for j in range(3)];trace=sum(r[i][i] for i in range(3))
   if trace>0:
    s=math.sqrt(trace+1)*2;q=[(r[2][1]-r[1][2])/s,(r[0][2]-r[2][0])/s,(r[1][0]-r[0][1])/s,s/4]
   else:
    a=max(range(3),key=lambda i:r[i][i]);b=(a+1)%3;c=(a+2)%3;s=math.sqrt(1+r[a][a]-r[b][b]-r[c][c])*2;q=[0]*4;q[a]=s/4;q[b]=(r[b][a]+r[a][b])/s;q[c]=(r[c][a]+r[a][c])/s;q[3]=(r[c][b]-r[b][c])/s
   return m[12:15]+q+scale
  return node.get('translation',[0,0,0])+node.get('rotation',[0,0,0,1])+node.get('scale',[1,1,1])
 def image(self,index):
  if type(index)!=int or not 0<=index<len(self.doc.get('images',[])):raise ValueError('Invalid image index')
  image=self.doc['images'][index]
  if 'uri' in image:return self.uri(image['uri'])
  view=self.doc['bufferViews'][image['bufferView']];start=view.get('byteOffset',0);return self.buffers[view['buffer']][start:start+view['byteLength']]

def bmp(data,budget=None):
 from PIL import Image
 image=load_image(data,'RGBA',budget)
 return bmp_image(image)

def bmp_image(image):
 w,h=image.size
 pixels=bytearray(image.tobytes())
 for i in range(0,len(pixels),4):pixels[i],pixels[i+2]=pixels[i+2],pixels[i]
 header=bytearray(108);struct.pack_into('<IiiHHII',header,0,108,w,-h,1,32,3,len(pixels));struct.pack_into('<IIIII',header,40,0xff0000,0xff00,0xff,0xff000000,0x73524742)
 return struct.pack('<2sIHHI',b'BM',122+len(pixels),0,0,122)+header+pixels

def cook(source,output,asset_id,hlod_distance=0,hlod_transition=8,hlod_error=0,usd_root=None):
 try:
  if not re.fullmatch(r'[A-Za-z0-9_.-]+',asset_id):raise ValueError('Asset ID must use letters, digits, dot, underscore or hyphen')
  if source.suffix.lower() in ('.usd','.usda','.usdc','.usdz'):
   import importlib.util,types
   spec=importlib.util.spec_from_file_location('atlas_usd_cook',Path(__file__).with_name('cook-usd.py'));usd=importlib.util.module_from_spec(spec);spec.loader.exec_module(usd)
   converter=usd.cook_package if source.suffix.lower()=='.usdz' else usd.cook
   return converter(source,output,asset_id,hlod_distance,hlod_transition,hlod_error,types.SimpleNamespace(**globals()),usd_root)
  return _cook(source,output,asset_id,hlod_distance,hlod_transition,hlod_error)
 except (KeyError,IndexError,TypeError,AttributeError,OverflowError,RecursionError,ZeroDivisionError,struct.error,MemoryError) as error:
  raise ValueError('Malformed or unrepresentable asset: '+str(error)) from error

def _cook(source,output,asset_id,hlod_distance,hlod_transition,hlod_error,extra_dependencies=None,provenance=None,auxiliary=None):
 if not re.fullmatch(r'[A-Za-z0-9_.-]+',asset_id):raise ValueError('Asset ID must use letters, digits, dot, underscore or hyphen')
 output.mkdir(parents=True,exist_ok=True);prefix=asset_id+'-';payloads=Payloads();rows=[];dependencies={str(source):bounded_read(source)};geometry_channels={}
 def put(name,data):payloads[prefix+name]=data.encode() if isinstance(data,str) else data;return prefix+name
 if source.suffix.lower()=='.obj':
  vertices,indices=obj_mesh(source);name=put('mesh.atlasmesh',cooked_mesh(vertices,indices));rows.append(['mesh',asset_id+'/mesh',name])
 else:
  gltf=Gltf(source);d=gltf.doc;materials=[]
  if hlod_distance and (d.get('animations') or any('skin' in node for node in d.get('nodes',[])) or any(primitive.get('targets') for mesh in d.get('meshes',[]) for primitive in mesh['primitives'])):raise ValueError('HLOD cooking accepts static non-morph scenes only')
  material_names=[m.get('name','') for m in d.get('materials',[])];material_ids=[]
  for i,m in enumerate(d.get('materials',[])):
   foliage=m.get('extras',{}).get('atlas_foliage')
   if foliage is not None:
    if not isinstance(foliage,dict) or set(foliage)-{'transmission','wind','padding'}:raise ValueError('Invalid foliage policy')
    transmission=foliage.get('transmission',.6);wind=foliage.get('wind',True);padding=foliage.get('padding',.25)
    if type(wind)!=bool or type(transmission) not in (int,float) or type(padding) not in (int,float) or not math.isfinite(transmission) or not 0<=transmission<=1 or not math.isfinite(padding) or not 0<=padding<=16 or wind and (transmission<=0 or padding<.201):raise ValueError('Invalid foliage transmission/wind/padding')
    if hlod_distance and wind:raise ValueError('Wind-driven foliage retains original instancing; static HLOD cannot bake its object-local wind')
   pbr=m.get('pbrMetallicRoughness',{});color=pbr.get('baseColorFactor',[1,1,1,1]);texture='-'
   alpha=m.get('alphaMode','OPAQUE');cutoff=m.get('alphaCutoff',.5)
   if alpha not in ('OPAQUE','MASK'):raise ValueError('Blended/unknown glTF alpha modes are unsupported')
   if len(color)!=4 or any(not math.isfinite(v) or not 0<=v<=1 for v in color):raise ValueError('Invalid base color factor')
   if color[3]!=1:raise ValueError('Base color alpha factor other than 1 remains unsupported')
   if not math.isfinite(cutoff) or not 0<=cutoff<=1:raise ValueError('Invalid alpha cutoff')
   def sampling(info):
    if info is None:return [10497,10497,9987,9729]
    texture_index=info['index']
    if not isinstance(texture_index,int) or not 0<=texture_index<len(d.get('textures',[])):raise ValueError('Invalid texture index')
    texture=d['textures'][texture_index];sampler_index=texture.get('sampler')
    if sampler_index is not None and (not isinstance(sampler_index,int) or not 0<=sampler_index<len(d.get('samplers',[]))):raise ValueError('Invalid sampler index')
    sampler=d['samplers'][sampler_index] if sampler_index is not None else {}
    values=[sampler.get('wrapS',10497),sampler.get('wrapT',10497),sampler.get('minFilter',9987),sampler.get('magFilter',9729)]
    if values[0] not in (10497,33071,33648) or values[1] not in (10497,33071,33648) or values[2] not in (9728,9729,9984,9985,9986,9987) or values[3] not in (9728,9729):raise ValueError('Invalid glTF sampler')
    return values
   for value in [pbr.get('roughnessFactor',1),pbr.get('metallicFactor',1),m.get('occlusionTexture',{}).get('strength',1),*m.get('emissiveFactor',[0,0,0])]:
    if type(value) not in (int,float) or not math.isfinite(value) or not 0<=value<=1:raise ValueError('Invalid material factor')
   samplers=sampling(pbr.get('baseColorTexture'))+sampling(m.get('normalTexture'))+sampling(pbr.get('metallicRoughnessTexture',m.get('occlusionTexture')))
   if 'metallicRoughnessTexture' in pbr and 'occlusionTexture' in m and sampling(pbr['metallicRoughnessTexture'])!=sampling(m['occlusionTexture']):raise ValueError('Packed ORM maps require matching samplers')
   if 'baseColorTexture' in pbr:
    info=pbr['baseColorTexture']
    if info.get('texCoord',0)!=0 or info.get('extensions'):raise ValueError('Only untransformed TEXCOORD_0 is supported')
    image=d['textures'][info['index']]['source'];texture=put(f'texture-{image}.bmp',bmp(gltf.image(image),gltf.budget))
   normal='-';orm='-'
   def texture_image(info):
    if info.get('texCoord',0)!=0 or info.get('extensions'):raise ValueError('Only untransformed TEXCOORD_0 is supported')
    return gltf.image(d['textures'][info['index']]['source'])
   if 'normalTexture' in m:
    if m['normalTexture'].get('scale',1)!=1:raise ValueError('Normal scale other than 1 is unsupported')
    normal=put(f'material-{i}-normal.bmp',bmp(texture_image(m['normalTexture']),gltf.budget))
   if 'metallicRoughnessTexture' in pbr or 'occlusionTexture' in m:
    from PIL import Image
    mr=load_image(texture_image(pbr['metallicRoughnessTexture']),'RGB',gltf.budget) if 'metallicRoughnessTexture' in pbr else None
    ao=load_image(texture_image(m['occlusionTexture']),'RGB',gltf.budget) if 'occlusionTexture' in m else None
    size=mr.size if mr else ao.size
    if ao and ao.size!=size:ao=ao.resize(size,Image.Resampling.BILINEAR)
    strength=m.get('occlusionTexture',{}).get('strength',1)
    roughness=pbr.get('roughnessFactor',1);metallic=pbr.get('metallicFactor',1)
    gltf.budget.reserve(size[0]*size[1]*16)
    pixels=bytearray(size[0]*size[1]*4)
    for y in range(size[1]):
     for x in range(size[0]):
      rv=mr.getpixel((x,y))[1] if mr else 255
      mv=mr.getpixel((x,y))[2] if mr else 255
      av=ao.getpixel((x,y))[0] if ao else 255
      offset=(y*size[0]+x)*4
      pixels[offset:offset+4]=bytes((round(255+(av-255)*strength),round(rv*roughness),round(mv*metallic),255))
    packed=Image.frombytes('RGBA',size,bytes(pixels));orm=put(f'material-{i}-orm.bmp',bmp_image(packed))
   if texture=='-' and (normal!='-' or orm!='-' or alpha=='MASK' or foliage is not None):
    from PIL import Image
    white=Image.new('RGBA',(1,1),(255,255,255,255));memory=io.BytesIO();white.save(memory,format='PNG');texture=put(f'material-{i}-white.bmp',bmp(memory.getvalue()))
   if len(color)!=4 or color[3]!=1:raise ValueError('Base color alpha factors are unsupported')
   identity=m.get('extras',{}).get('atlas_id')
   if identity is None:identity=material_names[i] if material_names[i] and material_names.count(material_names[i])==1 else str(i)
   if not isinstance(identity,str) or not identity or any(c in identity for c in '\t\n\r') or identity in material_ids:raise ValueError('Invalid/duplicate material atlas_id')
   material_ids.append(identity);key=asset_id+'/material/'+identity;materials.append(key)
   rows.append(['material',key,texture,*map(number,color[:3]),number(pbr.get('roughnessFactor',1)),number(pbr.get('metallicFactor',1)),number(max(m.get('emissiveFactor',[0,0,0]))),normal,orm,*map(str,samplers),str(1 if alpha=='OPAQUE' else 2),number(cutoff)])
   if foliage is not None:rows[-1]+=[number(transmission),str(int(wind)),number(padding)]
  primitive_keys={};skins={};playback=[]
  node_names=[node.get('name','') for node in d.get('nodes',[])]
  identities=[]
  for ni,node in enumerate(d.get('nodes',[])):
   identity=node.get('extras',{}).get('atlas_id')
   if identity is None:identity=node_names[ni] if node_names[ni] and node_names.count(node_names[ni])==1 else str(ni)
   if not isinstance(identity,str) or any(c in identity for c in '\t\n'):raise ValueError('Invalid atlas_id')
   if identity in identities:raise ValueError('Duplicate node atlas_id')
   identities.append(identity)
  for ni,node in enumerate(d.get('nodes',[])):
   if 'mesh' not in node:continue
   mesh=d['meshes'][node['mesh']]
   primitive_ids=set()
   for pi,primitive in enumerate(mesh['primitives']):
    if primitive.get('mode',4)!=4:raise ValueError('Only triangle primitives are supported')
    attrs=primitive['attributes']
    colors=gltf.accessor(attrs['COLOR_0']) if 'COLOR_0' in attrs else []
    positions=gltf.accessor(attrs['POSITION']);n=len(positions)
    if colors:
     if len(colors)!=n or any(len(row) not in (3,4) or any(not 0<=value<=1 for value in row) for row in colors):raise ValueError('Invalid vertex color array')
     colors=[row+[1] if len(row)==3 else row for row in colors]
    indices=[r[0] for r in gltf.accessor(primitive['indices'])] if 'indices' in primitive else list(range(n))
    normals=gltf.accessor(attrs['NORMAL']) if 'NORMAL' in attrs else [[0,0,0] for _ in range(n)]
    uvs=gltf.accessor(attrs['TEXCOORD_0']) if 'TEXCOORD_0' in attrs else [[0,0] for _ in range(n)]
    if len(indices)%3 or len(normals)!=n or len(uvs)!=n or any(i<0 or i>=n or not isinstance(i,int) for i in indices) or any(len(p)!=3 for p in positions+normals) or any(len(uv)!=2 for uv in uvs):raise ValueError('Invalid primitive arrays')
    if 'NORMAL' not in attrs:
     for j in range(0,len(indices),3):
      a,b,c=(positions[indices[j+k]] for k in range(3));face=cross([y-x for x,y in zip(a,b)],[y-x for x,y in zip(a,c)])
      for k in indices[j:j+3]:normals[k]=[x+y for x,y in zip(normals[k],face)]
     normals=list(map(unit,normals))
    primitive_id=primitive.get('extras',{}).get('atlas_id',str(pi))
    if not isinstance(primitive_id,str) or not primitive_id or any(c in primitive_id for c in '\t\n\r') or primitive_id in primitive_ids:raise ValueError('Invalid/duplicate primitive atlas_id')
    primitive_ids.add(primitive_id)
    key=asset_id+'/node/'+identities[ni]+'/primitive/'+primitive_id;stem=f'node-{ni}-primitive-{pi}'
    name=put(stem+'.atlasmesh',cooked_mesh([p+normal+[uv[0],1-uv[1]] for p,normal,uv in zip(positions,normals,uvs)],indices));rows.append(['mesh',key,name]);primitive_keys[(ni,pi)]=(key,materials[primitive['material']] if 'material' in primitive else '')
    tangents=gltf.accessor(attrs['TANGENT']) if 'TANGENT' in attrs else []
    if tangents and (len(tangents)!=n or any(len(t)!=4 or t[3] not in (-1,1) for t in tangents)):raise ValueError('Invalid tangent array')
    tangents=[t[:3]+[-t[3]] for t in tangents]
    targets=[]
    if len(primitive.get('targets',[]))>64:raise ValueError('Too many morph targets')
    for target in primitive.get('targets',[]):
     if set(target)-{'POSITION','NORMAL','TANGENT'} or 'TANGENT' in target and not tangents:raise ValueError('Invalid morph target attributes')
     channels=[gltf.accessor(target[attr]) if attr in target else [[0,0,0] for _ in range(n)] for attr in ['POSITION','NORMAL','TANGENT']]
     if any(len(channel)!=n or any(len(v)!=3 for v in channel) for channel in channels):raise ValueError('Morph vertex count/layout mismatch')
     targets.append([sum((channel[i] for channel in channels),[]) for i in range(n)])
    weights=node.get('weights',mesh.get('weights',[0]*len(targets)))
    if len(weights)!=len(targets) or any(not math.isfinite(v) for v in weights):raise ValueError('Invalid default morph weights')
    if tangents or targets or colors:geometry_channels[name]=(tangents,targets,weights,colors)
    if 'skin' in node:
     skin_index=node['skin'];skin=d['skins'][skin_index];joints=gltf.accessor(attrs['JOINTS_0']);weights=gltf.accessor(attrs['WEIGHTS_0'])
     if len(joints)!=n or len(weights)!=n:raise ValueError('Skin vertex count mismatch')
     mapped=[]
     for js,ws in zip(joints,weights):
      total=sum(ws)
      if len(js)!=4 or len(ws)!=4 or any(type(j)!=int or j<0 or j>=len(skin['joints']) for j in js) or any(w<0 for w in ws) or not math.isfinite(total) or total<=0:raise ValueError('Invalid skin influences')
      mapped.append(record([skin['joints'][j] for j in js]+[w/total for w in ws]))
     put(stem+'.atlasskin','ATLAS_SKIN_1\n'+str(ni)+'\n'+'\n'.join(mapped)+'\n');skins[skin_index]=skin
     playback.append(['skin',key,prefix+stem+'.atlasmeshb',prefix+stem+'.atlasskinb',prefix+f'skin-{skin_index}.atlasskeletonb'])
    elif targets:playback.append(['morph',key,prefix+stem+'.atlasmeshb'])
  for si,skin in skins.items():
   inverses=gltf.accessor(skin['inverseBindMatrices']) if 'inverseBindMatrices' in skin else [IDENTITY]*len(skin['joints'])
   if len(inverses)!=len(skin['joints']):raise ValueError('Inverse bind count mismatch')
   mapping=dict(zip(skin['joints'],inverses));skeleton='ATLAS_SKELETON_1\n'
   for i,node in enumerate(d.get('nodes',[])):skeleton+=record([i,gltf.parents[i]]+gltf.transform(node)+mapping.get(i,IDENTITY))+'\n'
   put(f'skin-{si}.atlasskeleton',skeleton)
  for ai,animation in enumerate(d.get('animations',[])):
   cubic=any(s.get('interpolation')=='CUBICSPLINE' for s in animation['samplers']);clip='ATLAS_CLIP_2\n' if cubic else 'ATLAS_CLIP_1\n';morph='ATLAS_MORPH_CLIP_1\n';pose_index=0;morph_keys=0;morph_tracks=0;seen_channels=set()
   for ti,channel in enumerate(animation['channels']):
    sampler=animation['samplers'][channel['sampler']];interpolation=sampler.get('interpolation','LINEAR');target=channel['target'];path=target['path']
    if interpolation not in ('LINEAR','STEP','CUBICSPLINE') or path not in ('translation','rotation','scale','weights'):raise ValueError('Unsupported animation interpolation/channel')
    times=gltf.accessor(sampler['input']);values=gltf.accessor(sampler['output'])
    mode=['LINEAR','STEP','CUBICSPLINE'].index(interpolation);factor=3 if mode==2 else 1;width=4 if path=='rotation' else 3
    channel_id=(target['node'],path)
    if channel_id in seen_channels:raise ValueError('Duplicate animation channel')
    seen_channels.add(channel_id)
    if path=='weights':
     node=d['nodes'][target['node']]
     if 'mesh' not in node:raise ValueError('Morph animation target has no mesh')
     primitives=d['meshes'][node['mesh']]['primitives'];width=len(primitives[0].get('targets',[]))
     if not 1<=width<=64 or any(len(p.get('targets',[]))!=width for p in primitives):raise ValueError('Morph animation requires consistent target counts')
     if not times or len(times)>10000 or any(len(t)!=1 or t[0]<0 for t in times) or any(a[0]>=b[0] for a,b in zip(times,times[1:])):raise ValueError('Invalid morph key times')
     if len(values)!=len(times)*factor*width or any(len(v)!=1 for v in values) or mode==2 and len(times)<2:raise ValueError('Invalid morph weight output')
     morph_keys+=len(times)*len(primitives);morph_tracks+=len(primitives)
     if morph_tracks>4096:raise ValueError('Morph animation track budget exceeded')
     if morph_keys>100000:raise ValueError('Morph animation key budget exceeded')
     for pi in range(len(primitives)):
      key=primitive_keys[(target['node'],pi)][0]
      if len(key.encode())>4096 or any(c in key for c in '\t\r\n\0'):raise ValueError('Invalid morph asset key')
      for ki,t in enumerate(times):
       weights=[v[0] for v in values[ki*factor*width:(ki+1)*factor*width]]
       morph+='\t'.join([key,str(mode),str(width),number(t[0])]+[number(v) for v in weights])+'\n'
       if len(morph.encode())>32*1024*1024:raise ValueError('Morph clip exceeds 32 MiB runtime limit')
     continue
    if len(times)*factor!=len(values) or mode==2 and len(times)<2 or any(len(t)!=1 or t[0]<0 for t in times) or any(len(v)!=width for v in values) or any(a[0]>=b[0] for a,b in zip(times,times[1:])):raise ValueError('Invalid animation key times/values')
    if not 0<=target['node']<len(d.get('nodes',[])):raise ValueError('Invalid animation target')
    def expanded(value):return value+([0] if len(value)==3 else [])
    for ki,t in enumerate(times):
     value=expanded(values[ki*3+1] if mode==2 else values[ki]);tangents=expanded(values[ki*3])+expanded(values[ki*3+2]) if mode==2 else [0]*8
     clip+=record([pose_index,target['node'],['translation','rotation','scale'].index(path),mode,t[0]]+value+(tangents if cubic else []))+'\n'
    pose_index+=1
   put(f'animation-{ai}.atlasclip',clip)
   if morph_keys:put(f'animation-{ai}.atlasmorphclip',morph)
  if d.get('animations'):
   for ai in range(len(d['animations']) if provenance and provenance.get('format')=='atlas-usd-source-1' else 1):
    playback.append(['clip',prefix+f'animation-{ai}.atlasclipb'])
    if prefix+f'animation-{ai}.atlasmorphclip' in payloads:playback.append(['weights',prefix+f'animation-{ai}.atlasmorphclip'])
  put('playback.atlasplayback','ATLAS_PLAYBACK_1\n'+''.join('\t'.join(row)+'\n' for row in playback))
  scene='MOJO_SCENE_3\n';scene_rows=[]
  for i,node in enumerate(d.get('nodes',[])):
   name=node.get('name',f'node-{i}').replace('\t',' ').replace('\n',' ')
   scene_rows.append([str(i),name,str(gltf.parents[i]),'-1','1',*map(number,gltf.transform(node)),'.7','.7','.7','.6','0','0','-1','',''])
  for (ni,pi),(key,material) in primitive_keys.items():scene_rows.append([str(len(scene_rows)),f'primitive-{ni}-{pi}',str(ni),'-1','1','0','0','0','0','0','0','1','1','1','1','.7','.7','.7','.6','0','0','-1',key,material])
  for i,row in enumerate(scene_rows):
   identity=row[22] or identities[i]
   row.append(str(uuid.uuid5(uuid.NAMESPACE_URL,'atlas/'+asset_id+'/'+identity)))
  put('scene.scene',scene+''.join('\t'.join(r)+'\n' for r in scene_rows));dependencies=gltf.dependencies
 recipes=[]
 if hlod_distance:
  if source.suffix.lower()=='.obj':raise ValueError('HLOD cooking needs a static glTF scene')
  import importlib.util,types
  spec=importlib.util.spec_from_file_location('atlas_hlod_cook',Path(__file__).with_name('cook-hlod.py'));hlod=importlib.util.module_from_spec(spec);spec.loader.exec_module(hlod)
  api=types.SimpleNamespace(MAX_VERTICES=MAX_VERTICES,MAX_INDICES=MAX_INDICES,MAX_FILE=MAX_FILE,unit=unit,cooked_mesh=cooked_mesh,binary_text=binary_text)
  recipes=hlod.cook(payloads,prefix,rows,geometry_channels,hlod_distance,hlod_transition,hlod_error,gltf.budget,api)
 if extra_dependencies:dependencies.update(extra_dependencies)
 if provenance:put('source.json',json.dumps(provenance,indent=2,sort_keys=True)+'\n')
 if auxiliary:
  for name,data in auxiliary.items():
   if not re.fullmatch(r'[A-Za-z0-9_.-]+',name):raise ValueError('Invalid auxiliary asset name')
   put(name,data)
 owned_manifest=prefix+'assets.atlas';payloads[owned_manifest]=('ATLAS_ASSETS_1\n'+''.join('\t'.join(r)+'\n' for r in rows)).encode()
 binary_outputs(payloads,geometry_channels)
 if hlod_distance:
  names=[prefix+'scene.sceneb',owned_manifest+'b']+[next(row[2]+'b' for row in rows if row[0]=='mesh' and row[1]==recipe[8]) for recipe in recipes]
  payloads[prefix+'world.atlashlodb']=envelope(8,hlod.encode(recipes,api,payloads,rows,checksum),[(name,payloads[name]) for name in names])
 if sum(map(len,payloads.values()))>MAX_BUNDLE:raise ValueError('Cooked bundle exceeds 256 MiB limit')
 generation=hashlib.sha256(b''.join(name.encode()+hashlib.sha256(data).digest() for name,data in sorted(payloads.items()))).hexdigest()
 directory='generations/'+asset_id+'/'+generation
 generation_payloads=payloads.copy()
 payloads[owned_manifest],payloads[owned_manifest+'b']=generation_manifest(payloads[owned_manifest],payloads,directory)
 if hlod_distance:
  payloads[prefix+'world.atlashlodb']=envelope(8,hlod.encode(recipes,api,generation_payloads,rows,checksum),[(directory+'/'+name,generation_payloads[name]) for name in names])
 state_path=output/(prefix+'cook.json');state={'generation':directory,'version':VERSION,'cooker_sha256':hashlib.sha256(Path(__file__).read_bytes()+Path(__file__).with_name('cook-hlod.py').read_bytes()).hexdigest(),'asset_id':asset_id,'dependencies':{p:hashlib.sha256(data).hexdigest() for p,data in sorted(dependencies.items())},'outputs':{name:hashlib.sha256(data).hexdigest() for name,data in sorted(payloads.items())}}
 if state_path.exists() and json.loads(state_path.read_text())==state and all((output/name).exists() and hashlib.sha256(bounded_read(output/name)).hexdigest()==digest for name,digest in state['outputs'].items()) and all((output/directory/name).exists() and hashlib.sha256(bounded_read(output/directory/name)).digest()==hashlib.sha256(data).digest() for name,data in generation_payloads.items()):return 'cached'
 # Freeze the complete dependency set before replacing either root manifest.
 # Old generation directories are retained for readers and interrupted reloads.
 generation_path=output/directory
 generation_path.mkdir(parents=True,exist_ok=True)
 for name,data in generation_payloads.items():
  path=generation_path/name
  if not path.exists() or hashlib.sha256(bounded_read(path)).digest()!=hashlib.sha256(data).digest():atomic(path,data)
 sync_directory(generation_path);sync_directory(generation_path.parent);sync_directory(generation_path.parent.parent)
 for name,data in payloads.items():
  if name not in (owned_manifest,owned_manifest+'b'):atomic(output/name,data)
 atomic(output/owned_manifest,payloads[owned_manifest])
 atomic(output/(owned_manifest+'b'),payloads[owned_manifest+'b'])
 atomic(state_path,json.dumps(state,indent=2)+'\n');return 'cooked'

def main():
 parser=argparse.ArgumentParser();parser.add_argument('source',type=Path);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--id');parser.add_argument('--hlod-distance',type=float,default=0);parser.add_argument('--hlod-transition',type=float,default=8);parser.add_argument('--hlod-error',type=float,default=0);parser.add_argument('--usd-root',type=Path);args=parser.parse_args()
 source=args.source.resolve()
 if source.suffix.lower() not in ('.obj','.gltf','.glb','.usd','.usda','.usdc','.usdz'):parser.error('Input must be OBJ, glTF, GLB, USD, USDA, USDC or USDZ')
 try:print(cook(source,args.output.resolve(),args.id or source.stem,args.hlod_distance,args.hlod_transition,args.hlod_error,args.usd_root))
 except (ValueError,OSError) as error:raise SystemExit('Asset cook failed: '+str(error))
if __name__=='__main__':main()
