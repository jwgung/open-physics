## Model drive of one body (method "kinematic_model", Phase 1 Task 4d: spring, buoyancy, orbit): the
## body follows a BodyModel stepped at the fixed step, the way CollisionRailDriver drives the
## collision lab's balls (Task 4c). The body is a frozen kinematic RigidBody3D: each fixed step,
## before the physics server steps, the driver records where the engine has the body, advances the
## model one step and poses the body on it, so after the step the engine body stands where the
## formula says (float32 positions). Forces do not move it and it pushes nothing it does not touch.
## Why not force injection (Jolt integrates the formula force): measured against the formula over
## long runs, injection left the formula trajectory by more than 1e-4 m (numbers per lab in
## docs/formula-correction.md, Task 4d).
## The driver also keeps the measured motion: the engine position after each step (bounded like
## the samples; the latest one stays in last_engine), the worst |engine - model| position and the
## worst engine step velocity (displacement / dt) against the model's displacement / dt.
class_name BodyModelDriver
extends KinematicModelCorrector

var model: BodyModel
## Engine positions after each step since the reset (index k = after k steps, 0 = the start),
## at most history_steps of them; the latest is also in last_engine.
var engine: PackedVector3Array = PackedVector3Array()
var last_engine := Vector3.ZERO
var worst_position := 0.0
var worst_velocity := 0.0
var _posed := PackedFloat64Array([0.0, 0.0, 0.0])   # model position the body was posed on (64-bit)
var _from := PackedFloat64Array([0.0, 0.0, 0.0])    # model position before the last step


## Binds the model and the body (kinematic while driven) and poses it.
func bind(target_model: BodyModel, target: RigidBody3D) -> void:
	model = target_model
	attach(target)


## A new run from the model's current state (the body is posed there).
func reset() -> void:
	reset_history()
	engine.clear()
	worst_position = 0.0
	worst_velocity = 0.0
	body.global_transform = pose()
	last_engine = body.global_position


func step(dt: float) -> void:
	var at := body.global_position
	if steps > 0:
		var dx := Vector3(float(at.x) - _posed[0], float(at.y) - _posed[1], float(at.z) - _posed[2])
		worst_position = maxf(worst_position, maxf(absf(dx.x), maxf(absf(dx.y), absf(dx.z))))
		for i in 3:
			var moved := (float(at[i]) - float(last_engine[i])) / dt
			var want := (_posed[i] - _from[i]) / dt
			worst_velocity = maxf(worst_velocity, absf(moved - want))
	if engine.size() < history_steps:
		engine.append(at)
	last_engine = at
	super(dt)


func advance(dt: float) -> void:
	_from[0] = model.x
	_from[1] = model.y
	_from[2] = model.z
	model.step(dt)


func pose() -> Transform3D:
	_posed[0] = model.x
	_posed[1] = model.y
	_posed[2] = model.z
	return Transform3D(body.global_basis, model.position())


func measure() -> float:
	return model.engine_sample(body.global_position)
