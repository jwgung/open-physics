#!/usr/bin/env bash
# Collects OPBENCH frame logs plus device temperature, thermal status and memory.
# Usage: spikes/bench/collect.sh <candidate> <scene> <run> <package> <seconds>
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <candidate> <scene> <run> <package> <seconds>" >&2
  exit 2
fi

candidate=$1 scene=$2 run=$3 package=$4 seconds=$5
out_dir="$(dirname "$0")/results"
mkdir -p "$out_dir"
frames="$out_dir/${candidate}-${scene}-${run}.jsonl"
device="$out_dir/${candidate}-${scene}-${run}.device.jsonl"

adb logcat -c
adb logcat -v raw -s OPBENCH:I > "$frames" &
logcat_pid=$!
trap 'kill "$logcat_pid" 2>/dev/null || true' EXIT

end=$((SECONDS + seconds))
: > "$device"
while (( SECONDS < end )); do
  temp=$(adb shell dumpsys battery | awk '/temperature/ {print $2 / 10; exit}')
  thermal=$(adb shell dumpsys thermalservice | awk -F': ' '/Thermal Status/ {print $2; exit}')
  pss=$(adb shell dumpsys meminfo "$package" | awk '/TOTAL PSS:/ {print $3 / 1024; exit}')
  printf '{"t":%d,"batteryC":%s,"thermal":"%s","pssMB":%s}\n' \
    "$((seconds - (end - SECONDS)))" "${temp:-null}" "${thermal:-unknown}" "${pss:-null}" >> "$device"
  sleep 10
done

echo "saved $frames and $device"
