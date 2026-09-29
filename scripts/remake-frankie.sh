#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONPATH="$PWD/.deps/blender-python${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONNOUSERSITE=1
export ALSOFT_DRIVERS=null
export XDG_CACHE_HOME="${TMPDIR:-/tmp}/frankie-blender-cache"
export XDG_CONFIG_HOME="${TMPDIR:-/tmp}/frankie-blender-config"
"${BLENDER_MODERN:-blender}" --background --factory-startup --python-use-system-env --python-exit-code 1 \
    --python scripts/remake_frankie_blender.py -- "$@"
