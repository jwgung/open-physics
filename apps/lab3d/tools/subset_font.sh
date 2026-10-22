#!/usr/bin/env bash
# Rebuilds the Hangul UI fonts in assets/fonts/ from Noto Sans CJK KR (SIL OFL 1.1, Regular + Bold)
# with only ASCII + the characters used in scripts/**/*.gd, experiments/**/*.gd and
# content/**/*.json, so every build (Android, later Web) renders Korean without system fonts.
# Same approach as spikes/godot/tools/subset_font.sh. Run again whenever UI text changes;
# tests/run_tests.gd fails when a used character is missing from the subset.
# Symbols Noto Sans CJK lacks (subscripts such as x₀ in the shared lab texts, ⚖ ⌁ ▰ list icons) come
# from a DejaVu Sans subset (Bitstream Vera licence, assets/fonts/DejaVu-LICENSE.txt) that UiTheme
# sets as the fallback of both faces; it holds the same character list (Hangul is not in DejaVu).
# Needs: pyftsubset (fonttools; falls back to `uvx --from fonttools pyftsubset`), fonts-noto-cjk
# and fonts-dejavu-core.
set -euo pipefail
cd "$(dirname "$0")/.."
noto_dir=${NOTO_CJK_DIR:-/usr/share/fonts/opentype/noto}
if command -v pyftsubset >/dev/null; then subset=(pyftsubset); else subset=(uvx --from fonttools pyftsubset); fi
chars=$(python3 -I tools/used_chars.py)
for weight in Regular Bold; do
  # Font number 1 in the Noto Sans CJK collection is the KR face.
  "${subset[@]}" "$noto_dir/NotoSansCJK-$weight.ttc" --font-number=1 --text="$chars" --unicodes="U+0020-007E" \
    --layout-features='*' --output-file="assets/fonts/NotoSansKR-Lab3dSubset-$weight.otf"
done
dejavu_dir=${DEJAVU_DIR:-/usr/share/fonts/truetype/dejavu}
for face in "DejaVuSans Regular" "DejaVuSans-Bold Bold"; do
  set -- $face
  "${subset[@]}" "$dejavu_dir/$1.ttf" --text="$chars" --layout-features='*' \
    --output-file="assets/fonts/Lab3dSymbols-$2.ttf"
done
ls -l assets/fonts/*.otf assets/fonts/*.ttf
