## A vertical line an upright object is dragged along (Phase 1 Task 4d: the buoyancy drum moved up
## into the air or down into the water): a ManipSurface line whose frame x is world up and whose
## normal faces the front camera (+z). Unlike a plain ManipSurface, the object keeps its upright
## basis (pose() ignores the frame's rotation) and its centre stays on the line (no lift along the
## normal): plane coordinates are (world height, 0). The footprint marker is then a level ring at the
## object's centre height.
class_name UprightLineSurface
extends ManipSurface

var _lift := 0.0


## The line through `at` (its x / z; heights `low`..`high` of the object's centre, grid `step`
## from y = 0); `lift`: the object's half extent the manipulator holds it above its surface.
func _init(at := Vector3.ZERO, low := 0.0, high := 0.0, step := 0.0, lift := 0.0) -> void:
	super(Transform3D(Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT), Vector3(at.x, 0.0, at.z)),
		Vector2(low, 0.0), Vector2(high, 0.0), Vector2(step, 0.0))
	_lift = lift


func pose(p: Vector2, _above: float) -> Transform3D:
	return Transform3D(Basis(), frame * Vector3(p.x, 0.0, p.y))


## An object on the line counts as resting `lift` above its surface (picked up where it is).
func height_of(world: Vector3) -> float:
	return _lift + super(world)


func project_ray(origin: Vector3, direction: Vector3, _above: float) -> Variant:
	return super(origin, direction, 0.0)
