#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${1:?usage: make-archive.sh <dir with drivers/ and dlls/> [out.tar.gz]}
out=${2:-$PWD/oxp3-game-pack.tar.gz}
bin=$(cd "$bin" && pwd)
( cd "$bin" && sha256sum --quiet -c "$here/BINARIES.sha256" )
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
p=$stage/oxp3-game-pack
mkdir -p "$p"
cp -a "$here/oxp3-game-pack.sh" "$here/oxp3-run" "$here/README.md" "$here/games" "$here/patches" "$p/"
while read -r _ f; do
  mkdir -p "$p/$(dirname "$f")"
  cp "$bin/$f" "$p/$f"
done < "$here/BINARIES.sha256"
( cd "$p" && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | sed 's|^\./||' | xargs sha256sum > SHA256SUMS )
tar -C "$stage" --owner=0 --group=0 -czf "$out" oxp3-game-pack
sha256sum "$out"
