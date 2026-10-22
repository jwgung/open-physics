## Model drive of several bodies at once (method "kinematic_model", Phase 1 Task 4e): one
## BodyModelDriver per body, stepped and reset together, so a ModelDrivenLab with more than one
## moving body (the constraints lab's string and rod bobs) keeps a single `driver`. Each member
## keeps its own engine measurements; worst_position / worst_velocity are the largest of them.
class_name BodyModelGroupDriver
extends FormulaCorrector

var members: Array[BodyModelDriver] = []


func _init() -> void:
	method = "kinematic_model"


## A member driving `body` on `model` (bound and posed now); `history` = its kept engine steps.
func add(model: BodyModel, body: RigidBody3D, history: int) -> BodyModelDriver:
	var member := BodyModelDriver.new()
	member.history_steps = history
	member.bind(model, body)
	members.append(member)
	return member


## A new run of every member from its model's current state.
func reset() -> void:
	reset_history()
	for member in members:
		member.reset()


func step(dt: float) -> void:
	steps += 1
	for member in members:
		member.step(dt)


## Largest |engine - model| position (m) of any member since the reset.
func worst_position() -> float:
	var worst := 0.0
	for member in members:
		worst = maxf(worst, member.worst_position)
	return worst


## Largest step-velocity difference (m/s) of any member since the reset.
func worst_velocity() -> float:
	var worst := 0.0
	for member in members:
		worst = maxf(worst, member.worst_velocity)
	return worst
