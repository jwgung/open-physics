## Rigid body whose formula corrector runs every fixed step before the physics server steps.
## The correction must happen in _physics_process, not _integrate_forces: in Godot 4.7 + Jolt,
## _integrate_forces is called after the step, so a force applied there only reaches the next step
## (docs/formula-correction.md, "Jolt findings"). A frozen body is not corrected.
class_name FormulaBody
extends RigidBody3D

var corrector: FormulaCorrector


func _physics_process(delta: float) -> void:
	if corrector and not freeze:
		corrector.apply(self, delta)
