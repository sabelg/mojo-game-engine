#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tool="$root/.deps/ffmpeg-9.0.2/.pixi/envs/default/bin/ffmpeg"
[[ -x "$tool" ]] || { echo 'Run bash scripts/setup-ffmpeg.sh to install Atlas FFmpeg 9.0.2.' >&2; exit 1; }
unset LD_LIBRARY_PATH LD_PRELOAD
exec "$tool" "$@"
