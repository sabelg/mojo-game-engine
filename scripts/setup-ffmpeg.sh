#!/usr/bin/env bash
# Optional Atlas CLI tooling in its own versioned conda-forge environment.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -m) == aarch64 ]] || { echo 'This pinned FFmpeg setup targets Linux ARM64.' >&2; exit 1; }
available_kib=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
(( available_kib >= 35651584 )) || { echo 'FFmpeg setup requires 32 GiB system reserve plus 2 GiB working headroom.' >&2; exit 1; }
pixi_bin=$(command -v pixi || true)
[[ -n "$pixi_bin" ]] || { echo 'Install Pixi before setting up Atlas FFmpeg.' >&2; exit 1; }
prefix="$PWD/.deps/ffmpeg-9.0.2"
mkdir -p "$prefix"
manifest="$prefix/pixi.toml"
expected=$(mktemp)
trap 'rm -f "$expected"' EXIT
cat > "$expected" <<'TOML'
[workspace]
name = "atlas-ffmpeg-9-0-2"
channels = ["https://conda.anaconda.org/conda-forge"]
platforms = ["linux-aarch64"]

[dependencies]
ffmpeg = { version = "==9.0.2", build = "gpl_h2f3dd36_103" }
TOML
if [[ -f "$manifest" ]]; then
    cmp -s "$manifest" "$expected" || { echo 'Existing FFmpeg manifest differs; preserve it and inspect before proceeding.' >&2; exit 1; }
else
    cp "$expected" "$manifest"
fi
# This optional setup solves only the media environment. Atlas's root lock is untouched.
# Run only after the coordinated installation/build slot has been granted.
if [[ -f "$prefix/pixi.lock" ]]; then
    nice -n 10 "$pixi_bin" install --manifest-path "$manifest" --locked --concurrent-solves 1 --concurrent-downloads 2
else
    nice -n 10 "$pixi_bin" install --manifest-path "$manifest" --concurrent-solves 1 --concurrent-downloads 2
fi
python3 scripts/qualify-ffmpeg.py --inspect-only
