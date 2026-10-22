## Spring experiment: AnchoredSpringLaw (F = -k x - b v_r along the anchor-body line) injected each
## step. The sample is the extension x (m). Displayed energies use the TS definitions (web
## physics-playground: kinetic m v^2 / 2, spring k x^2 / 2 about the rest length; gravity's m g h is
## a separate panel value):
## - no damping and no engine gravity (energy conserved): total E = k A^2 / 2 for the release
##   amplitude A, spring energy from the measured x, kinetic = the rest;
## - otherwise (damping, or a hanging spring under gravity): energies of the current state, kinetic
##   from the step-synchronised speed of the sample and total = kinetic + spring.
## The damping term uses the engine's linear_velocity, which is v_(k-1/2), half a step behind the
## position; a position difference (x_k - x_(k-1)) / dt gives the same value under symplectic Euler,
## and a step-point velocity would need the force it is part of, so it is kept (damping rate exact
## to first order in dt; docs/formula-correction.md, limits).
class_name SpringInjector
extends ForceInjectionCorrector

var anchor := Vector3.ZERO
var rest_length := 1.0
var stiffness := 5.0
var damping := 0.0
var amplitude := 0.0   # extension at release
var _speed := 0.0      # step-synchronised speed (m/s) of the last sample


func reset(body: RigidBody3D) -> void:
	super(body)
	amplitude = extension(body)
	last_sample = amplitude   # state before the first step (not recorded)
	_speed = body.linear_velocity.length()


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
	# Before the first step the engine velocity is the release velocity itself (not half a step behind).
	_speed = (body.linear_velocity if steps == 0 else synced_velocity(body)).length()
	return extension(body)


func formula_values() -> Dictionary:
	var spring := PhysicsLaws.spring_potential_energy(stiffness, last_sample)
	var omega := PhysicsLaws.angular_frequency(stiffness, mass)
	var total: float
	var kinetic: float
	if damping == 0.0 and engine_gravity == Vector3.ZERO:
		total = PhysicsLaws.harmonic_energy(stiffness, amplitude)
		kinetic = maxf(0.0, total - spring)
	else:
		kinetic = PhysicsLaws.kinetic_energy(mass, _speed)
		total = kinetic + spring
	return {
		"period": PhysicsLaws.period_from_angular_frequency(omega),
		"total_energy": total,
		"spring_energy": spring,
		"kinetic_energy": kinetic,
	}


## Energy of the engine state (step-synchronised velocity), for checks and a labelled readout.
func engine_energy(body: RigidBody3D) -> float:
	return PhysicsLaws.kinetic_energy(mass, synced_velocity(body).length()) \
		+ PhysicsLaws.spring_potential_energy(stiffness, extension(body))
