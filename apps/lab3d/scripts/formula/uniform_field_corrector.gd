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
## The release contacts are the report of the first released step: before it the body was frozen
## (a static body reports nothing) or the report is the previous run's, so neither is read. A
## surface first touched within that step therefore counts as a release surface too. With
## `surfaces` set, only those bodies (the ground: floor, the lab's surfaces) can be landed on;
## another ball touched in the air is not a landing.
## Displayed numbers (formula_values) come from PhysicsLaws at the sample time (until the contact),
## with the field the engine applies to the body (strength and direction, read on release).
## Optional `rolling` (Task 4f, the guided labs' balls): from the formula landing time on, a 64-bit
## model of the bounces, slide, roll and stop on the level floor puts the body on its path every
## step (RollingContact); the body has no engine friction or bounce and turns freely. The landing
## step is then the first sample at or after the formula touch (the engine never reaches the floor
## to report it).
class_name UniformFieldCorrector
extends FormulaCorrector

var origin := Vector3.ZERO
var initial_velocity := Vector3.ZERO
## Field strength (m/s^2) and direction the formulas use. release() sets them to the engine field on
## the body (get_gravity(), which already includes gravity_scale and area gravity: Godot 4.7 + Jolt,
## measured in tests/formula_checks.gd); a strength that equals the engine's to float32 rounding
## keeps its 64-bit value (the engine vector is 32-bit: 9.81 stays 9.81, not 9.8100004).
var g := 9.81
var field_direction := Vector3.DOWN
var mass := 1.0
## Fixed-step length (s): set on release from Engine.physics_ticks_per_second (so a reading between
## the release and the first step already uses the real step), then from each step's delta.
var dt := 1.0 / 60.0
## True from release until the body lands (see the header).
var in_flight := false
## Step index of the landing (-1 = none yet).
var landed_step := -1
## offsets[k] = body position - origin after k steps (bounded like samples; samples hold y).
var offsets: PackedVector3Array = PackedVector3Array()
var _engine_field := Vector3.ZERO
## Bodies a landing can be on (the ground); empty = any body.
var surfaces: Array[Node3D] = []
## Formula ground friction and spin of a ball (null: the engine's contacts alone).
var rolling: RollingContact = null
## Bodies touching the released body after its first released step (see the header); one leaves the
## set once the body is apart from it.
var _start_contacts: Array[Node3D] = []


func _init() -> void:
	method = "uniform_field"


## Releases `body` from its current position with `velocity` (call before the step, e.g. from
## _physics_process or right after awaiting physics_frame).
func release(body: RigidBody3D, velocity: Vector3) -> void:
	reset_history()
	offsets.clear()
	origin = body.global_position
	initial_velocity = velocity
	_engine_field = body.get_gravity()
	var strength := float(_engine_field.length())
	if absf(strength - g) > 1e-6 * maxf(1.0, g):
		g = strength
	if strength > 0.0:
		var direction := _engine_field / strength
		if not direction.is_equal_approx(field_direction):
			field_direction = direction
	mass = body.mass
	dt = 1.0 / float(Engine.physics_ticks_per_second)
	in_flight = true
	landed_step = -1
	_start_contacts.clear()   # seeded from the first released step's report (_check_landing)
	body.max_contacts_reported = maxi(body.max_contacts_reported, 4)   # 0 (the default) reports nothing
	if not body.contact_monitor:
		body.contact_monitor = true
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = velocity
	if rolling:
		rolling.release(body, velocity, g)


func apply(body: RigidBody3D, step_dt: float) -> void:
	dt = step_dt
	var factor := start_factor(steps == 0)
	var offset := body.global_position - origin
	record(offset.y)
	if offsets.size() < history_steps:
		offsets.append(offset)
	if in_flight:
		_check_landing(body)
	if rolling:
		rolling.apply(body, steps, step_dt, _engine_field * factor * step_dt)
		if rolling.active:
			in_flight = false     # the floor contact is the model's from here
			var touch := rolling.landing_step(dt)
			if landed_step < 0 and touch >= 0 and steps >= touch:
				landed_step = touch   # the first sample at or after the formula touch
	if factor != 1.0:
		body.apply_central_force((factor - 1.0) * mass * _engine_field)   # net force m g / 2 on the first step
	steps += 1


## Ends the free flight at a contact with a ground body (`surfaces`, or any body when empty) that
## is not a release surface still being left. Contact reports describe the previous step, so a
## landing is found on the step after the touch.
func _check_landing(body: RigidBody3D) -> void:
	if steps == 0:
		return   # the report is from before the release (frozen, or the previous run)
	var touching := body.get_colliding_bodies()
	if steps == 1:
		_start_contacts.assign(touching)   # the first released step: the release contacts
		return
	_start_contacts.assign(_start_contacts.filter(func(other: Node3D) -> bool: return touching.has(other)))
	for other in touching:
		if not _start_contacts.has(other) and (surfaces.is_empty() or surfaces.has(other)):
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
