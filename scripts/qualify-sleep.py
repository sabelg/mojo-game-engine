"""G05b bounded actual GPU sleep/wake source/precompiled qualification; no installs."""
import argparse,importlib.util,json,os,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('g01',ROOT/'scripts/qualify-physics-gpu.py')
G=importlib.util.module_from_spec(spec);spec.loader.exec_module(G)
OUT=ROOT/'build/physics-g05-sleep'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode',choices=['test','packaged','demo'])
    p.add_argument('--slot-confirmed',action='store_true');a=p.parse_args()
    if not a.slot_confirmed:p.error('Exclusive slot required; H3 remains paused')
    for pattern,version in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
        records=list((G.GPU_ENV/'conda-meta').glob(pattern))
        if len(records)!=1 or json.loads(records[0].read_text())['version']!=version:raise SystemExit('Pinned matching environment required')
    OUT.mkdir(exist_ok=True);G.OUT=OUT
    env=os.environ.copy();e=G.GPU_ENV
    env.update(PATH=str(e/'bin')+':'+env['PATH'],CONDA_PREFIX=str(e),MODULAR_HOME=str(e/'share/max'),LD_LIBRARY_PATH=str(e/'lib')+':'+str(ROOT/'.deps/sdl3/lib'))
    target=ROOT/'experimental/physics_gpu/test_sleep.mojo';source=target.read_text();includes=[ROOT];stages=[]
    if a.mode=='demo':
        target=ROOT/'experimental/physics_gpu/sleep_diagnostic.mojo';source=target.read_text()
    if a.mode=='packaged':
        package_src=OUT/'package-src/gpu_sleep_api';package_src.mkdir(parents=True,exist_ok=True)
        package=OUT/'package';package.mkdir(exist_ok=True)
        for name in ['__init__.mojo', 'core.mojo', 'kernels.mojo', 'lifecycle.mojo', 'lifecycle_kernels.mojo', 'shape_kernels.mojo', 'collision.mojo', 'contact_oracle.mojo', 'box_oracle.mojo', 'history_kernels.mojo', 'contact_history.mojo', 'contact_reference.mojo', 'response_kernels.mojo', 'normal_response.mojo', 'response_reference.mojo', 'boundary_reference.mojo', 'test_g04a.mojo', 'friction_kernels.mojo', 'friction_response.mojo', 'friction_reference.mojo', 'test_g04b.mojo', 'stability_kernels.mojo', 'stable_friction.mojo', 'stable_reference.mojo', 'recommended.mojo', 'island_kernels.mojo', 'sleep.mojo', 'sleep_kernels.mojo','sleep_reference.mojo']:
            (package_src/name).write_text((ROOT/'experimental/physics_gpu'/name).read_text().replace('from experimental.physics_gpu.', 'from gpu_sleep_api.').replace('def main() raises:', 'def qualification_main() raises:'))
        stages.append(G.stage(a.mode+'-precompile',[str(e/'bin/mojo'),'precompile',str(package_src),'-I',str(ROOT),'-o',str(package/'gpu_sleep_api.mojoc')],180,env))
        source=source.replace('from experimental.physics_gpu.', 'from gpu_sleep_api.');includes=[package,ROOT]
    generated=OUT/(a.mode+'.mojo');generated.write_text(source)
    command=[str(e/'bin/mojo'),'build','--num-threads','1',str(generated)]
    for inc in includes:command+=['-I',str(inc)]
    command+=['-o',str(OUT/a.mode)]
    sources=sorted((ROOT/'experimental/physics_gpu').glob('*.mojo'))+[ROOT/'mojo_game'/n for n in ['math3d.mojo','transform3d.mojo','rigidbody3d.mojo']]+[Path(__file__),generated,ROOT/'pixi.lock',ROOT/'.deps/physics-gpu-g01/pixi.lock']
    hashes={str(f.relative_to(ROOT)):G.digest(f) for f in sources}
    if a.mode=='packaged':hashes['compiled_GPU_API']=G.digest(package/'gpu_sleep_api.mojoc')
    stages.append(G.stage(a.mode+'-compile',command,180,env))
    stages.append(G.stage(a.mode+'-run',[str(OUT/a.mode)],30,env))
    receipt={'status':'passed','mode':a.mode,'sources':hashes,'executable_sha256':G.digest(OUT/a.mode),'stages':stages,
             'state_machine':'actual serial GPU island-aware sleep/wake with strict motion/support eligibility; opt-in whole-world idle gate',
             'canonical_label':'minimum live body slot and exact generation/namespace; contact output sorted by shape pair',
             'publication':'GPU sleep-state/clock/counter candidate validation and commit after successful qualified physics; lifecycle/integration/response are separate earlier commits; retained wake intent on failure',
             'limits':{'bodies':256,'shapes':64,'contacts':64,'sleep':True,'idle_gate_default':False,'per_island_skip':False,'warm_start':False,'solver_scheduling':False,'performance_claim':False},
             'H3_resumed':False,'settings_changed':False}
    (OUT/(a.mode+'-qualification.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    print('G05b sleep passed:',a.mode,flush=True)
if __name__=='__main__':main()
