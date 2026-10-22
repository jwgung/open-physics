## Model drive of the pulley lab's load (method "kinematic_model", Phase 1 Task 4e): a frozen
## kinematic body posed each fixed step at its ground place raised by PulleyLabModel.lift(), the way
## the web app poses its load. Before posing, the driver measures where the engine has it against the
## pose of the step before (worst_position since the reset); samples = the engine lift after each step.
class_name PulleyLabDriver
extends FormulaCorrector

var model: PulleyLabModel
var load_body: RigidBody3D
var base := Vector3.ZERO           # load centre on the ground (lift 0)
var worst_position := 0.0
var _posed := 0.0                  # model lift the load was posed on (64-bit)
var pose_writes := 0               # times the bodies were moved (poses that changed, and forced ones)
var _has_pose := false


func _init() -> void:
	method = "kinematic_model"


func attach(target_model: PulleyLabModel, target: RigidBody3D, ground: Vector3) -> void:
	model = target_model
	load_body = target
	base = ground
	load_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	load_body.freeze = true
	reset()


func reset() -> void:
	reset_history()
	worst_position = 0.0
	pose(true)


## The engine load's lift above its ground place (m).
func engine_lift() -> float:
	return load_body.global_position.y - base.y


func step(_dt: float) -> void:
	var at := load_body.global_position
	if steps > 0:
		worst_position = maxf(worst_position, maxf(absf(float(at.y) - (base.y + _posed)), maxf(absf(at.x - base.x), absf(at.z - base.z))))
	record(engine_lift())
	steps += 1
	pose()


## The load at the model's lift; only moved when the lift changed (a held load costs the engine
## nothing), or with `force` (a start).
func pose(force := false) -> void:
	var lift := model.lift()
	if not force and _has_pose and lift == _posed:
		return
	_has_pose = true
	pose_writes += 1
	_posed = lift
	load_body.global_transform = Transform3D(Basis(), Vector3(base.x, base.y + _posed, base.z))
