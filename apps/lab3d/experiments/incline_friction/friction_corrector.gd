## Incline friction on the formula correction layer: a ContactFrictionCorrector (method
## "contact_force", law "surface") on the incline pivot, whose local +y is the surface normal and
## whose -x is downhill. First correction case, moved onto the layer in Task 3 with unchanged
## numerics (scripts/formula/contact_friction_corrector.gd holds the logic).
class_name InclineFrictionCorrector
extends ContactFrictionCorrector

## Pivot whose local +y is the surface normal, top surface at local y = 0. Another name for
## `surface` (no separate storage): setting either one sets both.
var incline: Node3D:
	get:
		return surface
	set(value):
		surface = value


func downhill() -> Vector3:
	return tangent()
