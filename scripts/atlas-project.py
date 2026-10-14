"""Atlas project create/import/check/export, using durable settings and generations."""
import argparse,fcntl,subprocess,platform,hashlib,importlib.util,json,math,os,re,shutil,struct,tempfile,uuid
from pathlib import Path

MAX_FILE=64*1024*1024
MAX_PROJECT=512*1024*1024
SETTING='atlas.project'
def read(path,limit=MAX_FILE):
 with path.open('rb') as f:data=f.read(limit+1)
 if len(data)>limit:raise ValueError('Project file exceeds byte budget: '+str(path))
 return data
def relative(value):
 if not value or '\\' in value or ':' in value or any(c in value for c in '\0\t\r\n') or value.startswith('/') or any(part in ('','.','..') for part in value.split('/')):raise ValueError('Invalid project-relative path')
 return value
def atomic(path,data):
 path.parent.mkdir(parents=True,exist_ok=True);temporary=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
 try:
  with temporary.open('xb') as f:f.write(data);f.flush();os.fsync(f.fileno())
  temporary.replace(path)
  fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
  try:os.fsync(fd)
  finally:os.close(fd)
 finally:temporary.unlink(missing_ok=True)
def settings(root):
 rows=read(root/SETTING,256*1024).decode().splitlines()
 if not rows or rows[0]!='ATLAS_PROJECT_1':raise ValueError('Unsupported project version')
 result={'manifests':[]};seen=set()
 for row in rows[1:]:
  fields=row.split('\t')
  if len(fields)!=2:raise ValueError('Invalid project setting')
  key,value=fields
  if key=='manifest':result['manifests'].append(relative(value));continue
  if key in seen or key not in ('name','cell_size','seed'):raise ValueError('Unknown/duplicate project setting')
  seen.add(key);result[key]=value
 if seen!={'name','cell_size','seed'} or not result['name'] or len(result['name'].encode())>128:raise ValueError('Incomplete project settings')
 size=float(result['cell_size']);seed=int(result['seed'])
 if not math.isfinite(size) or not 1<=size<=4096 or not -(1<<31)<=seed<(1<<31) or len(result['manifests'])>256 or len(set(result['manifests']))!=len(result['manifests']):raise ValueError('Invalid project limits')
 return result
def save_settings(root,values):
 data='ATLAS_PROJECT_1\n'+''.join(key+'\t'+str(values[key])+'\n' for key in ['name','cell_size','seed'])+''.join('manifest\t'+value+'\n' for value in values['manifests'])
 atomic(root/SETTING,data.encode())
def create(root,name):
 if root.exists() and (root/SETTING).exists():raise ValueError('Project already exists')
 if not name or len(name.encode())>128 or any(c in name for c in '\t\r\n\0'):raise ValueError('Invalid project name')
 root.mkdir(parents=True,exist_ok=True);save_settings(root,dict(name=name,cell_size=256,seed=42,manifests=[]))
def path_in(root,value):
 value=relative(value);path=root/value
 if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):raise ValueError('Project dependency escapes its directory')
 return path
def scene_check(data,meshes,materials,terrain=False):
 rows=data.decode().splitlines()
 if not rows or rows[0] not in ('MOJO_SCENE_1','MOJO_SCENE_2','MOJO_SCENE_3'):raise ValueError('Unsupported scene')
 version=int(rows[0][-1]);parents=[];active=[];identities=set();records=[]
 for row in rows[1:]:
  if not row:continue
  fields=row.split('\t')
  if len(fields)!={1:22,2:24,3:25}[version] or len(parents)>=100000 or int(fields[0])!=len(parents):raise ValueError('Invalid scene record')
  values=list(map(float,fields[5:21]))
  if any(not math.isfinite(v) for v in values) or abs(math.prod(values[7:10]))<1e-12:raise ValueError('Invalid scene transform')
  live=int(fields[4])
  if live not in (0,1):raise ValueError('Invalid scene active flag')
  if live and version>=2 and ((fields[22] and fields[22] not in meshes) or (fields[23] and fields[23] not in materials)):raise ValueError('Scene references missing asset')
  if live and version==3:
   if not fields[24] or fields[24] in identities:raise ValueError('Duplicate/missing scene identity')
   identities.add(fields[24])
  parents.append(int(fields[2]));active.append(bool(live));records.append(fields)
 states=[0]*len(parents)
 for i in range(len(parents)):
  if not active[i]:continue
  current=i;chain=[]
  while current!=-1 and states[current]!=2:
   if not 0<=current<len(parents) or not active[current] or states[current]==1:raise ValueError('Invalid scene hierarchy')
   states[current]=1;chain.append(current);current=parents[current]
   if current < -1 or current>=len(parents):raise ValueError('Invalid scene parent')
  for current in chain:states[current]=2
 if terrain:
  if not records or len(records)>65537 or records[0][1]!='ATLAS_TERRAIN_1' or not .25<=float(records[0][5])<=64:raise ValueError('Invalid terrain header')
  points=set()
  for i,fields in enumerate(records):
   if fields[2]!='-1' or fields[3]!='-1' or fields[4]!='1' or fields[21]!='-1' or fields[22] or fields[23] or list(map(float,fields[8:15]))!=[0,0,0,1,1,1,1]:raise ValueError('Invalid terrain record')
   if i==0:continue
   x,y,z=map(float,fields[5:8]);key=f'{int(x)}:{int(z)}'
   if abs(x)>1<<40 or abs(z)>1<<40 or abs(y)>1024 or int(x)!=x or int(z)!=z or key in points or fields[1]!=key or fields[24]!='terrain:'+key or any(not 0<=float(v)<=1 for v in fields[15:18]):raise ValueError('Invalid terrain sample')
   points.add(key)
def inventory(root,values=None):
 if (root/'.atlas-transaction/commit').exists():raise ValueError('Recover the committed world journal before exporting')
 values=settings(root) if values is None else values;files={SETTING:read(root/SETTING)};meshes=set();materials=set()
 def add(path):
  key=str(path.relative_to(root));relative(key)
  if key not in files:
   files[key]=read(path)
   if len(files)>4096 or sum(map(len,files.values()))>MAX_PROJECT:raise ValueError('Project export exceeds budget')
 for name in values['manifests']:
  manifest=path_in(root,name);add(manifest);rows=files[name].decode().splitlines()
  if not rows or rows[0]!='ATLAS_ASSETS_1':raise ValueError('Project manifests must use the text migration format')
  for row in rows[1:]:
   fields=row.split('\t')
   if fields[0] not in ('mesh','material','collision') or len(fields)<3:raise ValueError('Invalid asset manifest')
   table=meshes if fields[0]=='mesh' else materials if fields[0]=='material' else None
   if table is not None:
    if fields[1] in table:raise ValueError('Duplicate project asset identity')
    table.add(fields[1])
   columns=[2]+([9,10] if fields[0]=='material' and len(fields)>=11 else [])
   for column in columns:
    if fields[column]=='-':continue
    asset=path_in(manifest.parent,fields[column]);add(asset)
    # A generation is the complete immutable rig/material/scene dependency set.
    if 'generations' in asset.relative_to(root).parts:
     for companion in sorted(asset.parent.iterdir()):
      if companion.is_file():add(companion)
  binary=manifest.with_suffix('.atlasb')
  if binary.exists():add(binary)
 for path in sorted(root.glob('cell_*_*.scene')):
  add(path);scene_check(files[str(path.relative_to(root))],meshes|{'atlas/cube','atlas/sphere'},materials,path.name=='cell_-9223372036854775808_-9223372036854775808.scene')
 for name,data in files.items():
  if name.endswith(('.atlasmeshb','.atlasb','.sceneb','.atlasskinb','.atlasskeletonb','.atlasclipb','.atlascollisionb','.atlashlodb')):
   if len(data)<36 or data[:8]!=b'ATLASB2\0' or struct.unpack_from('<I',data,8)[0]!=2 or struct.unpack_from('<Q',data,16)[0]!=len(data)-32:raise ValueError('Invalid binary envelope: '+name)
   checksum=14695981039346656037
   for value in data[32:]:checksum=((checksum^value)*1099511628211)&0xffffffffffffffff
   if checksum!=struct.unpack_from('<Q',data,24)[0]:raise ValueError('Invalid binary checksum: '+name)
   cursor=32;count=struct.unpack_from('<I',data,cursor)[0];cursor+=4
   if count>4096:raise ValueError('Invalid dependency count')
   seen=set()
   for _ in range(count):
    length=struct.unpack_from('<I',data,cursor)[0];cursor+=4
    if length>1024*1024 or cursor+length+8>len(data):raise ValueError('Invalid binary dependency')
    dependency=data[cursor:cursor+length].decode();cursor+=length
    expected=struct.unpack_from('<Q',data,cursor)[0];cursor+=8
    target=str((Path(name).parent/relative(dependency)))
    if dependency in seen or target not in files:raise ValueError('Missing/duplicate binary dependency')
    seen.add(dependency);actual=14695981039346656037
    for value in files[target]:actual=((actual^value)*1099511628211)&0xffffffffffffffff
    if actual!=expected:raise ValueError('Stale binary dependency')
 if (root/'.atlas-transaction/commit').exists():raise ValueError('World changed during project inspection')
 return files

def imported(root,source,asset_id,usd_root=None):
 values=settings(root)
 if not re.fullmatch(r'[A-Za-z0-9_.-]+',asset_id):raise ValueError('Invalid asset ID')
 spec=importlib.util.spec_from_file_location('atlas_cook',Path(__file__).with_name('cook-assets.py'));cook=importlib.util.module_from_spec(spec);spec.loader.exec_module(cook)
 output=root/'assets'/asset_id;cook.cook(source.resolve(),output,asset_id,usd_root=usd_root)
 manifest=f'assets/{asset_id}/{asset_id}-assets.atlas'
 if manifest not in values['manifests']:values['manifests'].append(manifest)
 inventory(root,values);save_settings(root,values)
def runtime_files(sdk):
 sdk=sdk.resolve();binary=sdk/'build/atlas-world'
 data=read(binary)
 if data[:4]!=b'\x7fELF' or len(data)<20 or struct.unpack_from('<H',data,18)[0]!={'aarch64':183,'x86_64':62}.get(platform.machine()):raise ValueError('Runtime architecture does not match this host')
 result={'bin/atlas-world':data}
 linked=subprocess.run(['ldd',str(binary)],capture_output=True,text=True,check=True,timeout=15)
 if 'not found' in linked.stdout:raise ValueError('Runtime dependency is missing')
 for line in linked.stdout.splitlines():
  fields=line.split()
  if len(fields)>=3 and fields[1]=='=>':
   library=Path(fields[2])
   if fields[0].startswith(('libKGEN','libMSupport','libAsync')) and not library.resolve().is_relative_to((sdk/'.pixi').resolve()):raise ValueError('Runtime was built against another SDK environment; rebuild in the selected SDK before export')
   if library.is_absolute() and (library.resolve().is_relative_to((sdk/'.pixi').resolve()) or fields[0].startswith('libSDL3.so')):result['bin/lib/'+fields[0]]=read(library)
 result['run.sh']=b'#!/usr/bin/env bash\nset -euo pipefail\nroot=$(cd "$(dirname "$0")" && pwd)\nexport LD_LIBRARY_PATH="$root/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec "$root/bin/atlas-world" --project "$root" --play-only "$@"\n'
 result['RUNTIME.txt']=('Atlas world player for '+platform.machine()+'.\nNeeds Linux, the system Vulkan loader and a Vulkan-capable graphics driver. SDL3 3.4.18 is bundled.\nBundled runtime libraries include pinned project-local SDL3 and the locked Mojo runtime.\n').encode()
 return result

def _export(root,destination,sdk=None,play_copy=False):
 if destination.exists():raise ValueError('Export destination already exists')
 files=inventory(root)
 if sdk is not None:files.update(runtime_files(sdk))
 if play_copy:files['.atlas-play-owner']=(json.dumps({'kind':'atlas-play-copy','origin':str(root.resolve())})+'\n').encode()
 if len(files)>4096 or sum(map(len,files.values()))>MAX_PROJECT:raise ValueError('Project export exceeds budget')
 destination.parent.mkdir(parents=True,exist_ok=True)
 temporary=Path(tempfile.mkdtemp(prefix='.atlas-export-',dir=destination.parent))
 try:
  for name,data in files.items():atomic(temporary/relative(name),data)
  state={name:hashlib.sha256(data).hexdigest() for name,data in sorted(files.items())}
  atomic(temporary/'atlas-export.json',(json.dumps({'version':1,'files':state},indent=2)+'\n').encode())
  inventory(temporary)
  if sdk is not None:
   (temporary/'run.sh').chmod(0o755);(temporary/'bin/atlas-world').chmod(0o755)
  temporary.rename(destination)
  fd=os.open(destination.parent,os.O_RDONLY|os.O_DIRECTORY)
  try:os.fsync(fd)
  finally:os.close(fd)
 finally:
  if temporary.exists():shutil.rmtree(temporary)
 return len(files)
def export(root,destination,sdk=None,play_copy=False,editor_snapshot=False):
 with (root/'.atlas-world.lock').open('a+b') as lock:
  if not editor_snapshot:
   try:fcntl.flock(lock,fcntl.LOCK_SH|fcntl.LOCK_NB)
   except BlockingIOError:raise ValueError('World is open for editing; export from its editor')
  return _export(root,destination,sdk,play_copy)

def cleanup_play(root,destination):
 root=root.resolve();destination=destination.resolve()
 if destination.parent!=root/'play' or not re.fullmatch(r'world-[0-9]+',destination.name):raise ValueError('Invalid play copy path')
 if not destination.exists():return
 marker=json.loads(read(destination/'.atlas-play-owner',4096))
 if marker!={'kind':'atlas-play-copy','origin':str(root)}:raise ValueError('Play copy is not owned by this project')
 with (destination/'.atlas-world.lock').open('a+b') as lock:
  try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:raise ValueError('Play world is still open')
  shutil.rmtree(destination)

def usd_author(root, source, commands, destination, package=False):
 settings(root)
 if not source or not destination:raise ValueError('USD authoring needs --source and --destination')
 operations=json.loads(read(commands,1024*1024)) if commands else []
 if not isinstance(operations,list) or len(operations)>1000:raise ValueError('Expected at most 1000 USD operations')
 allowed={'undo','redo','assign_ids','repair_ids','timeline','clear_sample','variant','transform','attribute','visibility','active','load','unload','reload','reset'}
 for operation in operations:
  if not isinstance(operation,dict) or operation.get('op') not in allowed:raise ValueError('Unsupported USD authoring operation')
 spec=importlib.util.spec_from_file_location('atlas_usd_session',Path(__file__).with_name('usd-session.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 with module.StageSession() as stage:
  stage.request('open',source=str(source.resolve()))
  for operation in operations:stage.request(**operation)
  return stage.request('package' if package else 'save',destination=str(destination.resolve()))

def usd_export(root,source,destination,editor_snapshot=False):
 if source is None or destination is None:raise ValueError('USD export needs --source scene and --destination directory')
 values=settings(root)
 source=source if source.is_absolute() else root/source
 if not source.resolve().is_relative_to(root.resolve()):raise ValueError('USD scene must belong to this project')
 with (root/'.atlas-world.lock').open('a+b') as lock:
  if not editor_snapshot:
   try:fcntl.flock(lock,fcntl.LOCK_SH|fcntl.LOCK_NB)
   except BlockingIOError:raise ValueError('World is open for editing; export from its editor')
  if (root/'.atlas-transaction/commit').exists():raise ValueError('Recover the committed world journal before exporting')
  spec=importlib.util.spec_from_file_location('atlas_usd_export',Path(__file__).with_name('export-usd.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  return module.export_scene(source,[path_in(root,name) for name in values['manifests']],destination)

def main():
 parser=argparse.ArgumentParser();parser.add_argument('command',choices=['create','import','check','export','cleanup-play','usd-author','usd-package','usd-export']);parser.add_argument('--project',type=Path,required=True);parser.add_argument('--name',default='Atlas world');parser.add_argument('--source',type=Path);parser.add_argument('--id');parser.add_argument('--destination',type=Path);parser.add_argument('--report',type=Path);parser.add_argument('--sdk',type=Path);parser.add_argument('--usd-root',type=Path);parser.add_argument('--commands',type=Path);parser.add_argument('--play-copy',action='store_true');parser.add_argument('--editor-snapshot',action='store_true');args=parser.parse_args()
 try:
  root=args.project.resolve()
  if args.command=='create':create(root,args.name);message='Project created'
  elif args.command=='import':
   if not args.source or not args.id:raise ValueError('Import needs --source and --id')
   imported(root,args.source,args.id,args.usd_root);message='Import complete'
  elif args.command=='usd-export':
   result=usd_export(root,args.source,args.destination,args.editor_snapshot);message='USD scene exported: '+str(result['mesh_occurrences'])+' mesh occurrences'
  elif args.command in ('usd-author','usd-package'):
   result=usd_author(root,args.source,args.commands,args.destination,args.command=='usd-package');message='USD authoring exported: '+result['destination']
  elif args.command=='check':message=f'Project validated: {len(inventory(root))} files'
  elif args.command=='cleanup-play':
   if not args.destination:raise ValueError('Cleanup needs --destination')
   cleanup_play(root,args.destination);message='Play copy removed'
  else:
   if not args.destination:raise ValueError('Export needs --destination')
   message=f'Project exported: {export(root,args.destination.resolve(),args.sdk,args.play_copy,args.editor_snapshot)} files'
  if args.report:atomic(args.report,('OK\t'+message+'\n').encode())
  print(message)
 except (ValueError,OSError,KeyError,TypeError,IndexError,struct.error) as error:
  message=str(error).replace('\n',' ').replace('\t',' ')[:4096]
  if args.report:atomic(args.report,('ERROR\t'+message+'\n').encode())
  raise SystemExit('Project operation failed: '+message)
if __name__=='__main__':main()
