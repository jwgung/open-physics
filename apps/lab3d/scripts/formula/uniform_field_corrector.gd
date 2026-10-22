## Uniform-field correction (method "uniform_field"): free fall and projectiles.
## Jolt integrates gravity itself with symplectic Euler (v += g dt, then x += v dt), which puts a
## released body at x0 + v0 t + g (t^2 + t dt) / 2: half a step ahead of the formula. The only
## correction is the leapfrog start: on the first released step a force of -m g / 2 cancels half of
## the engine gravity, after which the step positions equal constantAccelerationDisplacement
## exactly (to float32 position precision). Jolt keeps owning contacts (the floor, other bodies);
## the free-flight samples end at the first landing: a contact with a body the released body was
## not touching at release, or with a release surface after it has left it once (engine contact
## reports, get_colliding_bodies(): release() turns contact_monitor on when it is off). A body
## thrown from the floor or off a table edge therefore does not "land" on the surface it starts on.
## Displayed numbers (formula_values) come from PhysicsLaws at the sample time (until the contact),
## with the field the engine applies to the body (strength and direction, read on release).
class_name UniformFieldCorrector
extends FormulaCorrector

var origin := Vector3.ZERO
var initial_velocity := Vector3.ZERO
## Field strength (m/s^2) and direction the formulas use. release() sets them to the engine field on
## the body (get_gravity() * gravity_scale); a strength that equals the engine's to float32 rounding
## keeps its 64-bit value (the engine vector is 32-bit: 9.81 stays 9.81, not 9.8100004).
var g := 9.81
var field_direction := Vector3.DOWN
var mass := 1.0
var dt := 1.0 / 60.0
## True from release until the body lands (see the header).
var in_flight := false
## Step index of the landing (-1 = none yet).
var landed_step := -1
## offsets[k] = body position - origin after k steps (bounded like samples; samples hold y).
var offsets: PackedVector3Array = PackedVector3Array()
var _engine_field := Vector3.ZERO
## Bodies touching the released body at release (or, when the contact monitor was just turned on,
## after the first step); one leaves the set once the body is apart from it.
var _start_contacts: Array[Node3D] = []
var _seed_contacts := false   # contact_monitor was off at release: take the first report as the start


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
	var strength := float(_engine_field.length())
	if absf(strength - g) > 1e-6 * maxf(1.0, g):
		g = strength
	if strength > 0.0:
		var direction := _engine_field / strength
		if not direction.is_equal_approx(field_direction):
			field_direction = direction
	mass = body.mass
	in_flight = true
	landed_step = -1
	_seed_contacts = not body.contact_monitor
	if _seed_contacts:
		body.contact_monitor = true
		body.max_contacts_reported = maxi(body.max_contacts_reported, 4)
		_start_contacts.clear()
	else:
		_start_contacts.assign(body.get_colliding_bodies())
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = velocity


func apply(body: RigidBody3D, step_dt: float) -> void:
	dt = step_dt
	var offset := body.global_position - origin
	record(offset.y)
	if offsets.size() < history_steps:
		offsets.append(offset)
	if in_flight:
		_check_landing(body)
	var factor := start_factor(steps == 0)
	if factor != 1.0:
		body.apply_central_force((factor - 1.0) * mass * _engine_field)   # net force m g / 2 on the first step
	steps += 1


## Ends the free flight at a contact with a body that is not a release surface still being left.
## Contact reports describe the previous step, so a landing is found on the step after the touch.
func _check_landing(body: RigidBody3D) -> void:
	var touching := body.get_colliding_bodies()
	if _seed_contacts and steps == 1:
		_seed_contacts = false
		_start_contacts.assign(touching)
		return
	_start_contacts.assign(_start_contacts.filter(func(other: Node3D) -> bool: return touching.has(other)))
	for other in touching:
		if not _start_contacts.has(other):
			in_flight = false
			landed_step = steps
			return


## Time (s) of the last recorded sample, or of the landing (the formulas describe the free flight
## only).
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
