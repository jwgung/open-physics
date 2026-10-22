## Kinematic model drive (method "kinematic_model"): the experiment's moving part follows a formula
## model stepped at the fixed step (PendulumModel, LeverChallenge, PulleyAdvantageChallenge), the
## same way the web app poses these bodies. The body is kinematic (RigidBody3D frozen in
## FREEZE_MODE_KINEMATIC, or an AnimatableBody3D): Jolt moves it to the posed transform during the
## step and still pushes dynamic bodies it touches, but forces do not move it. Jolt joints were
## measured and rejected for these (docs/formula-correction.md): a PinJoint3D pendulum keeps its
## length to 0.1 mm but loses 1.3% of its amplitude in 30 s (constraint solver damping), and the
## web model's own damping and angle curve would not be reproduced.
## Each step: record the measured quantity of the body (after k steps), advance the model one
## step, pose the body for the coming physics step. Subclasses implement advance(), pose(),
## measure().
class_name KinematicModelCorrector
extends FormulaCorrector

var body: PhysicsBody3D


func _init() -> void:
	method = "kinematic_model"


## Makes `target` kinematic, resets the model state and poses it.
func attach(target: PhysicsBody3D) -> void:
	body = target
	if body is RigidBody3D:
		var rigid := body as RigidBody3D
		rigid.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rigid.freeze = true
	reset_history()
	body.global_transform = pose()


func step(dt: float) -> void:
	_record_step(dt)
	steps += 1
	advance(dt)
	body.global_transform = pose()


## Records this step's measurement (before the model advances); a driver that keeps its own
## measurements instead of one sample series overrides it.
func _record_step(_dt: float) -> void:
	record(measure())


## Advances the model by one fixed step.
func advance(_dt: float) -> void:
	pass


## Transform of the body for the current model state.
func pose() -> Transform3D:
	return body.global_transform


## Measured quantity of the body (engine state) for the history.
func measure() -> float:
	return 0.0
