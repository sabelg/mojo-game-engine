"""Finite predeclared GPU interacting-box trajectory matrix; failures retained."""
import argparse,importlib.util,json,os,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('g01',ROOT/'scripts/qualify-physics-gpu.py');G=importlib.util.module_from_spec(spec);spec.loader.exec_module(G)
OUT=ROOT/'build/physics-box-interactions'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['source','packaged']);p.add_argument('--slot-confirmed',action='store_true');p.add_argument('--first',type=int,default=0);p.add_argument('--count',type=int,default=70);p.add_argument('--reuse-build',action='store_true');a=p.parse_args()
 if not a.slot_confirmed:p.error('Exclusive slot required; H3 remains paused')
 e=G.GPU_ENV;G.OUT=OUT
 frozen=json.loads((OUT/'predeclared.json').read_text());assert G.digest(Path(frozen['design_path']))==frozen['design_sha256'];assert G.digest(OUT/'cases.json')==frozen['case_matrix_sha256']
 for pattern,version in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
  records=list((e/'conda-meta').glob(pattern));assert len(records)==1 and json.loads(records[0].read_text())['version']==version
 env=os.environ.copy();env.update(PATH=str(e/'bin')+':'+env['PATH'],CONDA_PREFIX=str(e),MODULAR_HOME=str(e/'share/max'),LD_LIBRARY_PATH=str(e/'lib')+':'+str(ROOT/'.deps/sdl3/lib'))
 target=ROOT/'experimental/physics_gpu/test_box_interactions.mojo';source=target.read_text();includes=[ROOT];stages=[]
 if a.mode=='packaged':
  package_src=OUT/'package-src/gpu_box_interactions_api';package_src.mkdir(parents=True,exist_ok=True);package=OUT/'package';package.mkdir(exist_ok=True)
  if not a.reuse_build:
   for f in sorted((ROOT/'experimental/physics_gpu').glob('*.mojo')):
    if (f.name.startswith('test') and f.name!='test_box_response.mojo') or f.name.endswith('_diagnostic.mojo') or f.name=='capability.mojo':continue
    (package_src/f.name).write_text(f.read_text().replace('from experimental.physics_gpu.','from gpu_box_interactions_api.').replace('def main() raises:','def qualification_main() raises:'))
   stages.append(G.stage(a.mode+'-precompile',[str(e/'bin/mojo'),'precompile',str(package_src),'-I',str(ROOT),'-o',str(package/'gpu_box_interactions_api.mojoc')],180,env))
  source=source.replace('from experimental.physics_gpu.','from gpu_box_interactions_api.');includes=[package,ROOT]
 generated=OUT/(a.mode+'.mojo');generated.write_text(source);command=[str(e/'bin/mojo'),'build','--num-threads','1',str(generated)]
 for inc in includes:command+=['-I',str(inc)]
 command+=['-o',str(OUT/a.mode)]
 sources=sorted((ROOT/'experimental/physics_gpu').glob('*.mojo'))+[ROOT/'mojo_game'/n for n in ['math3d.mojo','transform3d.mojo','rigidbody3d.mojo']]+[Path(__file__),generated,ROOT/'pixi.lock',ROOT/'.deps/physics-gpu-g01/pixi.lock',OUT/'cases.json',ROOT/'experimental/physics_gpu/BOX_INTERACTIONS_DESIGN.md']
 hashes={str(f.relative_to(ROOT)):G.digest(f) for f in sources}
 if a.mode=='packaged':hashes['compiled_GPU_API']=G.digest(package/'gpu_box_interactions_api.mojoc')
 build_file=OUT/(a.mode+'-build.json')
 if a.reuse_build:
  build=json.loads(build_file.read_text());assert build['sources']==hashes and build['executable_sha256']==G.digest(OUT/a.mode)
 else:
  stages.append(G.stage(a.mode+'-compile',command,180,env));build={'sources':hashes,'executable_sha256':G.digest(OUT/a.mode),'stages':stages};build_file.write_text(json.dumps(build,indent=2)+'\n')
 cases=json.loads((OUT/'cases.json').read_text());runs=OUT/'runs'/a.mode;runs.mkdir(parents=True,exist_ok=True);results=[]
 for index,c in list(enumerate(cases))[a.first:a.first+a.count]:
  assert all(G.digest(ROOT/n)==h for n,h in hashes.items() if n!='compiled_GPU_API'),'Sources changed'
  name=f"case-{index:02}-id{c['id']}-hz{c['hz']}-p{c['policy']}-seed{c['seed']}-v{c['variant']}";prefix=runs/name
  result=G.stage(a.mode+'-'+name,[str(OUT/a.mode),str(prefix),str(c['id']),str(c['hz']),str(c['policy']),str(c['seed']),str(c['variant'])],30,env);stages.append(result)
  record=json.loads(Path(str(prefix)+'-result.json').read_text());results.append({'case_index':index,'case':c,'prefix':str(prefix),'result':record});print('Completed',a.mode,index,record['status'],flush=True)
 receipt={'status':'executed_with_explicit_case_outcomes','mode':a.mode,'build':build,'stages':stages,'results':results,'predeclared':frozen,'H3_resumed':False,'settings_changed':False,'performance_claim':False}
 (OUT/(a.mode+f'-cases-{a.first}-{a.count}.json')).write_text(json.dumps(receipt,indent=2)+'\n')
 print('Interacting trajectory batch complete',a.mode,a.first,a.count,flush=True)
if __name__=='__main__':main()
