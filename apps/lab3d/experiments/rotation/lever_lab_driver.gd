## Model drive of the lever lab's beam and load (method "kinematic_model", Phase 1 Task 4e): both are
## frozen kinematic bodies posed from LeverLabModel each fixed step (the beam turned about the
## fulcrum to the model's angle, the load riding on it), the way the web app poses its lever. Before
## posing, the driver measures where the engine has them (the beam's angle from its basis, the
## load's centre) against the pose of the step before: worst_angle / worst_position since the reset.
## samples = the engine beam angle after each step (bounded history).
class_name LeverLabDriver
extends FormulaCorrector

var model: LeverLabModel
var beam: RigidBody3D
var load_body: RigidBody3D
var worst_angle := 0.0
var worst_position := 0.0
var _posed_angle := 0.0
var _posed_load := PackedFloat64Array([0.0, 0.0])
var _posed_beam := PackedFloat64Array([0.0, 0.0])


func _init() -> void:
	method = "kinematic_model"


func attach(target_model: LeverLabModel, target_beam: RigidBody3D, target_load: RigidBody3D) -> void:
	model = target_model
	beam = target_beam
	load_body = target_load
	for body in [beam, load_body]:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
	reset()


## A new run: history and worst values cleared, the bodies posed on the model now.
func reset() -> void:
	reset_history()
	worst_angle = 0.0
	worst_position = 0.0
	pose()


## The engine beam's angle about +z (rad), from its basis.
func engine_angle() -> float:
	var x := beam.global_basis.x
	return atan2(x.y, x.x)


func step(_dt: float) -> void:
	var a := engine_angle()
	if steps > 0:
		worst_angle = maxf(worst_angle, absf(a - _posed_angle))
		var l := load_body.global_position
		var b := beam.global_position
		worst_position = maxf(worst_position, maxf(absf(l.x - _posed_load[0]), absf(l.y - _posed_load[1])))
		worst_position = maxf(worst_position, maxf(absf(b.x - _posed_beam[0]), absf(b.y - _posed_beam[1])))
	record(a)
	steps += 1
	pose()


## Beam and load on the model's state (the beam's centre is x = 0 on the level beam).
func pose() -> void:
	_posed_angle = model.angle()
	var turn := Basis(Vector3.BACK, _posed_angle)
	_posed_beam[0] = model.beam_x(0.0, 0.0)
	_posed_beam[1] = model.beam_y(0.0, 0.0)
	_posed_load[0] = model.beam_x(model.load_x, model.load_up)
	_posed_load[1] = model.beam_y(model.load_x, model.load_up)
	beam.global_transform = Transform3D(turn, Vector3(_posed_beam[0], _posed_beam[1], 0.0))
	load_body.global_transform = Transform3D(turn, Vector3(_posed_load[0], _posed_load[1], 0.0))
