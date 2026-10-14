#!/usr/bin/env bash
# Build pinned official SDL3 locally; never replace the operating-system SDL.
set -euo pipefail
cd "$(dirname "$0")/.."
version=3.4.18
digest=9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3
cache="$PWD/.deps/sdl3-source"
prefix="$PWD/.deps/sdl3"
mkdir -p "$cache"
archive="$cache/SDL3-$version.tar.gz"
if [[ ! -f "$archive" ]]; then
    if [[ -n "${ATLAS_SDL_SOURCE_ARCHIVE:-}" ]]; then
        cp "$ATLAS_SDL_SOURCE_ARCHIVE" "$archive"
    else
        curl --fail --location --proto '=https' --tlsv1.2 \
            "https://github.com/libsdl-org/SDL/releases/download/release-$version/SDL3-$version.tar.gz" \
            --output "$archive.tmp"
        mv "$archive.tmp" "$archive"
    fi
fi
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status
if [[ ! -d "$cache/SDL3-$version" ]]; then
    tar -xzf "$archive" -C "$cache"
fi
cmake -S "$cache/SDL3-$version" -B "$cache/build-$version-$(uname -m)" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    -DSDL_INSTALL=ON -DSDL_X11_XTEST=OFF
cmake --build "$cache/build-$version-$(uname -m)" --parallel "${ATLAS_BUILD_JOBS:-4}"
cmake --install "$cache/build-$version-$(uname -m)"
python3 - "$prefix" "$version" "$digest" <<'PY'
import ctypes,hashlib,json,sys
from pathlib import Path
p=Path(sys.argv[1]);library=p/'lib/libSDL3.so'
sdl=ctypes.CDLL(str(library));sdl.SDL_GetVersion.restype=ctypes.c_int
assert sdl.SDL_GetVersion()==3004018,'SDL3 runtime does not match pinned version'
(p/'ATLAS-SDL3.json').write_text(json.dumps({'version':sys.argv[2],'official_source_sha256':sys.argv[3],'library_sha256':hashlib.sha256(library.read_bytes()).hexdigest(),'X11_XTEST':False},indent=2)+'\n')
print('Project-local native SDL3',sys.argv[2],'installed and verified.')
PY
