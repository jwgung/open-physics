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
var pose_writes := 0               # times the bodies were moved (poses that changed, and forced ones)
var _has_pose := false


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
	pose(true)


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


## Beam and load on the model's state (the beam's centre is x = 0 on the level beam). The bodies are
## only moved when the pose changed (a held beam costs the engine nothing); `force` poses them
## anyway (a start, or the load was dragged by hand and must go back to the model's place).
func pose(force := false) -> void:
	var angle := model.angle()
	var beam_at_x := model.beam_x(0.0, 0.0)
	var beam_at_y := model.beam_y(0.0, 0.0)
	var load_at_x := model.beam_x(model.load_x, model.load_up)
	var load_at_y := model.beam_y(model.load_x, model.load_up)
	if not force and _has_pose and angle == _posed_angle and beam_at_x == _posed_beam[0] and beam_at_y == _posed_beam[1] \
			and load_at_x == _posed_load[0] and load_at_y == _posed_load[1]:
		return
	_has_pose = true
	pose_writes += 1
	_posed_angle = angle
	_posed_beam[0] = beam_at_x
	_posed_beam[1] = beam_at_y
	_posed_load[0] = load_at_x
	_posed_load[1] = load_at_y
	var turn := Basis(Vector3.BACK, angle)
	beam.global_transform = Transform3D(turn, Vector3(beam_at_x, beam_at_y, 0.0))
	load_body.global_transform = Transform3D(turn, Vector3(load_at_x, load_at_y, 0.0))
