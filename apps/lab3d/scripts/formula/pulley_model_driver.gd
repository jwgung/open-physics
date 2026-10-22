## Pulley (the "pulley" experiment): PulleyAdvantageChallenge. The load rises pull / n for a rope
## pull, up to max_lift; the required force is m g / n. The sample is the measured lift (m).
class_name PulleyModelDriver
extends KinematicModelCorrector

var base := Transform3D.IDENTITY   # load transform at lift 0
var load_mass := 20.0
var g := 9.81
var strands := 1                   # 1, 2 or 4 supporting strands
var pull_distance := 0.0           # rope pulled by the learner (m)
var max_lift := 4.0


func lift() -> float:
	return minf(max_lift, PhysicsLaws.pulley_lift_distance(pull_distance, strands))


func pose() -> Transform3D:
	return Transform3D(base.basis, base.origin + Vector3.UP * lift())


func measure() -> float:
	return body.global_position.y - base.origin.y


func formula_values() -> Dictionary:
	return {
		"required_force": PhysicsLaws.pulley_required_force(load_mass, g, strands),
		"lift": lift(),
		"pull_for_lift": PhysicsLaws.pulley_pull_distance(lift(), strands),
	}
