#!/usr/bin/env bash
# Collects OPBENCH frame logs plus device temperature, thermal status and memory.
# OPPERF lines (Godot monitors, if the app emits them) go to <candidate>-<scene>-<run>.perf.jsonl.
# Usage: spikes/bench/collect.sh <candidate> <scene> <run> <package> <seconds>
# OPBENCH_RESULTS_DIR overrides the output directory (default: spikes/bench/results).
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <candidate> <scene> <run> <package> <seconds>" >&2
  exit 2
fi

candidate=$1 scene=$2 run=$3 package=$4 seconds=$5
out_dir="${OPBENCH_RESULTS_DIR:-$(dirname "$0")/results}"
mkdir -p "$out_dir"
frames="$out_dir/${candidate}-${scene}-${run}.jsonl"
device="$out_dir/${candidate}-${scene}-${run}.device.jsonl"
perf="$out_dir/${candidate}-${scene}-${run}.perf.jsonl"

adb logcat -c
adb logcat -v raw -s OPBENCH:I > "$frames" &
logcat_pid=$!
adb logcat -v raw -s OPPERF:I > "$perf" &
perf_pid=$!
trap 'kill "$logcat_pid" "$perf_pid" 2>/dev/null || true' EXIT

end=$((SECONDS + seconds))
: > "$device"
while (( SECONDS < end )); do
  temp=$(adb shell dumpsys battery | awk '/temperature/ {print $2 / 10; exit}')
  thermal=$(adb shell dumpsys thermalservice | awk -F': ' '/Thermal Status/ {print $2; exit}')
  # By pid: on SM-P200 `dumpsys meminfo <package>` sometimes falls back to the system summary.
  pid=$(adb shell pidof "$package" | tr -d '\r')
  pss=$(adb shell dumpsys meminfo "${pid:-$package}" | awk '/TOTAL PSS:/ {print $3 / 1024; exit}')
  printf '{"t":%d,"batteryC":%s,"thermal":"%s","pssMB":%s}\n' \
    "$((seconds - (end - SECONDS)))" "${temp:-null}" "${thermal:-unknown}" "${pss:-null}" >> "$device"
  sleep 10
done

grep -q "^{" "$perf" || rm -f "$perf"   # candidates without OPPERF
echo "saved $frames and $device"
