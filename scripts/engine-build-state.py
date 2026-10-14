"""Engine-only source/archive/API fingerprints, independent of any game."""
import argparse,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def fingerprint():
 h=hashlib.sha256()
 for name in ['mojo_game','native/mojo','shaders','examples','scripts/build.sh','scripts/embed_shaders.py','pixi.lock','scripts/setup-sdl3.sh']:
  p=ROOT/name
  for f in sorted(p.rglob('*')) if p.is_dir() else [p]:
   if f.is_file() and '__pycache__' not in f.parts:h.update(str(f.relative_to(ROOT)).encode()+b'\0'+f.read_bytes()+b'\0')
 lib=ROOT/'.deps/sdl3/lib/libSDL3.so'
 h.update(b'SDL3-3.4.18\0'+lib.read_bytes()+b'\0')
 return h.hexdigest()
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def state():return {'engine_source_sha256':fingerprint(),'archive_sha256':digest(ROOT/'build/libmojo_graphics.a'),'module_sha256':digest(ROOT/'build/mojo_game.mojoc'),'editor_sha256':digest(ROOT/'build/atlas-world')}
def main():
 p=argparse.ArgumentParser();p.add_argument('mode',choices=['begin','write','check']);args=p.parse_args();file=ROOT/'build/atlas-build-state.json'
 start=ROOT/'build/atlas-build-source.json'
 if args.mode=='begin':start.write_text(json.dumps({'source':fingerprint()})+'\n');return
 if args.mode=='write':
  if not start.exists() or json.loads(start.read_text())['source']!=fingerprint():raise SystemExit('Engine sources changed during the build; rerun scripts/build.sh.')
  file.write_text(json.dumps(state(),indent=2)+'\n');return
 try:valid=json.loads(file.read_text())==state()
 except (OSError,ValueError):valid=False
 if not valid:raise SystemExit('Atlas engine is stale or unbuilt; run pixi run bash scripts/build.sh in the engine project.')
 print('Atlas engine source, archive and compiled API match.')
if __name__=='__main__':main()
