"""Run the declared USD profile checks; publish evidence only after all pass."""
import argparse
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
import shutil
import fcntl
import platform
from PIL import Image, ImageChops

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hardware',action='store_true',help='Require the host Vulkan GPU')
    args=parser.parse_args()
    parent=ROOT/'build/usd-qualification'
    mode='hardware' if args.hardware else 'software'
    parent.mkdir(parents=True,exist_ok=True)
    # Fixtures and captures use shared build paths. Concurrent qualification
    # could otherwise report success using another run's output.
    lock=(parent/'run.lock').open('a')
    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:raise SystemExit('Another USD qualification is running')
    subprocess.run([sys.executable,'scripts/engine-build-state.py','check'],cwd=ROOT,check=True)
    evidence=parent/(mode+'-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())+'-'+uuid.uuid4().hex[:8])
    evidence.mkdir(parents=True)
    checks=[]
    commands=[[sys.executable,'tests/'+name+'.py'] for name in
              ('usd_assets','usd_stage','usd_layers','usd_workspace','usd_workspace_editor','usd_source_editing','usd_identity_payloads','usd_source_editor','usd_authoring','usd_curves_authoring','usd_playback','usd_preview','usd_history','usd_watch','usd_identity','usd_materials','usd_geometry',
               'usd_cameras','usd_camera_animation','usd_light_animation','usd_local_lights',
               'morph_animation','usd_visibility','usdz_assets','usd_export','usd_instancers','usd_curves')]
    commands += [['bash','scripts/run-vulkan.sh','build/preview_playback-test'],
                 ['bash','scripts/run-vulkan.sh','build/atlas-usd-editor','--source',str(ROOT/'build/usd-playback.usda'),'--output',str(evidence/'playback-exports'),'--smoke-playback'],
                 ['bash','scripts/run-vulkan.sh','build/atlas-world','--smoke-usd-export','--project',str(evidence/'world-export-project')],
                 ['build/morph_animation-test'],
                 ['bash','scripts/run-vulkan.sh','build/morph_render-test'],
                 ['bash','scripts/run-vulkan.sh','build/visibility_animation-test'],
                 ['bash','scripts/run-vulkan.sh','build/usd_camera-test'],
                 ['bash','scripts/run-vulkan.sh','build/atlas-usd-scene','--smoke'],
                 ['build/usd_camera_animation-test'],['build/usd_light_animation-test'],
                 ['bash','scripts/run-vulkan.sh','build/local_lighting-test'],
                 ['bash','scripts/run-vulkan.sh','build/atlas-usd-editor','--source',
                 str(ROOT/'build/usd-camera-animation.usda'),'--output',str(evidence/'editor-exports'),'--smoke'],
                 ['bash','scripts/run-vulkan.sh','build/atlas-usd-editor','--source',
                  str(ROOT/'assets/usd/scene.usda'),'--output',str(evidence/'viewport-exports'),'--smoke-viewport']]
    commands.append(['bash','scripts/run-vulkan.sh','build/atlas-usd-editor','--source',str(ROOT/'build/usd-keyframes-source.usda'),'--output',str(evidence/'keyframe-exports'),'--smoke-keys'])
    commands.append(['bash','scripts/run-vulkan.sh','build/atlas-usd-editor','--source',str(ROOT/'build/usd-keyframes-source.usda'),'--output',str(evidence/'layer-exports'),'--smoke-layers'])
    commands.append(['bash','scripts/run-vulkan.sh','build/atlas-usd-editor','--source',str(ROOT/'build/usd-keyframes-source.usda'),'--output',str(evidence/'workspace-exports'),'--workspace',str(evidence/'workspace'),'--smoke-workspace'])
    commands.append(['bash','scripts/run-vulkan.sh','build/atlas-usd-editor','--source',str(ROOT/'build/usd-keyframes-source.usda'),'--output',str(evidence/'source-exports'),'--workspace',str(evidence/'source-workspace'),'--smoke-source'])
    commands += [[sys.executable,'tests/'+name+'.py'] for name in
                 ('usd_typed_curves','usd_typed_editor','usd_spline_rejection','usd_animation_authoring',
                  'usd_animation_editor','usd_skel_authoring','usd_animation_latency','usd_fractional_sampling',
                  'usd_fractional_playback','usd_animation_workload','usd_animation_render')]
    commands.append(['bash','scripts/run-vulkan.sh','build/usd_animation_render-test'])
    spec=importlib.util.spec_from_file_location('atlas_sdk_identity',ROOT/'scripts/package-atlas.py')
    sdk=importlib.util.module_from_spec(spec);spec.loader.exec_module(sdk)
    def identity():
        files=sdk.engine_files()
        files['pixi.toml']=ROOT/'pixi.toml'
        for name in ('inspect','stage'):
            path=Path(os.environ.get('ATLAS_USD_'+name.upper(),ROOT/f'.deps/usd-tools/bin/atlas-usd-{name}'))
            files['tool/'+name]=path
        for command in commands:
            for arg in command:
                if arg.startswith('build/') and (ROOT/arg).is_file():files[arg]=ROOT/arg
        for name in ('build/libmojo_graphics.a','build/mojo_game.mojoc'):
            files[name]=ROOT/name
        return {name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in sorted(files.items())}
    tested_identity=identity()
    environment=dict(os.environ)
    environment['ALSOFT_DRIVERS']='null'
    environment['SDL_AUDIO_DRIVER']='dummy'
    environment.pop('MOJO_VK_SOFTWARE',None)
    environment.pop('MOJO_VK_REQUIRE_HARDWARE',None)
    environment['MOJO_VK_VALIDATION']='1'
    environment['VK_LAYER_VALIDATE_SYNC']='1'
    environment['MOJO_VK_REQUIRE_HARDWARE' if args.hardware else 'MOJO_VK_SOFTWARE']='1'
    for index,command in enumerate(commands):
        if 'build/atlas-usd-editor' in command:
            editor_source_before=(ROOT/'build/usd-camera-animation.usda').read_bytes()
        if '--smoke-keys' in command:keyframe_source_before=(ROOT/'build/usd-keyframes-source.usda').read_bytes()
        started=time.monotonic()
        with (evidence/f'{index}.log').open('w') as log:
            result=subprocess.run(command,cwd=ROOT,env=environment,stdout=log,stderr=subprocess.STDOUT,timeout=600)
        checks.append({'command':command,'seconds':time.monotonic()-started,'exit_code':result.returncode})
        if result.returncode:
            raise SystemExit(f'USD qualification failed; see {evidence / (str(index)+".log")}')
    cell_exports=list((evidence/'world-export-project/exports').glob('usd-cell-*/scene.usda'))
    assert len(cell_exports)==1, 'World editor did not export its selected cell'
    exports=list((evidence/'editor-exports').glob('*.usda'))
    assert len(exports)==1, 'Native editor did not save one override layer'
    spec=importlib.util.spec_from_file_location('atlas_usd_session',ROOT/'scripts/usd-session.py')
    session=importlib.util.module_from_spec(spec);spec.loader.exec_module(session)
    with session.StageSession() as stage:
        saved=stage.request('open',source=str(exports[0]))
        assert len(saved['prims'])==2 and all(p.get('stable_id','').startswith('atlas:') for p in saved['prims']), 'Native editor did not persist IDs'
    key_exports=list((evidence/'keyframe-exports').glob('*.usda'))
    assert len(key_exports)==1
    with session.StageSession() as stage:
        stage.request('open',source=str(key_exports[0]))
        curve=next(c for c in stage.request('curves',path='/Shot',time=3)['curves'] if c['name']=='focalLength')
        assert [(k['time'],k['value']) for k in curve['keys']]==[(1,35),(3,55),(5,70)], 'Editor lost or changed composed curve keys'
    layer_exports=list((evidence/'layer-exports').glob('*.usda'))
    assert len(layer_exports)==1
    with session.StageSession() as stage:
        stage.request('open',source=str(layer_exports[0]))
        curve=next(c for c in stage.request('curves',path='/Shot',time=3)['curves'] if c['name']=='focalLength')
        assert [(k['time'],k['value']) for k in curve['keys']]==[(1,35),(3,55),(5,70)], 'Layer editor lost composed keys'
    with Image.open(ROOT/'build/usd-layers.bmp') as capture:capture.save(evidence/'usd-layers.png')
    with session.StageSession() as stage:
        state=stage.request('open_workspace',source=str(evidence/'source-workspace'))
        assert state['edit_target']=='working:0' and state['edit_context']=='/Shot'
        curve=next(c for c in stage.request('curves',path='/Shot',time=3)['curves'] if c['name']=='focalLength')
        assert curve['value']==77, 'Source editor did not persist its owned key'
    with Image.open(ROOT/'build/usd-source.bmp') as capture:capture.save(evidence/'usd-source.png')
    assert keyframe_source_before==(ROOT/'build/usd-keyframes-source.usda').read_bytes()
    with Image.open(ROOT/'build/usd-keyframes.bmp') as capture:capture.save(evidence/'usd-keyframes.png')
    assert editor_source_before==(ROOT/'build/usd-camera-animation.usda').read_bytes(), 'Native editor changed the source' 
    images=[]
    for camera in range(2):
        first=ROOT/f'build/usd-camera-{camera}-0.bmp'
        shifted=ROOT/f'build/usd-camera-{camera}-1.bmp'
        if first.read_bytes()!=shifted.read_bytes():
            raise SystemExit('USD camera floating-origin images differ')
        with Image.open(first) as image:
            rgb=image.convert('RGB')
            extrema=rgb.getextrema()
            if max(high-low for low,high in extrema)<10:
                raise SystemExit('USD camera capture is blank or has insufficient contrast')
        shutil.copyfile(first,evidence/first.name)
        images.append({'camera':camera,'sha256':hashlib.sha256(first.read_bytes()).hexdigest(),
                       'floating_origin_identical':True,'extrema':extrema})
    local=[]
    for index in range(7):
        source=ROOT/f'build/local-light-{index}.bmp'
        with Image.open(source) as image:
            rgb=image.convert('RGB')
            local.append({'center':rgb.getpixel((64,64)), 'bbox':rgb.getbbox()})
        shutil.copyfile(source,evidence/source.name)
    assert local[0]['bbox'] is None and local[4]['bbox'] is None, 'Disabled/backwards lights must be dark'
    assert min(local[1]['center'])>30, 'Point light did not illuminate geometry'
    for index in (2,3,5,6):
        assert max(abs(a-b) for a,b in zip(local[1]['center'],local[index]['center']))<=2, 'Light intensity/cone/array/origin regression'
    assert (ROOT/'build/local-light-1.bmp').read_bytes()==(ROOT/'build/local-light-6.bmp').read_bytes(), 'Local light floating-origin images differ'
    assert local[3]['bbox'][2]-local[3]['bbox'][0] < local[1]['bbox'][2]-local[1]['bbox'][0], 'Spot cone did not restrict illumination'
    shutil.copyfile(ROOT/'build/usd-editor.bmp',evidence/'usd-editor.bmp')
    animation_images=[]
    for sample in range(3):
        actual=ROOT/f'build/morph-render-{sample}-0.bmp'
        reference=ROOT/f'build/morph-render-{sample}-1.bmp'
        with Image.open(actual) as a,Image.open(reference) as b:
            assert not ImageChops.difference(a.convert('RGB'),b.convert('RGB')).getbbox(), 'Morph raster differs from independent transformed reference'
        shutil.copyfile(actual,evidence/actual.name)
        animation_images.append({'file':actual.name,'sha256':hashlib.sha256(actual.read_bytes()).hexdigest()})
    assert len({row['sha256'] for row in animation_images})==3, 'Morph animation captures did not change'
    visibility=[]
    for index in range(4):
        path=ROOT/f'build/visibility-animation-{index}.bmp'
        visibility.append(path.read_bytes());shutil.copyfile(path,evidence/path.name)
    assert visibility[0]!=visibility[1] and visibility[0]==visibility[2] and visibility[1]==visibility[3], 'Visibility rendering/cache parity failed'
    viewport_pixels=[]
    for name in ('before','after'):
        source=ROOT/('build/usd-viewport-'+name+'.bmp')
        with Image.open(source) as capture:
            crop=capture.convert('RGB').crop((360,175,1270,550))
            viewport_pixels.append(sum(1 for pixel in crop.getdata() if max(pixel)<120))
            capture.save(evidence/('usd-viewport-'+name+'.png'))
    assert viewport_pixels[0]>viewport_pixels[1]*1.5 and viewport_pixels[1]>400, 'USD variant edit did not shrink visible viewport geometry'
    playback_images=[]
    for index in range(2):
        source=ROOT/f'build/usd-playback-{index}.bmp'
        with Image.open(source) as capture:
            playback_images.append(capture.convert('RGB').crop((360,175,1270,550)))
            capture.save(evidence/f'usd-playback-{index}.png')
    assert ImageChops.difference(*playback_images).getbbox(), 'Animated viewport did not change between endpoints'
    profile=json.loads((ROOT/'assets/usd/compatibility-profile.json').read_text())
    authored_animation_images=[]
    for sample in range(4):
        actual=ROOT/f'build/usd-m03-render-{sample}-0.bmp';reference=ROOT/f'build/usd-m03-render-{sample}-1.bmp'
        with Image.open(actual) as a,Image.open(reference) as b:
            assert ImageChops.difference(a.convert('RGB'),b.convert('RGB')).getbbox() is None,'Authored spline camera render differs from analytic reference'
            assert max(hi-lo for lo,hi in a.convert('RGB').getextrema())>10,'Authored spline camera render is blank'
        shutil.copyfile(actual,evidence/actual.name)
        authored_animation_images.append({'file':actual.name,'sha256':hashlib.sha256(actual.read_bytes()).hexdigest()})
    assert len({row['sha256'] for row in authored_animation_images})==4,'Authored spline camera renders did not change'
    fractional_images=[]
    for sample in range(7):
        actual=ROOT/f'build/usd-m03-skin-{sample}-0.bmp';reference=ROOT/f'build/usd-m03-skin-{sample}-1.bmp'
        with Image.open(actual) as a,Image.open(reference) as b:
            assert ImageChops.difference(a.convert('RGB'),b.convert('RGB')).getbbox() is None,'Fractional rig raster differs from independent USD pose'
            assert max(hi-lo for lo,hi in a.convert('RGB').getextrema())>10,'Fractional rig capture is blank'
        shutil.copyfile(actual,evidence/actual.name)
        fractional_images.append({'file':actual.name,'sha256':hashlib.sha256(actual.read_bytes()).hexdigest()})
    assert len({r['sha256'] for r in fractional_images})>=5,'Fractional rig captures did not change'
    workload_images=[]
    for sample in range(4):
        actual=ROOT/f'build/usd-m03-workload-{sample}.bmp'
        with Image.open(actual) as a:assert max(hi-lo for lo,hi in a.convert('RGB').getextrema())>10,'Representative mesh capture is blank'
        shutil.copyfile(actual,evidence/actual.name)
        workload_images.append({'file':actual.name,'sha256':hashlib.sha256(actual.read_bytes()).hexdigest()})
    assert workload_images[0]['sha256']==workload_images[3]['sha256'],'Representative reverse seek changed start pose'
    assert len({r['sha256'] for r in workload_images})==3,'Representative mesh poses did not change'
    if identity()!=tested_identity:raise SystemExit('USD qualification inputs changed during the run; evidence was not published')
    report={'compatibility_profile':profile, 'evidence_directory':str(evidence), 'profile':'atlas-usd-1','openusd_version':2603,
            'viewport_variant_pixels':viewport_pixels,'tested_sha256':tested_identity,'host':platform.platform(),'python':sys.version,
            'driver_mode':'hardware' if args.hardware else 'software','checks':checks,'images':images,'local_light_images':local,'morph_images':animation_images,'visibility_cache_parity':True,
            'native_stage':json.loads((ROOT/'build/usd-stage-test.json').read_text()),
            'fractional_skin_images':fractional_images,'representative_workload_images':workload_images,
            'fractional_playback':json.loads((ROOT/'build/usd-fractional-playback.json').read_text()),
            'representative_workload':json.loads((ROOT/'build/usd-animation-workload.json').read_text()),
            'authored_animation_images':authored_animation_images,'animation_latency':json.loads((ROOT/'build/usd-animation-latency.json').read_text()),
            'limitations':['No full USD conformance claim','No external DCC image-fidelity qualification',
                           'Finite distant lights use a directional approximation',
                           'No general MaterialX graph execution, geometry caches or GPU morph computation',
                           'Payload limits apply to authoring service, not game-world GPU streaming']}
    # Earlier results remain intact on any failed check.
    temporary=evidence/'report.tmp'
    temporary.write_text(json.dumps(report,indent=2)+'\n')
    shutil.copyfile(temporary,evidence/'report.json')
    temporary.replace(parent/(mode+'.json'))
    print('USD profile qualification passed:',report['driver_mode'],len(checks),'checks; image/origin comparisons passed')
if __name__=='__main__':main()
