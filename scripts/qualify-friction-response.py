"""Finite G04b bounded serial GPU normal response source/compiled-API/game qualification; no dependency changes."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('atlas_g01_qualification',ROOT/'scripts/qualify-physics-gpu.py')
G01=importlib.util.module_from_spec(spec)
spec.loader.exec_module(G01)
OUT=ROOT/'build/physics-g04b'
G01.OUT=OUT
ENV_ROOT=G01.GPU_ENV

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['test','packaged','demo'])
    parser.add_argument('--slot-confirmed',action='store_true')
    parser.add_argument('--build',action='store_true')
    args=parser.parse_args()
    if not args.slot_confirmed:parser.error('Exclusive CPU/GPU slot confirmation required; H3 must remain paused')
    for pattern,version in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
        records=list((ENV_ROOT/'conda-meta').glob(pattern))
        if len(records)!=1 or json.loads(records[0].read_text())['version']!=version:
            raise SystemExit('Matching existing isolated G01 environment required; no install performed')
    env=os.environ.copy()
    env['PATH']=str(ENV_ROOT/'bin')+':'+env['PATH']
    env['CONDA_PREFIX']=str(ENV_ROOT);env['MODULAR_HOME']=str(ENV_ROOT/'share/max')
    env['LD_LIBRARY_PATH']=str(ENV_ROOT/'lib')+':'+str(ROOT/'.deps/sdl3/lib')+(':'+env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
    OUT.mkdir(parents=True,exist_ok=True)
    sources=sorted((ROOT/'experimental/physics_gpu').glob('*.mojo'))
    sources += [ROOT/'mojo_game'/n for n in ['rigidbody3d.mojo','math3d.mojo','transform3d.mojo']]
    sources += [ROOT/'scripts/qualify-physics-gpu.py',Path(__file__)]
    target=ROOT/'experimental/physics_gpu/test_g04b.mojo'
    include=[ROOT]
    command=[str(ENV_ROOT/'bin/mojo'),'build','--num-threads','1']
    cwd=ROOT
    if args.mode=='packaged':
        package_src=OUT/'package-src/gpu_friction_api';package_src.mkdir(parents=True,exist_ok=True)
        package=OUT/'package';package.mkdir(exist_ok=True)
        for name in ['__init__.mojo','core.mojo','kernels.mojo','lifecycle.mojo','lifecycle_kernels.mojo','shape_kernels.mojo','collision.mojo','contact_oracle.mojo','box_oracle.mojo','history_kernels.mojo','contact_history.mojo','contact_reference.mojo','response_kernels.mojo','normal_response.mojo','response_reference.mojo','boundary_reference.mojo','test_g04a.mojo','friction_kernels.mojo','friction_response.mojo','friction_reference.mojo']:
            (package_src/name).write_text((ROOT/'experimental/physics_gpu'/name).read_text().replace('from experimental.physics_gpu.','from gpu_friction_api.').replace('def main() raises:', 'def qualification_main() raises:'))
        package_file=package/'gpu_friction_api.mojoc'
        # Precompile serializes non-elaborated code; this CLI exposes no thread
        # option. Architecture-specific native builds below always use one thread.
        G01.stage('g03-api-precompile',[str(ENV_ROOT/'bin/mojo'),'precompile',str(package_src),'-I',str(ROOT),'-o',str(package_file)],180,env)
        target=OUT/'packaged-test.mojo'
        target.write_text((ROOT/'experimental/physics_gpu/test_g04b.mojo').read_text().replace('from experimental.physics_gpu.','from gpu_friction_api.').replace('from experimental.physics_gpu.lifecycle','from gpu_friction_api.lifecycle').replace('from experimental.physics_gpu.kernels','from gpu_friction_api.kernels').replace('from experimental.physics_gpu.collision','from gpu_friction_api.collision').replace('from experimental.physics_gpu.shape_kernels','from gpu_friction_api.shape_kernels').replace('from experimental.physics_gpu.contact_oracle','from gpu_friction_api.contact_oracle').replace('from experimental.physics_gpu.box_oracle','from gpu_friction_api.box_oracle').replace('from experimental.physics_gpu.history_kernels','from gpu_friction_api.history_kernels').replace('from experimental.physics_gpu.contact_history','from gpu_friction_api.contact_history').replace('from experimental.physics_gpu.contact_reference','from gpu_friction_api.contact_reference').replace('from experimental.physics_gpu.response_kernels','from gpu_friction_api.response_kernels').replace('from experimental.physics_gpu.normal_response','from gpu_friction_api.normal_response').replace('from experimental.physics_gpu.response_reference','from gpu_friction_api.response_reference').replace('from experimental.physics_gpu.boundary_reference','from gpu_friction_api.boundary_reference'))
        include=[package,ROOT]
    elif args.mode=='demo':
        game=ROOT/'games/yo-frankie';cwd=game;target=game/'examples/gpu_friction_review.mojo';include=[ROOT,game]
        sources += sorted((game/'frankie').glob('*.mojo'))+[target,ROOT/'build/libmojo_graphics.a',ROOT/'.deps/sdl3/lib/libSDL3.so']
        subprocess.run(['python3',str(ROOT/'scripts/engine-build-state.py'),'check'],check=True,timeout=10)
        env.update({'VK_DRIVER_FILES':'/usr/share/vulkan/icd.d/nvidia_icd.json','MOJO_VK_SOFTWARE':'0','MOJO_VK_REQUIRE_HARDWARE':'1',
                    'MOJO_VK_VALIDATION':'1','VK_LAYER_VALIDATE_SYNC':'1','SDL_AUDIO_DRIVER':'dummy'})
    fingerprint={str(p.relative_to(ROOT)):G01.digest(p) for p in sources}
    fingerprint['GPU_ENV/pixi.lock']=G01.digest(ENV_ROOT.parents[2]/'pixi.lock')
    if args.mode=='packaged':fingerprint['compiled_GPU_API']=G01.digest(package_file)
    executable=OUT/args.mode;state_file=OUT/(args.mode+'-build.json')
    try:
        old=json.loads(state_file.read_text());valid=old['sources']==fingerprint and old['executable_sha256']==G01.digest(executable)
    except (OSError,KeyError,ValueError):valid=False
    if args.build or not valid:
        command += [str(target)]
        for path in include:command += ['-I',str(path)]
        if args.mode=='demo':
            command += ['-Xlinker',str(ROOT/'build/libmojo_graphics.a'),'-Xlinker','-L','-Xlinker',str(ROOT/'.deps/sdl3/lib'),
                        '-Xlinker','-rpath','-Xlinker',str(ROOT/'.deps/sdl3/lib'),'-Xlinker','-lSDL3','-Xlinker','-lvulkan','-Xlinker','-lm']
        command += ['-o',str(executable)]
        G01.stage(args.mode+'-compile',command,180,env)
        state_file.write_text(json.dumps({'sources':fingerprint,'executable_sha256':G01.digest(executable)},indent=2)+'\n')
    run=[str(executable)]
    if args.mode=='demo':run=['bash',str(ROOT/'games/yo-frankie/scripts/run-vulkan.sh'),str(executable)]
    result=G01.stage(args.mode+'-run',run,30,env,cwd)
    if args.mode in ('test','packaged'):
        shutil.copy2(ROOT/'build/physics-g04a/boundary-last.jsonl',OUT/(args.mode+'-boundary.jsonl'))
    receipt={'status':'passed','milestone':'G04b','mode':args.mode,'build':json.loads(state_file.read_text()),'run':result,
             'GPU_registry':'device active/generation arrays; GPU free-slot selection and handle validation',
             'solver':'serial GPU coupled normal/circular tangent-block Coulomb sweeps; one coefficient; split COM projection; cold accumulators','solver_contact_capacity_max':64,'history_capacity_default':256,'event_capacity_default':512,'host_registry':False,'body_state_upload_each_step':False,'precision':'Float64 correctness profile',
             'supported_pairs':['sphere/sphere','sphere/oriented-box in either slot order'],'box_box_candidates_excluded':True,'body_capacity':256,'shape_capacity':64,'shape_command_capacity':64,'pair_algorithm':'bounded all-pairs AABB filtering; not a scalable broadphase','pair_order':'canonical shape slot a<b, lexicographic order','CPU_fallback':False,'actual_DMA_bytes_measured':False,
             'unsupported':['plane and mesh geometry','box/box geometry','general multi-point manifolds','impulse reuse','scalable broadphase','separate static/dynamic coefficients','joints','CCD','direct CUDA-Vulkan sharing']}
    (OUT/(args.mode+'-qualification.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    print('G04b passed:',args.mode,'; receipt:',OUT/(args.mode+'-qualification.json'))

if __name__=='__main__':main()
