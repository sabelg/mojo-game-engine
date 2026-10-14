"""Bounded axis-angle CPU/precompiled/actual GPU repair qualification; no installs."""
import argparse,importlib.util,json,os,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('g01',ROOT/'scripts/qualify-physics-gpu.py')
G=importlib.util.module_from_spec(spec);spec.loader.exec_module(G)
OUT=ROOT/'build/axis-normalization-recovery'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode',choices=['cpu','gpu','packaged-cpu','packaged-gpu'])
    p.add_argument('--slot-confirmed',action='store_true');a=p.parse_args()
    if not a.slot_confirmed:p.error('Exclusive slot required; H3 remains paused')
    for pattern,version in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
        records=list((G.GPU_ENV/'conda-meta').glob(pattern))
        if len(records)!=1 or json.loads(records[0].read_text())['version']!=version:raise SystemExit('Pinned matching environment required')
    OUT.mkdir(exist_ok=True);G.OUT=OUT
    env=os.environ.copy();e=G.GPU_ENV
    env.update(PATH=str(e/'bin')+':'+env['PATH'],CONDA_PREFIX=str(e),MODULAR_HOME=str(e/'share/max'),LD_LIBRARY_PATH=str(e/'lib')+':'+str(ROOT/'.deps/sdl3/lib'))
    target=ROOT/'tests/axis_normalization.mojo';source=target.read_text();includes=[ROOT];stages=[]
    if 'gpu' in a.mode:
        source=source.replace('def main() raises:', 'def cpu_main() raises:')+(ROOT/'tests/axis_normalization_gpu.mojo').read_text()
    if 'packaged' in a.mode:
        package_src=OUT/'package-src/axis_math_api';package_src.mkdir(parents=True,exist_ok=True)
        package=OUT/'package';package.mkdir(exist_ok=True)
        for name in ['math3d.mojo','transform3d.mojo']:
            shutil.copy2(ROOT/'mojo_game'/name,package_src/name)
        (package_src/'__init__.mojo').write_text('')
        stages.append(G.stage(a.mode+'-precompile',[str(e/'bin/mojo'),'precompile',str(package_src),'-o',str(package/'axis_math_api.mojoc')],180,env))
        source=source.replace('from mojo_game.', 'from axis_math_api.');includes=[package]
    generated=OUT/(a.mode+'.mojo');generated.write_text(source)
    command=[str(e/'bin/mojo'),'build','--num-threads','1',str(generated)]
    for inc in includes:command+=['-I',str(inc)]
    command+=['-o',str(OUT/a.mode)]
    hashes={str(f.relative_to(ROOT)):G.digest(f) for f in [ROOT/'mojo_game/math3d.mojo',ROOT/'mojo_game/transform3d.mojo',target,ROOT/'tests/axis_normalization_gpu.mojo',Path(__file__),generated,ROOT/'pixi.lock',ROOT/'.deps/physics-gpu-g01/pixi.lock']}
    if 'packaged' in a.mode:hashes['compiled_math_API']=G.digest(package/'axis_math_api.mojoc')
    stages.append(G.stage(a.mode+'-compile',command,180,env))
    stages.append(G.stage(a.mode+'-run',[str(OUT/a.mode)],30,env))
    receipt={'status':'passed','mode':a.mode,'sources':hashes,'executable_sha256':G.digest(OUT/a.mode),'stages':stages,
             'tolerance':'1e-11*(1+abs(expected))','oracle':'1200-digit Decimal exact Float64 directions; scalar Rodrigues; conjugate inverse',
             'GPU_scope':'production _axis_angle_from_sin_cos normalization/assembly and rotate; host trig coefficients; full Float64 axis_angle trig unsupported on locked NVIDIA backend',
             'H3_resumed':False,'settings_changed':False}
    (OUT/(a.mode+'-qualification.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    print('Axis normalization passed:',a.mode,flush=True)
if __name__=='__main__':main()
