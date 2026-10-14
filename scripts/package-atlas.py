"""A reusable source SDK that deliberately excludes games, their assets and launchers."""
import hashlib,io,json,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SCRIPTS=['setup-sdl3.sh','build.sh','test.sh','smoke.sh','embed_shaders.py','run-vulkan.sh','test-vulkan-window.sh','check_render.py','check-msaa.py','check-skin.py','check-cascades.py','check-hdr.py','check-lod.py','check-hlod.py','engine-build-state.py','package-atlas.py','new-game.py','check-engine-boundary.py','cook-assets.py','cook-hlod.py','atlas-project.py','benchmark-atlas.sh','report-atlas-benchmark.py','qualify-atlas.py','qualify-sdk.py','evaluate-temporal.py']
TESTS=['vector_rotation.mojo','axis_normalization.mojo','HEPJO_MATH_AUDIT.md','rigidbody3d.mojo','rigidbody_integration.mojo','sdl3_window.c','sdl3_abi.c','sdl3_abi.py','sdl3_events.c','sdl3_events.mojo','core.mojo','platform.mojo','world3d.mojo','graphics3d.mojo','native_abi.mojo','msaa.mojo','vulkan_window.c','vulkan_hdr_window.c','media.mojo','input.c','controller.c','atlas_systems.mojo','atlas_render.mojo','world_recovery.mojo','scheduler.mojo','uploads.mojo','frames.mojo','binary_assets.mojo','triangle_collision.mojo','gpu_skin.mojo','gameplay3d.mojo','textures.mojo','terrain_authoring.mojo','terrain_stream.mojo','project3d.mojo','editor_commands.mojo','visibility3d.mojo','cascades.mojo','hdr.mojo','preview3d.mojo','lod3d.mojo','hlod3d.mojo','foliage3d.mojo','terrain_fade.mojo','project_workflow.py','cook_assets.py','benchmark_reports.py']
SCRIPTS += ['usd-preview.py','export-usd.py','usd-instancers.h','usd-curves.h','cook-usd.py','usd-blender-export.py','usd-inspect.cc','build-usd-tools.sh','setup-usd-tools.sh','build-blender.sh','blender.sh','usd-stage.cc','usd-camera.h','usd-materials.h','usd-material-profile.h','usd-lights.h','usd-color.h','usd-session.py','qualify-usd.py','usd-editor-bridge.py']
TESTS += ['usd_layers.py','usd_curves_authoring.py','usd_playback.py','preview_playback.mojo','usd_preview.py','usd_authoring.py','usd_history.py','usd_export.py','usd_instancers.py','usd_curves.py','morph_animation.py','morph_animation.mojo','morph_render.mojo','usd_visibility.py','visibility_animation.mojo','usdz_assets.py','usd_assets.py','usd_rig_fixture.py','usd_stage.py','usd_camera.mojo','usd_cameras.py','usd_materials.py','usd_geometry.py','usd_camera_animation.py','usd_camera_animation.mojo','usd_light_animation.py','usd_light_animation.mojo','usd_watch.py','usd_identity.py','usd_local_lights.py','local_lighting.mojo']
SCRIPTS += ['usd-numeric.h','usd-curve-authoring.h','usd-animation-authoring.h','usd-animation-sampling.h']
SCRIPTS += ['usd-workspace.h','usd-workspace-session.h','usd-working-layers.h','usd-identities.h']
TESTS += ['usd_typed_curves.py','usd_typed_editor.py','usd_spline_fixture.cc','usd_spline_rejection.py']
TESTS += ['usd_animation_authoring.py','usd_animation_editor.py','usd_skel_authoring.py','usd_pose_oracle.cc','usd_animation_render.py','usd_animation_render.mojo','usd_animation_latency.py','usd_fractional_sampling.py','usd_fractional_playback.py','usd_animation_workload.py']
TESTS += ['usd_source_editing.py','usd_identity_payloads.py','usd_source_editor.py']
TESTS += ['usd_workspace.py','usd_workspace_editor.py']
SCRIPTS += ['setup-ffmpeg.sh','ffmpeg.sh','ffprobe.sh','qualify-ffmpeg.py']
def engine_files():
 files={}
 for name in ['mojo_game','native','shaders','examples','assets','docs','README.md','pixi.lock']+['scripts/'+s for s in SCRIPTS]+['tests/'+t for t in TESTS]:
  p=ROOT/name
  for f in sorted(p.rglob('*')) if p.is_dir() else [p]:
   if f.is_file() and '__pycache__' not in f.parts and f.suffix!='.pyc':files[str(f.relative_to(ROOT))]=f
 return files
def engine_manifest():
 text=(ROOT/'pixi.toml').read_text()
 return '\n'.join(l for l in text.splitlines() if not l.startswith(('frankie','play =','play-hardware ='))) +'\n'
def main():
 files=engine_files();payloads={n:p.read_bytes() for n,p in files.items()};payloads['pixi.toml']=engine_manifest().encode()
 manifest={'kind':'atlas-source-sdk','format':1,'files':{n:{'bytes':len(v),'sha256':hashlib.sha256(v).hexdigest()} for n,v in payloads.items()}}
 output=ROOT/'build/mojo-game-source.tar.gz';output.parent.mkdir(exist_ok=True);temp=output.with_suffix('.tmp')
 with tarfile.open(temp,'w:gz') as tar:
  for n,data in payloads.items():
   info=tarfile.TarInfo(n);info.size=len(data);info.mode=0o644;tar.addfile(info,io.BytesIO(data))
  data=(json.dumps(manifest,indent=2)+'\n').encode();info=tarfile.TarInfo('ENGINE-MANIFEST.json');info.size=len(data);tar.addfile(info,io.BytesIO(data))
 with tarfile.open(temp) as tar:
  for n,r in manifest['files'].items():assert hashlib.sha256(tar.extractfile(n).read()).hexdigest()==r['sha256'],n
 temp.replace(output);(ROOT/'build/atlas-release-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print('Atlas source SDK:',len(files)+1,'files;',round(output.stat().st_size/1024**2,2),'MiB; no game content')
if __name__=='__main__':main()
