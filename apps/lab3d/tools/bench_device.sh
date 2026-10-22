#!/usr/bin/env bash
# Measures the incline friction experiment on a connected Android device with the benchmark
# procedure (docs/3d-phase0/benchmark-spec.md section 5, as used in Phase 1 Task 1):
# shader-cache run, then <runs> x (app restart, 30 s warm-up, <seconds> s capture), then one
# 600 s sustained capture. The panel shows the observations and the graph (--scroll-to), and the
# box is dragged and released every 4 s so the drag, physics, observations and graph keep updating.
# Usage: apps/lab3d/tools/bench_device.sh <tier> [runs] [seconds] [rest_s]   e.g. low 3 90 60
# Output: $OPBENCH_RESULTS_DIR (default spikes/bench/results/phase1-task2a)/lab3d-<tier>-S3-*.jsonl
# plus gpu-clock-<tier>.log ("<unix s> <Mali kHz> <AP °C>" every 5 s). Summarise with
# node spikes/bench/summarize.mjs <dir>.
set -uo pipefail
tier=${1:?tier}
runs=${2:-3}
seconds=${3:-90}
rest=${4:-60}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
export OPBENCH_RESULTS_DIR=${OPBENCH_RESULTS_DIR:-$repo/spikes/bench/results/phase1-task2a}
package=org.openphysics.lab3d
# Task 2b: every 4 s the box is dragged to a new start through the finger input path (1 s drag,
# put down) and released 0.4 s later. Task 2a/2c measured OPBENCH_PLAY=--auto-release=4 (re-release only).
play=${OPBENCH_PLAY:---auto-drag=4}
args="--experiment=incline-friction,--quality=$tier,--orientation=portrait,--scroll-to=observations,$play,--ctl-angle=30"
mkdir -p "$OPBENCH_RESULTS_DIR"

adb_ready() { adb start-server >/dev/null 2>&1; adb wait-for-device; }
launch() {
  adb_ready
  adb shell am force-stop "$package"
  adb shell input keyevent KEYCODE_WAKEUP
  adb shell am start -n "$package/com.godot.game.GodotAppLauncher" --es opargs "$args" >/dev/null
}
log() { echo "[$(date +%H:%M:%S)] $*"; }

adb_ready
( while true; do
    echo "$(date +%s) $(adb shell 'cat /sys/class/misc/mali0/device/clock; dumpsys thermalservice | grep -m1 -o "mValue=[0-9.]*, mType=0" | cut -d= -f2 | cut -d, -f1' 2>/dev/null | tr '\n' ' ')"
    sleep 5
  done ) >> "$OPBENCH_RESULTS_DIR/gpu-clock-$tier.log" &
sampler=$!
trap 'kill $sampler 2>/dev/null' EXIT

log "shader cache run"; launch; sleep 20
for run in $(seq 1 "$runs"); do
  log "run $run: launch + 30 s warm-up"; launch; sleep 30
  log "run $run: capture $seconds s"
  "$repo/spikes/bench/collect.sh" "lab3d-$tier" S3 "$run" "$package" "$seconds"
  log "run $run: rest $rest s"; adb shell am force-stop "$package"; sleep "$rest"
done
log "sustained: launch + 30 s warm-up"; launch; sleep 30
log "sustained: capture 600 s"
"$repo/spikes/bench/collect.sh" "lab3d-$tier" S3 sustained "$package" 600
adb shell am force-stop "$package"
log "done"
