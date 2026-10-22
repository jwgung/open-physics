## Contact force correction (method "contact_force"): a body sliding on one known flat surface.
## Jolt has a single Coulomb coefficient (no static/kinetic split) and combines materials its own
## way, so the body and the surface use friction 0 in Jolt and this corrector applies the TS-core
## friction as a tangential force each fixed step. Jolt still owns the normal contact, integration
## and collisions. First case: the incline (spike S3, Task 2a); also the floor push of the
## "friction" experiment.
## Laws (PhysicsLaws ports):
##   "surface"  SurfaceContactFrictionModifier (corrected_tangential_force): gravity's tangential
##              component (+ an applied force) against static / kinetic friction (incline).
##   "push"     PushFrictionLaw (push_friction_force): a learner's applied force on a level floor.
## One discretisation correction: on the step where the body leaves rest only half of the net
## tangential force acts (leapfrog start), so positions follow s = a t^2 / 2 exactly.
class_name ContactFrictionCorrector
extends FormulaCorrector

const CONTACT_TOLERANCE := 0.02
const REST_SPEED := 0.01

var law := "surface"
var mu_s := 0.5
var mu_k := 0.4
## Surface frame: local +y is the surface normal, the top surface is at local y = 0, the contact
## patch spans |local x| <= half_length.
var surface: Node3D
## Direction of positive samples in the surface frame (incline: downhill = -x).
var tangent_axis := Vector3(-1.0, 0.0, 0.0)
var half_length := 4.0
var half_extent := 0.2         # body half height along the normal
## Learner-applied force along the tangent (N), injected by this corrector (law "push", or extra
## push on the "surface" law). Not an engine force.
var applied_force := 0.0

var status := "holding"
## The body centre is beyond either end of the surface patch: it has left the surface. Updated once
## per step in apply(); a brief loss of contact does not set it.
var past_end := false
var origin := Vector3.ZERO
## samples[k] / velocities[k] (base record()) = tangential displacement / velocity after k steps.
var max_offset := 0.0          # largest |displacement| (any direction) seen since release, m


func _init() -> void:
	method = "contact_force"


func reset(release_origin: Vector3) -> void:
	status = "holding"
	past_end = false
	origin = release_origin
	reset_history()
	max_offset = 0.0


func tangent() -> Vector3:
	return (surface.global_transform.basis * tangent_axis).normalized()


## Called from the body's _physics_process (FormulaBody), i.e. before the physics server steps,
## so the force lands in the same step.
func apply(body: RigidBody3D, dt: float) -> void:
	var position := body.global_position
	var velocity := body.linear_velocity
	var mass := body.mass
	var direction := tangent()
	record((position - origin).dot(direction), velocity.dot(direction))
	max_offset = maxf(max_offset, (position - origin).length())
	steps += 1
	var local := surface.global_transform.affine_inverse() * position
	past_end = absf(local.x) > half_length
	if not _in_contact(local):
		return
	var normal := surface.global_transform.basis.y.normalized()
	var gravity_force := body.get_gravity() * body.gravity_scale * mass
	var normal_load := maxf(0.0, -gravity_force.dot(normal))
	var engine_tangential := gravity_force.dot(direction)
	var tangential_speed := velocity.dot(direction)
	var corrected: float
	var holding: bool
	var rest_speed := PhysicsLaws.PUSH_REST_SPEED if law == "push" else REST_SPEED   # the incline keeps its 2a threshold
	if law == "push":
		var normal_acceleration := normal_load / mass
		corrected = engine_tangential + PhysicsLaws.push_friction_force(
			applied_force, tangential_speed, mass, mu_s, mu_k, normal_acceleration, dt)
		holding = PhysicsLaws.push_friction_holding(applied_force, tangential_speed, mass, mu_s, normal_acceleration)
	else:
		corrected = PhysicsLaws.corrected_tangential_force(
			engine_tangential + applied_force, tangential_speed, normal_load, mu_s, mu_k, mass, dt)
		holding = absf(tangential_speed) < REST_SPEED and corrected == 0.0
	corrected *= start_factor(status == "holding" and not holding and absf(tangential_speed) < rest_speed)
	status = "holding" if holding else "sliding"
	body.apply_central_force(direction * (corrected - engine_tangential))


## `local` = the body position in the surface frame.
func _in_contact(local: Vector3) -> bool:
	return absf(local.y - half_extent) <= CONTACT_TOLERANCE and absf(local.x) <= half_length


func formula_values() -> Dictionary:
	return {"mu_s": mu_s, "mu_k": mu_k, "applied_force": applied_force}


func engine_values() -> Dictionary:
	return {"distance": last_sample, "velocity": last_velocity, "status": status, "past_end": past_end}
