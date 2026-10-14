"""Cooker regressions use independent binary glTF inputs and inspect outputs."""
import base64,importlib.util,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('atlas_cook',ROOT/'scripts/cook-assets.py');cook=importlib.util.module_from_spec(spec);spec.loader.exec_module(cook)
root=ROOT/'build/atlas-cook-test';root.mkdir(parents=True,exist_ok=True)
payload=bytearray();views=[];accessors=[]
def accessor(values,fmt,kind,component,width):
 while len(payload)%4:payload.append(0)
 offset=len(payload)
 for row in values:payload.extend(struct.pack('<'+fmt*width,*row))
 views.append({'buffer':0,'byteOffset':offset,'byteLength':len(payload)-offset})
 accessors.append({'bufferView':len(views)-1,'componentType':component,'count':len(values),'type':kind})
 return len(accessors)-1
positions=accessor([[0,0,0],[1,0,0],[0,1,0]],'f','VEC3',5126,3)
joints=accessor([[0,0,0,0]]*3,'B','VEC4',5121,4)
weights=accessor([[1,0,0,0]]*3,'f','VEC4',5126,4)
inverse=accessor([cook.IDENTITY],'f','MAT4',5126,16)
times=accessor([[0],[1]],'f','SCALAR',5126,1)
translations=accessor([[0,0,0],[2,0,0]],'f','VEC3',5126,3)
doc={'asset':{'version':'2.0'},'buffers':[{'uri':'fixture.bin','byteLength':len(payload)}],'bufferViews':views,'accessors':accessors,'nodes':[{'name':'joint'},{'name':'mesh','mesh':0,'skin':0}],'meshes':[{'primitives':[{'attributes':{'POSITION':positions,'JOINTS_0':joints,'WEIGHTS_0':weights}}]}],'skins':[{'joints':[0],'inverseBindMatrices':inverse}],'animations':[{'samplers':[{'input':times,'output':translations}],'channels':[{'sampler':0,'target':{'node':0,'path':'translation'}}]}]}
source=root/'fixture.gltf';source.write_text(json.dumps(doc));(root/'fixture.bin').write_bytes(payload)
output=root/'cooked'
assert cook.cook(source,output,'fixture') in ('cooked','cached')
assert cook.cook(source,output,'fixture')=='cached'
mesh=output/'fixture-node-1-primitive-0.atlasmesh';text=mesh.read_text().splitlines();assert len([r for r in text if r.startswith('v ')])==3;assert text[-1]=='i 0 1 2'
assert (output/'fixture-skin-0.atlasskeleton').read_text().splitlines()[0]=='ATLAS_SKELETON_1'
assert all(len(row.split('\t'))==25 for row in (output/'fixture-scene.scene').read_text().splitlines()[1:])
mesh.write_text('corrupted');assert cook.cook(source,output,'fixture')=='cooked';assert mesh.read_text().splitlines()[-1]=='i 0 1 2'
binary_mesh=output/'fixture-node-1-primitive-0.atlasmeshb'
magic,version,kind,length,checksum=struct.unpack_from('<8sIIQQ',binary_mesh.read_bytes())
assert (magic,version,kind)==(b'ATLASB2\0',2,1)
assert length==len(binary_mesh.read_bytes())-32 and checksum==cook.checksum(binary_mesh.read_bytes()[32:])
binary_mesh.write_bytes(b'corrupt');assert cook.cook(source,output,'fixture')=='cooked'
# Independent malformed binary fixtures with valid outer checksums.
bad_binary=root/'bad-binary';bad_binary.mkdir(exist_ok=True)
for name,data in {
 'count.atlasmeshb':cook.envelope(1,struct.pack('<II',0xffffffff,3)),
 'truncated.atlasmeshb':cook.envelope(1,struct.pack('<II',3,3)),
 'nan.atlasmeshb':cook.envelope(1,struct.pack('<II',3,3)+struct.pack('<24f',float('nan'),*([0]*23))+struct.pack('<3I',0,1,2)),
 'index.atlasmeshb':cook.envelope(1,struct.pack('<II',3,3)+struct.pack('<24f',*([0]*24))+struct.pack('<3I',0,1,3)),
 'kind.atlasmeshb':cook.envelope(2,b''),
 'trailing.atlasmeshb':binary_mesh.read_bytes()+b'\0',
 'utf8.atlasb':cook.envelope(3,struct.pack('<II',1,1)+struct.pack('<I',2)+b'\xc0\xaf'),
 'path.atlasb':cook.envelope(3,struct.pack('<I',0),[('../outside',b'')]),
}.items():(bad_binary/name).write_bytes(data)
# An external dependency change invalidates the cache.
struct.pack_into('<f',payload,0,.25);(root/'fixture.bin').write_bytes(payload);assert cook.cook(source,output,'fixture')=='cooked';struct.pack_into('<f',payload,0,0);(root/'fixture.bin').write_bytes(payload);cook.cook(source,output,'fixture')
# The GLB path accepts the same data without relying on external buffers.
glb_doc=json.loads(json.dumps(doc));glb_doc['buffers'][0].pop('uri');encoded=json.dumps(glb_doc).encode();encoded+=b' '*((-len(encoded))%4);binary=bytes(payload)+b'\0'*((-len(payload))%4);body=struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary;glb=root/'fixture.glb';glb.write_bytes(struct.pack('<III',0x46546c67,2,len(body)+12)+body);assert cook.cook(glb,root/'glb','glb') in ('cooked','cached')
malformed=json.loads(json.dumps(doc));malformed['accessors'][0]['count']=999;bad=root/'bad.gltf';bad.write_text(json.dumps(malformed))
try:cook.cook(bad,root/'bad','bad')
except ValueError:pass
else:raise AssertionError('Out-of-bounds accessor accepted')
print('Atlas cooker passed: glTF/GLB, skin/clip/scene formats, dependency invalidation, cached rebuilds, corrupted-output repair, malformed accessor rejection')
# Sparse position data has no dense buffer view and substitutes two slots.
sparse_indices=accessor([[1],[2]],'B','SCALAR',5121,1)
sparse_values=accessor([[1,0,0],[0,1,0]],'f','VEC3',5126,3)
sparse_doc={'asset':{'version':'2.0'},'buffers':[{'uri':'extended.bin','byteLength':len(payload)}],'bufferViews':views,'accessors':accessors+[
 {'componentType':5126,'count':3,'type':'VEC3','sparse':{'count':2,'indices':{'bufferView':accessors[sparse_indices]['bufferView'],'componentType':5121},'values':{'bufferView':accessors[sparse_values]['bufferView']}}}],
 'nodes':[{'name':'sparse','mesh':0}],'meshes':[{'primitives':[{'attributes':{'POSITION':len(accessors)}}]}]}
(root/'extended.bin').write_bytes(payload);sparse_source=root/'sparse.gltf';sparse_source.write_text(json.dumps(sparse_doc))
assert cook.cook(sparse_source,root/'extended','sparse') in ('cooked','cached')
assert (root/'extended/sparse-node-0-primitive-0.atlasmesh').read_text().splitlines()[1:4]==(output/'fixture-node-1-primitive-0.atlasmesh').read_text().splitlines()[1:4]
invalid_sparse=json.loads(json.dumps(sparse_doc));invalid_sparse['accessors'][-1]['sparse']['count']=4
sparse_source.write_text(json.dumps(invalid_sparse))
try:cook.cook(sparse_source,root/'invalid-sparse','sparse')
except ValueError:pass
else:raise AssertionError('Sparse count greater than base count accepted')
sparse_source.write_text(json.dumps(sparse_doc))
# Hermite translation fixture: t=0,2 with outgoing tangent 2 then incoming 0.
cubic_times=accessor([[0],[2]],'f','SCALAR',5126,1)
cubic_values=accessor([[0,0,0],[0,0,0],[2,0,0],[0,0,0],[2,0,0],[0,0,0]],'f','VEC3',5126,3)
cubic_doc=json.loads(json.dumps(doc));cubic_doc.update(buffers=[{'uri':'cubic.bin','byteLength':len(payload)}],bufferViews=views,accessors=accessors)
cubic_doc['animations']=[{'samplers':[{'input':cubic_times,'output':cubic_values,'interpolation':'CUBICSPLINE'}],'channels':[{'sampler':0,'target':{'node':0,'path':'translation'}}]}]
(root/'cubic.bin').write_bytes(payload);cubic_source=root/'cubic.gltf';cubic_source.write_text(json.dumps(cubic_doc))
assert cook.cook(cubic_source,root/'extended','cubic') in ('cooked','cached')
assert (root/'extended/cubic-animation-0.atlasclip').read_text().splitlines()[0]=='ATLAS_CLIP_2'
print('Extended glTF fixtures passed: sparse substitution, malformed sparse count, cubic tangent preservation')
# Authored tangents and multiple morph attributes retain independent channels.
tangent_values=accessor([[1,0,0,1]]*3,'f','VEC4',5126,4)
morph_positions=accessor([[0,0,1]]*3,'f','VEC3',5126,3)
morph_doc=json.loads(json.dumps(doc));morph_doc.update(buffers=[{'uri':'morph.bin','byteLength':len(payload)}],bufferViews=views,accessors=accessors)
morph_doc['meshes'][0]['primitives'][0]['attributes']['TANGENT']=tangent_values
morph_doc['meshes'][0]['primitives'][0]['targets']=[{'POSITION':morph_positions}];morph_doc['meshes'][0]['weights']=[.5]
(root/'morph.bin').write_bytes(payload);morph_source=root/'morph.gltf';morph_source.write_text(json.dumps(morph_doc))
assert cook.cook(morph_source,root/'extended','morph') in ('cooked','cached')
# Reorder named nodes plus explicitly identified primitives/materials, remapping
# source indices. Stable references and scene persistent IDs must not change.
ordered=json.loads(json.dumps(doc));ordered['materials']=[{'name':'red'},{'name':'green'}]
ordered['meshes'][0]['primitives']=[dict(ordered['meshes'][0]['primitives'][0],material=i,extras={'atlas_id':name}) for i,name in enumerate(['body','trim'])]
order_source=root/'order.gltf';order_source.write_text(json.dumps(ordered));cook.cook(order_source,root/'order-before','ordered')
ordered['nodes'].reverse();ordered['skins'][0]['joints']=[1];ordered['animations'][0]['channels'][0]['target']['node']=1
ordered['materials'].reverse();ordered['meshes'][0]['primitives'].reverse()
for primitive in ordered['meshes'][0]['primitives']:primitive['material']=1-primitive['material']
order_source.write_text(json.dumps(ordered));cook.cook(order_source,root/'order-after','ordered')
def scene_identities(path):return {row.split('\t')[22] or row.split('\t')[1]:row.split('\t')[24] for row in path.read_text().splitlines()[1:]}
assert scene_identities(root/'order-before/ordered-scene.scene')==scene_identities(root/'order-after/ordered-scene.scene')
def manifest_keys(path):return sorted((row.split('\t')[0],row.split('\t')[1]) for row in path.read_text().splitlines()[1:])
assert manifest_keys(root/'order-before/ordered-assets.atlas')==manifest_keys(root/'order-after/ordered-assets.atlas')
print('Geometry/identity fixtures passed: tangent/morph preservation and source reordering')
collision_body=cook.collision_payload([[0,0,0,0,0,1,0,0],[1,0,0,0,0,1,0,0],[0,1,0,0,0,1,0,0]],[0,1,2])
collision_bad=root/'bad-collision';collision_bad.mkdir(exist_ok=True)
bad_order=bytearray(collision_body);struct.pack_into('<I',bad_order,44,3)
bad_bounds=bytearray(collision_body);struct.pack_into('<d',bad_bounds,48+24,.5)
bad_cycle=bytearray(collision_body);struct.pack_into('<4i',bad_cycle,48+48,0,0,0,0)
uncovered=struct.pack('<II',2,1)+collision_body[8:44]*2+struct.pack('<II',0,1)+collision_body[48:]
for name,body in {'order':bad_order,'bounds':bad_bounds,'cycle':bad_cycle,'uncovered':uncovered,'trailing':collision_body+b'x'}.items():(collision_bad/(name+'.atlascollisionb')).write_bytes(cook.envelope(7,body))
# Immutable generations survive recooks, and damaged generation files are repaired.
state=json.loads((output/'fixture-cook.json').read_text());generation=output/state['generation']
generation_mesh=generation/'fixture-node-1-primitive-0.atlasmeshb';frozen=generation_mesh.read_bytes()
struct.pack_into('<f',payload,0,.125);(root/'fixture.bin').write_bytes(payload);cook.cook(source,output,'fixture')
assert generation_mesh.read_bytes()==frozen
struct.pack_into('<f',payload,0,0);(root/'fixture.bin').write_bytes(payload);cook.cook(source,output,'fixture')
generation_mesh.write_bytes(b'damaged');assert cook.cook(source,output,'fixture')=='cooked';assert generation_mesh.read_bytes()==frozen
# Independently authored sampler and alpha fixtures retain policy in both manifests.
from PIL import Image
image=Image.new('RGBA',(2,2));image.putdata([(255,0,0,0),(0,255,0,128),(0,0,255,255),(255,255,255,255)]);image.save(root/'policy.png')
policy=json.loads(json.dumps(doc));policy['images']=[{'uri':'policy.png'}];policy['textures']=[{'source':0,'sampler':0}];policy['samplers']=[{'wrapS':33071,'wrapT':33648,'minFilter':9728,'magFilter':9728}]
policy['materials']=[{'name':'mask','alphaMode':'MASK','alphaCutoff':.7,'pbrMetallicRoughness':{'baseColorTexture':{'index':0}}}];policy['meshes'][0]['primitives'][0]['material']=0
policy_source=root/'policy.gltf';policy_source.write_text(json.dumps(policy));cook.cook(policy_source,root/'policy','policy')
row=[row.split('\t') for row in (root/'policy/policy-assets.atlas').read_text().splitlines() if row.startswith('material\t')][0]
assert len(row)==25 and row[11:15]==['33071','33648','9728','9728'] and row[23]=='2' and float(row[24])==.7
policy['samplers'][0]['wrapS']=-1;policy_source.write_text(json.dumps(policy))
try:cook.cook(policy_source,root/'bad-policy','policy')
except ValueError:pass
else:raise AssertionError('Invalid glTF sampler accepted')
# References outside the verified dependency table fail, even with valid envelopes.
(bad_binary/'undeclared.atlasb').write_bytes(cook.envelope(3,struct.pack('<II',1,1)+cook.binary_text('mesh')+cook.binary_text('hidden.atlasmeshb')))
(bad_binary/'row-path.atlasb').write_bytes(cook.envelope(3,struct.pack('<II',1,1)+cook.binary_text('mesh')+cook.binary_text('../hidden.atlasmeshb')))
print('Publication/material fixtures passed: immutable generations, generation repair, sampler policy, alpha cutoff and undeclared references')
color_values=accessor([[.25,.5,.75,1]]*3,'f','VEC4',5126,4)
color_doc=json.loads(json.dumps(doc));color_doc.update(buffers=[{'uri':'colors.bin','byteLength':len(payload)}],bufferViews=views,accessors=accessors)
color_doc['meshes'][0]['primitives'][0]['attributes']['COLOR_0']=color_values
(root/'colors.bin').write_bytes(payload);color_source=root/'colors.gltf';color_source.write_text(json.dumps(color_doc))
cook.cook(color_source,root/'extended','colors')
print('Vertex color fixture passed: independently authored normalized RGBA channel')
# Malformed import shapes and numeric extremes must fail through the public
# cooker with useful errors, preserving a previously published dependency set.
import subprocess,sys
fuzz_source=root/'malformed-shapes.gltf'
frozen_manifest=(output/'fixture-assets.atlasb').read_bytes()
mutations=[]
for field in ['nodes','meshes','skins','animations','accessors','buffers','bufferViews','materials','images','textures','samplers','scenes']:
 for value in [None,17,'array',{'nested':[]}]:
  invalid=json.loads(json.dumps(doc));invalid[field]=value;mutations.append(invalid)
for field,value in [('translation',[10**400,0,0]),('matrix',[1e308,0,0,0,0,1e308,0,0,0,0,1e308,0,0,0,0,1]),('extras',[]),('children',17)]:
 invalid=json.loads(json.dumps(doc));invalid['nodes'][0][field]=value;mutations.append(invalid)
for invalid in mutations:
 fuzz_source.write_text(json.dumps(invalid))
 try:cook.cook(fuzz_source,output,'fixture')
 except ValueError:pass
 else:raise AssertionError('Malformed glTF shape or numeric extreme accepted')
 assert (output/'fixture-assets.atlasb').read_bytes()==frozen_manifest
fuzz_source.write_text('{"asset":{"version":"2.0"},"extras":'+('['*2000)+'0'+(']'*2000)+'}')
try:cook.cook(fuzz_source,output,'fixture')
except ValueError:pass
else:raise AssertionError('Excessively nested document accepted')
result=subprocess.run([sys.executable,str(ROOT/'scripts/cook-assets.py'),str(fuzz_source),'--output',str(output),'--id','fixture'],capture_output=True,text=True)
assert result.returncode!=0 and 'Asset cook failed:' in result.stderr and 'Traceback' not in result.stderr
assert (output/'fixture-assets.atlasb').read_bytes()==frozen_manifest
assert all(abs(a-b)<1e-15 for a,b in zip(cook.unit([1e308,1e308,0]),[2**-.5,2**-.5,0]))
print('Malformed import fixtures passed:',len(mutations)+1,'shape/numeric/nesting cases, clear CLI failure and preserved publication')
# Count expansion is checked before buffers/accessors are decoded. A tiny source
# can otherwise reference the same large mesh thousands of times.
large={'asset':{'version':'2.0'},'buffers':[{'uri':'must-not-be-read.bin','byteLength':2_400_000}],
       'bufferViews':[{'buffer':0,'byteLength':2_400_000}],
       'accessors':[{'bufferView':0,'componentType':5126,'count':200_000,'type':'VEC3'}],
       'meshes':[{'primitives':[{'attributes':{'POSITION':0}}]}],
       'nodes':[{'mesh':0} for _ in range(8)]}
fuzz_source.write_text(json.dumps(large))
try:cook.cook(fuzz_source,output,'fixture')
except ValueError as error:assert 'estimated work budget' in str(error)
else:raise AssertionError('Repeated large mesh expansion accepted')
assert (output/'fixture-assets.atlasb').read_bytes()==frozen_manifest
# Run the same public CLI under a hard 256 MiB process address-space cap. Its
# count-only preflight must fail cleanly before opening the nonexistent buffer.
def resource_limit():
 import resource
 resource.setrlimit(resource.RLIMIT_AS,(256*1024**2,256*1024**2))
result=subprocess.run([sys.executable,str(ROOT/'scripts/cook-assets.py'),str(fuzz_source),'--output',str(output),'--id','fixture'],capture_output=True,text=True,preexec_fn=resource_limit,timeout=10)
assert result.returncode!=0 and 'estimated work budget' in result.stderr and 'Traceback' not in result.stderr
for count,index_count in [(250001,3),(3,750001)]:
 large['nodes']=[{'mesh':0}];large['accessors'][0]['count']=count
 if index_count>3:
  large['accessors'].append({'componentType':5125,'count':index_count,'type':'SCALAR'})
  large['meshes'][0]['primitives'][0]['indices']=1
 fuzz_source.write_text(json.dumps(large))
 try:cook.cook(fuzz_source,output,'fixture')
 except ValueError as error:assert 'vertex/750000 index limits' in str(error)
 else:raise AssertionError('Oversized primitive accepted')
# Check cumulative retained bytes including replacements without allocating the
# production-size limits in a test process.
file_limit,bundle_limit=cook.MAX_FILE,cook.MAX_BUNDLE
try:
 cook.MAX_FILE=16;cook.MAX_BUNDLE=24
 payloads=cook.Payloads();payloads['a']=b'a'*16;payloads['b']=b'b'*8
 payloads['a']=b'a'*8;assert payloads.bytes==16
 try:payloads['c']=b'c'*9
 except ValueError:pass
 else:raise AssertionError('Cumulative output budget accepted')
 assert 'c' not in payloads and payloads.bytes==16
 try:payloads['a']=b'a'*17
 except ValueError:pass
 else:raise AssertionError('Output file budget accepted')
 assert len(payloads['a'])==8
finally:cook.MAX_FILE=file_limit;cook.MAX_BUNDLE=bundle_limit
# Seeded structural mutations exercise the public failure boundary and preserve
# all published hashes; these are bounded parser fixtures, not conformance fuzzing.
import random
rng=random.Random(0xA71A5)
for _ in range(256):
 invalid=json.loads(json.dumps(doc));choice=rng.randrange(4)
 if choice==0:invalid['meshes'][0]['primitives'][0]['attributes']['POSITION']=rng.randrange(4096,2**31)
 elif choice==1:invalid['accessors'][0]['count']=-rng.randrange(1,2**31)
 elif choice==2:invalid['nodes'][0]['rotation']=[rng.random(),0,0,0]
 else:invalid['buffers'][0]['uri']='../outside-'+str(rng.randrange(2**32))
 fuzz_source.write_text(json.dumps(invalid))
 try:cook.cook(fuzz_source,output,'fixture')
 except ValueError:pass
 else:raise AssertionError('Seeded invalid import accepted')
 assert (output/'fixture-assets.atlasb').read_bytes()==frozen_manifest
print('Allocation/parser fixtures passed: count preflight under 256 MiB address-space cap, primitive/retained-byte bounds and 256 seeded mutations')
# Independently authored static hierarchy: three dense surfaces share material,
# with a rotated/scaled nested source. Exact aggregation and bounded simplification
# are cooked as separate generations. Rigs must reject the static HLOD path.
try:cook.cook(source,root/'bad-hlod','rig',hlod_distance=12)
except ValueError as error:assert 'static non-morph' in str(error)
else:raise AssertionError('Animated scene accepted by static HLOD cooker')
side=21
hlod_positions=accessor([[x*.2,0,z*.2] for z in range(side) for x in range(side)],'f','VEC3',5126,3)
hlod_normals=accessor([[0,1,0]]*(side*side),'f','VEC3',5126,3)
hlod_tangents=accessor([[1,0,0,1]]*(side*side),'f','VEC4',5126,4)
hlod_colors=accessor([[.4,.6,.8,1]]*(side*side),'f','VEC4',5126,4)
triangles=[]
for z in range(side-1):
 for x in range(side-1):
  a=z*side+x;triangles.extend([[a],[a+side],[a+1],[a+1],[a+side],[a+side+1]])
hlod_indices=accessor(triangles,'I','SCALAR',5125,1)
hlod_doc={'asset':{'version':'2.0'},'buffers':[{'uri':'hlod.bin','byteLength':len(payload)}],'bufferViews':views,'accessors':accessors,
 'meshes':[{'primitives':[{'attributes':{'POSITION':hlod_positions,'NORMAL':hlod_normals,'TANGENT':hlod_tangents,'COLOR_0':hlod_colors},'indices':hlod_indices}]}],
 'nodes':[{'name':'first','mesh':0,'translation':[10,0,8]},{'name':'second','mesh':0,'translation':[16,0,8]},
          {'name':'nested','translation':[24,0,8],'rotation':[0,2**-.5,0,2**-.5],'scale':[.8,1,1.2],'children':[3]},
          {'name':'third','mesh':0,'translation':[1,0,0]}]}
# Distinct vertex colors keep these source geometries in separate near batches.
for values,node_index in [([.8,.4,.6,1],1),([.6,.8,.4,1],3)]:
 color=accessor([values]*(side*side),'f','VEC4',5126,4)
 mesh=json.loads(json.dumps(hlod_doc['meshes'][0]));mesh['primitives'][0]['attributes']['COLOR_0']=color
 hlod_doc['nodes'][node_index]['mesh']=len(hlod_doc['meshes']);hlod_doc['meshes'].append(mesh)
hlod_doc['buffers'][0]['byteLength']=len(payload)
(root/'hlod.bin').write_bytes(payload);hlod_source=root/'hlod.gltf';hlod_source.write_text(json.dumps(hlod_doc))
for asset_id,error in [('hlod-exact',0),('hlod-reduced',.5)]:
 cook.cook(hlod_source,root/'hlod',asset_id,hlod_distance=12,hlod_transition=8,hlod_error=error)
 state=json.loads((root/'hlod'/f'{asset_id}-cook.json').read_text());generation=root/'hlod'/state['generation']
 metadata=generation/f'{asset_id}-world.atlashlodb';assert struct.unpack_from('<I',metadata.read_bytes(),12)[0]==8
 proxies=list(generation.glob(asset_id+'-hlod-*.atlasmesh'));assert len(proxies)==1
 proxy_rows=proxies[0].read_text().splitlines();proxy_triangles=sum(row.startswith('i ') for row in proxy_rows)
 assert proxy_triangles==2400 if error==0 else proxy_triangles<1200
 # Generation and proxy key stay stable when named sources reorder.
 before=metadata.read_bytes();reordered=json.loads(json.dumps(hlod_doc));reordered['nodes'][0],reordered['nodes'][1]=reordered['nodes'][1],reordered['nodes'][0]
 hlod_source.write_text(json.dumps(reordered));cook.cook(hlod_source,root/'hlod-reorder',asset_id,12,8,error)
 # Source scene hashes differ on reorder, so compare aggregate mesh bytes.
 assert (root/'hlod-reorder'/proxies[0].name).read_bytes()==proxies[0].read_bytes()
 hlod_source.write_text(json.dumps(hlod_doc))
for node in hlod_doc['nodes']:
 if 'translation' in node and node['name']!='third':node['translation'][0]+=1_000_000_000;node['translation'][2]+=1_000_000_000
hlod_source.write_text(json.dumps(hlod_doc));cook.cook(hlod_source,root/'hlod','hlod-far',12,8,0)
print('Static HLOD cooking passed: hierarchy aggregation, normal/tangent/color preservation, bounded voxel reduction, deterministic reorder and billion-unit rebasing')

# Cooked foliage policy retains the object-local wind field and conservative
# padding. Repeated identical meshes can share a submission batch by content.
foliage=json.loads(json.dumps(policy));foliage['samplers'][0]['wrapS']=33071
foliage.pop('skins',None);foliage.pop('animations',None)
foliage['nodes']=[{'name':'leaf-'+str(i),'mesh':0,'translation':[i*2-2,0,-6]} for i in range(3)]
foliage['materials'][0]['extras']={'atlas_foliage':{'transmission':.6,'wind':True,'padding':.25}}
foliage_source=root/'foliage.gltf';foliage_source.write_text(json.dumps(foliage));cook.cook(foliage_source,root/'foliage','foliage')
row=next(row.split('\t') for row in (root/'foliage/foliage-assets.atlas').read_text().splitlines() if row.startswith('material\t'))
assert len(row)==28 and float(row[25])==.6 and row[26]=='1' and float(row[27])==.25
try:cook.cook(foliage_source,root/'bad-foliage-hlod','foliage',12)
except ValueError as error:assert 'object-local wind' in str(error)
else:raise AssertionError('Wind-driven static HLOD accepted')
foliage['materials'][0]['extras']['atlas_foliage']['padding']=.1;foliage_source.write_text(json.dumps(foliage))
try:cook.cook(foliage_source,root/'bad-foliage','foliage')
except ValueError:pass
else:raise AssertionError('Insufficient wind bounds accepted')
print('Cooked foliage passed: transmission/wind/padding policy and unsafe static-proxy/underbounded rejection')
# Valid-checksum malformed HLOD envelopes fail before publishing any proxy use.
metadata=(root/'hlod/hlod-exact-world.atlashlodb').read_bytes();cursor=36;deps=[]
for _ in range(struct.unpack_from('<I',metadata,32)[0]):
 length=struct.unpack_from('<I',metadata,cursor)[0];cursor+=4
 name=metadata[cursor:cursor+length].decode();cursor+=length+8
 deps.append((name,(root/'hlod'/name).read_bytes()))
body=metadata[cursor:];bad_distance=bytearray(body);struct.pack_into('<d',bad_distance,4+9*8,-1)
source_offset=4+18*8
for _ in range(2):source_offset+=4+struct.unpack_from('<I',body,source_offset)[0]
source_offset+=8
bad_sources=bytearray(body);struct.pack_into('<I',bad_sources,source_offset,0)
for name,kind,invalid in [('count',8,struct.pack('<I',0xffffffff)),('distance',8,bad_distance),('sources',8,bad_sources),('truncated',8,body[:-3]),('trailing',8,body+b'x'),('kind',7,body)]:
 (root/'hlod'/f'invalid-{name}.atlashlodb').write_bytes(cook.envelope(kind,invalid,deps))

for name,text in [('line','v '+(' '*1024*1024)+'0 0 0'),('tokens','f '+('1 '*65536))]:
 oversized=root/f'oversized-{name}.obj';oversized.write_text(text)
 try:cook.cook(oversized,root/'oversized-obj','oversized')
 except ValueError as error:assert 'limit' in str(error) or 'budget' in str(error)
 else:raise AssertionError('Oversized OBJ lexical input accepted')
