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
##   rest     nothing changes,
##   fence    (when wall_x is set) the ball's front reaching the fence face below its top: back at
##            e_w v and the Coulomb impulse along the face (a rolling ball hops back a little).
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
## Fences (Task 4f, the projectile island's ends): world x of the faces towards the ball, right
## (wall_x, the ball meets it moving +x) and left (wall_left_x, moving -x); +-INF: none. Their top
## above the floor and their restitution.
var wall_x := INF
var wall_left_x := -INF
var wall_top := 0.0
var wall_restitution := 0.6
## World height of the floor surface.
var floor_y := 0.0
## Field strength (m/s^2, straight down) of the run.
var g := 9.81
## Formula time (s from the release) of the first floor contact (INF: none).
var landing := INF
## Formula time of the flight meeting the fence (INF: it does not; see _flight_fence_time).
var fence_time := INF
## True once the model owns the motion (from the step whose interval holds `landing`).
var active := false
## Events (tests): impact times and approach speeds, the first time the slip ended (rolling) and the
## time the ball stopped (-1: not yet).
var impact_times := PackedFloat64Array()
var impact_speeds := PackedFloat64Array()
var roll_time := -1.0
var stop_time := -1.0
var wall_times := PackedFloat64Array()
var wall_speeds := PackedFloat64Array()

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
var _wall_side := 1.0


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
	fence_time = _flight_fence_time()
	active = false
	impact_times.clear()
	impact_speeds.clear()
	wall_times.clear()
	wall_speeds.clear()
	roll_time = -1.0
	stop_time = -1.0
	body.angular_velocity = Vector3(0.0, 0.0, spin)


## Formula time (s from the release) at which the free flight's front reaches the right fence face
## below its top, before the floor landing (INF: it lands first or passes over the top). The flight
## is the formula's up to there (2026-10-23 user decision: such a ball hits the fence).
func _flight_fence_time() -> float:
	if not is_finite(wall_x) or _vx0 <= 0.0:
		return INF
	var t := (wall_x - radius - _origin.x) / _vx0
	if t < 0.0 or t >= landing:
		return INF
	return t if _h0 + _vy0 * t - 0.5 * g * t * t < wall_top else INF


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
	if not active or landing <= 0.0 or hit_fence_in_flight():
		return -1
	return ceili(landing / dt - 1e-9)


## One fixed step before the physics server steps; `k` = the sample just recorded (the body is
## after k steps), `field_dv` = the velocity the engine itself adds in this step (field, leapfrog).
func apply(body: RigidBody3D, k: int, dt: float, field_dv: Vector3) -> void:
	var t_next := (k + 1) * dt
	if not active:
		if not (minf(landing, fence_time) < t_next - 1e-12):
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


## True when the free flight ends on the fence, not on the floor.
func hit_fence_in_flight() -> bool:
	return fence_time < landing


## The model takes over at the landing time (or the fence time, when the flight meets the fence
## first) with the flight's state there.
func _start() -> void:
	active = true
	if hit_fence_in_flight():
		_t = fence_time
		_x = _vx0 * _t
		_y = _h0 + _vy0 * _t - 0.5 * g * _t * _t
		_vx = _vx0
		_vy = _vy0 - g * _t
		_w = _w0
		_th = _w0 * _t
		_ground = false
		_wall_side = 1.0
		_wall_impact()
		return
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


## Advances the model to time t1. Every piece has constant accelerations (air: -g; slide: kinetic
## friction; roll: rolling resistance with omega = -v / r; rest: none), so the state and the next
## event (floor impact, end of the slip, stop, fence) are closed forms.
func _advance(t1: float) -> void:
	var guard := 0
	while _t < t1 and guard < 10000:
		guard += 1
		var left := t1 - _t
		var ax := 0.0
		var ay := 0.0
		var aw := 0.0
		var d_end := INF
		var kind := 0   # 1 floor impact, 2 slip ends, 3 stop
		if not _ground:
			ay = -g
			if g > 0.0:
				d_end = (_vy + sqrt(_vy * _vy + 2.0 * g * maxf(0.0, _y))) / g
				kind = 1
		else:
			var u := _vx + radius * _w
			if absf(u) > 1e-12 and mu > 0.0 and g > 0.0:
				ax = -mu * g * signf(u)
				aw = radius * mass * ax / _inertia()
				d_end = absf(u) / absf(ax + radius * aw)
				kind = 2
			elif _vx != 0.0 and mu_roll > 0.0 and g > 0.0:
				ax = -mu_roll * g * signf(_vx)
				aw = -ax / radius
				d_end = absf(_vx) / (mu_roll * g)
				kind = 3
		var d_wall := _wall_time(ax, ay, minf(d_end, left))
		var d := minf(left, minf(d_end, d_wall))
		_x += _vx * d + 0.5 * ax * d * d
		_y += _vy * d + 0.5 * ay * d * d
		_th += _w * d + 0.5 * aw * d * d
		_vx += ax * d
		_vy += ay * d
		_w += aw * d
		_t += d
		if d_wall <= d:
			_wall_impact()
		elif d_end <= d:
			match kind:
				1:
					_y = 0.0
					_impact()
				2:
					_w = -_vx / radius   # rolling from here (no leftover slip from rounding)
					if roll_time < 0.0:
						roll_time = _t
				3:
					_vx = 0.0
					_w = 0.0
					if stop_time < 0.0:
						stop_time = _t
	if _t < t1:
		push_warning("RollingContact._advance: step guard spent at t = %f of %f" % [_t, t1])


## Time until the ball reaches a fence face (its front at the right face moving +x, or its back at
## the left face moving -x) within `limit`, with its bottom below the fence top then; INF when not
## (moving away, stopping short, or passing over the top). Sets _wall_side (+1 right, -1 left).
func _wall_time(ax: float, ay: float, limit: float) -> float:
	var best := INF
	for side in [1.0, -1.0]:
		var face: float = wall_x if side > 0.0 else wall_left_x
		if not is_finite(face):
			continue
		# Along the outward direction `side`: distance to go, speed and acceleration.
		var gap: float = side * ((face - side * radius - _origin.x) - _x)
		var v: float = side * _vx
		var a: float = side * ax
		if gap < -1e-9 or (v <= 0.0 and a <= 0.0):
			continue
		var s := INF
		if absf(a) < 1e-15:
			if v > 0.0:
				s = gap / v
		else:
			var disc := v * v + 2.0 * a * gap
			if disc >= 0.0:
				s = (-v + sqrt(disc)) / a   # the first root after now (also while slowing down)
		if s < 0.0 or s > limit or s >= best:
			continue
		if _y + _vy * s + 0.5 * ay * s * s < wall_top:
			best = s
			_wall_side = side
	return best


## Impact on a fence face (normal against the motion, contact at the ball's equator): back at e_w v
## (the web's wall rule: v *= -e, no threshold) and the Coulomb friction impulse along the face
## (vertical), |P| <= mu (1 + e_w) v, no more than ends the slip there. A rolling ball (topspin) is
## pushed up a little and hops back.
func _wall_impact() -> void:
	var v := absf(_vx)
	wall_times.append(_t)
	wall_speeds.append(v)
	var jn := (1.0 + wall_restitution) * v
	_vx = -_wall_side * wall_restitution * v
	# Contact point at side * (r, 0, 0): omega x r = (0, side * omega_z r, 0).
	var u := _vy + _wall_side * radius * _w
	if u != 0.0:
		var inertia := _inertia()
		var stick := absf(u) / (1.0 + mass * radius * radius / inertia)
		var p := minf(mu * jn, stick) * -signf(u)
		_vy += p
		_w += _wall_side * radius * mass * p / inertia
	if _vy > 0.0 and _ground:
		_ground = false      # lifted off the floor by the fence's friction
	elif _ground:
		_vy = 0.0


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
