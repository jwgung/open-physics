## Manipulation surface of the projectile's velocity arrow knob (Phase 1 Task 4a): the vertical plane
## through the launch point, facing the front camera, with polar "snapping" like the web's purple
## arrow (direction in 15 deg steps, speed = arrow length, capped). Plane coordinates are those of
## ManipSurface (frame x = world +x, frame z = world -y); polar() turns one into (angle deg, speed).
## The arrow tip sits OFFSET + speed * SCALE metres from the ball centre. The polar snapping itself is
## PolarArrowSurface's (shared with the orbit lab's level arrow, Task 4d).
class_name ArrowSurface
extends PolarArrowSurface

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
	arrow_scale = SCALE
	arrow_offset = OFFSET
	angle_step = ANGLE_STEP
	speed_step = SPEED_STEP
	speed_min = SPEED_MIN
	speed_max = SPEED_MAX
	angle_min = ANGLE_MIN
	angle_max = ANGLE_MAX


## (angle deg, speed m/s) of a plane point (unsnapped).
static func polar(p: Vector2) -> Vector2:
	return polar_point(p, OFFSET, SCALE)


## Plane point of the arrow tip for (angle deg, speed).
static func tip(angle_deg: float, speed: float) -> Vector2:
	return tip_point(angle_deg, speed, OFFSET, SCALE)


## Snapped (angle, speed): angle to the 15 deg grid (not clamped: a direction outside 0..90 deg is
## shown as "cannot place"), speed to the 0.5 m/s grid and capped to SPEED_MIN..SPEED_MAX like the
## web arrow's length cap.
static func snap_polar(p: Vector2) -> Vector2:
	return snap_polar_point(p, OFFSET, SCALE, ANGLE_STEP, SPEED_STEP, SPEED_MIN, SPEED_MAX)
