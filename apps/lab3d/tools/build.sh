#!/usr/bin/env bash
# Headless pipeline for the 3D app: import -> tests -> Android release APK.
# Usage: apps/lab3d/tools/build.sh [test|android|all]   (default: all)
# The APK is signed with the Android debug keystore (development only, not for distribution).
# Godot 4.7.2 + export templates: spikes/godot/tools/setup_editor.sh (GODOT overrides the binary).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/.local/share/godot-spike/godot}
what=${1:-all}
mkdir -p exports && touch exports/.gdignore   # keep export output out of the Godot import scan

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true   # fresh checkout: class cache + font import

if [[ $what == test || $what == all ]]; then
  log=exports/test.log
  status=0
  "$GODOT" --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd >"$log" 2>&1 || status=$?
  grep -E '^(PASS|FAIL|RESULT|==)' "$log" || true
  if [[ $status -ne 0 ]] || grep -q '^FAIL' "$log" || ! grep -q '^RESULT: PASS' "$log"; then
    echo "lab3d tests failed (exit $status); tail of $log:" >&2
    tail -n 40 "$log" >&2
    exit 1
  fi
fi
if [[ $what == android || $what == all ]]; then
  mkdir -p exports/android
  GODOT_ANDROID_KEYSTORE_RELEASE_PATH=${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$HOME/.android/debug.keystore} \
  GODOT_ANDROID_KEYSTORE_RELEASE_USER=${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-androiddebugkey} \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-android} \
    "$GODOT" --headless --path . --export-release Android exports/android/open-physics-lab3d.apk
  ls -l exports/android/open-physics-lab3d.apk
fi
