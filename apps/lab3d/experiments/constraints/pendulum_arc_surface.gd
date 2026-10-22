## Manipulation surface of a pendulum bob (Phase 1 Task 4e): the circle of radius L around the anchor
## in the pendulum's vertical swing plane. The finger ray meets that plane and the bob is held on the
## circle at the finger's angle, so the anchor-bob distance stays L while it is dragged (a taut
## string, a rigid rod); it snaps to `angle_step` degrees within +-angle_max.
## Plane coordinates (ManipSurface): frame origin = the anchor, frame x = world +x (the swing's side),
## frame z = world down, the normal = world +z (towards the front camera). A plane point p is
## (L sin a, L cos a) for the angle a from straight down (+ = towards +x), PendulumModel's pose.
class_name PendulumArcSurface
extends ManipSurface

var length := 2.0
var angle_step := 5.0        # deg
var angle_max := 75.0        # deg either side of straight down
var _lift := 0.0


## The circle around `anchor` of radius `arc_length`; `lift` = the bob radius (the manipulator holds
## a body that far above its surface; here the bob's centre stays on the circle).
func _init(anchor := Vector3.ZERO, arc_length := 2.0, step_deg := 5.0, max_deg := 75.0, lift := 0.0) -> void:
	length = arc_length
	angle_step = step_deg
	angle_max = max_deg
	_lift = lift
	# The region is the box around the lower half circle (not a line: a line region would make the
	# shell project the finger on a line); contains() / nearest_inside() decide by angle.
	super(Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), anchor),
		Vector2(-arc_length, 0.0), Vector2(arc_length, arc_length))


## Plane point of the bob at `deg` degrees from straight down.
func point_at(deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(length * sin(a), length * cos(a))


## Angle (deg) of a plane point from straight down (+ towards +x).
func angle_of(p: Vector2) -> float:
	return rad_to_deg(atan2(p.x, p.y))


## `deg` on the grid of `step` degrees (whole steps; no grid when step <= 0). The one snapping both the
## drag surface and the experiment's angle_at use.
static func snap_deg(deg: float, step: float) -> float:
	return roundf(deg / step) * step if step > 0.0 else deg


## The angle of `p` on the grid (not clamped).
func snapped_angle(p: Vector2) -> float:
	return snap_deg(angle_of(p), angle_step)


func snap_point(p: Vector2) -> Vector2:
	return point_at(snapped_angle(p))


func contains(p: Vector2) -> bool:
	return absf(angle_of(p)) <= angle_max + 0.01


## A held bob stays on the circle, at most `margin` metres of arc beyond the allowed angles.
func clamp_soft(p: Vector2, margin: float) -> Vector2:
	var limit := angle_max + rad_to_deg(margin / length)
	return point_at(clampf(angle_of(p), -limit, limit))


func nearest_inside(p: Vector2) -> Vector2:
	return point_at(clampf(snapped_angle(p), -angle_max, angle_max))


## The bob upright at the plane point (on the circle), its centre in the swing plane.
func pose(p: Vector2, _above: float) -> Transform3D:
	return Transform3D(Basis(), frame * Vector3(p.x, 0.0, p.y))


## A bob in the swing plane counts as resting `lift` above its surface (picked up where it is).
func height_of(world: Vector3) -> float:
	return _lift + super(world)


func project_ray(origin: Vector3, direction: Vector3, _above: float) -> Variant:
	return super(origin, direction, 0.0)
