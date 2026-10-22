## Uniform-field correction (method "uniform_field"): free fall and projectiles.
## Jolt integrates gravity itself with symplectic Euler (v += g dt, then x += v dt), which puts a
## released body at x0 + v0 t + g (t^2 + t dt) / 2: half a step ahead of the formula. The only
## correction is the leapfrog start: on the first released step a force of -m g / 2 cancels half of
## the engine gravity, after which the step positions equal constantAccelerationDisplacement
## exactly (to float32 position precision). Jolt keeps owning contacts (the floor, other bodies);
## the free-flight samples end at the first contact (needs contact_monitor on the body).
## Displayed numbers (formula_values) come from PhysicsLaws at the sample time (until the contact).
class_name UniformFieldCorrector
extends FormulaCorrector

var origin := Vector3.ZERO
var initial_velocity := Vector3.ZERO
## Field strength (m/s^2) and direction the formulas use (64-bit; the engine's own gravity vector
## is 32-bit, so it is used only for the start correction).
var g := 9.81
var field_direction := Vector3.DOWN
var mass := 1.0
var dt := 1.0 / 60.0
## True from release until the body first touches anything.
var in_flight := false
## Step index of the first contact (-1 = none yet).
var landed_step := -1
## offsets[k] = body position - origin after k steps (bounded like samples; samples hold y).
var offsets: PackedVector3Array = PackedVector3Array()
var _engine_field := Vector3.ZERO


func _init() -> void:
	method = "uniform_field"


## Releases `body` from its current position with `velocity` (call before the step, e.g. from
## _physics_process or right after awaiting physics_frame).
func release(body: RigidBody3D, velocity: Vector3) -> void:
	reset_history()
	offsets.clear()
	origin = body.global_position
	initial_velocity = velocity
	_engine_field = body.get_gravity() * body.gravity_scale
	mass = body.mass
	in_flight = true
	landed_step = -1
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = velocity


func apply(body: RigidBody3D, step_dt: float) -> void:
	dt = step_dt
	var offset := body.global_position - origin
	record(offset.y)
	if offsets.size() < history_steps:
		offsets.append(offset)
	if in_flight and body.contact_monitor and body.get_contact_count() > 0:
		in_flight = false
		landed_step = steps
	if steps == 0 and leapfrog_start:
		body.apply_central_force(-0.5 * mass * _engine_field)   # net force m g / 2 on the first step
	steps += 1


## Time (s) of the last recorded sample, or of the first contact (the formulas describe the free
## flight only).
func time() -> float:
	return (landed_step if landed_step >= 0 else maxi(0, steps - 1)) * dt


func formula_values() -> Dictionary:
	var t := time()
	var a := [field_direction.x * g, field_direction.y * g, field_direction.z * g]
	var vx := PhysicsLaws.constant_acceleration_velocity(initial_velocity.x, a[0], t)
	var vy := PhysicsLaws.constant_acceleration_velocity(initial_velocity.y, a[1], t)
	var vz := PhysicsLaws.constant_acceleration_velocity(initial_velocity.z, a[2], t)
	var speed := sqrt(vx * vx + vy * vy + vz * vz)
	var height := PhysicsLaws.constant_acceleration_displacement(initial_velocity.y, a[1], t)
	return {
		"time": t,
		"x": PhysicsLaws.constant_acceleration_displacement(initial_velocity.x, a[0], t),
		"y": height,
		"z": PhysicsLaws.constant_acceleration_displacement(initial_velocity.z, a[2], t),
		"speed": speed,
		"kinetic_energy": PhysicsLaws.kinetic_energy(mass, speed),
		"momentum": PhysicsLaws.momentum(mass, speed),
	}


func engine_values() -> Dictionary:
	return {"offset": offsets[-1] if offsets.size() > 0 else Vector3.ZERO, "in_flight": in_flight, "landed_step": landed_step}
