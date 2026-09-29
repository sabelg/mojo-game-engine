#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
converter=${BLENDER_LEGACY:-.deps/blender279/blender}
if [[ ! -x "$converter" ]]; then
    echo 'Set BLENDER_LEGACY to Blender 2.79b. Blender 5 discards these legacy animations.' >&2
    exit 1
fi
"$converter" -b -noaudio --python-exit-code 1 --python scripts/export_yofrankie.py
"$converter" -b -noaudio --python-exit-code 1 --python scripts/export_yofrankie.py -- animation
"$converter" -b -noaudio --python-exit-code 1 --python scripts/export_yofrankie.py -- enemies

python3 scripts/upgrade-frankie-materials.py
python3 scripts/check-frankie-assets.py
