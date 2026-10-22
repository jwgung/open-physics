## Manipulation surface of the projectile's velocity arrow knob (Phase 1 Task 4a): the vertical plane
## through the launch point, facing the front camera, with polar "snapping" like the web's purple
## arrow (direction in 15 deg steps, speed = arrow length, capped). Plane coordinates are those of
## ManipSurface (frame x = world +x, frame z = world -y); polar() turns one into (angle deg, speed).
## The arrow tip sits OFFSET + speed * SCALE metres from the ball centre.
class_name ArrowSurface
extends ManipSurface

const SCALE := 0.25          # m of arrow per m/s
const OFFSET := 0.35         # m from the ball centre to the tip at speed 0 (outside the ball)
const ANGLE_STEP := 15.0     # deg (web VELOCITY_ANGLE_SNAP_RADIANS)
const SPEED_STEP := 0.5      # m/s (the speed slider's step)
const SPEED_MIN := 1.0
const SPEED_MAX := 9.0       # web: 96 px / 0.22 = 436 px/s = 9.09 m/s, on the slider's grid
const ANGLE_MIN := 0.0
const ANGLE_MAX := 90.0


## `center`: the ball centre (world); `knob_half`: the knob's half extent along the plane normal, so
## a knob placed on the plane has its centre in the ball's vertical plane.
func _init(center := Vector3.ZERO, knob_half := 0.0) -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)   # x, normal (+z, to the front camera), z
	var reach := OFFSET + SPEED_MAX * SCALE + 0.6
	super(Transform3D(basis, center - Vector3.BACK * knob_half), Vector2(-reach, -reach), Vector2(reach, reach))


## (angle deg, speed m/s) of a plane point (unsnapped).
static func polar(p: Vector2) -> Vector2:
	var dx := p.x
	var dy := -p.y
	return Vector2(rad_to_deg(atan2(dy, dx)), (Vector2(dx, dy).length() - OFFSET) / SCALE)


## Plane point of the arrow tip for (angle deg, speed).
static func tip(angle_deg: float, speed: float) -> Vector2:
	var length := OFFSET + speed * SCALE
	var a := deg_to_rad(angle_deg)
	return Vector2(cos(a) * length, -sin(a) * length)


## Snapped (angle, speed): angle to the 15 deg grid (not clamped: a direction outside 0..90 deg is
## shown as "cannot place"), speed to the 0.5 m/s grid and capped to SPEED_MIN..SPEED_MAX like the
## web arrow's length cap.
static func snap_polar(p: Vector2) -> Vector2:
	var q := polar(p)
	var angle := roundf(q.x / ANGLE_STEP) * ANGLE_STEP
	var speed := clampf(roundf(q.y / SPEED_STEP) * SPEED_STEP, SPEED_MIN, SPEED_MAX)
	return Vector2(angle, speed)


func snap_point(p: Vector2) -> Vector2:
	var q := snap_polar(p)
	return tip(q.x, q.y)


func contains(p: Vector2) -> bool:
	var angle := polar(p).x
	return angle >= ANGLE_MIN - 0.01 and angle <= ANGLE_MAX + 0.01


## A dragged knob stays within `margin` of the longest arrow.
func clamp_soft(p: Vector2, margin: float) -> Vector2:
	var limit := OFFSET + SPEED_MAX * SCALE + margin
	return p.limit_length(limit)


func nearest_inside(p: Vector2) -> Vector2:
	var q := snap_polar(p)
	return tip(clampf(q.x, ANGLE_MIN, ANGLE_MAX), q.y)
