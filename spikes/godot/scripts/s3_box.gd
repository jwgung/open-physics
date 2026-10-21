## 1 kg box for S3. Delegates per-step friction to InclineFrictionCorrector.
class_name S3Box
extends RigidBody3D

var corrector: InclineFrictionCorrector


func _physics_process(delta: float) -> void:
	if corrector and not freeze:
		corrector.apply(self, delta)
