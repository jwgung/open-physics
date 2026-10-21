## Formula correction layer for the incline friction experiment, copied from
## spikes/godot/scripts/incline_friction.gd (spike S3). Task 3 generalises this layer.
## Jolt has one Coulomb friction coefficient and no static/kinetic split, so the box and incline use
## friction 0 in Jolt and this layer applies the TS-core friction model (PhysicsLaws port of
## SurfaceContactFrictionModifier) as a tangential force each fixed step. Jolt still owns the normal
## contact, integration and collisions. One discretisation correction: on the step where the box
## leaves rest, only half of the net tangential force is applied (leapfrog start), so Jolt's
## symplectic Euler positions equal s = a t^2 / 2 exactly instead of a (t^2 + t dt) / 2.
class_name InclineFrictionCorrector
extends RefCounted

const CONTACT_TOLERANCE := 0.02
const REST_SPEED := 0.01

var mu_s := 0.5
var mu_k := 0.4
var incline: Node3D            # pivot whose local +y is the surface normal, top surface at local y = 0
var half_length := 4.0
var half_extent := 0.2         # box half height along the normal
var leapfrog_start := true

var status := "holding"
## The box centre is beyond either end of the incline (its length is half_length * 2): the box has
## left the incline. Updated once per step in apply(); a brief loss of contact does not set it.
var past_end := false
var steps := 0
var origin := Vector3.ZERO
## samples[k] = downhill displacement (m) after k steps since release; velocities likewise.
## Only the first `history_steps` entries are kept (the graph window / tests); later steps update
## last_sample / last_velocity only, so a long run does not grow the arrays.
var samples: PackedFloat64Array = PackedFloat64Array()
var velocities: PackedFloat64Array = PackedFloat64Array()
var history_steps := 600
var last_sample := 0.0
var last_velocity := 0.0
var max_offset := 0.0          # largest |displacement| (any direction) seen since release, m


func reset(release_origin: Vector3) -> void:
	status = "holding"
	past_end = false
	steps = 0
	origin = release_origin
	samples.clear()
	velocities.clear()
	last_sample = 0.0
	last_velocity = 0.0
	max_offset = 0.0


func downhill() -> Vector3:
	return -incline.global_transform.basis.x.normalized()


## Called from the body's _physics_process, i.e. before the physics server steps, so the force
## lands in the same step. (Godot-Jolt runs _integrate_forces after the step: its force would
## only reach the next step, letting the first released step slide uncorrected.)
func apply(body: RigidBody3D, dt: float) -> void:
	var position := body.global_position
	var velocity := body.linear_velocity
	var mass := body.mass
	var tangent := downhill()
	last_sample = (position - origin).dot(tangent)
	last_velocity = velocity.dot(tangent)
	if samples.size() < history_steps:
		samples.append(last_sample)
		velocities.append(last_velocity)
	max_offset = maxf(max_offset, (position - origin).length())
	steps += 1
	var local := incline.global_transform.affine_inverse() * position
	past_end = absf(local.x) > half_length
	if not _in_contact(local):
		return
	var normal := incline.global_transform.basis.y.normalized()
	var gravity_force := body.get_gravity() * body.gravity_scale * mass
	var normal_load := maxf(0.0, -gravity_force.dot(normal))
	var tangential_force := gravity_force.dot(tangent)
	var tangential_speed := velocity.dot(tangent)
	var corrected := PhysicsLaws.corrected_tangential_force(
		tangential_force, tangential_speed, normal_load, mu_s, mu_k, mass, dt)
	var holding := absf(tangential_speed) < REST_SPEED and corrected == 0.0
	if leapfrog_start and status == "holding" and not holding and absf(tangential_speed) < REST_SPEED:
		corrected *= 0.5
	status = "holding" if holding else "sliding"
	body.apply_central_force(tangent * (corrected - tangential_force))


## `local` = the box position in the incline pivot's frame.
func _in_contact(local: Vector3) -> bool:
	return absf(local.y - half_extent) <= CONTACT_TOLERANCE and absf(local.x) <= half_length
