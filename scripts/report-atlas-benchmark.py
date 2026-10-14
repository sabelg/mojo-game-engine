"""Parse benchmark telemetry without conflating host time, GPU time or memory budgets."""
import argparse,hashlib,json,math,statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def summary(values):
 values=sorted(values)
 if not values:return None
 if any(not math.isfinite(v) for v in values):raise ValueError('Non-finite benchmark measurement')
 return {'median_ms':statistics.median(values),'p95_ms':values[max(0,math.ceil(len(values)*.95)-1)],'p99_ms':values[max(0,math.ceil(len(values)*.99)-1)],'max_ms':max(values)}
def report(path,metadata=None):
 rows=[line.split('\t') for line in path.read_text().splitlines()]
 frames=[list(map(float,r[1:])) for r in rows if r[0]=='frame']
 if not frames:raise ValueError('Missing benchmark samples')
 if ['validation','0'] not in rows:raise ValueError('Missing successful Vulkan validation result')
 measured=next((r for r in rows if r[0]=='measured'),None)
 if measured and int(measured[1])!=len(frames):raise ValueError('Incomplete benchmark samples')
 columns=next((r[1:] for r in rows if r[0]=='columns'),['host_ms','gpu_ms','draws','triangles'])
 if any(len(frame)!=len(columns) for frame in frames):raise ValueError('Malformed benchmark row')
 data={name:[frame[i] for frame in frames] for i,name in enumerate(columns)}
 result={'device':next(r[1] for r in rows if r[0]=='device'),'frames':len(frames),'host':summary(data['host_ms']),'gpu':summary([v for v in data['gpu_ms'] if v>=0]),'draws':frames[-1][2],'triangles':frames[-1][3]}
 result['stages']={name:summary(values) for name,values in data.items() if name.endswith('_ms') and name not in ('host_ms','gpu_ms')}
 result['peaks']={name:max(values) for name,values in data.items() if not name.endswith('_ms')}
 config=next((r for r in rows if r[0]=='config'),None)
 if config:result['configuration']=dict(zip(['width','height','warmup','max_frames','seconds','pacing_ms'],map(float,config[1:])))
 if measured:result['elapsed_seconds']=float(measured[2])
 memory=[r for r in rows if r[0]=='memory']
 if memory:
  rss=[int(r[2]) for r in memory];quarter=max(1,len(rss)//4)
  result['process_memory']={'samples':len(rss),'first_rss_kib':rss[0],'last_rss_kib':rss[-1],'peak_rss_kib':max(rss),'median_change_kib':statistics.median(rss[-quarter:])-statistics.median(rss[:quarter])}
 for row in rows:
  if row[0]=='streaming':result['streaming']=dict(zip(['uploads','evictions','resident_chunks','peak_cpu_reservations','vulkan_allocated_bytes'],map(int,row[1:])))
  if row[0]=='terrain_fades':result['terrain_fades']=dict(zip(['transitions','immediate_replacements','retained_bytes_at_end'],map(int,row[1:])))
  if row[0]=='jobs':result['jobs']=dict(zip(['accepted','rejected','completed','cancelled','errors','work_ms'],map(float,row[1:])))
  if row[0]=='saves':result['saves']=dict(zip(['commits','recoveries'],map(int,row[1:])))
  if row[0]=='color_pipeline':result['color_pipeline']=row[1]
  if row[0]=='shadows':result['shadows']={'cascades':int(row[1]),'distance_metres':float(row[2]),'tile_pixels':int(row[3])}
 if metadata:result['identity']=metadata
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('mode');args=p.parse_args();path=ROOT/'build/atlas-benchmark'/f'{args.mode}.tsv'
 state=ROOT/'build/atlas-benchmark'/f'{args.mode}.metadata.json'
 metadata=json.loads(state.read_text()) if state.exists() else {'executable_sha256':hashlib.sha256((path.parent/args.mode).read_bytes()).hexdigest()}
 result=report(path,metadata);path.with_suffix('.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
