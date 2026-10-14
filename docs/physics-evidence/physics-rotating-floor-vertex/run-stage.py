import importlib.util,json,os,sys,contextlib,io
from pathlib import Path
R=Path('/home/user/mojo-game-engine');O=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('guard',R/'scripts/qualify-physics-gpu.py');g=importlib.util.module_from_spec(s);s.loader.exec_module(g);g.OUT=O;E=g.GPU_ENV
base=json.loads((O/'baseline.json').read_text());assert all(g.digest(R/n)==h for n,h in base.items())
for pat,v in [('mojo-compiler-*.json','1.2.0.dev2026092905'),('max-core-*.json','26.7.0.dev2026092905')]:
 p=list((E/'conda-meta').glob(pat));assert len(p)==1 and json.loads(p[0].read_text())['version']==v
env=os.environ.copy();env.update(PATH=str(E/'bin')+':'+env['PATH'],CONDA_PREFIX=str(E),MODULAR_HOME=str(E/'share/max'),LD_LIBRARY_PATH=str(E/'lib')+':'+str(R/'.deps/sdl3/lib'))
name=sys.argv[1];guard=int(sys.argv[2]);cmd=sys.argv[3:];assert not (O/(name+'-telemetry.json')).exists(),'Never duplicate a stage'
try:
 with contextlib.redirect_stdout(io.StringIO()):g.stage(name,cmd,guard,env)
 print('Stage PASS',name,flush=True)
except SystemExit:
 print((O/(name+'.log')).read_text()[-5000:],flush=True);raise
