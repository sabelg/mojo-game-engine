"""Finite opt-in coupled-friction target/replay and interacting matrix qualification."""
import argparse,importlib.util,json,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'build/physics-box-friction'
spec=importlib.util.spec_from_file_location('g01',ROOT/'scripts/qualify-physics-gpu.py');G=importlib.util.module_from_spec(spec);spec.loader.exec_module(G)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['source','packaged']);p.add_argument('--suite',choices=['target','interactions'],default='target');p.add_argument('--first',type=int,default=0);p.add_argument('--count',type=int,default=70);p.add_argument('--prefix-steps',type=int,default=0);p.add_argument('--reuse-build',action='store_true');p.add_argument('--slot-confirmed',action='store_true');a=p.parse_args()
 if not a.slot_confirmed:p.error('Exclusive slot; H3 remains paused')
 G.OUT=OUT;e=G.GPU_ENV
 frozen=json.loads((OUT/'policy-predeclared.json').read_text());assert G.digest(Path(frozen['design_path']))==frozen['sha256']
 for pattern,version in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
  records=list((e/'conda-meta').glob(pattern));assert len(records)==1 and json.loads(records[0].read_text())['version']==version
 env=os.environ.copy();env.update(PATH=str(e/'bin')+':'+env['PATH'],CONDA_PREFIX=str(e),MODULAR_HOME=str(e/'share/max'),LD_LIBRARY_PATH=str(e/'lib')+':'+str(ROOT/'.deps/sdl3/lib'))
 target=ROOT/'experimental/physics_gpu'/('test_box_coupled.mojo' if a.suite=='target' else 'test_box_interactions.mojo');source=target.read_text();includes=[ROOT];stages=[]
 if a.suite=='interactions':
  source=source.replace('from experimental.physics_gpu.box_response import GpuBoxResponse,BoxResponseReport','from experimental.physics_gpu.coupled_box_response import GpuCoupledBoxResponse as GpuBoxResponse\nfrom experimental.physics_gpu.box_response import BoxResponseReport')
  source=source.replace('from experimental.physics_gpu.box_response_reference import CpuBoxResponse,CpuBoxResult,cpu_geometry','from experimental.physics_gpu.coupled_box_reference import CpuCoupledBoxResponse as CpuBoxResponse,CpuBoxResult,cpu_geometry')
  source=source.replace('from experimental.physics_gpu.test_box_response import add_box_response,near,vector,bits_equal,total_kinetic,potential','from experimental.physics_gpu.test_coupled_helpers import add_box_coupled as add_box_response\nfrom experimental.physics_gpu.test_box_response import near,vector,bits_equal,total_kinetic,potential')
  if a.prefix_steps:source=source.replace('var completed=0;',f'var full_steps=steps;steps=min(steps,{a.prefix_steps});var completed=0;')
  source=source.replace('var fixed_checks=0;', 'var total_work=List[Float64]();\n    for i in range(10):total_work.append(0)\n    var fixed_checks=0;')
  source=source.replace('gpu_error=gpu.last_error;cpu_error=cpu.last_error','gpu_error=gpu.last_error;cpu_error=cpu.last_error\n                var measured_work=gpu.work_report();var step_work=List[Float64]()\n                for i in range(10):\n                    step_work.append(Float64(measured_work[i]));total_work[i]=max(total_work[i],Float64(measured_work[i])) if i==8 else total_work[i]+Float64(measured_work[i])')
  source=source.replace("',\"state_error_gate_ratio\":'+String(ratio)","',\"coupled_work\":'+json_values(step_work)+',\"state_error_gate_ratio\":'+String(ratio)")
  source=source.replace("',\"stale_update_rollback\":'+", "',\"coupled_work_total\":'+json_values(total_work)+',\"stale_update_rollback\":'+")
  if a.prefix_steps:
   source=source.replace('    if completed==steps:', '    if completed==steps and steps==full_steps:')
   source=source.replace('    with open(prefix+"-result.json"', '    if completed==steps and steps<full_steps:status="prefix_completed"\n    with open(prefix+"-result.json"')
 if a.mode=='packaged':
  package_src=OUT/'package-src/gpu_coupled_box_api';package_src.mkdir(parents=True,exist_ok=True);package=OUT/'package';package.mkdir(exist_ok=True)
  if not a.reuse_build:
   for f in sorted((ROOT/'experimental/physics_gpu').glob('*.mojo')):
    if (f.name.startswith('test') and f.name not in ['test_box_response.mojo','test_box_interactions.mojo','test_coupled_helpers.mojo']) or f.name.endswith('_diagnostic.mojo') or f.name=='capability.mojo':continue
    (package_src/f.name).write_text(f.read_text().replace('from experimental.physics_gpu.','from gpu_coupled_box_api.').replace('def main() raises:','def qualification_main() raises:'))
   stages.append(G.stage(a.mode+'-'+a.suite+'-precompile',[str(e/'bin/mojo'),'precompile',str(package_src),'-I',str(ROOT),'-o',str(package/'gpu_coupled_box_api.mojoc')],180,env))
  source=source.replace('from experimental.physics_gpu.','from gpu_coupled_box_api.');includes=[package,ROOT]
 name=a.mode+'-'+a.suite+('-prefix'+str(a.prefix_steps) if a.prefix_steps else '');generated=OUT/(name+'.mojo');generated.write_text(source);exe=OUT/name
 files=sorted((ROOT/'experimental/physics_gpu').glob('*.mojo'))+[ROOT/'mojo_game'/n for n in ['math3d.mojo','transform3d.mojo','rigidbody3d.mojo']]+[Path(__file__),generated,ROOT/'pixi.lock',ROOT/'.deps/physics-gpu-g01/pixi.lock']
 hashes={str(f.relative_to(ROOT)):G.digest(f) for f in files}
 if a.mode=='packaged':hashes['compiled_GPU_API']=G.digest(package/'gpu_coupled_box_api.mojoc')
 buildfile=OUT/(name+'-build.json')
 if a.reuse_build:
  build=json.loads(buildfile.read_text());assert build['sources']==hashes and build['executable_sha256']==G.digest(exe)
 else:
  cmd=[str(e/'bin/mojo'),'build','--num-threads','1',str(generated)]
  for inc in includes:cmd+=['-I',str(inc)]
  cmd+=['-o',str(exe)];stages.append(G.stage(name+'-compile',cmd,180,env));build={'sources':hashes,'executable_sha256':G.digest(exe),'stages':stages};buildfile.write_text(json.dumps(build,indent=2)+'\n')
 results=[]
 if a.suite=='target':
  stages.append(G.stage(name+'-run',[str(exe),str(OUT/name)],30,env));results=[json.loads((OUT/f'{name}-basis-{i}.json').read_text()) for i in range(3)]
 else:
  cases=json.loads((ROOT/'experimental/physics_gpu/BOX_INTERACTIONS_CASES.json').read_text());runs=OUT/'runs'/name;runs.mkdir(parents=True,exist_ok=True)
  for index,c in list(enumerate(cases))[a.first:a.first+a.count]:
   assert all(G.digest(ROOT/n)==h for n,h in hashes.items() if n!='compiled_GPU_API')
   label=f"case-{index:02}-id{c['id']}-hz{c['hz']}-p{c['policy']}-seed{c['seed']}-v{c['variant']}";prefix=runs/label
   stages.append(G.stage(name+'-'+label,[str(exe),str(prefix),str(c['id']),str(c['hz']),str(c['policy']),str(c['seed']),str(c['variant'])],30,env));r=json.loads(Path(str(prefix)+'-result.json').read_text());results.append({'case_index':index,'prefix':str(prefix),'result':r});print('Completed',name,index,r['status'],flush=True)
 receipt={'status':'executed_with_explicit_case_outcomes','mode':a.mode,'suite':a.suite,'prefix_steps':a.prefix_steps,'build':build,'stages':stages,'results':results,'original_gates_and_owner_unchanged':True,'H3_resumed':False,'performance_claim':False}
 suffix='' if a.suite=='target' else f'-{a.first}-{a.count}';(OUT/(name+suffix+'-qualification.json')).write_text(json.dumps(receipt,indent=2)+'\n')
 print('Coupled qualification batch complete',name,flush=True)
if __name__=='__main__':main()
