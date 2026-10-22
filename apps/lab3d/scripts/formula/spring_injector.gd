## Spring experiment: AnchoredSpringLaw (F = -k x - b v_r along the anchor-body line) injected each
## step. The sample is the extension x (m). Displayed energies come from the formula: total
## E = k A^2 / 2 for the release amplitude A, spring energy k x^2 / 2 from the measured x, motion
## energy = the rest (no damping); with damping the total is the formula energy of the current state.
class_name SpringInjector
extends ForceInjectionCorrector

var anchor := Vector3.ZERO
var rest_length := 1.0
var stiffness := 5.0
var damping := 0.0
var amplitude := 0.0   # extension at release


func reset(body: RigidBody3D) -> void:
	super(body)
	amplitude = extension(body)


func extension(body: RigidBody3D) -> float:
	return (body.global_position - anchor).length() - rest_length


func formula_force(body: RigidBody3D) -> Vector3:
	var offset := body.global_position - anchor
	var length := offset.length()
	if length == 0.0:
		return Vector3.ZERO
	var direction := offset / length
	var radial := body.linear_velocity.dot(direction)
	return direction * PhysicsLaws.anchored_spring_force(length - rest_length, radial, stiffness, damping)


func sample(body: RigidBody3D) -> float:
	return extension(body)


func formula_values() -> Dictionary:
	var total := PhysicsLaws.harmonic_energy(stiffness, amplitude)
	var spring := PhysicsLaws.spring_potential_energy(stiffness, last_sample)
	var omega := PhysicsLaws.angular_frequency(stiffness, mass)
	return {
		"period": PhysicsLaws.period_from_angular_frequency(omega),
		"total_energy": total,
		"spring_energy": spring,
		"kinetic_energy": maxf(0.0, total - spring),
	}


## Energy of the engine state (step-synchronised velocity), for checks and a labelled readout.
func engine_energy(body: RigidBody3D) -> float:
	return PhysicsLaws.kinetic_energy(mass, synced_velocity(body).length()) \
		+ PhysicsLaws.spring_potential_energy(stiffness, extension(body))
