"""Create an independent asset-free Mojo game consuming an explicit Atlas engine checkout."""
import argparse,json,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('directory',type=Path);args=p.parse_args();dest=args.directory.resolve()
 if dest.exists() and any(dest.iterdir()):raise SystemExit('Choose a new or empty project directory')
 dest.mkdir(parents=True,exist_ok=True);(dest/'src').mkdir();(dest/'scripts').mkdir()
 shutil.copy2(ROOT/'examples/orb_collector.mojo',dest/'src/main.mojo');shutil.copy2(ROOT/'pixi.lock',dest/'pixi.lock')
 (dest/'pixi.toml').write_text('[workspace]\nname = "atlas-game"\nversion = "0.1.0"\nchannels = ["https://conda.modular.com/max-nightly", "conda-forge"]\nplatforms = ["linux-64", "linux-aarch64"]\n[tasks]\nbuild = "bash scripts/build.sh"\nplay = {cmd = "build/game", depends-on = ["build"]}\n[dependencies]\nmojo = ">=1.2.0.dev2026092905,<2"\n')
 (dest/'engine-path.txt').write_text(str(ROOT)+'\n')
 (dest/'scripts/build.sh').write_text('''#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine_root=${ATLAS_ENGINE_ROOT:-$(cat engine-path.txt)}
engine_root=$(cd "$engine_root" && pwd)
python3 "$engine_root/scripts/engine-build-state.py" check
mkdir -p build
mojo build src/main.mojo -I "$engine_root/build" -Xlinker "$engine_root/build/libmojo_graphics.a" -Xlinker -L -Xlinker "$engine_root/.deps/sdl3/lib" -Xlinker -rpath -Xlinker "$engine_root/.deps/sdl3/lib" -Xlinker -lSDL3 -Xlinker -lvulkan -Xlinker -lm -o build/game
''')
 (dest/'.gitignore').write_text('/build/\n/.pixi/\n')
 (dest/'README.md').write_text('# Independent Atlas game\n\nBuild Atlas once, then run `pixi run build` or `pixi run play` here.\nThis starter contains Orb Collector gameplay and no Yo Frankie content.\nSet `ATLAS_ENGINE_ROOT` to another compatible engine checkout/SDK; game outputs stay under `build/`.\n')
 print('Created independent game:',dest)
if __name__=='__main__':main()
