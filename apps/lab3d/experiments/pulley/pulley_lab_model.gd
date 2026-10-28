## Formula model of the pulley lab (Phase 1 Task 4e; web preset "pulley"): the web's
## PulleyAdvantageChallenge (src/app/mechanics-challenges.ts) - n = 1, 2 or 4 supporting strands,
## required force F = m g / n, the load rises d_pull / n for d_pull of rope pulled (up to max_lift).
## The rope is pulled hand over hand in strokes on a 5 cm grid (cells, CELLS_PER_M per metre);
## letting go keeps the rope (a ratchet at the guide wheel holds the load) and the next stroke adds
## to it. The hand's force `hand` (N) is the lab's input since 2026-10-28 (press and hold, HoldRamp):
## on the rope it is min(hand, F) while held (the rope moves only once it reaches F; F is all a
## steady pull needs). With no hand force given (INF: the TS vectors' strokes) the hand pulls with F
## while it holds a load off the ground (the web's graph), and 0 when the ratchet holds it.
## Pulled lengths are counted in whole cells, so the TS vectors and this model add the same numbers.
class_name PulleyLabModel
extends RefCounted

const CELLS_PER_M := 20            # the 5 cm handle grid (default; the lab sets cells_per_m from the definition's snap)

var cells_per_m := CELLS_PER_M     # handle cells per metre: 1 / the definition's handle snap
var strands := 1
var mass := 20.0
var g := 9.81
var max_lift := 2.4                # m: the load stops under the top block
var cells_before := 0              # rope pulled in earlier strokes (cells), held by the ratchet
var stroke_cells := 0              # the stroke the hand is pulling now (cells)
var holding := false               # the hand holds the rope
var hand := INF                    # N: the hand's force while holding (INF = "pulls with F", the strokes of the vectors)


func reset() -> void:
	cells_before = 0
	stroke_cells = 0


## Rope pulled so far (m).
func pulled() -> float:
	return (cells_before + stroke_cells) / float(cells_per_m)


## How far the load has risen (m): d_pull / n (PulleyAdvantageChallenge.liftDistanceForPull), at most max_lift.
func lift() -> float:
	return minf(max_lift, PhysicsLaws.pulley_lift_distance(pulled(), strands))


## The most the current stroke may pull (cells): the rest of the rope up to max_lift.
func stroke_limit() -> int:
	return maxi(0, roundi(PhysicsLaws.pulley_pull_distance(max_lift, strands) * cells_per_m) - cells_before)


## F = m g / n (PulleyAdvantageChallenge.requiredForce).
func required() -> float:
	return PhysicsLaws.pulley_required_force(mass, g, strands)


## The hand's pull (N): while holding, min(hand, F) (with no hand force given: F once the load is off
## the ground, else 0); 0 when not holding.
func applied() -> float:
	if not holding:
		return 0.0
	if is_finite(hand):
		return minf(hand, required())
	return required() if pulled() > 0.0 else 0.0


## Rope to pull for 1 m of lift (m): PulleyAdvantageChallenge.pullDistanceForLift(1).
func pull_per_metre() -> float:
	return PhysicsLaws.pulley_pull_distance(1.0, strands)


func weight() -> float:
	return PhysicsLaws.uniform_gravity_force(mass, g)


## Work of the hand F d_pull (J): the rope was pulled with F all the way.
func work_in() -> float:
	return PhysicsLaws.work_1d(required(), pulled())


## Potential energy the load gained, m g d_lift (J).
func work_out() -> float:
	return PhysicsLaws.gravitational_potential_energy(mass, g, lift())


## The stroke ends: the ratchet keeps the pulled rope.
func let_go() -> void:
	cells_before += stroke_cells
	stroke_cells = 0
	holding = false
