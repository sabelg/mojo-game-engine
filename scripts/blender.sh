#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
binary="${ATLAS_BLENDER:-$repo/.deps/blender-source/build/bin/blender}"
[[ -x "$binary" ]] || { echo 'Blender is missing. Run scripts/setup-usd-tools.sh or set ATLAS_BLENDER.' >&2; exit 1; }
exec "$binary" "$@"
