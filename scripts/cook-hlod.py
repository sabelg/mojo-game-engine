"""Static hierarchy aggregation for the Atlas cooker, with bounded voxel error.

Animated/morph meshes are excluded by the caller. Dynamic wind is not baked:
wind-driven foliage retains ordinary instancing and its object-local field.
"""
import hashlib,math,struct

def matrix(trs):
 x,y,z,qx,qy,qz,qw,sx,sy,sz=trs
 length=math.sqrt(qx*qx+qy*qy+qz*qz+qw*qw)
 if length<1e-12:qx,qy,qz,qw=0,0,0,1
 else:qx,qy,qz,qw=(v/length for v in [qx,qy,qz,qw])
 def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
 def rotate(v):
  q=[qx,qy,qz];t=[a*2 for a in cross(q,v)];c=cross(q,t)
  return [v[i]+t[i]*qw+c[i] for i in range(3)]
 return rotate([sx,0,0])+[0]+rotate([0,sy,0])+[0]+rotate([0,0,sz])+[0]+[x,y,z,1]
def multiply(a,b):return [sum(a[k*4+r]*b[c*4+k] for k in range(4)) for c in range(4) for r in range(4)]
def point(m,p):return [sum(m[c*4+r]*p[c] for c in range(3))+m[12+r] for r in range(3)]
def direction(m,p):return [sum(m[c*4+r]*p[c] for c in range(3)) for r in range(3)]
def normal(m,n,unit):
 a,b,c=(m[i:i+3] for i in [0,4,8])
 cross=lambda u,v:[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
 bc,ca,ab=cross(b,c),cross(c,a),cross(a,b)
 det=sum(a[i]*bc[i] for i in range(3))
 if not math.isfinite(det) or abs(det)<1e-12:raise ValueError('Singular HLOD transform')
 return unit([(bc[i]*n[0]+ca[i]*n[1]+ab[i]*n[2])/det for i in range(3)]),det

def cook(payloads,prefix,manifest,channels,distance,width,error,budget,api):
 if not all(math.isfinite(v) for v in [distance,width,error]) or distance<1 or distance>100000 or width<0 or width>distance or error<0 or error>16:raise ValueError('Invalid HLOD distance/transition/error policy')
 scene=payloads[prefix+'scene.scene'].decode().splitlines()[1:]
 rows=[row.split('\t') for row in scene];matrices=[None]*len(rows)
 if len(rows)>100000:raise ValueError('HLOD scene exceeds node budget')
 def world(index,depth=0):
  if depth>256:raise ValueError('HLOD hierarchy exceeds depth 256')
  if matrices[index] is None:
   row=rows[index];local=matrix(list(map(float,row[5:15])));parent=int(row[2])
   matrices[index]=multiply(world(parent,depth+1),local) if parent>=0 else local
  return matrices[index]
 meshes={row[1]:row[2] for row in manifest if row[0]=='mesh'};groups={}
 for index,row in enumerate(rows):
  if not int(row[4]) or not row[22]:continue
  name=meshes[row[22]];m=world(index)
  budget.reserve(len(payloads[name])*8)
  lines=payloads[name].decode().splitlines()[1:]
  vertices=[list(map(float,line.split()[1:])) for line in lines if line.startswith('v ')]
  indices=[int(v) for line in lines if line.startswith('i ') for v in line.split()[1:]]
  world_positions=[point(m,v[:3]) for v in vertices]
  lo=[min(p[i] for p in world_positions) for i in range(3)];hi=[max(p[i] for p in world_positions) for i in range(3)]
  grid=tuple(math.floor((lo[i]+hi[i])*.5/64) for i in [0,2])
  material=tuple(map(float,row[15:21]));key=grid+(row[23],material)
  groups.setdefault(key,[]).append((row[24],row[22],m,vertices,indices,lo,hi,channels.get(name)))
 if len(groups)>4096:raise ValueError('HLOD exceeds 4096 clusters')
 recipes=[]
 for key,sources in sorted(groups.items()):
  # Preserve single objects; aggregation is useful when it replaces several draws.
  if len(sources)<2:continue
  sources.sort(key=lambda source:source[0])
  lo=[min(source[5][i] for source in sources) for i in range(3)];hi=[max(source[6][i] for source in sources) for i in range(3)]
  center=[(lo[i]+hi[i])*.5 for i in range(3)];vertices=[];indices=[];tangents=[];colors=[]
  has_tangent=any(source[7] and source[7][0] for source in sources)
  has_color=any(source[7] and len(source[7])>3 and source[7][3] for source in sources)
  for identity,asset,m,vs,ids,_,_,attrs in sources:
   base=len(vertices)
   if base+len(vs)>api.MAX_VERTICES or len(indices)+len(ids)>api.MAX_INDICES:raise ValueError('HLOD cluster exceeds geometry limits; split source clusters')
   for i,v in enumerate(vs):
    p=point(m,v[:3]);n,det=normal(m,v[3:6],api.unit)
    vertices.append([p[j]-center[j] for j in range(3)]+n+v[6:8])
    if has_tangent:
     t=attrs[0][i] if attrs and attrs[0] else [1,0,0,1]
     tangents.append(api.unit(direction(m,t[:3]))+[t[3]*(1 if det>0 else -1)])
    if has_color:colors.append(attrs[3][i] if attrs and len(attrs)>3 and attrs[3] else [1]*4)
   indices.extend(base+index for index in ids)
  # Normal, UV and authored channels form seam keys. Only positions within a
  # cell merge; the first representative bounds displacement by sqrt(3)*cell.
  actual_error=0
  if error>0:
   cell=error/math.sqrt(3);lookup={};mapping=[];simplified=[];st=[];sc=[]
   for i,v in enumerate(vertices):
    bucket=tuple(math.floor(p/cell) for p in v[:3])+tuple(round(n,6) for n in v[3:6])+tuple(v[6:])
    if has_tangent:bucket+=tuple(round(t,6) for t in tangents[i])
    if has_color:bucket+=tuple(colors[i])
    if bucket not in lookup:
     lookup[bucket]=len(simplified);simplified.append(v)
     if has_tangent:st.append(tangents[i])
     if has_color:sc.append(colors[i])
    target=lookup[bucket];mapping.append(target)
    actual_error=max(actual_error,math.dist(v[:3],simplified[target][:3]))
   reduced=[]
   for offset in range(0,len(indices),3):
    triangle=[mapping[index] for index in indices[offset:offset+3]]
    if len(set(triangle))==3:reduced.extend(triangle)
   if reduced:vertices,indices,tangents,colors=simplified,reduced,st,sc
   else:actual_error=0
  identity=hashlib.sha256(repr(key).encode()).hexdigest()[:16];name=prefix+'hlod-'+identity+'.atlasmesh';asset=prefix.removesuffix('-')+'/hlod/'+identity
  payloads[name]=api.cooked_mesh(vertices,indices).encode();channels[name]=(tangents,[],[],colors)
  manifest.append(['mesh',asset,name])
  recipes.append((center,lo,hi,distance,width,actual_error,key[2],key[3],asset,sources))
 return recipes

def encode(recipes,api,payloads,manifest,checksum):
 meshes={row[1]:row[2]+'b' for row in manifest if row[0]=='mesh'}
 body=bytearray(struct.pack('<I',len(recipes)))
 for center,lo,hi,distance,width,error,material,values,proxy,sources in recipes:
  body.extend(struct.pack('<18d',*center,*lo,*hi,distance,width,error,*values))
  body.extend(api.binary_text(material));body.extend(api.binary_text(proxy));body.extend(struct.pack('<QI',checksum(payloads[meshes[proxy]]),len(sources)))
  for identity,asset,m,*_ in sources:
   body.extend(api.binary_text(identity));body.extend(api.binary_text(asset));body.extend(struct.pack('<Q16d',checksum(payloads[meshes[asset]]),*m))
  if len(body)>api.MAX_FILE-32:raise ValueError('HLOD metadata exceeds file budget')
 return bytes(body)
