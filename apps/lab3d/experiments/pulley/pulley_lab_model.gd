## Formula model of the pulley lab (Phase 1 Task 4e; web preset "pulley"): the web's
## PulleyAdvantageChallenge (src/app/mechanics-challenges.ts) - n = 1, 2 or 4 supporting strands,
## required force F = m g / n, the load rises d_pull / n for d_pull of rope pulled (up to max_lift).
## The rope is pulled hand over hand: the grip is pulled down in strokes on a 5 cm grid (the handle's
## cells, CELLS_PER_M per metre); letting go keeps the rope (a ratchet at the guide wheel holds the
## load) and the next stroke adds to it. The hand pulls with F while it holds a load off the ground
## (the web's graph: the required force once the rope was pulled), 0 when the ratchet holds it.
## Pulled lengths are counted in whole cells, so the TS vectors and this model add the same numbers.
class_name PulleyLabModel
extends RefCounted

const CELLS_PER_M := 20            # 5 cm handle grid

var strands := 1
var mass := 20.0
var g := 9.81
var max_lift := 2.4                # m: the load stops under the top block
var cells_before := 0              # rope pulled in earlier strokes (cells), held by the ratchet
var stroke_cells := 0              # the stroke the hand is pulling now (cells)
var holding := false               # the hand holds the grip


func reset() -> void:
	cells_before = 0
	stroke_cells = 0


## Rope pulled so far (m).
func pulled() -> float:
	return (cells_before + stroke_cells) / float(CELLS_PER_M)


## How far the load has risen (m): d_pull / n (PulleyAdvantageChallenge.liftDistanceForPull), at most max_lift.
func lift() -> float:
	return minf(max_lift, PhysicsLaws.pulley_lift_distance(pulled(), strands))


## The most the current stroke may pull (cells): the rest of the rope up to max_lift.
func stroke_limit() -> int:
	return maxi(0, roundi(PhysicsLaws.pulley_pull_distance(max_lift, strands) * CELLS_PER_M) - cells_before)


## F = m g / n (PulleyAdvantageChallenge.requiredForce).
func required() -> float:
	return PhysicsLaws.pulley_required_force(mass, g, strands)


## The hand's pull (N): F while it holds the load off the ground, else 0.
func applied() -> float:
	return required() if holding and pulled() > 0.0 else 0.0


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
