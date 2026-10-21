#!/usr/bin/env bash
# Headless pipeline: bake textures -> import -> S3 tests -> Android release APK + Web export.
# Usage: spikes/godot/tools/build.sh [test|android|web|all]   (default: all)
# Release APK is signed with the Android debug keystore (spike only, not for distribution).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/.local/share/godot-spike/godot}
what=${1:-all}
mkdir -p exports && touch exports/.gdignore   # keep export output out of the Godot import scan

if [[ ! -f assets/generated/web/planet_7_normal.png ]]; then
  "$GODOT" --headless --path . -s res://tools/bake_textures.gd
fi
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

if [[ $what == test || $what == all ]]; then
  "$GODOT" --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd | grep -E '^(PASS|FAIL|RESULT|==)'
  test "${PIPESTATUS[0]}" -eq 0
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
