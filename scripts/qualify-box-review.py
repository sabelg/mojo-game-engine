"""Opt-in Yo Frankie bounded box response hardware-render/source/package review."""
import argparse,importlib.util,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('g01',ROOT/'scripts/qualify-physics-gpu.py');G=importlib.util.module_from_spec(spec);spec.loader.exec_module(G)
OUT=ROOT/'build/physics-box-review'
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['source','packaged']);p.add_argument('--slot-confirmed',action='store_true');a=p.parse_args()
    if not a.slot_confirmed:p.error('Exclusive slot required; H3 remains paused')
    e=G.GPU_ENV
    for pattern,version in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
        records=list((e/'conda-meta').glob(pattern))
        if len(records)!=1 or json.loads(records[0].read_text())['version']!=version:raise SystemExit('Pinned matching environment required')
    OUT.mkdir(exist_ok=True);G.OUT=OUT;game=ROOT/'games/yo-frankie';env=os.environ.copy()
    env.update(PATH=str(e/'bin')+':'+env['PATH'],CONDA_PREFIX=str(e),MODULAR_HOME=str(e/'share/max'),LD_LIBRARY_PATH=str(e/'lib')+':'+str(ROOT/'.deps/sdl3/lib'),VK_DRIVER_FILES='/usr/share/vulkan/icd.d/nvidia_icd.json',MOJO_VK_SOFTWARE='0',MOJO_VK_REQUIRE_HARDWARE='1',MOJO_VK_VALIDATION='1',VK_LAYER_VALIDATE_SYNC='1',SDL_AUDIO_DRIVER='dummy')
    subprocess.run(['python3',str(ROOT/'scripts/engine-build-state.py'),'check'],check=True,timeout=10)
    original=game/'examples/gpu_box_response_review.mojo';source=original.read_text();includes=[ROOT,game];stages=[]
    if a.mode=='packaged':
        package_src=OUT/'package-src/gpu_box_review_api';package_src.mkdir(parents=True,exist_ok=True);package=OUT/'package';package.mkdir(exist_ok=True)
        for f in sorted((ROOT/'experimental/physics_gpu').glob('*.mojo')):
            if f.name.startswith('test') or f.name.endswith('_diagnostic.mojo') or f.name=='capability.mojo':continue
            (package_src/f.name).write_text(f.read_text().replace('from experimental.physics_gpu.','from gpu_box_review_api.'))
        stages.append(G.stage(a.mode+'-precompile',[str(e/'bin/mojo'),'precompile',str(package_src),'-I',str(ROOT),'-o',str(package/'gpu_box_review_api.mojoc')],180,env))
        source=source.replace('from experimental.physics_gpu.','from gpu_box_review_api.');includes=[package,ROOT,game]
    generated=OUT/(a.mode+'.mojo');generated.write_text(source);command=[str(e/'bin/mojo'),'build','--num-threads','1',str(generated)]
    for inc in includes:command+=['-I',str(inc)]
    command+=['-Xlinker',str(ROOT/'build/libmojo_graphics.a'),'-Xlinker','-L','-Xlinker',str(ROOT/'.deps/sdl3/lib'),'-Xlinker','-rpath','-Xlinker',str(ROOT/'.deps/sdl3/lib'),'-Xlinker','-lSDL3','-Xlinker','-lvulkan','-Xlinker','-lm','-o',str(OUT/a.mode)]
    sources=sorted((ROOT/'experimental/physics_gpu').glob('*.mojo'))+sorted((ROOT/'mojo_game').glob('*.mojo'))+sorted((game/'frankie').glob('*.mojo'))+[original,generated,Path(__file__),ROOT/'scripts/qualify-physics-gpu.py',ROOT/'build/libmojo_graphics.a',ROOT/'build/mojo_game.mojoc',ROOT/'.deps/sdl3/lib/libSDL3.so',ROOT/'pixi.lock',ROOT/'.deps/physics-gpu-g01/pixi.lock']
    hashes={str(f.relative_to(ROOT)):G.digest(f) for f in sources}
    if a.mode=='packaged':hashes['compiled_GPU_API']=G.digest(package/'gpu_box_review_api.mojoc')
    stages.append(G.stage(a.mode+'-compile',command,180,env))
    frames=OUT/'frames'/a.mode;frames.mkdir(parents=True,exist_ok=True);results=[]
    for scene in [1,2,3,4]:
        assert all(G.digest(ROOT/n)==h for n,h in hashes.items() if n!='compiled_GPU_API'),'Sources changed'
        stages.append(G.stage(a.mode+'-scene-'+str(scene),['bash',str(game/'scripts/run-vulkan.sh'),str(OUT/a.mode),str(frames),str(scene)],30,env,game))
        result=json.loads((frames/f'scene-{scene}.json').read_text());assert result['validation_errors']==0;results.append(result)
    (OUT/(a.mode+'-qualification.json')).write_text(json.dumps({'status':'passed','mode':a.mode,'sources':hashes,'executable_sha256':G.digest(OUT/a.mode),'stages':stages,'scenes':results,'H3_resumed':False,'settings_changed':False,'real_time_performance_claim':False,'simulation_duration_s_each_passed_fixture':2,'physics_hz':30,'CPU_fallback':False,'campaign_adoption':False},indent=2)+'\n');print('Box renderer review passed',a.mode,flush=True)
if __name__=='__main__':main()
