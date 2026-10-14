"""Compare the actual Mojo compiler layout with independently compiled SDL3 headers."""
import ctypes,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 prefix=ROOT/'.deps/sdl3';out=ROOT/'build';out.mkdir(exist_ok=True)
 library=ctypes.CDLL(str(prefix/'lib/libSDL3.so'));library.SDL_GetVersion.restype=ctypes.c_int
 assert library.SDL_GetVersion()==3004018,library.SDL_GetVersion()
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(prefix/'include'),str(ROOT/'tests/sdl3_abi.c'),'-o',str(out/'sdl3-header-oracle')],check=True)
 header=subprocess.check_output([str(out/'sdl3-header-oracle')],text=True)
 expected=dict(line.split('=',1) for line in header.splitlines())
 source=['from native.mojo.abi import *','from native.mojo.runtime_support import c_address','from std.sys import size_of','def main():']
 names=['SDL_Surface','SDL_DisplayMode','SDL_AudioSpec','SDL_KeyboardEvent','SDL_Event']
 for name in names:
  source+=['    var v_'+name+'='+name+'()',f'    print("{name}.size=",size_of[{name}](),sep="")']
  for key in expected:
   if not key.startswith(name+'.') or key.endswith('.size'):continue
   field=key.split('.')[1];field={'format':'c_format','type':'c_type'}.get(field,field)
   source+=[f'    print("{key}=",c_address(Pointer(to=v_{name}.{field}))-c_address(Pointer(to=v_{name})),sep="")']
 p=out/'sdl3-mojo-layout.mojo';p.write_text('\n'.join(source)+'\n')
 subprocess.run(['mojo','build','--num-threads',os.environ.get('ATLAS_BUILD_JOBS','1'),str(p),'-I',str(ROOT),'-o',str(out/'sdl3-mojo-layout')],check=True)
 mojo=dict(line.split('=',1) for line in subprocess.check_output([str(out/'sdl3-mojo-layout')],text=True).splitlines())
 for key,value in mojo.items():assert expected[key]==value,(key,expected[key],value)
 result={'SDL_runtime':'3.4.18','native_layouts':mojo,'header_oracle':expected,'compared_fields':len(mojo),'status':'passed'}
 (out/'sdl3-abi.json').write_text(json.dumps(result,indent=2)+'\n')
 print('SDL3 3.4.18: C/Mojo ABI comparison passed:',len(mojo),'sizes/offsets')
if __name__=='__main__':main()
