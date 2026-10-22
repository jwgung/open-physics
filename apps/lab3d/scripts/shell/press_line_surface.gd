## A vertical line a handle is pressed or pulled down along (Phase 1 Task 4e: the lever's handle,
## the pulley's rope grip): an UprightLineSurface whose frame x points down from `top`, so the plane
## coordinate is how far the handle is below its rest point (0..reach, grid `step` from the top).
## The handle keeps its upright basis and its centre stays on the line.
class_name PressLineSurface
extends UprightLineSurface


## The line down from `top` (the handle's rest centre) over `reach` metres; `lift` as in
## UprightLineSurface (the handle's half height).
func _init(top := Vector3.ZERO, reach := 0.0, step := 0.0, lift := 0.0) -> void:
	super(top, 0.0, reach, step, lift)
	frame = Transform3D(Basis(Vector3.DOWN, Vector3.BACK, Vector3.LEFT), top)


## Distance (m) of a world point below the top along the line.
func depth_of(world: Vector3) -> float:
	return to_plane(world).x
