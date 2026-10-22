## Formula model of one pendulum of the constraints lab (Phase 1 Task 4e; web preset "constraints"):
## the web's PendulumModel (src/app/mechanics-scenes.ts) - angular acceleration
## alpha = -(g / L) sin(angle) - damping * omega (PhysicsLaws.pendulum_angular_acceleration), the
## bob at anchor + L (sin angle along +x, cos angle down): the anchor-bob distance is L by
## construction, for the string and for the rod alike (the web models both the same way).
## Stepping: classic RK4, SUBSTEPS per fixed step, of that same equation - the law's motion to
## about 1e-7 rad over 60 s (tools/constraints-lab-vectors.test.ts). The web steps it with
## semi-implicit Euler at 60 Hz, which puts a 2 m bob about 2 cm off the law's motion (its phase
## lags by half a step from the start), so the lab does not copy that integrator (Task 4d chose the
## exact spring motion for the same reason).
## The period shown is measured on the model: the time between two zero crossings in the same
## direction (linear interpolation within the step), 0 until a full swing was seen.
class_name PendulumLabModel
extends BodyModel

const SUBSTEPS := 4

## Anchor (world m), 64-bit.
var anchor_x := 0.0
var anchor_y := 0.0
var anchor_z := 0.0
var length := 2.0
var damping := 0.0          # 1/s (PendulumModel damping)
var g := 9.81
var mass := 1.0             # bob mass (kg), the web's 1 kg: only the tension uses it
var start_angle := 0.0      # rad, the release angle (0 = hanging straight down, + = towards +x)
var angle := 0.0
var omega := 0.0            # rad/s
## Time between the last two same-direction zero crossings (s; 0 until a full swing was seen).
var period := 0.0
var _last_up := -1.0
var _last_down := -1.0


## The bob at rest at `start` (waiting there or released from there).
func reset(start: float) -> void:
	steps = 0
	stopped = false
	start_angle = start
	angle = start
	omega = 0.0
	period = 0.0
	_last_up = -1.0
	_last_down = -1.0
	_place()


func acceleration(a: float, w: float) -> float:
	return PhysicsLaws.pendulum_angular_acceleration(a, w, g, length, damping)


func advance(step_dt: float) -> void:
	var before := angle
	var h := step_dt / SUBSTEPS
	for i in SUBSTEPS:
		_rk4(h)
	var up := before < 0.0 and angle >= 0.0
	var down := before > 0.0 and angle <= 0.0
	if up or down:
		var t := (steps - 1 + before / (before - angle)) * step_dt
		var last := _last_up if up else _last_down
		if last >= 0.0:
			period = t - last
		if up:
			_last_up = t
		else:
			_last_down = t
	_place()


## One RK4 step of h seconds (the same operations as the TS vector generator).
func _rk4(h: float) -> void:
	var a := angle
	var w := omega
	var k1a := w
	var k1w := acceleration(a, w)
	var k2a := w + 0.5 * h * k1w
	var k2w := acceleration(a + 0.5 * h * k1a, w + 0.5 * h * k1w)
	var k3a := w + 0.5 * h * k2w
	var k3w := acceleration(a + 0.5 * h * k2a, w + 0.5 * h * k2w)
	var k4a := w + h * k3w
	var k4w := acceleration(a + h * k3a, w + h * k3w)
	angle = a + (h / 6.0) * (k1a + 2.0 * k2a + 2.0 * k3a + k4a)
	omega = w + (h / 6.0) * (k1w + 2.0 * k2w + 2.0 * k3w + k4w)


## Position and velocity of the bob for the angle now (PendulumModel.pose: offset L (sin, cos)).
func _place() -> void:
	# The same two products as PhysicsLaws.pendulum_offset, without its array (called every step).
	x = anchor_x + length * sin(angle)
	y = anchor_y - length * cos(angle)
	z = anchor_z
	vx = length * cos(angle) * omega
	vy = length * sin(angle) * omega
	vz = 0.0


## Bob offset from the anchor along +x and down (m): PendulumModel.pose().position - anchor.
func offset() -> PackedFloat64Array:
	return PhysicsLaws.pendulum_offset(length, angle)


## Distance anchor-bob of the formula position (m): L.
func distance() -> float:
	var o := offset()
	return sqrt(o[0] * o[0] + o[1] * o[1])


## Bob speed (m/s): mechanics.ts tangentialSpeed(L, omega).
func speed() -> float:
	return absf(PhysicsLaws.tangential_speed(length, omega))


## Pull of the string (rod) on the bob towards the anchor (N): m g cos(angle) + m v^2 / L.
func tension() -> float:
	return mass * g * cos(angle) + PhysicsLaws.centripetal_force(mass, PhysicsLaws.tangential_speed(length, omega), length)


## Small-angle period 2 pi sqrt(L / g) (oscillation.ts pendulumPeriod; 0 without gravity).
func small_angle_period() -> float:
	return PhysicsLaws.pendulum_period(length, g) if g > 0.0 else 0.0
