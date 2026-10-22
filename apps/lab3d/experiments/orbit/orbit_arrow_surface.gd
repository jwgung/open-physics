## Manipulation surface of the orbit lab's launch arrow knob (Phase 1 Task 4d): the level orbit plane
## through the planet (frame = world axes, so the direction is counter-clockwise seen from above,
## 0 deg = away from the star), polar snapping like the web's purple arrow: 5 deg and 0.1 m/s steps,
## 0-6 m/s, any direction. The arrow tip sits OFFSET + speed * SCALE metres from the planet centre.
class_name OrbitArrowSurface
extends PolarArrowSurface

const SCALE := 0.4           # m of arrow per m/s
const OFFSET := 0.45         # m from the planet centre to the tip at speed 0 (outside the planet)
const ANGLE_STEP := 5.0      # deg
const SPEED_STEP := 0.1      # m/s
const SPEED_MAX := 6.0


## `center`: the planet centre (world); `knob_half`: the knob's half height, so a knob placed on the
## plane has its centre in the orbit plane.
func _init(center := Vector3.ZERO, knob_half := 0.0) -> void:
	var reach := OFFSET + SPEED_MAX * SCALE + 0.6
	super(Transform3D(Basis(), center - Vector3.UP * knob_half), Vector2(-reach, -reach), Vector2(reach, reach))
	arrow_scale = SCALE
	arrow_offset = OFFSET
	angle_step = ANGLE_STEP
	speed_step = SPEED_STEP
	speed_min = 0.0
	speed_max = SPEED_MAX


## (direction deg in 0..360, speed m/s) on the grid for a knob at plane point `p`: whole 5 deg and
## 0.1 m/s cells (64-bit: [direction, speed]; a Vector2 would round them to 32 bit).
static func launch_of(p: Vector2) -> PackedFloat64Array:
	var launch := PackedFloat64Array([0.0, 0.0])
	launch_into(p, launch)
	return launch


## launch_of() written into `out` (two elements), for callers that run every frame.
static func launch_into(p: Vector2, out: PackedFloat64Array) -> void:
	var q := polar_point(p, OFFSET, SCALE)
	out[0] = fposmod(roundf(q.x / ANGLE_STEP) * ANGLE_STEP, 360.0)
	out[1] = clampf(roundi(q.y / SPEED_STEP) / (1.0 / SPEED_STEP), 0.0, SPEED_MAX)
