#!/usr/bin/env bash
# Measures the incline friction experiment on a connected Android device with the benchmark
# procedure (docs/3d-phase0/benchmark-spec.md section 5, as used in Phase 1 Task 1):
# shader-cache run, then <runs> x (app restart, 30 s warm-up, <seconds> s capture), then one
# 600 s sustained capture. The panel shows the observations and the graph (--scroll-to), and the
# box is dragged (put down, released 0.4 s later) every 4 s so the drag, physics, observations and
# graph keep updating. OPBENCH_PLAY=--auto-release=4 re-releases only (the Task 2a/2c measurement:
# the experiment's own release action, no UI work besides what the experiment emits).
# Other experiments (Task 4a): OPBENCH_EXPERIMENT=<id> (default incline-friction). The scene name is
# the experiment definition's bench_id (content/experiments/<id>.json, the name the app logs; the id
# when it has none). OPBENCH_CTL=<comma-separated launch args> (default: --ctl-angle=30, the
# incline's measured angle, for incline-friction only; none for the others; "" for the defaults);
# OPBENCH_SUSTAINED=0 skips the 600 s sustained capture.
# Usage: apps/lab3d/tools/bench_device.sh <tier> [runs] [seconds] [rest_s]   e.g. low 3 90 60
# Output: $OPBENCH_RESULTS_DIR/lab3d-<tier>-<scene>-*.jsonl, plus gpu-clock-<tier>.log ("<unix s>
# <Mali kHz> <AP °C>" every 5 s). The default folder is per experiment and play mode,
# spikes/bench/results/lab3d-<experiment>-<drag|release>, never a recorded baseline (phase1-task*):
# a folder that already holds lab3d-<tier>-<scene>-* results is refused (OPBENCH_OVERWRITE=1 to
# replace them). Summarise with node spikes/bench/summarize.mjs <dir>.
set -uo pipefail
tier=${1:?tier}
runs=${2:-3}
seconds=${3:-90}
rest=${4:-60}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
package=org.openphysics.lab3d
# Task 2b: every 4 s the box is dragged to a new start through the finger input path (1 s drag,
# put down) and released 0.4 s later. Task 2a/2c measured OPBENCH_PLAY=--auto-release=4 (re-release only).
play=${OPBENCH_PLAY:---auto-drag=4}
case $play in
  *auto-drag*) mode=drag ;;
  *) mode=release ;;
esac
experiment=${OPBENCH_EXPERIMENT:-incline-friction}
definition="$here/../content/experiments/$experiment.json"
if [[ ! -f $definition ]]; then
  echo "bench_device: no experiment definition $definition" >&2
  exit 2
fi
scene=$(sed -n 's/.*"bench_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$definition" | head -n 1)
scene=${scene:-$experiment}
if [[ $experiment == incline-friction ]]; then
  ctl=${OPBENCH_CTL---ctl-angle=30}
else
  ctl=${OPBENCH_CTL-}
fi
export OPBENCH_RESULTS_DIR=${OPBENCH_RESULTS_DIR:-$repo/spikes/bench/results/lab3d-$experiment-$mode}
if [[ ${OPBENCH_OVERWRITE:-0} != 1 ]] && compgen -G "$OPBENCH_RESULTS_DIR/lab3d-$tier-$scene-*" >/dev/null; then
  echo "bench_device: $OPBENCH_RESULTS_DIR already holds lab3d-$tier-$scene-* results (OPBENCH_OVERWRITE=1 replaces them)" >&2
  exit 2
fi
args="--experiment=$experiment,--quality=$tier,--orientation=portrait,--scroll-to=observations,$play${ctl:+,$ctl}"
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
  "$repo/spikes/bench/collect.sh" "lab3d-$tier" "$scene" "$run" "$package" "$seconds"
  log "run $run: rest $rest s"; adb shell am force-stop "$package"; sleep "$rest"
done
if [[ ${OPBENCH_SUSTAINED:-1} != 0 ]]; then
  log "sustained: launch + 30 s warm-up"; launch; sleep 30
  log "sustained: capture 600 s"
  "$repo/spikes/bench/collect.sh" "lab3d-$tier" "$scene" sustained "$package" 600
fi
adb shell am force-stop "$package"
log "done"
