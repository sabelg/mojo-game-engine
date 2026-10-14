"""Separate finite actual GPU translation-boundary source/precompiled qualification."""
import argparse,importlib.util,json,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'build/physics-translation-boundary'
s=importlib.util.spec_from_file_location('g',ROOT/'scripts/qualify-physics-gpu.py');G=importlib.util.module_from_spec(s);s.loader.exec_module(G)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['source','packaged']);p.add_argument('--first',type=int,default=0);p.add_argument('--count',type=int,default=75);p.add_argument('--reuse-build',action='store_true');p.add_argument('--slot-confirmed',action='store_true');a=p.parse_args()
 if not a.slot_confirmed:p.error('Exclusive native GPU slot required; H3 stays paused')
 G.OUT=OUT;e=G.GPU_ENV;frozen=json.loads((OUT/'predeclared.json').read_text());assert G.digest(ROOT/frozen['design'])==frozen['design_sha256'];assert G.digest(OUT/'cases.json')==frozen['cases_sha256']
 for pattern,version in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
  records=list((e/'conda-meta').glob(pattern));assert len(records)==1 and json.loads(records[0].read_text())['version']==version
 env=os.environ.copy();env.update(PATH=str(e/'bin')+':'+env['PATH'],CONDA_PREFIX=str(e),MODULAR_HOME=str(e/'share/max'),LD_LIBRARY_PATH=str(e/'lib')+':'+str(ROOT/'.deps/sdl3/lib'))
 source=(ROOT/'experimental/physics_gpu/test_translation_boundary.mojo').read_text();includes=[ROOT];stages=[]
 if a.mode=='packaged':
  package_src=OUT/'package-src/gpu_translation_boundary_api';package_src.mkdir(parents=True,exist_ok=True);package=OUT/'package';package.mkdir(exist_ok=True)
  if not a.reuse_build:
   for f in sorted((ROOT/'experimental/physics_gpu').glob('*.mojo')):
    if (f.name.startswith('test') and f.name not in ['test_box_response.mojo','test_box_interactions.mojo','test_coupled_helpers.mojo']) or f.name.endswith('_diagnostic.mojo') or f.name=='capability.mojo':continue
    (package_src/f.name).write_text(f.read_text().replace('from experimental.physics_gpu.','from gpu_translation_boundary_api.').replace('def main() raises:','def qualification_main() raises:'))
   stages.append(G.stage('packaged-precompile',[str(e/'bin/mojo'),'precompile',str(package_src),'-I',str(ROOT),'-o',str(package/'gpu_translation_boundary_api.mojoc')],180,env))
  source=source.replace('from experimental.physics_gpu.','from gpu_translation_boundary_api.');includes=[package,ROOT]
 generated=OUT/(a.mode+'.mojo');generated.write_text(source);exe=OUT/a.mode;files=sorted((ROOT/'experimental/physics_gpu').glob('*.mojo'))+[ROOT/'mojo_game'/n for n in ['math3d.mojo','transform3d.mojo','rigidbody3d.mojo']]+[Path(__file__),generated,ROOT/'pixi.lock',ROOT/'.deps/physics-gpu-g01/pixi.lock',ROOT/frozen['design'],OUT/'cases.json'];hashes={str(f.relative_to(ROOT)):G.digest(f) for f in files}
 if a.mode=='packaged':hashes['compiled_GPU_API']=G.digest(package/'gpu_translation_boundary_api.mojoc')
 buildfile=OUT/(a.mode+'-build.json')
 if a.reuse_build:
  build=json.loads(buildfile.read_text());assert build['sources']==hashes and G.digest(exe)==build['executable_sha256']
 else:
  cmd=[str(e/'bin/mojo'),'build','--num-threads','1',str(generated)]
  for inc in includes:cmd+=['-I',str(inc)]
  cmd+=['-o',str(exe)];stages.append(G.stage(a.mode+'-compile',cmd,180,env));build={'sources':hashes,'executable_sha256':G.digest(exe),'stages':stages};buildfile.write_text(json.dumps(build,indent=2)+'\n')
 cases=json.loads((OUT/'cases.json').read_text());runs=OUT/'runs'/a.mode;runs.mkdir(parents=True,exist_ok=True);results=[]
 for index,c in list(enumerate(cases))[a.first:a.first+a.count]:
  assert all(G.digest(ROOT/n)==h for n,h in hashes.items() if n!='compiled_GPU_API')
  label=f"case-{index:02}";prefix=runs/label
  try:
   assert not (OUT/(a.mode+'-'+label+'-telemetry.json')).exists(), 'Existing fixture outcome must be preserved; select an unexecuted case'
   stages.append(G.stage(a.mode+'-'+label,[str(exe),str(prefix),str(1 if c['kind']=='dynamic' else 0),str(c['half']),str(c['translation']),str(c['sign']),str(c['hz'])],30,env));r=json.loads(Path(str(prefix)+'-result.json').read_text())
  except SystemExit as err:print('Retained finite fixture failure',err,flush=True);r={'status':'bounded_fixture_failed'};stages.append(json.loads((OUT/(a.mode+'-'+label+'-telemetry.json')).read_text()))
  results.append({'index':index,'case':c,'prefix':str(prefix),'result':r});(OUT/(a.mode+f'-cases-{a.first}-{a.count}.json')).write_text(json.dumps({'build':build,'stages':stages,'results':results,'original70case_count_not_changed':True},indent=2)+'\n');print('Recorded translation boundary',a.mode,index,r['status'],flush=True)
if __name__=='__main__':main()
