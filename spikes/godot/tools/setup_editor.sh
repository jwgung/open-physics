#!/usr/bin/env bash
# Prepares the self-contained Godot 4.7.2 install used by this spike (editor_data next to the binary).
# Usage: spikes/godot/tools/setup_editor.sh   (env: GODOT_HOME, ANDROID_SDK, JAVA_HOME_SPIKE)
set -euo pipefail
GODOT_HOME=${GODOT_HOME:-$HOME/.local/share/godot-spike}
ANDROID_SDK=${ANDROID_SDK:-$HOME/Android/Sdk}
JAVA_HOME_SPIKE=${JAVA_HOME_SPIKE:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}
VERSION=4.7.2-stable
BASE=https://github.com/godotengine/godot/releases/download/$VERSION

mkdir -p "$GODOT_HOME"
cd "$GODOT_HOME"
if [[ ! -x Godot_v${VERSION}_linux.x86_64 ]]; then
  curl -sSLO "$BASE/SHA512-SUMS.txt"
  curl -sSLO "$BASE/Godot_v${VERSION}_linux.x86_64.zip"
  curl -sSLO "$BASE/Godot_v${VERSION}_export_templates.tpz"
  grep -E " Godot_v${VERSION}_(linux.x86_64.zip|export_templates.tpz)$" SHA512-SUMS.txt | sha512sum -c -
  unzip -q -o "Godot_v${VERSION}_linux.x86_64.zip"
  tpl_dir=editor_data/export_templates/4.7.2.stable
  mkdir -p "$tpl_dir"
  unzip -q -o -j "Godot_v${VERSION}_export_templates.tpz" \
    'templates/android_*' 'templates/web_*' 'templates/version.txt' -d "$tpl_dir"
  rm -f "Godot_v${VERSION}_export_templates.tpz"
fi
ln -sf "Godot_v${VERSION}_linux.x86_64" godot
touch _sc_   # self-contained mode: settings and templates stay in $GODOT_HOME/editor_data

settings=editor_data/editor_settings-4.7.tres
if [[ ! -f $settings ]]; then
  ./godot --headless -e --quit --path "$(mktemp -d)" >/dev/null 2>&1 || true
fi
python3 - "$settings" "$ANDROID_SDK" "$JAVA_HOME_SPIKE" "$HOME/.android/debug.keystore" <<'PY'
import re, sys
path, sdk, java, keystore = sys.argv[1:]
text = open(path).read()
values = {
    "export/android/android_sdk_path": sdk,
    "export/android/java_sdk_path": java,
    "export/android/debug_keystore": keystore,
    "export/android/debug_keystore_user": "androiddebugkey",
    "export/android/debug_keystore_pass": "android",
}
for key, value in values.items():
    line = f'{key} = "{value}"'
    pattern = re.compile(rf'^{re.escape(key)} = .*$', re.M)
    text = pattern.sub(line, text) if pattern.search(text) else text.rstrip("\n") + "\n" + line + "\n"
open(path, "w").write(text)
PY
echo "Godot ready: $GODOT_HOME/godot ($(./godot --headless --version))"
