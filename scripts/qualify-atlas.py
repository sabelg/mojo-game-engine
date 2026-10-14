"""Repeated Atlas hardware runs; freeze identities before each run, retain failures."""
import argparse,hashlib,importlib.util,json,math,os,platform,signal,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('atlas_report',ROOT/'scripts/report-atlas-benchmark.py');reports=importlib.util.module_from_spec(spec);spec.loader.exec_module(reports)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('mode',choices=['current','instanced','streaming','soak']);p.add_argument('--runs',type=int,default=3);p.add_argument('--seconds',type=float);p.add_argument('--frames',type=int);p.add_argument('--warmup',type=int);p.add_argument('--pacing-ms',type=int);p.add_argument('--windowed',action='store_true');p.add_argument('--1080p',action='store_true');p.add_argument('--hdr',action='store_true');p.add_argument('--terrain-fade',type=float,default=0);p.add_argument('--shadow-cascades',type=int,choices=[0,2,4],default=0);a=p.parse_args()
 if not math.isfinite(a.terrain_fade) or not 0<=a.terrain_fade<=2:p.error('Terrain fade must be in 0..2 seconds')
 if a.runs<1 or a.runs>100 or a.seconds is not None and a.seconds<=0:p.error('Invalid qualification duration')
 subprocess.run(['python3','scripts/engine-build-state.py','check'],cwd=ROOT,check=True)
 output=ROOT/'build/atlas-qualification'/time.strftime('%Y%m%dT%H%M%SZ',time.gmtime());output.mkdir(parents=True,exist_ok=True)
 binary=output/a.mode
 source=(ROOT/'examples/atlas_benchmark.mojo').read_text()
 if a.terrain_fade:
  original='WorldStreamer(terrain,asynchronous=True,scheduler=scheduler.copy())'
  if source.count(original)!=1:raise ValueError('Benchmark streamer source changed; update the explicit qualification adapter')
  source=source.replace(original,original[:-1]+',transition_seconds='+repr(a.terrain_fade)+')')
  # The benchmark is paced in milliseconds. Supply that elapsed policy instead
  # of the library's fixed 1/60 convenience default during this experiment.
  timestep=(a.pacing_ms if a.pacing_ms is not None else (8 if a.mode=='soak' else 0))/1000
  source=source.replace('stream.update(device,origin)','stream.update(device,origin,'+repr(timestep if timestep>0 else 1/60)+')')
  source=source.replace('print("streaming', 'print("terrain_fades\\t"+String(stream.transition_count)+"\\t"+String(stream.immediate_count)+"\\t"+String(stream.transition_bytes()))\n        print("streaming',1)
 source_path=output/'benchmark-source.mojo';source_path.write_text(source)
 subprocess.run(['mojo','build',str(source_path),'-I','build','-Xlinker','build/libmojo_graphics.a','-Xlinker','-L','-Xlinker',str(ROOT/'.deps/sdl3/lib'),'-Xlinker','-rpath','-Xlinker',str(ROOT/'.deps/sdl3/lib'),'-Xlinker','-lSDL3','-Xlinker','-lvulkan','-Xlinker','-lm','-o',str(binary)],cwd=ROOT,check=True)
 options=[]
 if a.mode=='instanced':options+=['--instanced']
 if a.mode=='streaming':options+=['--streaming']
 if a.mode=='soak':options+=['--soak']
 seconds=a.seconds if a.seconds is not None else (1800 if a.mode=='soak' else None)
 if seconds is not None:options+=['--seconds',str(seconds)]
 if a.frames is not None:options+=['--frames',str(a.frames)]
 options+=['--warmup',str(a.warmup if a.warmup is not None else (1200 if a.mode=='soak' and seconds>30 else 10))]
 pacing=a.pacing_ms if a.pacing_ms is not None else (8 if a.mode=='soak' else 0)
 options+=['--pacing-ms',str(pacing)]
 if a.windowed:options+=['--windowed']
 if a.__dict__['1080p']:options+=['--1080p']
 options+=['--shadow-cascades',str(a.shadow_cascades)]
 if a.hdr:options+=['--hdr']
 env=os.environ.copy();env.update(MOJO_VK_REQUIRE_HARDWARE='1',MOJO_VK_PROFILE='1');env.setdefault('MOJO_VK_VALIDATION','1' if a.mode=='soak' else '0');env.setdefault('VK_LAYER_VALIDATE_SYNC','1')
 try:driver=subprocess.check_output(['nvidia-smi','--query-gpu=name,driver_version','--format=csv,noheader'],text=True).strip()
 except (OSError,subprocess.CalledProcessError):driver=None
 identity={'engine':json.loads((ROOT/'build/atlas-build-state.json').read_text()),'executable_sha256':digest(binary),'benchmark_source_sha256':digest(source_path),'upstream_benchmark_source_sha256':digest(ROOT/'examples/atlas_benchmark.mojo'),'terrain_transition_seconds':a.terrain_fade,'host':platform.platform(),'driver':driver,'arguments':options,'environment':{k:env.get(k) for k in ['MOJO_VK_VALIDATION','MOJO_VK_MSAA','MOJO_VK_DEVICE_LOCAL_MESH','MOJO_VK_MESH_POOL','MOJO_VK_REQUIRE_HARDWARE','MOJO_VK_FRAMES_IN_FLIGHT','MOJO_VK_PROFILE','MOJO_VK_PRESENT_MODE','MOJO_VK_PRESENT_SYNC']}}
 (output/'identity.json').write_text(json.dumps(identity,indent=2)+'\n');results=[]
 for run in range(a.runs):
  path=output/f'run-{run+1}.tsv';errors=path.with_suffix('.stderr');started=time.monotonic()
  timed_out=False
  with path.open('w') as log,errors.open('w') as err:
   process=subprocess.Popen(['bash','scripts/run-vulkan.sh',str(binary),*options],cwd=ROOT,env=env,stdout=log,stderr=err,start_new_session=True)
   try:code=process.wait(timeout=seconds+90 if seconds is not None else 120)
   except subprocess.TimeoutExpired:
    timed_out=True
    os.killpg(process.pid,signal.SIGTERM)
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:
     os.killpg(process.pid,signal.SIGKILL);process.wait()
    code=124
  status={'exit_code':code,'elapsed_seconds':time.monotonic()-started,'stdout':path.name,'stderr':errors.name}
  if timed_out:status['error']='Qualification timed out; the process group was stopped.'
  if code==0:
   try:status.update(reports.report(path,identity))
   except (ValueError,StopIteration,IndexError) as error:status.update(exit_code=1,error=str(error))
  path.with_suffix('.json').write_text(json.dumps(status,indent=2)+'\n');results.append(status)
  print('Qualification run',run+1,'exit',status['exit_code'],'report',path.with_suffix('.json'),flush=True)
  if status['exit_code']:break
 summary={'mode':a.mode,'requested_runs':a.runs,'completed_runs':len(results),'passed':len(results)==a.runs and all(r['exit_code']==0 for r in results),'reports':[f'run-{i+1}.json' for i in range(len(results))]}
 if summary['passed']:
  summary['host_p99_range_ms']=[min(r['host']['p99_ms'] for r in results),max(r['host']['p99_ms'] for r in results)]
  summary['host_median_range_ms']=[min(r['host']['median_ms'] for r in results),max(r['host']['median_ms'] for r in results)]
 (output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2));raise SystemExit(0 if summary['passed'] else 1)
if __name__=='__main__':main()
