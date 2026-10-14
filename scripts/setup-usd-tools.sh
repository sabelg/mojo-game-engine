#!/usr/bin/env bash
# Native Ubuntu ARM64 setup. Tools stay inside the SDK's .deps directory.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
base="$repo/.deps/blender-source"
[[ "$(uname -m)" == aarch64 ]] || { echo 'This pinned setup targets Linux ARM64; use ATLAS_BLENDER/ATLAS_USD_INSPECT for other hosts.' >&2; exit 1; }
mkdir -p "$base/compiler-packages" "$base/compiler" "$base/lib"
checkout() {
  local url="$1" directory="$2" revision="$3"
  if [[ ! -d "$directory/.git" ]]; then
    GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --no-checkout --filter=blob:none "$url" "$directory"
    git -C "$directory" fetch --depth 1 origin "$revision"
    GIT_LFS_SKIP_SMUDGE=1 git -C "$directory" checkout --detach "$revision"
  fi
  [[ "$(git -C "$directory" rev-parse HEAD)" == "$revision" ]] || {
    echo "Unexpected revision in $directory; refusing to replace an existing checkout" >&2; exit 1;
  }
}
checkout https://github.com/blender/blender.git "$base/blender" d13f752e3b9c4f8c261cda552b1021f8bcc0382c
git -C "$base/blender" config lfs.url https://projects.blender.org/blender/blender.git/info/lfs
git -C "$base/blender" lfs pull --include='release/**,assets/**'
checkout https://projects.blender.org/blender/lib-linux_arm64.git "$base/lib/linux_arm64" 125b4ba5a9e75eede4e9b65e47dde28fbe7d67d0
git -C "$base/lib/linux_arm64" lfs pull
checkout https://github.com/NVIDIA/optix-dev.git "$base/optix" fff65c2a7c592f1ea5f1661ad7d2381cf965f9bd
(
  cd "$base/compiler-packages"
  version=14.2.0-4ubuntu2~24.04.1
  packages=()
  for name in cpp-14 cpp-14-aarch64-linux-gnu gcc-14 gcc-14-aarch64-linux-gnu g++-14 g++-14-aarch64-linux-gnu libgcc-14-dev libstdc++-14-dev; do
    packages+=("$name=$version")
  done
  apt-get download "${packages[@]}"
)
for package in "$base/compiler-packages"/*.deb; do dpkg-deb -x "$package" "$base/compiler"; done
bash "$repo/scripts/build-blender.sh"
bash "$repo/scripts/build-usd-tools.sh"
echo 'Built Blender and the OpenUSD inspector. Run the USD tests before using new imports.'
