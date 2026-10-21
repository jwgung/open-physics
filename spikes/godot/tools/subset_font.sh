#!/usr/bin/env bash
# Rebuilds assets/fonts/NotoSansKR-OpenPhysicsSubset.otf from Noto Sans CJK KR (SIL OFL 1.1) with
# only ASCII + the glyphs used in scripts/*.gd, so the web build renders Hangul without system fonts.
# Needs: python fonttools (pyftsubset) and fonts-noto-cjk. Run again whenever UI strings change.
set -euo pipefail
cd "$(dirname "$0")/.."
src=${NOTO_CJK:-/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc}
chars=$(python3 -I -c 'import sys,glob; print("".join(sorted({c for f in glob.glob("scripts/*.gd") for c in open(f,encoding="utf-8").read() if ord(c) > 126})))')
pyftsubset "$src" --font-number=1 --text="$chars°·²½θμ−…" --unicodes="U+0020-007E" \
  --layout-features='*' --output-file=assets/fonts/NotoSansKR-OpenPhysicsSubset.otf
ls -l assets/fonts/NotoSansKR-OpenPhysicsSubset.otf
