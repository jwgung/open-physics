## Model drive of the collision lab's two balls (method "kinematic_model", Phase 1 Task 4c): the
## balls follow CollisionModel (the web's collision preset on the TS world, 64-bit) step by step, the
## way the web app moves its circles. Both balls are kinematic (frozen RigidBody3D, FREEZE_MODE_KINEMATIC)
## while a run goes: each fixed step, before the physics server steps, the driver records where the
## engine has the balls (the measured motion), advances the model one step and poses the balls on it,
## so after the step the engine balls stand where the formula says (float32 positions, about 5e-7 m).
## Jolt does not resolve the A-B contact (a collision exception): the formula decides when the balls
## touch and what the hit does. Why not the collision corrector (Jolt contact + formula velocities):
## its balls left the formula trajectory by up to 0.084 m around the hit (Jolt's speculative contact
## changes the contact steps' positions) and 0.23 m after 5 s (docs/formula-correction.md, Task 4c).
## Visual rolling is not here: the props spin a child mesh, the bodies keep their basis.
class_name CollisionRailDriver
extends FormulaCorrector

var model: CollisionModel
var ball_a: RigidBody3D
var ball_b: RigidBody3D
## Engine centres along the rail after each step since the release (index k = after k steps; index 0
## = the start). Bounded by history_steps like samples (a run goes on after that; the step before
## the latest one is kept in last_engine, like FormulaCorrector.last_sample).
var engine_a: PackedFloat64Array = PackedFloat64Array()
var engine_b: PackedFloat64Array = PackedFloat64Array()
## Largest |engine - model| position (m) and step velocity (m/s: engine displacement over a step / dt
## against the model velocity that step moved with) seen since the reset; push-out and wall steps
## (the formula moves the ball there without its velocity) count only for the position.
var last_engine := PackedFloat64Array([0.0, 0.0])
var worst_position := 0.0
var worst_velocity := 0.0
var _posed := PackedFloat64Array([0.0, 0.0])     # model centres the balls were posed on
var _step_v := PackedFloat64Array([0.0, 0.0])    # model velocities the posed step moved with
var _free_step := false                          # that step moved both balls by their velocity only


func _init() -> void:
	method = "kinematic_model"


## Binds the balls (kinematic while driven, never touching each other in the engine).
func attach(target_model: CollisionModel, a: RigidBody3D, b: RigidBody3D) -> void:
	model = target_model
	ball_a = a
	ball_b = b
	for ball in [a, b]:
		ball.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		ball.freeze = true
	a.add_collision_exception_with(b)


## A new run from the model's current state (the balls are posed there).
func reset() -> void:
	reset_history()
	engine_a.clear()
	engine_b.clear()
	last_engine = PackedFloat64Array([ball_a.global_position.x, ball_b.global_position.x])
	worst_position = 0.0
	worst_velocity = 0.0
	_pose()


func step(dt: float) -> void:
	var xa := float(ball_a.global_position.x)
	var xb := float(ball_b.global_position.x)
	if steps > 0:
		# The engine after this many steps against the model state it was posed on.
		worst_position = maxf(worst_position, maxf(absf(xa - _posed[0]), absf(xb - _posed[1])))
		if _free_step:
			var moved_a := (xa - last_engine[0]) / dt
			var moved_b := (xb - last_engine[1]) / dt
			worst_velocity = maxf(worst_velocity, maxf(absf(moved_a - _step_v[0]), absf(moved_b - _step_v[1])))
	if engine_a.size() < history_steps:
		engine_a.append(xa)
		engine_b.append(xb)
	last_engine[0] = xa
	last_engine[1] = xb
	record(xb - xa)
	steps += 1
	_step_v[0] = model.va
	_step_v[1] = model.vb
	var from_a := _posed[0]
	var from_b := _posed[1]
	model.step(dt)
	# A step that moved both balls by their velocity only (no push-out, no wall): x' = x + v dt.
	_free_step = absf(model.xa - (from_a + _step_v[0] * dt)) < 1e-12 and absf(model.xb - (from_b + _step_v[1] * dt)) < 1e-12
	_pose()


## Puts the balls on the model's centres (rail axis x; y and z stay).
func _pose() -> void:
	_posed[0] = model.xa
	_posed[1] = model.xb
	ball_a.global_position = Vector3(model.xa, ball_a.global_position.y, ball_a.global_position.z)
	ball_b.global_position = Vector3(model.xb, ball_b.global_position.y, ball_b.global_position.z)


## Engine values: the balls' centres now and the momentum of their last engine step (kg m/s).
func engine_values() -> Dictionary:
	if steps < 2:
		return {"momentum": 0.0}
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var va := (float(ball_a.global_position.x) - last_engine[0]) / dt
	var vb := (float(ball_b.global_position.x) - last_engine[1]) / dt
	return {"momentum": model.mass_a * va + model.mass_b * vb}
