#!/usr/bin/env bash
# Quick variant loop for the Godot spike (Phase 1 Task 1): launch one scene + quality variant through
# the `opargs` intent extra (no rebuild), wait, capture OPBENCH + OPPERF and sample the GPU clock and
# SoC (AP) temperature every 2 s, then print a one-line summary.
# Usage: spikes/bench/godot-variant.sh <name> <warmup_s> <capture_s> [app args...]
#   e.g. spikes/bench/godot-variant.sh s2-msaa0 20 40 --scene=S2 --quality=high --q-msaa=0
# Output: $OPBENCH_VARIANT_DIR (default spikes/bench/results/phase1-task1/bisect)/<name>.log and .clk
set -uo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <name> <warmup_s> <capture_s> [app args...]" >&2
  exit 2
fi
name=$1 warmup=$2 capture=$3
shift 3
here=$(cd "$(dirname "$0")" && pwd)
out_dir=${OPBENCH_VARIANT_DIR:-$here/results/phase1-task1/bisect}
package=${OPBENCH_PACKAGE:-org.openphysics.spike.godot}  # apps/lab3d: org.puppyland.lab3d
mkdir -p "$out_dir"

adb start-server >/dev/null 2>&1
adb wait-for-device
adb shell am force-stop "$package"
adb shell input keyevent KEYCODE_WAKEUP
extras=()
(( $# > 0 )) && extras=(--es opargs "$(IFS=,; echo "$*")")  # adb drops an empty value
adb shell am start -W -n "$package/com.godot.game.GodotAppLauncher" ${extras[@]+"${extras[@]}"} >/dev/null
sleep "$warmup"
adb logcat -c
# Mali clock (kHz) and the AP thermal sensor; both readable without root on SM-P200.
timeout "$capture" adb shell 'while true; do echo $(cat /sys/class/misc/mali0/device/clock) $(dumpsys thermalservice | grep -m1 -o "mValue=[0-9.]*, mType=0" | cut -d= -f2 | cut -d, -f1); sleep 2; done' \
  > "$out_dir/$name.clk" 2>/dev/null &
timeout "$capture" adb logcat -v raw -s OPBENCH:I OPPERF:I > "$out_dir/$name.log"
wait
node "$here/variant-summary.mjs" "$out_dir/$name.log" "$name" "$out_dir/$name.clk"
