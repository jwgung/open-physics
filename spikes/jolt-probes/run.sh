#!/usr/bin/env bash
# Runs the Jolt behaviour probes behind apps/lab3d/docs/formula-correction.md section 2
# (Godot 4.7.2 + Jolt, 60 Hz, headless). Usage: spikes/jolt-probes/run.sh [probe.gd ...]
set -euo pipefail
cd "$(dirname "$0")"
GODOT=${GODOT:-$HOME/.local/share/godot-spike/godot}
probes=("$@")
[[ ${#probes[@]} -gt 0 ]] || probes=(callback_timing.gd integrate_forces_position.gd gravity_integration.gd \
  custom_integrator.gd contact_report.gd restitution_combine.gd joint_pin_pendulum.gd joint_6dof_spring.gd)
for probe in "${probes[@]}"; do
  echo "== $probe"
  timeout 120 "$GODOT" --headless --path . --fixed-fps 60 -s "res://$probe" 2>&1 | grep -v '^Godot Engine\|^$'
done
