## Press-and-hold force (2026-10-28 user decision "손잡이 없이 물체에 직접"): while a finger holds the
## object, the applied force grows from 0 at `rate` N/s up to `cap` N; letting go puts it back to 0 at
## once. The force is counted in fixed steps (steps * rate / ticks per second, 64-bit), so the frame
## rate never changes it. The labs give force() to the formula models as the applied force they
## already take (PushFrictionModel.step, LeverLabModel.hand, PulleyLabModel.hand); the gauge beside
## the object shows fraction() (ForceGauge). Rates per lab: apps/lab3d/README.md "조작".
class_name HoldRamp
extends RefCounted

var rate := 0.0     # N per second while held
var cap := 0.0      # N, the most the hold gives
var held := false
## Fixed steps since the hold began.
var steps := 0


func _init(rate_n_per_s := 0.0, cap_n := 0.0) -> void:
	rate = rate_n_per_s
	cap = cap_n


func start() -> void:
	held = true
	steps = 0


func stop() -> void:
	held = false
	steps = 0


## One fixed step (call it before reading force() in the step).
func tick() -> void:
	if held:
		steps += 1


## The applied force now (N): rate x held time, at most cap; 0 when not held.
func force() -> float:
	if not held:
		return 0.0
	return minf(cap, rate * steps / float(Engine.physics_ticks_per_second))


## The gauge's fill (0..1 of cap).
func fraction() -> float:
	return force() / cap if cap > 0.0 else 0.0


## Seconds of holding until the force reaches `force_n` (INF beyond the cap).
func seconds_to(force_n: float) -> float:
	if force_n > cap or rate <= 0.0:
		return INF
	return force_n / rate
