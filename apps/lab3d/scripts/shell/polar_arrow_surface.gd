## Manipulation surface of a velocity arrow's knob snapped in polar steps (direction and speed), like
## the web's purple arrows: the knob sits at the arrow tip, `offset` + speed * `scale` metres from the
## body centre, in a plane through it. Plane coordinates are those of ManipSurface; the direction is
## measured from frame +x towards frame -z (angle = atan2(-p.y, p.x)): for the projectile's vertical
## plane (frame z = world -y) that is up from the horizon. Subclass: ArrowSurface (projectile, Task
## 4a; the orbit lab's knob surface went with its knob, 2026-10-28).
class_name PolarArrowSurface
extends ManipSurface

var arrow_scale := 0.25      # m of arrow per m/s
var arrow_offset := 0.35     # m from the centre to the tip at speed 0
var angle_step := 15.0       # deg
var speed_step := 0.5        # m/s
var speed_min := 0.0
var speed_max := 9.0
var angle_min := -INF        # deg; outside = "cannot place" (a full circle when unbounded)
var angle_max := INF


## (angle deg, speed m/s) of a plane point (unsnapped).
static func polar_point(p: Vector2, offset: float, scale: float) -> Vector2:
	return Vector2(rad_to_deg(atan2(-p.y, p.x)), (p.length() - offset) / scale)


## Plane point of the arrow tip for (angle deg, speed).
static func tip_point(angle_deg: float, speed: float, offset: float, scale: float) -> Vector2:
	var length := offset + speed * scale
	var a := deg_to_rad(angle_deg)
	return Vector2(cos(a) * length, -sin(a) * length)


## Snapped (angle, speed): angle to its grid (not clamped), speed to its grid within its range.
static func snap_polar_point(p: Vector2, offset: float, scale: float, a_step: float, s_step: float, s_min: float, s_max: float) -> Vector2:
	var q := polar_point(p, offset, scale)
	var angle := roundf(q.x / a_step) * a_step
	var speed := clampf(roundf(q.y / s_step) * s_step, s_min, s_max)
	return Vector2(angle, speed)


func polar_of(p: Vector2) -> Vector2:
	return polar_point(p, arrow_offset, arrow_scale)


func tip_of(angle_deg: float, speed: float) -> Vector2:
	return tip_point(angle_deg, speed, arrow_offset, arrow_scale)


func snap_of(p: Vector2) -> Vector2:
	return snap_polar_point(p, arrow_offset, arrow_scale, angle_step, speed_step, speed_min, speed_max)


func snap_point(p: Vector2) -> Vector2:
	var q := snap_of(p)
	return tip_of(q.x, q.y)


func contains(p: Vector2) -> bool:
	var angle := polar_of(p).x
	return angle >= angle_min - 0.01 and angle <= angle_max + 0.01


## A dragged knob stays within `margin` of the longest arrow.
func clamp_soft(p: Vector2, margin: float) -> Vector2:
	return p.limit_length(arrow_offset + speed_max * arrow_scale + margin)


func nearest_inside(p: Vector2) -> Vector2:
	var q := snap_of(p)
	return tip_of(clampf(q.x, angle_min, angle_max), q.y)
