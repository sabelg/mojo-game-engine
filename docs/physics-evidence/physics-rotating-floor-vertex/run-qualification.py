import pathlib,json,hashlib,subprocess,sys,importlib.util,struct,collections
R=pathlib.Path('/home/user/mojo-game-engine');O=pathlib.Path(__file__).resolve().parent;M=R/'.deps/physics-gpu-g01/.pixi/envs/default/bin/mojo';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();fp=json.loads((O/'pre-native-fingerprints-2.json').read_text());s=importlib.util.spec_from_file_location('independent',O/'reference.py');ref=importlib.util.module_from_spec(s);s.loader.exec_module(ref)
def frozen():assert all(sha(R/n)==h for n,h in fp.items())
def stage(n,sec,cmd):
 frozen();subprocess.run([sys.executable,str(O/'run-stage.py'),n,str(sec),*map(str,cmd)],check=True)
def check(path,variant):
 n=f'{path}-variant-{variant}';rows=[json.loads(x) for x in (O/(n+'-cases.jsonl')).read_text().splitlines()];assert len(rows)==643 and all(x['physical_pass']==1 for x in rows);ratios=[];diag=[];canonical={};codes=collections.Counter()
 for row in rows:
  a=row['actual'];inp=row['input'];kind=row['kind'];chain=row.get('chain',0);expected=ref.oracle(inp,None if chain or kind<24 else int(row['expected'][39]));assert a[39]==expected[39],row
  if a[39]==0:
   ratio=max(abs(a[i]-expected[i])/(1e-10*(1+abs(expected[i]))) for i in range(1,39));diagnostic=max(abs(a[i]-expected[i])/(1e-10*(1+abs(expected[i]))) for i in range(40,95));assert ratio<=1 and diagnostic<=1,(kind,variant,row['order'],chain,ratio,diagnostic);ratios.append(ratio);diag.append(diagnostic)
  else:
   assert all(struct.pack('d',a[i])==struct.pack('d',inp[i]) for i in range(1,39))
  if chain:assert a[44]==0 and a[55]==0 and a[49]<=expected[48]+1e-9*(1+expected[48])
  else:
   codes[int(a[39])]+=1;normalized=a.copy();normalized[38]=0
   if kind in canonical:assert normalized==canonical[kind],(kind,variant,row['order'])
   else:canonical[kind]=normalized
 if path=='package':assert (O/f'source-variant-{variant}-cases.jsonl').read_bytes()==(O/(n+'-cases.jsonl')).read_bytes()
 audit={'path':path,'variant':variant,'primary_records':640,'chain_records':3,'codes':dict(codes),'max_independent_state_gate_ratio':max(ratios),'max_independent_diagnostic_gate_ratio':max(diag),'all_16_enumerations_exact':True,'package_source_byte_identical':path=='package'};(O/(n+'-independent-check.json')).write_text(json.dumps(audit,indent=2)+'\n');print('INDEPENDENT_PHYSICAL_PASS',path,variant,640,3,max(ratios),max(diag),flush=True)
assert json.loads((O/'source-compile-2-telemetry.json').read_text())['returncode']==0
for v in range(4):
 n=f'source-variant-{v}';stage(n,30,[O/'source',O/n,O/f'fixtures-{v}.tsv']);check('source',v)
print('SOURCE_CORRECTNESS_COMPLETE',flush=True)
stage('package-precompile',180,['/usr/bin/taskset','-c','0',M,'precompile',O/'package-src/gpu_rotating_floor_vertex_api','-I',R,'-o',O/'package/gpu_rotating_floor_vertex_api.mojoc'])
stage('package-compile',180,[M,'build','--num-threads','1',O/'test-packaged.mojo','-I',O/'package','-I',R,'-o',O/'packaged'])
for v in range(4):
 n=f'package-variant-{v}';stage(n,30,[O/'packaged',O/n,O/f'fixtures-{v}.tsv']);check('package',v)
print('FULL_BOUNDED_ROTATING_VERTEX_CORRECTNESS_COMPLETE',flush=True)
