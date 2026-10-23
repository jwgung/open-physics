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
##            5 mu g / (2 r)) until u = 0 at t = 2 |u| / (7 mu g); with mu = 0 nothing changes (no
##            friction, and rolling resistance acts only on a rolling ball),
##   roll     v = omega r, slowed by rolling resistance mu_roll m g (a = mu_roll g) until it stops at
##            v0^2 / (2 mu_roll g) (0: no resistance, it rolls on),
##   rest     nothing changes,
##   fence    (when wall_x / wall_left_x are set) the ball meeting a fence board (face, top, back or
##            a top corner: circle against the board's rectangle, _fence_event): back at e_w v_n
##            along the contact normal and the Coulomb impulse along the surface; on the floor the
##            face and the floor push together (_resolve; a rolling ball hops back a little).
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
## Thickness (m) of each fence behind its face (its top and back can be met too).
var wall_thickness := 0.0
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
var wall_speeds := PackedFloat64Array()   # approach speed along the contact normal
## What each fence contact met: FACE, CORNER, TOP or BACK.
var wall_kinds := PackedInt32Array()

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
var _flight_hit := PackedFloat64Array([INF, 0.0, 0.0, 0.0, 0.0, 0.0])   # _fence_event of the flight


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
	wall_kinds.clear()
	roll_time = -1.0
	stop_time = -1.0
	body.angular_velocity = Vector3(0.0, 0.0, spin)


## Formula time (s from the release) of the free flight's first touch of a fence (face, top or
## corner; see _fence_event) before the floor landing (INF: it lands first or flies past). The
## flight is the formula's up to there (2026-10-23 user decision: such a ball hits the fence).
func _flight_fence_time() -> float:
	_flight_hit = _flight_fence_event(_origin.x, _h0, _vx0, _vy0, g)
	return _flight_hit[0]


## The same for any launch (no state read or changed: the lab's launch preview): ball centre at
## world x `x0`, bottom `h0` above the floor, launch velocity (vx, vy), field `field`. In zero
## gravity (no landing) a fence below the flight is met all the same (it has no other end).
func flight_fence_time(x0: float, h0: float, vx: float, vy: float, field: float) -> float:
	return _flight_fence_event(x0, h0, vx, vy, field)[0]


func _flight_fence_event(x0: float, h0: float, vx: float, vy: float, field: float) -> PackedFloat64Array:
	var land := PhysicsLaws.landing_time(vy, -field, h0) if field > 0.0 else INF
	var hit := _fence_event(x0, h0 + radius, vx, vy, 0.0, -field, land)
	if not (hit[0] < land):
		hit[0] = INF
	return hit


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
		_fence_impact(_flight_hit)
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
## friction; roll: rolling resistance with omega = -v / r; free slide (mu 0): none; rest: none), so
## the state and the next event (floor impact, end of the slip, stop, fence) are closed forms (the
## fence corners: the first root of a quartic, _first_entry).
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
			if absf(u) > 1e-12:
				# Sliding: kinetic friction mu m g against the slip (none when mu = 0 or no field: v
				# and omega stay, and the rolling resistance acts only on a rolling ball).
				if mu > 0.0 and g > 0.0:
					ax = -mu * g * signf(u)
					aw = radius * mass * ax / _inertia()
					d_end = absf(u) / absf(ax + radius * aw)
					kind = 2
			elif _vx != 0.0 and mu_roll > 0.0 and g > 0.0:
				ax = -mu_roll * g * signf(_vx)
				aw = -ax / radius
				d_end = absf(_vx) / (mu_roll * g)
				kind = 3
		var hit := _fence_event(_origin.x + _x, _y + radius, _vx, _vy, ax, ay, minf(d_end, left))
		var d_wall: float = hit[0]
		var d := minf(left, minf(d_end, d_wall))
		_x += _vx * d + 0.5 * ax * d * d
		_y += _vy * d + 0.5 * ay * d * d
		_th += _w * d + 0.5 * aw * d * d
		_vx += ax * d
		_vy += ay * d
		_w += aw * d
		_t += d
		if d_wall <= d:
			_fence_impact(hit)
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


# --- the fences ---------------------------------------------------------------------------------
# Each fence is a solid board of the lab (its profile in the x-y plane of the throw: the rectangle
# from the face to wall_thickness behind it, from the floor to wall_top). A ball (circle of radius r)
# meets it on its face, on its back, on its top or on one of its two top corners: the first time
# the centre comes within r of one of them, moving towards it. Faces and top: the centre on a line
# (x = face -+ r, y = top + r), with the contact point inside that side; corners: |centre - corner|
# = r (circle-point; inside a side's range that side is met first, so a corner needs no range).

const FACE := 0
const CORNER := 1
const TOP := 2
const BACK := 3

## The first fence contact within `limit` (s) of a piece starting with the centre at world x `x0`,
## height `y0` above the floor and constant accelerations: [time (INF: none), kind (FACE, CORNER,
## TOP, BACK), normal x, normal y, corner x, corner y]. Reads only the fence settings.
func _fence_event(x0: float, y0: float, vx: float, vy: float, ax: float, ay: float, limit: float) -> PackedFloat64Array:
	var best := PackedFloat64Array([INF, 0.0, 0.0, 0.0, 0.0, 0.0])
	var cx := PackedFloat64Array([x0, vx, 0.5 * ax])
	var cy := PackedFloat64Array([y0, vy, 0.5 * ay])
	# Where the centre can be in this piece (a finite piece: its box; none for an endless one).
	var bx := _span(cx, limit)
	var by := _span(cy, limit)
	for side in [1.0, -1.0]:
		var near: float = wall_x if side > 0.0 else wall_left_x
		if not is_finite(near):
			continue
		var far: float = near + side * wall_thickness
		if bx[1] < minf(near, far) - radius or bx[0] > maxf(near, far) + radius or by[0] > wall_top + radius:
			continue   # never within r of this board in the piece
		# Face towards the ball and back: the centre r in front of them, below the top.
		for line in [[near - side * radius, -side, FACE], [far + side * radius, side, BACK]]:
			var outward: float = line[1]
			var at: float = line[0]
			var gap := PackedFloat64Array([outward * (cx[0] - at), outward * cx[1], outward * cx[2]])
			for s in _entries(gap, minf(limit, best[0])):
				if _eval(cy, s) <= wall_top:
					best = PackedFloat64Array([s, line[2], outward, 0.0, 0.0, 0.0])
					break
		# Top: the centre r above it, over the board.
		var lo := minf(near, far)
		var hi := maxf(near, far)
		var above := PackedFloat64Array([cy[0] - wall_top - radius, cy[1], cy[2]])
		for s in _entries(above, minf(limit, best[0])):
			var x := _eval(cx, s)
			if x >= lo and x <= hi:
				best = PackedFloat64Array([s, TOP, 0.0, 1.0, 0.0, 0.0])
				break
		# Top corners: |centre - corner|^2 - r^2, a quartic in time.
		for corner_x: float in [near, far]:
			var a := PackedFloat64Array([cx[0] - corner_x, cx[1], cx[2]])
			var b := PackedFloat64Array([cy[0] - wall_top, cy[1], cy[2]])
			var f := PackedFloat64Array([a[0] * a[0] + b[0] * b[0] - radius * radius,
				2.0 * (a[0] * a[1] + b[0] * b[1]),
				a[1] * a[1] + b[1] * b[1] + 2.0 * (a[0] * a[2] + b[0] * b[2]),
				2.0 * (a[1] * a[2] + b[1] * b[2]),
				a[2] * a[2] + b[2] * b[2]])
			var e := _entries(f, minf(limit, best[0]))
			if e.size() > 0 and e[0] < best[0]:
				best = PackedFloat64Array([e[0], CORNER, 0.0, 0.0, corner_x, wall_top])
	return best


## Impact on a fence (`hit` from _fence_event, the model already at its time): restitution
## wall_restitution along the normal (the web's wall rule: v_n *= -e, no threshold) and Coulomb
## friction along the surface (_resolve). A ball on the floor meets the face together with the
## floor: both contacts at once (the floor pushes back what the face's friction presses into it).
## A rolling ball (topspin) is pushed up a little and hops back.
func _fence_impact(hit: PackedFloat64Array) -> void:
	var nx := hit[2]
	var ny := hit[3]
	if int(hit[1]) == CORNER:   # the normal from the corner to the centre
		var dx := _origin.x + _x - hit[4]
		var dy := _y + radius - hit[5]
		var length := sqrt(dx * dx + dy * dy)
		nx = dx / length
		ny = dy / length
	var vn := _vx * nx + _vy * ny
	wall_times.append(_t)
	wall_speeds.append(-vn)
	wall_kinds.append(int(hit[1]))
	var contacts := [[nx, ny, wall_restitution, false]]
	if _ground:
		contacts.append([0.0, 1.0, 0.0, true])
	var floor_mode := _resolve(contacts)
	if not _ground:
		return
	if floor_mode == SUPPORT_OFF and _vy > 0.0:
		_ground = false      # lifted off the floor by the fence's friction
		return
	_vy = 0.0
	if floor_mode == STICK and absf(_vx + radius * _w) > 0.0:
		_w = -_vx / radius   # the floor's friction ended the slip: rolling from here
		if roll_time < 0.0:
			roll_time = _t


## Floor impact with the current downward speed: bounce or stay, and the friction impulse.
func _impact() -> void:
	var v := -_vy
	impact_times.append(_t)
	impact_speeds.append(v)
	var e := restitution if v >= REST_SPEED else 0.0
	var slipping := _vx + radius * _w != 0.0
	var mode := _resolve([[0.0, 1.0, e, false]])
	if slipping and mode == STICK:
		_w = -_vx / radius   # the impact ended the slip: rolling from here
		if roll_time < 0.0:
			roll_time = _t
	if e > 0.0:
		_vy = e * v
		_ground = false
	else:
		_vy = 0.0
		_ground = true


# --- contact impulses ---------------------------------------------------------------------------
# A contact: unit normal n (from the surface to the ball's centre) in the x-y plane, tangent
# t = z x n = (-n_y, n_x), contact point at -r n. Impulses per mass N (along n) and T (along t);
# with the solid sphere's k = m r^2 / I (5/2): dv = N n + T t, d omega_z = -(r m / I) T, and the
# contact point's slip u = v . t - r omega_z changes by T (1 + k) (+ the other contact's share).
# Coulomb: |T| <= mu N; T ends the slip (stick) or is mu N against the slip that remains.

## Friction modes of a contact (the floor of a two-contact impact reports its own).
const STICK := 0
const SLIP_UP := 1         # T = +mu N
const SLIP_DOWN := 2       # T = -mu N
const SUPPORT_OFF := 3     # a supporting contact that does not push (the ball leaves it)

## Applies the impulses of the contacts `contacts` ([n_x, n_y, e, supporting]) to the velocity and
## the spin, all at once: an impact contact leaves with -e times its approach speed along n
## (Newton); a supporting one (the floor under a ball on it) pushes only as much as keeps the ball
## from going into it, or not at all (complementarity). Each pushing contact takes the Coulomb
## friction impulse above. One contact: closed form; two: the friction modes (stick, slip either
## way, support off) are tried in turn, each a linear system, and the first that satisfies every
## condition is applied. Returns the mode of the last contact.
func _resolve(contacts: Array) -> int:
	var inertia := _inertia()
	var k := mass * radius * radius / inertia
	if contacts.size() == 1:
		var c: Array = contacts[0]
		var nx: float = c[0]
		var ny: float = c[1]
		var n_imp: float = -(1.0 + float(c[2])) * (_vx * nx + _vy * ny)
		var u := -ny * _vx + nx * _vy - radius * _w
		var stick := -u / (1.0 + k)                     # the T that ends the slip
		var t_imp := clampf(stick, -mu * n_imp, mu * n_imp)
		_vx += n_imp * nx - t_imp * ny
		_vy += n_imp * ny + t_imp * nx
		_w -= radius * mass * t_imp / inertia
		if t_imp == stick:
			return STICK
		return SLIP_UP if t_imp > 0.0 else SLIP_DOWN
	var n_c := contacts.size()
	var modes := PackedInt32Array()
	modes.resize(n_c)
	var mode_lists: Array = []
	for c: Array in contacts:
		mode_lists.append([SUPPORT_OFF, STICK, SLIP_UP, SLIP_DOWN] if c[3] else [STICK, SLIP_UP, SLIP_DOWN])
	var combos := 1
	for list: Array in mode_lists:
		combos *= list.size()
	var scale := 1.0 + absf(_vx) + absf(_vy) + radius * absf(_w)
	var eps := 1e-12 * scale
	for combo in combos:
		var rest := combo
		for i in n_c:
			var list: Array = mode_lists[i]
			modes[i] = list[rest % list.size()]
			rest /= list.size()
		var z := _impulses(contacts, modes, k)
		if z.is_empty():
			continue
		var wx := _vx
		var wy := _vy
		var ww := _w
		var t_sum := 0.0
		for j in n_c:
			var cj: Array = contacts[j]
			wx += z[2 * j] * float(cj[0]) - z[2 * j + 1] * float(cj[1])
			wy += z[2 * j] * float(cj[1]) + z[2 * j + 1] * float(cj[0])
			t_sum += z[2 * j + 1]
		ww -= radius * mass * t_sum / inertia
		var ok := true
		for i in n_c:
			var ci: Array = contacts[i]
			var nx: float = ci[0]
			var ny: float = ci[1]
			var n_imp: float = z[2 * i]
			var t_imp: float = z[2 * i + 1]
			var u_after := -ny * wx + nx * wy - radius * ww
			match modes[i]:
				SUPPORT_OFF:
					ok = ok and wx * nx + wy * ny >= -eps
				STICK:
					ok = ok and n_imp >= -eps and absf(t_imp) <= mu * n_imp + eps
				SLIP_UP:
					ok = ok and n_imp >= -eps and u_after <= eps
				SLIP_DOWN:
					ok = ok and n_imp >= -eps and u_after >= -eps
		if ok:
			_vx = wx
			_vy = wy
			_w = ww
			return modes[n_c - 1]
	push_warning("RollingContact._resolve: no consistent contact mode; normal impulses only")
	for c: Array in contacts:
		if not c[3]:
			var n_imp: float = -(1.0 + float(c[2])) * (_vx * float(c[0]) + _vy * float(c[1]))
			_vx += n_imp * float(c[0])
			_vy += n_imp * float(c[1])
	return SUPPORT_OFF


## Impulses per mass [N_0, T_0, N_1, T_1, ...] of the contacts in the given modes (empty: none,
## the system is singular): the rows say what each mode fixes (normal: Newton or no penetration;
## tangent: no slip after, or T = +-mu N; support off: N = T = 0).
func _impulses(contacts: Array, modes: PackedInt32Array, k: float) -> PackedFloat64Array:
	var n := contacts.size() * 2
	var rows: Array = []
	var rhs := PackedFloat64Array()
	var u_now := -radius * _w
	for i in contacts.size():
		var ci: Array = contacts[i]
		var nx: float = ci[0]
		var ny: float = ci[1]
		var row_n := PackedFloat64Array()
		var row_t := PackedFloat64Array()
		row_n.resize(n)
		row_t.resize(n)
		if modes[i] == SUPPORT_OFF:
			row_n[2 * i] = 1.0
			row_t[2 * i + 1] = 1.0
			rows.append(row_n)
			rows.append(row_t)
			rhs.append(0.0)
			rhs.append(0.0)
			continue
		var vn := _vx * nx + _vy * ny
		var u := -ny * _vx + nx * _vy + u_now
		for j in contacts.size():
			var cj: Array = contacts[j]
			var mx: float = cj[0]
			var my: float = cj[1]
			# Contact j's N along n_j and T along t_j = (-m_y, m_x), seen along n_i and t_i.
			row_n[2 * j] = mx * nx + my * ny
			row_n[2 * j + 1] = -my * nx + mx * ny
			if modes[i] == STICK:
				row_t[2 * j] = -mx * ny + my * nx
				row_t[2 * j + 1] = my * ny + mx * nx + k
		rows.append(row_n)
		rhs.append(-(1.0 + float(ci[2])) * vn if not ci[3] else -vn)
		if modes[i] == STICK:
			rhs.append(-u)
		else:
			row_t[2 * i + 1] = 1.0
			row_t[2 * i] = -mu if modes[i] == SLIP_UP else mu
			rhs.append(0.0)
		rows.append(row_t)
	return _solve(rows, rhs)


## Gaussian elimination with partial pivoting (empty when singular).
static func _solve(rows: Array, rhs: PackedFloat64Array) -> PackedFloat64Array:
	var n := rhs.size()
	var a: Array = []
	for r: PackedFloat64Array in rows:
		a.append(r.duplicate())
	var b := rhs.duplicate()
	for col in n:
		var pivot := col
		for r in range(col + 1, n):
			if absf(a[r][col]) > absf(a[pivot][col]):
				pivot = r
		if absf(a[pivot][col]) < 1e-14:
			return PackedFloat64Array()
		if pivot != col:
			var tmp: PackedFloat64Array = a[col]
			a[col] = a[pivot]
			a[pivot] = tmp
			var tb := b[col]
			b[col] = b[pivot]
			b[pivot] = tb
		for r in range(col + 1, n):
			var f: float = a[r][col] / a[col][col]
			if f == 0.0:
				continue
			var row: PackedFloat64Array = a[r]
			for c in range(col, n):
				row[c] -= f * a[col][c]
			a[r] = row
			b[r] -= f * b[col]
	var x := PackedFloat64Array()
	x.resize(n)
	for r in range(n - 1, -1, -1):
		var acc := b[r]
		for c in range(r + 1, n):
			acc -= a[r][c] * x[c]
		x[r] = acc / a[r][r]
	return x


# --- polynomials in time ------------------------------------------------------------------------

## [min, max] of the quadratic c over [0, limit] (+-INF when the piece has no end).
static func _span(c: PackedFloat64Array, limit: float) -> PackedFloat64Array:
	if not is_finite(limit):
		return PackedFloat64Array([-INF, INF])
	var lo := minf(c[0], _eval(c, limit))
	var hi := maxf(c[0], _eval(c, limit))
	if c[2] != 0.0:
		var s := -c[1] / (2.0 * c[2])
		if s > 0.0 and s < limit:
			var v := _eval(c, s)
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return PackedFloat64Array([lo, hi])


## Value of c[0] + c[1] s + c[2] s^2 + ...
static func _eval(c: PackedFloat64Array, s: float) -> float:
	var acc := 0.0
	for i in range(c.size() - 1, -1, -1):
		acc = acc * s + c[i]
	return acc


## Times in [0, limit] at which the polynomial `c` (a distance-like value, > 0 apart) reaches 0
## falling (contact, the ball moving in), ascending. A touch at s = 0 counts only when moving in.
static func _entries(c: PackedFloat64Array, limit: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var d := PackedFloat64Array()
	for i in range(1, c.size()):
		d.append(i * c[i])
	if absf(c[0]) <= 1e-12 and d.size() > 0 and d[0] < 0.0:
		out.append(0.0)
		return out
	for s in _roots(c, 0.0, limit):
		if s > 0.0 and _eval(d, s) < 0.0:
			out.append(s)
	return out


## Real roots of the polynomial `c` (degree <= 4) in [lo, hi], ascending: closed forms up to the
## quadratic, above it the roots of the derivative split the range into monotone pieces, each
## bisected to the last bit. An infinite `hi` is cut at the Cauchy bound of the roots.
static func _roots(c: PackedFloat64Array, lo: float, hi: float) -> PackedFloat64Array:
	var deg := c.size() - 1
	while deg > 0 and c[deg] == 0.0:
		deg -= 1
	var out := PackedFloat64Array()
	if deg <= 0:
		return out
	var bound := 0.0
	for i in deg:
		bound = maxf(bound, absf(c[i] / c[deg]))
	hi = minf(hi, 1.0 + bound)
	if hi < lo:
		return out
	if deg == 1:
		var s := -c[0] / c[1]
		if s >= lo and s <= hi:
			out.append(s)
		return out
	if deg == 2:
		var disc := c[1] * c[1] - 4.0 * c[2] * c[0]
		if disc < 0.0:
			return out
		var q := -0.5 * (c[1] + (sqrt(disc) if c[1] >= 0.0 else -sqrt(disc)))
		var pair := [q / c[2], c[0] / q if q != 0.0 else q / c[2]]
		pair.sort()
		for s: float in pair:
			if s >= lo and s <= hi and (out.is_empty() or s != out[-1]):
				out.append(s)
		return out
	var d := PackedFloat64Array()
	for i in range(1, deg + 1):
		d.append(i * c[i])
	var cuts := PackedFloat64Array([lo])
	cuts.append_array(_roots(d, lo, hi))
	cuts.append(hi)
	for i in cuts.size() - 1:
		var a := cuts[i]
		var b := cuts[i + 1]
		var fa := _eval(c, a)
		var fb := _eval(c, b)
		if fa == 0.0:
			if out.is_empty() or a != out[-1]:
				out.append(a)
			continue
		if fa * fb > 0.0 or b <= a:
			continue
		if fb == 0.0:
			continue   # appended as the next piece's start (or the end below)
		for it in 200:
			var m := 0.5 * (a + b)
			if m <= a or m >= b:
				break
			var fm := _eval(c, m)
			if (fm < 0.0) == (fa < 0.0) and fm != 0.0:
				a = m
				fa = fm
			else:
				b = m
		out.append(b)
	if _eval(c, hi) == 0.0 and (out.is_empty() or hi != out[-1]):
		out.append(hi)
	return out
