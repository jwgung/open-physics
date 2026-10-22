## Lever (the "rotation" experiment): LeverChallenge. The beam turns about the pivot to the lift
## angle when the applied force reaches the required force F = m g r_load / r_effort, else lies
## level (the web app's 0 / 0.18 rad). The sample is the beam angle measured from the body.
class_name LeverModelDriver
extends KinematicModelCorrector

const LIFT_ANGLE := PhysicsLaws.LEVER_LIFT_ANGLE   # rad, web LEVER_LIFT_ANGLE

var pivot := Transform3D.IDENTITY  # beam rotates about the pivot's local z; beam centre at the pivot
var load_mass := 20.0
var g := 9.81
var load_arm := 1.0
var effort_arm := 2.0
var applied_force := 0.0
var angle := 0.0


func required_force() -> float:
	return PhysicsLaws.lever_required_force(load_mass, g, load_arm, effort_arm)


func lifting() -> bool:
	return PhysicsLaws.lever_lifting(applied_force, required_force())


func advance(_dt: float) -> void:
	# The load side (local -x) goes up when lifting: positive rotation about z raises +x, so negative.
	angle = -LIFT_ANGLE if lifting() else 0.0


func pose() -> Transform3D:
	return pivot * Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)


func measure() -> float:
	var beam_x := pivot.basis.inverse() * body.global_transform.basis.x
	return atan2(beam_x.y, beam_x.x)


func formula_values() -> Dictionary:
	var required := required_force()
	return {
		"required_force": required,
		"mechanical_advantage": PhysicsLaws.lever_mechanical_advantage(load_arm, effort_arm),
		"lifting": lifting(),
		"load_torque": PhysicsLaws.torque_2d(-load_arm, 0.0, 0.0, -PhysicsLaws.uniform_gravity_force(load_mass, g)),
		"effort_torque": PhysicsLaws.torque_2d(effort_arm, 0.0, 0.0, -maxf(0.0, applied_force)),
	}
