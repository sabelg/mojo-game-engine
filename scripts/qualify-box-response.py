"""Bounded isolated box response CPU/GPU reference, package and diagnostic qualification."""
import argparse,importlib.util,json,os,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('g01',ROOT/'scripts/qualify-physics-gpu.py')
G=importlib.util.module_from_spec(spec);spec.loader.exec_module(G)
OUT=ROOT/'build/physics-box-response'
GROUPS=['basic','conditioning','convergence']+[f'rest-{n}-{hz}' for n in [1,2,3] for hz in [30,60,120,240]]+['rest-3-30-96']+[f'{kind}-{hz}' for kind in ['slide','free'] for hz in [30,60,120,240]]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['test','packaged','demo']);p.add_argument('--group',default='all');p.add_argument('--slot-confirmed',action='store_true');a=p.parse_args()
    if not a.slot_confirmed:p.error('Exclusive slot required; H3 remains paused')
    if a.mode!='demo' and a.group!='all' and a.group not in GROUPS:p.error('Unknown test group')
    for pattern,version in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
        records=list((G.GPU_ENV/'conda-meta').glob(pattern))
        if len(records)!=1 or json.loads(records[0].read_text())['version']!=version:raise SystemExit('Pinned matching environment required')
    OUT.mkdir(exist_ok=True);G.OUT=OUT
    env=os.environ.copy();e=G.GPU_ENV;env.update(PATH=str(e/'bin')+':'+env['PATH'],CONDA_PREFIX=str(e),MODULAR_HOME=str(e/'share/max'),LD_LIBRARY_PATH=str(e/'lib')+':'+str(ROOT/'.deps/sdl3/lib'))
    target=ROOT/'experimental/physics_gpu'/('box_response_diagnostic.mojo' if a.mode=='demo' else 'test_box_response.mojo');source=target.read_text();includes=[ROOT];stages=[]
    if a.mode=='packaged':
        package_src=OUT/'package-src/gpu_box_response_api';package_src.mkdir(parents=True,exist_ok=True);package=OUT/'package';package.mkdir(exist_ok=True)
        for f in sorted((ROOT/'experimental/physics_gpu').glob('*.mojo')):
            if f.name.startswith('test') or f.name.endswith('_diagnostic.mojo') or f.name=='capability.mojo':continue
            (package_src/f.name).write_text(f.read_text().replace('from experimental.physics_gpu.', 'from gpu_box_response_api.'))
        stages.append(G.stage(a.mode+'-precompile',[str(e/'bin/mojo'),'precompile',str(package_src),'-I',str(ROOT),'-o',str(package/'gpu_box_response_api.mojoc')],180,env))
        source=source.replace('from experimental.physics_gpu.', 'from gpu_box_response_api.');includes=[package,ROOT]
    generated=OUT/(a.mode+'.mojo');generated.write_text(source)
    command=[str(e/'bin/mojo'),'build','--num-threads','1',str(generated)]
    for inc in includes:command+=['-I',str(inc)]
    command+=['-o',str(OUT/a.mode)]
    sources=sorted((ROOT/'experimental/physics_gpu').glob('*.mojo'))+[ROOT/'mojo_game'/n for n in ['math3d.mojo','transform3d.mojo','rigidbody3d.mojo']]+[Path(__file__),generated,ROOT/'pixi.lock',ROOT/'.deps/physics-gpu-g01/pixi.lock']
    hashes={str(f.relative_to(ROOT)):G.digest(f) for f in sources}
    if a.mode=='packaged':hashes['compiled_GPU_API']=G.digest(package/'gpu_box_response_api.mojoc')
    stages.append(G.stage(a.mode+'-compile',command,180,env))
    groups=['demo'] if a.mode=='demo' else GROUPS if a.group=='all' else [a.group];results=[]
    for group in groups:
        assert all(G.digest(ROOT/n)==h for n,h in hashes.items() if n!='compiled_GPU_API'),'Sources changed during qualification'
        args=[str(OUT/a.mode)]+([] if group=='demo' else [group]);name=a.mode+'-'+group+'-run'
        stages.append(G.stage(name,args,30,env));log=(OUT/(name+'.log')).read_text();lines=[s for s in log.splitlines() if s.startswith(('BOX_REST_','BOX_MOTION_','BOX_CONVERGENCE_RESULT','BOX_CONDITION_RESULT','BOX_RESPONSE_DEMO'))]
        results.append({'group':group,'result_lines':lines,'log':str(OUT/(name+'.log'))});print('Completed',a.mode,group,flush=True)
    original_failure=any('BOX_REST_BLOCKER 3 30 0 114 ' in line for result in results for line in result['result_lines'])
    receipt={'status':'passed','mode':a.mode,'suite_groups':groups,'sources':hashes,'executable_sha256':G.digest(OUT/a.mode),'stages':stages,'results':results,
             'scope':'bounded box-only multi-point response; no general stack guarantee or sphere/history/island/sleep adoption',
             'representation':'max-area <=4 footprint points; PSD minimum-norm unilateral normal block; all unreduced vertices validated',
             'physics':'private COM projection, rebuilt geometry, cold serial normal/Coulomb solve, energy/depth/profile checks and authoritative body commit',
             'oracle':'independent corner/constructive geometry, scalar elimination/null-space normal operators, spectral Coulomb reference; independent80-digit3x3 convergence diagnosis',
             'conditioning_reference':'equivalent SAT face conventions independently verified before conditional normal/point/state reconstruction; no device normal, point or solved-state reuse',
             'iteration_policies':{'baseline':64,'explicit_extended':96,'default_requested_sweeps':32,'position_max':64,'original_failure_reproduced':original_failure,'extra_maximum_patch_passes_percent':50},
             'gates':'predeclared design document unchanged; original residual/energy/cone/depth/analytic/body-byte gates retained',
             'limits':{'bodies':256,'shapes':64,'dynamic_patches':16,'selected_points':64,'points_per_patch':4,'warm_start':False,'persistent_manifold':False,'sleep_adoption':False,'performance_claim':False},'H3_resumed':False,'settings_changed':False}
    suffix='qualification.json' if a.group=='all' or a.mode=='demo' else a.group+'-qualification.json'
    (OUT/(a.mode+'-'+suffix)).write_text(json.dumps(receipt,indent=2)+'\n');print('Bounded GPU box response qualification complete:',a.mode,'; original64 counterexample remains explicit',flush=True)
if __name__=='__main__':main()
