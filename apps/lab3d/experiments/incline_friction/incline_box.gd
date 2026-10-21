## Box on the incline. Delegates per-step friction to InclineFrictionCorrector before the physics
## server steps (see friction_corrector.gd for why it is _physics_process, not _integrate_forces).
class_name InclineBox
extends RigidBody3D

var corrector: InclineFrictionCorrector


func _physics_process(delta: float) -> void:
	if corrector and not freeze:
		corrector.apply(self, delta)
