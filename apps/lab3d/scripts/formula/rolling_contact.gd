## The ball on the level ground after its free flight: a 64-bit formula model of the bounces, the
## slide, the roll and the stop of a solid sphere (I = 2/5 m r^2), which the engine ball is put on
## every fixed step (Phase 1 Task 4f; part of the uniform-field correction:
## UniformFieldCorrector.rolling, docs/formula-correction.md "Task 4f").
## Until the formula landing time T (PhysicsLaws.landing_time of the release) the engine flies the
## ball (leapfrog start, nothing changed). From the fixed step whose interval holds T the model owns
## the motion; event by event, in closed form inside each step:
##   air      no torque: omega constant; x += vx t, y = y0 + vy t - g t^2 / 2 (to the floor y = 0),
##   impact   at the exact time the bottom reaches the floor with speed v: up again at e v (e: the
##            ball's restitution; v below REST_SPEED (1 m/s, Jolt's and the web's threshold) -> e = 0,
##            the ball stays on the floor), and the Coulomb friction impulse of that impact,
##            |P| <= mu J_n with J_n = m (1 + e) v, no more than the 2/7 m |u| that ends the slip u,
##   slide    on the floor with slip u = vx + r omega_z: kinetic friction mu m g (v by mu g, omega by
##            5 mu g / (2 r)) until u = 0 at t = 2 |u| / (7 mu g),
##   roll     v = omega r, slowed by rolling resistance mu_roll m g (a = mu_roll g) until it stops at
##            v0^2 / (2 mu_roll g) (0: no resistance, it rolls on),
##   rest     nothing changes.
## The body (dynamic, engine friction and bounce 0) is put on the model each step: its velocity is
## set so that the engine's symplectic step (v += field dt, x += v dt) ends at the model's position,
## and its angular velocity so that it ends at the model's turn about z. The engine therefore never
## reaches into the floor and its contact never pushes; landing reactions (ArtJuice) read the
## body's step velocity as before.
## Limits: one level floor at floor_y, the field straight down, the ball's motion in the x-y plane
## (the labs' throws and drops); the turn is about z.
class_name RollingContact
extends RefCounted

## Approach speed (m/s) below which an impact does not bounce (Jolt bounce_velocity_threshold and
## the web's RESTING_REBOUND_SPEED, 48 px/s).
const REST_SPEED := 1.0

var radius := 0.25
var mass := 1.0
## Kinetic friction coefficient ball-floor.
var mu := 0.6
## Rolling resistance coefficient (deceleration mu_roll g while rolling).
var mu_roll := 0.05
## Restitution of a bounce on the floor.
var restitution := 0.6
## World height of the floor surface.
var floor_y := 0.0
## Field strength (m/s^2, straight down) of the run.
var g := 9.81
## Formula time (s from the release) of the first floor contact (INF: none).
var landing := INF
## True once the model owns the motion (from the step whose interval holds `landing`).
var active := false
## Events (tests): impact times and approach speeds, the first time the slip ended (rolling) and the
## time the ball stopped (-1: not yet).
var impact_times := PackedFloat64Array()
var impact_speeds := PackedFloat64Array()
var roll_time := -1.0
var stop_time := -1.0

var _origin := Vector3.ZERO     # body centre at the release
var _h0 := 0.0                  # bottom height above the floor at the release
var _vx0 := 0.0
var _vy0 := 0.0
var _w0 := 0.0
# Model state at time _t (s from the release): x from the release, bottom height y, velocities,
# angular velocity about z and the turn about z since the release.
var _t := 0.0
var _x := 0.0
var _y := 0.0
var _vx := 0.0
var _vy := 0.0
var _w := 0.0
var _th := 0.0
var _ground := false


## The ball is let go from where it is with `velocity` (x, y used) and `spin` (rad/s about z).
func release(body: RigidBody3D, velocity: Vector3, field: float, spin := 0.0) -> void:
	mass = body.mass
	g = field
	_origin = body.global_position
	_h0 = _origin.y - radius - floor_y
	_vx0 = velocity.x
	_vy0 = velocity.y
	_w0 = spin
	landing = PhysicsLaws.landing_time(_vy0, -g, _h0) if g > 0.0 else INF
	active = false
	impact_times.clear()
	impact_speeds.clear()
	roll_time = -1.0
	stop_time = -1.0
	body.angular_velocity = Vector3(0.0, 0.0, spin)


## The model's state at time `t` (s from the release; not before the model's own time):
## [x from the release, bottom height, vx, vy, omega_z, turn about z]. Only once active.
func state_at(t: float) -> PackedFloat64Array:
	_advance(t)
	return PackedFloat64Array([_x, _y, _vx, _vy, _w, _th])


## Slip speed of the contact point at the model's time (m/s; 0 = rolling or at rest).
func slip() -> float:
	return absf(_vx + radius * _w)


## Index of the first recorded sample at or after the landing (the measured landing step): -1 while
## not active, or when the ball starts on the floor (landing 0: the formula owns it).
func landing_step(dt: float) -> int:
	if not active or landing <= 0.0:
		return -1
	return ceili(landing / dt - 1e-9)


## One fixed step before the physics server steps; `k` = the sample just recorded (the body is
## after k steps), `field_dv` = the velocity the engine itself adds in this step (field, leapfrog).
func apply(body: RigidBody3D, k: int, dt: float, field_dv: Vector3) -> void:
	var t_next := (k + 1) * dt
	if not active:
		if not (landing < t_next - 1e-12):
			return
		_start()
	_advance(t_next)
	var target := Vector3(_origin.x + _x, floor_y + radius + _y, _origin.z)
	body.linear_velocity = (target - body.global_position) / dt - field_dv
	var q := body.global_basis.get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var turned := 2.0 * atan2(q.z, q.w)
	body.angular_velocity = Vector3(0.0, 0.0, wrapf(_th - turned, -PI, PI) / dt)


## The model takes over at the landing time with the flight's state there.
func _start() -> void:
	active = true
	_t = maxf(0.0, landing)
	_x = _vx0 * _t
	_y = 0.0
	_vx = _vx0
	_vy = _vy0 - g * _t
	_w = _w0
	_th = _w0 * _t
	_ground = false
	if _vy < 0.0:
		_impact()
	else:
		_vy = 0.0       # on the floor, not moving into it: it slides or rolls from here
		_ground = true


func _inertia() -> float:
	return PhysicsLaws.solid_sphere_moment_of_inertia(mass, radius)


## Advances the model to time t1 (events in closed form).
func _advance(t1: float) -> void:
	var guard := 0
	while _t < t1 and guard < 10000:
		guard += 1
		var span := t1 - _t
		if not _ground:
			var tau := (_vy + sqrt(_vy * _vy + 2.0 * g * _y)) / g if g > 0.0 else INF
			var s := minf(span, tau)
			_x += _vx * s
			_y += _vy * s - 0.5 * g * s * s
			_vy -= g * s
			_th += _w * s
			_t += s
			if tau <= span:
				_y = 0.0
				_impact()
		else:
			_ground_step(span)


## Floor impact with the current downward speed: bounce or stay, and the friction impulse.
func _impact() -> void:
	var v := -_vy
	impact_times.append(_t)
	impact_speeds.append(v)
	var e := restitution if v >= REST_SPEED else 0.0
	_friction_impulse((1.0 + e) * v)
	if e > 0.0:
		_vy = e * v
		_ground = false
	else:
		_vy = 0.0
		_ground = true


## Coulomb impulse per mass for the normal impulse per mass `jn`.
func _friction_impulse(jn: float) -> void:
	var u := _vx + radius * _w
	if u == 0.0:
		return
	var inertia := _inertia()
	var stick := absf(u) / (1.0 + mass * radius * radius / inertia)   # per mass: ends the slip
	var p := minf(mu * jn, stick) * -signf(u)
	_vx += p
	_w += radius * mass * p / inertia
	if stick <= mu * jn:
		_w = -_vx / radius
		if roll_time < 0.0:
			roll_time = _t


## On the floor for `span` seconds: slide (kinetic friction) -> roll (rolling resistance) -> rest.
func _ground_step(span: float) -> void:
	var left := span
	var guard := 0
	while left > 0.0 and guard < 8:
		guard += 1
		var u := _vx + radius * _w
		if absf(u) > 1e-12 and mu > 0.0 and g > 0.0:
			var a := -mu * g * signf(u)
			var alpha := radius * mass * a / _inertia()
			var t_stick := absf(u) / absf(a + radius * alpha)
			var stuck := t_stick <= left
			var d := t_stick if stuck else left
			_x += _vx * d + 0.5 * a * d * d
			_th += _w * d + 0.5 * alpha * d * d
			_vx += a * d
			_w += alpha * d
			_t += d
			left -= d
			if stuck:
				_w = -_vx / radius   # rolling from here (no leftover slip from rounding)
				if roll_time < 0.0:
					roll_time = _t
		elif _vx != 0.0 and mu_roll > 0.0 and g > 0.0:
			var a := -mu_roll * g * signf(_vx)
			var t_stop := absf(_vx) / (mu_roll * g)
			var stops := t_stop <= left
			var d := t_stop if stops else left
			var dx := _vx * d + 0.5 * a * d * d
			_x += dx
			_th -= dx / radius
			_vx += a * d
			_w = -_vx / radius
			_t += d
			left -= d
			if stops:
				_vx = 0.0
				_w = 0.0
				if stop_time < 0.0:
					stop_time = _t
		else:
			# Rolling without resistance (or no field), or at rest.
			_x += _vx * left
			_th += _w * left
			_t += left
			left = 0.0
