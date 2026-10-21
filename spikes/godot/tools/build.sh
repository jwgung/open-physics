#!/usr/bin/env bash
# Headless pipeline: bake textures -> import -> S3 tests -> Android release APK + Web export.
# Usage: spikes/godot/tools/build.sh [test|android|web|all]   (default: all)
# Release APK is signed with the Android debug keystore (spike only, not for distribution).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/.local/share/godot-spike/godot}
what=${1:-all}
mkdir -p exports && touch exports/.gdignore   # keep export output out of the Godot import scan

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true   # fresh checkout: build the class cache first
if [[ ! -f assets/generated/web/planet_7_normal.png ]]; then
  "$GODOT" --headless --path . -s res://tools/bake_textures.gd
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

if [[ $what == test || $what == all ]]; then
  log=exports/test.log
  status=0
  "$GODOT" --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd >"$log" 2>&1 || status=$?
  grep -E '^(PASS|FAIL|RESULT|==)' "$log" || true
  if [[ $status -ne 0 ]] || grep -q '^FAIL' "$log"; then
    echo "S3 tests failed (exit $status); tail of $log:" >&2
    tail -n 40 "$log" >&2
    exit 1
  fi
fi
if [[ $what == android || $what == all ]]; then
  mkdir -p exports/android
  GODOT_ANDROID_KEYSTORE_RELEASE_PATH=${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$HOME/.android/debug.keystore} \
  GODOT_ANDROID_KEYSTORE_RELEASE_USER=${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-androiddebugkey} \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-android} \
    "$GODOT" --headless --path . --export-release Android exports/android/open-physics-godot.apk
  ls -l exports/android/open-physics-godot.apk
fi
if [[ $what == web || $what == all ]]; then
  mkdir -p exports/web
  "$GODOT" --headless --path . --export-release Web exports/web/index.html
  du -sh exports/web
fi
