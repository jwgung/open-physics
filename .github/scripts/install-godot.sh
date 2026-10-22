#!/usr/bin/env bash
# Installs the pinned Godot editor binary for headless tests (CI and local reproduction).
# Usage: .github/scripts/install-godot.sh <dir>   -> <dir>/godot (prints the path)
# The zip comes from the official GitHub release and must match the pinned SHA-512 (from the
# release's SHA512-SUMS.txt). A zip already in <dir> (e.g. restored from the CI cache) is
# re-verified before use; a mismatch fails the run.
set -euo pipefail
VERSION=4.7.2-stable
ZIP=Godot_v${VERSION}_linux.x86_64.zip
SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
URL=https://github.com/godotengine/godot/releases/download/${VERSION}/${ZIP}

dir=${1:?usage: install-godot.sh <dir>}
mkdir -p "$dir"
cd "$dir"
if [[ ! -f $ZIP ]]; then
  curl -fsSL --retry 3 -o "$ZIP.part" "$URL"
  mv "$ZIP.part" "$ZIP"
fi
echo "$SHA512  $ZIP" | sha512sum -c - >&2
unzip -q -o "$ZIP"
ln -sf "Godot_v${VERSION}_linux.x86_64" godot
./godot --headless --version >&2
echo "$PWD/godot"
