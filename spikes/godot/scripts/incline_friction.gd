## Formula correction layer for S3 (guided incline friction).
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
var steps := 0
var origin := Vector3.ZERO
## samples[k] = downhill displacement (m) after k steps since release; velocities likewise.
var samples: PackedFloat64Array = PackedFloat64Array()
var velocities: PackedFloat64Array = PackedFloat64Array()
var max_offset := 0.0          # largest |displacement| (any direction) seen since release, m


func reset(release_origin: Vector3) -> void:
	status = "holding"
	steps = 0
	origin = release_origin
	samples.clear()
	velocities.clear()
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
	samples.append((position - origin).dot(tangent))
	velocities.append(velocity.dot(tangent))
	max_offset = maxf(max_offset, (position - origin).length())
	steps += 1
	if not _in_contact(position):
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


func _in_contact(position: Vector3) -> bool:
	var local := incline.global_transform.affine_inverse() * position
	return absf(local.y - half_extent) <= CONTACT_TOLERANCE and absf(local.x) <= half_length
