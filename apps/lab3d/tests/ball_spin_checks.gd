## Headless checks of the balls' spin, bounces and rolling (Phase 1 Task 4f), run by run_tests.gd.
## The ball is a solid sphere (I = 2/5 m r^2) and every expected value comes from textbook closed
## forms written out here (_Oracle), independently of the lab's RollingContact model:
## 1. flight: no torque, so omega stays what it was (0 when thrown without spin; a given spin turns
##    the body by omega dt every step), the flight positions are unchanged.
## 2. after the landing, the engine ball against the oracle step by step: bounces at the formula
##    times with e v (apex (e v)^2 / 2g, never into the floor), stop bouncing below 1 m/s, the
##    Coulomb friction impulse of each impact, slide -> roll at t* = 2 |u| / (7 mu g), rolling
##    resistance a = mu_roll g with v = omega r until the stop v^2 / (2 mu_roll g); throws, a level
##    roll along the floor, a slipping bounce (small mu), free fall drops; landing reactions and the
##    landing step still come.
## 3. where the thrown ball stops: the default and the farthest throw (reported).
## 4. what is seen turning is the body: the mesh (the yarn ball) is its child with no turn of its own.
## 5. free fall: the two balls never turn and do not drift sideways through their bounces.
## 6. collision lab (model driven): each ball's mesh turns by its travel over its radius (v = omega r).
## 7. colours (2026-10-23 user request): the free-fall balls and the development scene's boxes are
##    red / yellow / violet, and every label (ball names, observations, graph series and colours,
##    option notes) names the colour the mesh has; the balls are yarn balls (Task 4g: the yarn model,
##    textured, as big as the ball), the drop pads are white / grey.
extends RefCounted

const STEP_HZ := 60

## Records a ball's state after its corrector ran, once per physics frame.
class Recorder:
	extends Node
	var body: RigidBody3D
	var corrector: UniformFieldCorrector
	var steps := PackedInt32Array()
	var positions := PackedVector3Array()
	var bases: Array[Basis] = []
	var velocities := PackedVector3Array()
	var spins := PackedVector3Array()

	func _init() -> void:
		process_physics_priority = 100   # after the ball's own _physics_process

	func _physics_process(_delta: float) -> void:
		if body == null or body.freeze:
			return
		steps.append(corrector.steps - 1)
		positions.append(body.global_position)
		bases.append(body.global_basis)
		velocities.append(body.linear_velocity)
		spins.append(body.angular_velocity)

	func clear() -> void:
		steps.clear()
		positions.clear()
		bases.clear()
		velocities.clear()
		spins.clear()


## Textbook closed forms of a ball thrown in the x-y plane over a level floor (time from the
## release): segment list built once, evaluated at any t. x from the release, y = bottom height,
## turn about z.
class _Oracle:
	var g := 9.81
	var e := 0.6
	var mu := 0.6
	var mu_roll := 0.05
	var r := 0.25
	var landing := INF
	var impacts := PackedFloat64Array()   # impact times
	var speeds := PackedFloat64Array()    # approach speeds
	var roll_at := -1.0
	var stop_at := -1.0
	# segments: [t0, x0, y0, vx0, vy0, w0, th0, kind] kind 0 air, 1 slide, 2 roll, 3 rest
	var segments: Array = []

	func _init(h0: float, vx0: float, vy0: float, field: float, restitution: float, friction: float, resistance: float, radius: float, spin := 0.0) -> void:
		g = field
		e = restitution
		mu = friction
		mu_roll = resistance
		r = radius
		landing = PhysicsLaws.landing_time(vy0, -g, h0)
		segments.append([0.0, 0.0, h0, vx0, vy0, spin, 0.0, 0])
		if not is_finite(landing):
			return
		var t := landing
		var vx := vx0
		var w := spin
		var x := vx0 * t
		var th := spin * t
		var v := -(vy0 - g * t)
		if landing == 0.0 and v <= 0.0:
			v = 0.0
		# Bounces: each impact turns by the Coulomb impulse (per mass), then flies up at e v.
		while true:
			if v > 0.0:
				impacts.append(t)
				speeds.append(v)
			var ei := e if v >= 1.0 else 0.0
			var u := vx + r * w
			var stick := absf(u) * 2.0 / 7.0                 # 1 / (1 + m r^2 / I) = 2/7
			var p := minf(mu * (1.0 + ei) * v, stick)
			vx -= signf(u) * p
			w -= signf(u) * p * 5.0 / (2.0 * r)               # r P / I = 5 P / (2 r m)
			if stick <= mu * (1.0 + ei) * v and u != 0.0:
				w = -vx / r
				if roll_at < 0.0:
					roll_at = t
			if ei == 0.0:
				break
			var up := ei * v
			segments.append([t, x, 0.0, vx, up, w, th, 0])
			var flight := 2.0 * up / g
			x += vx * flight
			th += w * flight
			t += flight
			v = up
		# On the floor: slide while u != 0, then roll with resistance, then rest.
		var u := vx + r * w
		if absf(u) > 1e-12:
			segments.append([t, x, 0.0, vx, 0.0, w, th, 1])
			var a := -mu * g * signf(u)
			var ts := absf(u) / (3.5 * mu * g)
			x += vx * ts + 0.5 * a * ts * ts
			th += w * ts + 0.5 * (a * 5.0 / (2.0 * r)) * ts * ts
			vx += a * ts
			w = -vx / r
			t += ts
			if roll_at < 0.0:
				roll_at = t
		if vx != 0.0:
			segments.append([t, x, 0.0, vx, 0.0, w, th, 2])
			var tr := absf(vx) / (mu_roll * g)
			x += vx * tr - 0.5 * signf(vx) * mu_roll * g * tr * tr
			th -= (x - segments[-1][1]) / r
			t += tr
			stop_at = t
		segments.append([t, x, 0.0, 0.0, 0.0, 0.0, th, 3])

	## [x, y, vx, turn] at t.
	func at(t: float) -> PackedFloat64Array:
		var s: Array = segments[0]
		for seg in segments:
			if seg[0] <= t:
				s = seg
		var d: float = t - s[0]
		match int(s[7]):
			0:
				return PackedFloat64Array([s[1] + s[3] * d, s[2] + s[4] * d - 0.5 * g * d * d, s[3], s[6] + s[5] * d])
			1:
				var u: float = s[3] + r * s[5]
				var a := -mu * g * signf(u)
				return PackedFloat64Array([s[1] + s[3] * d + 0.5 * a * d * d, 0.0, s[3] + a * d, s[6] + s[5] * d + 0.25 * a * 5.0 / r * d * d])
			2:
				var a2 := -mu_roll * g * signf(s[3])
				var dx: float = s[3] * d + 0.5 * a2 * d * d
				return PackedFloat64Array([s[1] + dx, 0.0, s[3] + a2 * d, s[6] - dx / r])
		return PackedFloat64Array([s[1], 0.0, 0.0, s[6]])


var tree: SceneTree
var expect: Callable   # (ok: bool, label: String, detail: String)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_flight_spin()
	await check_contact_against_oracle()
	await check_where_throws_stop()
	await check_fences()
	await check_fence_in_flight()
	await check_fence_corner()
	await check_fence_on_floor_backspin()
	check_frictionless_slide()
	await check_zero_gravity_fences()
	await check_fence_preview()
	await check_mesh_is_body()
	await check_free_fall_no_spin()
	await check_collision_mesh_rolls()
	await check_ball_colours()


# --- helpers ----------------------------------------------------------------------------------

func _lab(id: String) -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find(id))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


func _recorder(lab: Experiment, ball: RigidBody3D) -> Recorder:
	var r := Recorder.new()
	r.body = ball
	r.corrector = ball.corrector
	lab.add_child(r)
	return r


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


## Turn (rad) about world z from basis a to basis b (|turn| < pi).
static func _turn_z(a: Basis, b: Basis) -> float:
	var q := (b * a.inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	return 2.0 * atan2(q.z, q.w)


## A projectile throw from the floor level (`height` of the ball's bottom) with angle / speed.
func _throw(lab: Experiment, angle: float, speed: float, height: float, gravity := "earth") -> void:
	lab.set_control("gravity", gravity)
	lab.set_control("angle", angle)
	lab.set_control("speed", speed)
	lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(lab.START_X, height + lab.BALL_RADIUS, 0.0)))


# --- 1. flight ---------------------------------------------------------------------------------

func check_flight_spin() -> void:
	var lab: Experiment = await _lab("projectile")
	var rec := _recorder(lab, lab.ball)
	lab.release()
	var c: UniformFieldCorrector = lab.corrector()
	var landing := roundi(lab.flight_time() * STEP_HZ)
	while c.steps - 1 < landing - 2:
		await tree.physics_frame
	var worst := 0.0
	for i in rec.steps.size():
		worst = maxf(worst, rec.spins[i].length())
		worst = maxf(worst, (rec.bases[i] * Basis().inverse()).get_rotation_quaternion().get_angle())
	expect.call(worst == 0.0 and not c.rolling.active,
		"ball spin: a ball thrown without spin does not turn in the air (omega 0, body unturned up to the landing)", "max %s over %d steps" % [str(worst), rec.steps.size()])
	# With a spin: the same flight, the body turns by omega dt every step, omega constant.
	rec.clear()
	lab.release()
	var spin := Vector3(0.0, 0.0, 7.5)
	c.rolling.release(lab.ball, lab.launch_velocity(), c.g, spin.z)
	while c.steps - 1 < landing - 2:
		await tree.physics_frame
	var worst_w := 0.0
	var worst_turn := 0.0
	for i in range(1, rec.steps.size()):
		worst_w = maxf(worst_w, (rec.spins[i] - spin).length())
		worst_turn = maxf(worst_turn, absf(_turn_z(rec.bases[i - 1], rec.bases[i]) - spin.z / STEP_HZ))
	var flight_diff := 0.0
	for k in range(1, landing - 2):
		var t := k / float(STEP_HZ)
		flight_diff = maxf(flight_diff, absf(c.offsets[k].x - lab.formula_x(t)))
		flight_diff = maxf(flight_diff, absf(c.offsets[k].y + lab.launch_height() - lab.formula_y(t)))
	expect.call(worst_w <= 1e-6 and worst_turn <= 1e-5 and flight_diff <= 1e-4,
		"ball spin: a spinning ball keeps omega in the air (no torque) and turns omega dt per step; its flight is the same parabola",
		"|omega - omega0| %s, turn per step - omega dt %s rad, flight vs formula %s m" % [String.num_scientific(worst_w), String.num_scientific(worst_turn), String.num_scientific(flight_diff)])
	await _free(lab)


# --- 2. after the landing ---------------------------------------------------------------------

## Runs one release of `ball` (corrector c) until `seconds` or the island stops it, and compares every
## recorded step with the oracle: [worst position, worst turn, worst below the floor, steps].
func _against(lab: Experiment, ball: RigidBody3D, oracle: _Oracle, seconds: float, start_x: float) -> PackedFloat64Array:
	var rec := _recorder(lab, ball)
	var c: UniformFieldCorrector = ball.corrector
	while c.steps - 1 < roundi(seconds * STEP_HZ) and not ball.freeze:
		await tree.physics_frame
	var worst_p := 0.0
	var worst_turn := 0.0
	var below := 0.0
	var turn := 0.0
	var floor_center: float = lab.BALL_RADIUS
	for i in rec.steps.size():
		var t := rec.steps[i] / float(STEP_HZ)
		var want := oracle.at(t)
		if i > 0:
			turn += _turn_z(rec.bases[i - 1], rec.bases[i])
		var p := rec.positions[i]
		worst_p = maxf(worst_p, maxf(absf(p.x - start_x - want[0]), absf(p.y - floor_center - want[1])))
		worst_turn = maxf(worst_turn, absf(wrapf(turn - want[3], -PI, PI)))
		below = maxf(below, floor_center - p.y)
	var n := rec.steps.size()
	rec.queue_free()
	return PackedFloat64Array([worst_p, worst_turn, below, n])


func check_contact_against_oracle() -> void:
	var lab: Experiment = await _lab("projectile")
	var r: float = lab.BALL_RADIUS
	var details := []
	var worst := PackedFloat64Array([0.0, 0.0, 0.0])
	var events_ok := true
	var landed_ok := true
	var juice_landings := [0]
	lab.props.juice.landed.connect(func(_s: float) -> void: juice_landings[0] += 1)
	# [gravity, angle, speed, height, mu (null = the lab's), seconds]
	for run in [["earth", 45.0, 9.0, 0.5, null, 4.0], ["jupiter", 15.0, 5.0, 3.0, null, 4.0], ["moon", 60.0, 4.0, 1.5, null, 8.0],
			["earth", 0.0, 4.0, 0.0, null, 6.0], ["earth", 0.0, 9.0, 0.0, null, 4.0], ["moon", 0.0, 1.5, 0.0, null, 5.0],
			["earth", 45.0, 9.0, 0.5, 0.02, 4.0], ["earth", 45.0, 5.0, 0.5, null, 7.0]]:
		_throw(lab, run[1], run[2], run[3], run[0])
		lab.release()
		var c: UniformFieldCorrector = lab.corrector()
		if run[4] != null:
			c.rolling.mu = run[4]
		# The floor laws alone here (the fences have their own check below).
		c.rolling.wall_x = INF
		c.rolling.wall_left_x = -INF
		var o := _Oracle.new(lab.launch_height(), lab.launch_velocity().x, lab.launch_velocity().y, lab.g, lab.BOUNCE,
			c.rolling.mu, lab.ROLLING_RESISTANCE, r)
		juice_landings[0] = 0
		var got := await _against(lab, lab.ball, o, run[5], lab.ball_center().x)
		for i in 3:
			worst[i] = maxf(worst[i], got[i])
		var model: RollingContact = c.rolling
		var elapsed := (c.steps - 1) / float(STEP_HZ)
		var due := 0   # oracle impacts the run has reached
		for t in o.impacts:
			if t <= elapsed:
				due += 1
		var same_events := model.impact_times.size() >= due
		for i in mini(model.impact_times.size(), due):
			same_events = same_events and absf(model.impact_times[i] - o.impacts[i]) <= 1e-9 and absf(model.impact_speeds[i] - o.speeds[i]) <= 1e-9
		var stop_ok := absf(model.stop_time - o.stop_at) <= 1e-9 if o.stop_at <= elapsed else model.stop_time < 0.0
		events_ok = events_ok and same_events and (stop_ok or lab.ball.freeze)
		if not (same_events and (stop_ok or lab.ball.freeze)):
			details.append("EVENTS DIFFER: model %s / %s, stop %.4f vs %.4f" % [str(model.impact_times), str(o.impacts), model.stop_time, o.stop_at])
		if o.landing > 0.0:
			var this_ok: bool = c.landed_step == ceili(o.landing * STEP_HZ - 1e-9) and juice_landings[0] == 1
			landed_ok = landed_ok and this_ok
			if not this_ok:
				details.append("LANDING: step %d (want %d), reactions %d" % [c.landed_step, ceili(o.landing * STEP_HZ - 1e-9), juice_landings[0]])
		details.append("%s %d° %.1f m/s h %.1f%s: %d bounces %s, roll %.3f s, stop %s, %d steps%s" % [run[0], run[1], run[2], run[3],
			"" if run[4] == null else " mu %.2f" % run[4], o.impacts.size(), str(Array(o.impacts).map(func(t: float) -> String: return "%.3f" % t)),
			o.roll_at, "%.3f s" % o.stop_at if o.stop_at >= 0.0 else "—", got[3], " (left the island)" if lab.ball.freeze else ""])
		lab.run_action("reset")
		c.rolling.mu = lab.BALL_FRICTION
		c.rolling.wall_x = lab.FENCE_X
		c.rolling.wall_left_x = lab.FENCE_LEFT_X
	expect.call(worst[0] <= 1e-4 and worst[1] <= 1e-4 and worst[2] <= 1e-5 and events_ok and landed_ok,
		"ball contact: after the landing the engine ball follows the textbook bounces (e v at the formula times, stop below 1 m/s), Coulomb impulses, slide -> roll and rolling resistance step by step, never into the floor; landing step and reaction still come",
		"position %s m, turn %s rad, below the floor %s m; %s" % [String.num_scientific(worst[0]), String.num_scientific(worst[1]), String.num_scientific(worst[2]), "; ".join(details)])
	# Free fall: three drops with the free-fall restitution.
	var ff: Experiment = await _lab("free-fall")
	var worst_ff := 0.0
	var below_ff := 0.0
	var ff_details := []
	for run in [["earth", 5.0], ["moon", 8.0], ["jupiter", 2.0]]:
		ff.set_control("gravity", run[0])
		ff.set_control("height", run[1])
		ff.release()
		var o := _Oracle.new(run[1], 0.0, 0.0, ff.g, ff.BOUNCE, ff.BALL_FRICTION, ff.ROLLING_RESISTANCE, r)
		var got := await _against(ff, ff.balls.red, o, o.impacts[-1] + 0.5 if o.impacts.size() > 0 else 3.0, ff.starts.red.x)
		worst_ff = maxf(worst_ff, got[0])
		below_ff = maxf(below_ff, got[2])
		var apexes := []
		for i in range(1, o.impacts.size()):
			apexes.append("%.3f" % (pow(ff.BOUNCE * o.speeds[i - 1], 2) / (2.0 * ff.g)))
		ff_details.append("%s %.0f m: impacts %s s, apexes (e v)^2 / 2g %s m" % [run[0], run[1], str(Array(o.impacts).map(func(t: float) -> String: return "%.3f" % t)), str(apexes)])
		ff.run_action("reset")
	expect.call(worst_ff <= 1e-4 and below_ff <= 1e-5,
		"ball contact: free-fall drops bounce at the formula times to e^2 times the height before (e 0.5), never into the floor",
		"position %s m, below %s m; %s" % [String.num_scientific(worst_ff), String.num_scientific(below_ff), "; ".join(ff_details)])
	await _free(ff)
	await _free(lab)


# --- 3. where the throws stop ------------------------------------------------------------------

## The default throw and the farthest (9 m/s, 0°, from 3 m) against the island's edge (x 12.5 m):
## the oracle's stop point, and whether the ball stays on the island (reported, not required).
func check_where_throws_stop() -> void:
	var lab: Experiment = await _lab("projectile")
	var lines := []
	var ok := true
	for run in [["default 45° 9 m/s 0.5 m", 45.0, 9.0, 0.5, -6.0], ["farthest 0° 9 m/s 3 m", 0.0, 9.0, 3.0, -3.0],
			["45° 5 m/s 0.5 m", 45.0, 5.0, 0.5, -6.0]]:
		lab.set_control("angle", run[1])
		lab.set_control("speed", run[2])
		lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(run[4], run[3] + lab.BALL_RADIUS, 0.0)))
		var o := _Oracle.new(lab.launch_height(), lab.launch_vx(), lab.launch_vy(), lab.g, lab.BOUNCE, lab.BALL_FRICTION, lab.ROLLING_RESISTANCE, lab.BALL_RADIUS)
		var rest: PackedFloat64Array = o.at(o.stop_at + 1.0)
		var stop_x: float = run[4] + rest[0]
		var roll_v: float = o.segments[-2][3]
		var stop_dist: float = roll_v * roll_v / (2.0 * lab.ROLLING_RESISTANCE * lab.g)
		ok = ok and absf(rest[0] - o.segments[-2][1] - stop_dist) <= 1e-9
		lines.append("%s: rolls from x %.2f m at %.3f m/s, stops after %.2f m (v^2 / 2 mu_r g) at x %.2f m, %.2f s -> %s" % [run[0],
			run[4] + o.segments[-2][1], roll_v, stop_dist, stop_x, o.stop_at, "on the island" if stop_x <= lab.BOUNDS_X.y else "leaves the island (edge 12.5 m)"])
	expect.call(ok, "ball rolling: where thrown balls would stop without the fences (stop distance v^2 / (2 mu_r g) after the last bounce)", "; ".join(lines))
	await _free(lab)


# --- 3b. fences --------------------------------------------------------------------------------

## The projectile island's fences (2026-10-23 user decision). A level roll into the right fence
## against closed forms: contact time and speed (slide, then roll with resistance), back at e v,
## the Coulomb impulse along the face lifting a topspinning ball (vy = min(mu (1 + e) v, 2/7 v))
## and its hop as a parabola; then the default and the farthest throws come to rest on the island
## between the fences (engine ball at rest).
func check_fences() -> void:
	var lab: Experiment = await _lab("projectile")
	var r: float = lab.BALL_RADIUS
	var g: float = lab.g
	var mu: float = lab.BALL_FRICTION
	var mu_r: float = lab.ROLLING_RESISTANCE
	var e: float = lab.BOUNCE
	var details := []
	# Level roll from the floor at x -3 with 9 m/s.
	lab.set_control("angle", 0.0)
	lab.set_control("speed", 9.0)
	lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(-3.0, r, 0.0)))
	var rec := _recorder(lab, lab.ball)
	lab.release()
	var c: UniformFieldCorrector = lab.corrector()
	var v0 := 9.0
	var ts := PhysicsLaws.slide_to_roll_time(v0, mu, g)
	var xs := v0 * ts - 0.5 * mu * g * ts * ts
	var vr := PhysicsLaws.rolling_speed_after_slip(v0, v0)
	var gap: float = (lab.FENCE_X - r) - (-3.0) - xs           # rolling distance to the fence
	var a := mu_r * g
	var tr := (vr - sqrt(vr * vr - 2.0 * a * gap)) / a   # first root of vr t - a t^2 / 2 = gap
	var t_wall := ts + tr
	var v_wall := vr - a * tr
	var vy_up := minf(mu * (1.0 + e) * v_wall, 2.0 / 7.0 * v_wall)
	var hop := 2.0 * vy_up / g
	while c.steps - 1 < ceili((t_wall + hop) * STEP_HZ) + 2 and not lab.ball.freeze:
		await tree.physics_frame
	var model: RollingContact = c.rolling
	var wall_ok := model.wall_times.size() >= 1 and absf(model.wall_times[0] - t_wall) <= 1e-9 and absf(model.wall_speeds[0] - v_wall) <= 1e-9
	var worst_hop := 0.0
	var top := -INF
	for i in rec.steps.size():
		var t := rec.steps[i] / float(STEP_HZ)
		if t <= t_wall or t >= t_wall + hop:
			continue
		var d := t - t_wall
		worst_hop = maxf(worst_hop, absf(rec.positions[i].x - ((lab.FENCE_X - r) - e * v_wall * d)))
		worst_hop = maxf(worst_hop, absf(rec.positions[i].y - r - (vy_up * d - 0.5 * g * d * d)))
		top = maxf(top, rec.positions[i].y - r)
	rec.queue_free()
	details.append("roll into the fence: contact %.4f s at %.4f m/s (closed form %.4f s, %.4f m/s), back at %.4f m/s, hop up %.4f m/s (%.3f m high)" % [
		model.wall_times[0] if model.wall_times.size() > 0 else -1.0, model.wall_speeds[0] if model.wall_speeds.size() > 0 else -1.0, t_wall, v_wall, e * v_wall, vy_up, vy_up * vy_up / (2.0 * g)])
	# Rest on the island: the default and the farthest throws.
	var rest_ok := true
	for run in [["default 45° 9 m/s 0.5 m", 45.0, 9.0, 0.5, -6.0], ["farthest 45° 9 m/s 3 m", 45.0, 9.0, 3.0, -3.0], ["fast level 0° 9 m/s 3 m", 0.0, 9.0, 3.0, -3.0]]:
		lab.set_control("angle", run[1])
		lab.set_control("speed", run[2])
		lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(run[4], run[3] + r, 0.0)))
		lab.release()
		var cc: UniformFieldCorrector = lab.corrector()
		var guard := 0
		while cc.rolling.stop_time < 0.0 and not lab.ball.freeze and guard < 40 * STEP_HZ:
			await tree.physics_frame
			guard += 1
		for i in 3:
			await tree.physics_frame
		var x: float = lab.ball.global_position.x
		var still: bool = lab.ball.linear_velocity.length() < 1e-4
		var on: bool = not lab.ball.freeze and x > lab.FENCE_LEFT_X + r - 1e-4 and x < lab.FENCE_X - r + 1e-4 and still and lab.status() == "landed"
		rest_ok = rest_ok and on
		rest_ok = rest_ok and cc.rolling._t >= (cc.steps - 1) / float(STEP_HZ) - 1e-9   # the step guard never ran out before the model caught up
		details.append("%s: %d fence hits, rests at x %.2f m after %.2f s%s" % [run[0], cc.rolling.wall_times.size(), x, cc.rolling.stop_time, "" if on else " (NOT ON THE ISLAND)"])
	# The fences stand wholly on the island top: every vertex within the inscribed circle of its
	# 14-sided top (apothem R cos(pi / 14)).
	var apothem := ArtKit.ISLAND_RADIUS * cos(PI / ArtKit.ISLAND_SIDES)
	var centre := ProjectileProps.ISLAND_CENTER
	var farthest := 0.0
	var fence_mesh: Mesh = lab.props.fence.mesh
	for surface in fence_mesh.get_surface_count():
		for v: Vector3 in fence_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = lab.props.fence.global_transform * v
			farthest = maxf(farthest, Vector2(w.x - centre.x, w.z - centre.z).length())
	var on_island := farthest <= apothem
	details.append("fence vertices up to %.2f m from the island centre (top inscribed radius %.2f m)" % [farthest, apothem])
	expect.call(wall_ok and worst_hop <= 1e-4 and rest_ok and on_island,
		"ball fences: on the island top; a roll meets the fence at the closed-form time and speed, bounces back at e v and hops by the Coulomb impulse; the default and farthest throws rest on the island",
		"hop vs closed form %s m; %s" % [String.num_scientific(worst_hop), "; ".join(details)])
	await _free(lab)


## A flight that meets the fence below its top (2026-10-23 user decision; the moon's long low throws,
## here 75 deg, 7.5 m/s from 1 m at x -8 m)
## hits it: the flight is the formula's up to the closed-form time (x reaches the face), there it
## bounces back at e v, the state reads "울타리에 맞음", the panel keeps the formula range and flight
## time and shows the flight at the fence time, no measured landing, and the ball stays on the
## island. A scan of moon throws (pure model) finds none passing through the fence.
func check_fence_in_flight() -> void:
	var lab: Experiment = await _lab("projectile")
	var r: float = lab.BALL_RADIUS
	lab.set_control("gravity", "moon")
	lab.set_control("angle", 75.0)
	lab.set_control("speed", 7.5)
	lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(-8.0, 1.0 + r, 0.0)))
	var rec := _recorder(lab, lab.ball)
	# The release velocity the corrector gets is the 32-bit launch_velocity().
	var vx: float = lab.launch_velocity().x
	var vy: float = lab.launch_velocity().y
	var g: float = lab.g
	var t_hit: float = (lab.FENCE_X - r - lab.ball_center().x) / vx
	var y_hit: float = lab.launch_height() + vy * t_hit - 0.5 * g * t_hit * t_hit
	lab.release()
	var c: UniformFieldCorrector = lab.corrector()
	var guard := 0
	while c.steps - 1 < ceili(t_hit * STEP_HZ) + 30 and guard < 2000:   # (a frozen ball stops the steps)
		await tree.physics_frame
		guard += 1
	var shown: Dictionary = lab.observations()
	var model: RollingContact = c.rolling
	var worst_flight := 0.0
	for i in rec.steps.size():
		var t := rec.steps[i] / float(STEP_HZ)
		if t >= t_hit:
			continue
		worst_flight = maxf(worst_flight, maxf(absf(rec.positions[i].x - lab.ball_center().x - lab.formula_x(t)), absf(rec.positions[i].y - r - lab.formula_y(t))))
	rec.queue_free()
	var hit_ok: bool = model.fence_time < lab.flight_time() and absf(model.fence_time - t_hit) <= 1e-9 and model.wall_speeds.size() >= 1 and absf(model.wall_speeds[0] - vx) <= 1e-9 and y_hit < lab.FENCE_HEIGHT
	var panel_ok: bool = shown.state == "울타리에 맞음" and lab.status() == "fence" and absf(float(shown.time) - t_hit) <= 1e-9 and float(shown.range) == lab.flight_range() \
		and float(shown.flight_time) == lab.flight_time() and str(shown.landing) == "—" and c.landed_step < 0
	for i in 20 * STEP_HZ:
		if model.stop_time >= 0.0 or lab.ball.freeze:
			break
		await tree.physics_frame
	var x: float = lab.ball.global_position.x
	var stays: bool = not lab.ball.freeze and x < lab.FENCE_X - r + 1e-4 and x > lab.FENCE_LEFT_X + r - 1e-4
	var face_r: float = lab.FENCE_X
	var top: float = lab.FENCE_HEIGHT
	var lab_values: Experiment = lab   # (kept until the scan is done: its constants)
	# Moon scan (pure model, the lab's fences and boards): a flight whose centre crosses the face
	# line below the top meets the face and ends on the island side; one crossing within r above the
	# top may meet the top corner (and go over or come back); none ever reaches into a board
	# (the model's centre sampled every 1/30 s for 20 s from the contact).
	var body := RigidBody3D.new()
	body.mass = 1.0
	tree.root.add_child(body)
	var crossing := 0
	var through := 0
	var band := 0
	var corner_hits := 0
	var deepest := 0.0
	for angle in range(0, 91, 15):
		for k in range(2, 19):
			for hh in range(0, 13):
				for x0: float in [-8.0, -5.5, -3.0]:
					var speed := k * 0.5
					var h := hh * 0.25
					var cvx := speed * cos(deg_to_rad(angle))
					var cvy := speed * sin(deg_to_rad(angle))
					var land := PhysicsLaws.landing_time(cvy, -1.62, h)
					var xc: float = face_r - r
					if cvx <= 0.0 or x0 + cvx * land <= xc:
						continue
					var tc: float = (xc - x0) / cvx
					var centre := h + r + cvy * tc - 0.81 * tc * tc
					if centre > top + r:
						continue   # clear over the top: "섬 밖으로 날아감" as before
					var m := _fenced_model(lab_values)
					body.global_position = Vector3(x0, h + r, 0.0)
					m.release(body, Vector3(cvx, cvy, 0.0), 1.62)
					m._start()   # take over at once (at the fence or the landing)
					var t := m._t
					for i in 600:
						t += 1.0 / 30.0
						var st: PackedFloat64Array = m.state_at(t)
						deepest = maxf(deepest, _overlap(lab_values, x0 + st[0], st[1] + r))
					var end: PackedFloat64Array = m.state_at(400.0)
					if centre <= top:
						crossing += 1
						if not is_finite(m.fence_time) or m.wall_kinds[0] != RollingContact.FACE or x0 + end[0] > xc + 1e-6:
							through += 1
					else:
						band += 1
						if m.wall_kinds.size() > 0 and m.wall_kinds[0] == RollingContact.CORNER:
							corner_hits += 1
	body.queue_free()
	# (A 9.5 s moon flight: the engine's float32 position steps add up to ~1.1e-4 m by the fence.)
	await _free(lab)
	expect.call(hit_ok and worst_flight <= 2e-4 and panel_ok and stays and crossing > 0 and through == 0 and deepest <= 1e-9,
		"ball fences: a flight meeting the fence below its top hits it at the closed-form time with its flight speed (flight = formula until then), reads '울타리에 맞음' with the formula range / time kept, and stays on the island; moon scan: none pass through, none reach into a board",
		"hit %.4f s (closed form %.4f s, y %.2f m), vx %.4f m/s, flight vs formula %s m, state '%s', time %s, landing %s, rests at x %.2f m; moon scan: %d crossings with the centre below the top (%d through), %d within r above it (%d meet the corner), deepest into a board %s m" % [
			model.fence_time, t_hit, y_hit, vx, String.num_scientific(worst_flight), shown.state, str(shown.time), str(shown.landing), x, crossing, through, band, corner_hits, String.num_scientific(deepest)])


# --- 3c. fence geometry, two contacts, no friction, zero gravity, preview -----------------------

## A pure model with the projectile lab's fences (RollingContact, no lab).
static func _fenced_model(lab: Experiment) -> RollingContact:
	var m := RollingContact.new()
	m.radius = lab.BALL_RADIUS
	m.mu = lab.BALL_FRICTION
	m.mu_roll = lab.ROLLING_RESISTANCE
	m.restitution = lab.BOUNCE
	m.wall_x = lab.FENCE_X
	m.wall_left_x = lab.FENCE_LEFT_X
	m.wall_top = lab.FENCE_HEIGHT
	m.wall_thickness = lab.FENCE_THICKNESS
	m.wall_restitution = lab.BOUNCE
	return m


## How far (m) a ball centred at (x, y) (y above the floor) reaches into a fence board of `lab`
## (0: apart; the boards' rectangles in the x-y plane).
static func _overlap(lab: Experiment, x: float, y: float) -> float:
	var r: float = lab.BALL_RADIUS
	var worst := 0.0
	for side in [1.0, -1.0]:
		var near: float = lab.FENCE_X if side > 0.0 else lab.FENCE_LEFT_X
		var far: float = near + side * lab.FENCE_THICKNESS
		var dx := x - clampf(x, minf(near, far), maxf(near, far))
		var dy := y - clampf(y, 0.0, lab.FENCE_HEIGHT)
		worst = maxf(worst, r - sqrt(dx * dx + dy * dy))
	return worst


## Post-impact velocity and spin of one contact with unit normal n (closed form, solid sphere):
## v' = v - (1 + e)(v . n) n + T t, t = (-n_y, n_x), T = clamp(-u / (1 + 5/2), +-mu N) with the
## slip u = v . t - r omega, omega' = omega - 5 T / (2 r). [vx, vy, omega].
static func _one_contact(vx: float, vy: float, w: float, nx: float, ny: float, e: float, mu: float, r: float) -> PackedFloat64Array:
	var vn := vx * nx + vy * ny
	var n_imp := -(1.0 + e) * vn
	var u := -ny * vx + nx * vy - r * w
	var t_imp := clampf(-u / 3.5, -mu * n_imp, mu * n_imp)
	return PackedFloat64Array([vx + n_imp * nx - t_imp * ny, vy + n_imp * ny + t_imp * nx, w - 2.5 * t_imp / r])


## A ball whose centre passes the fence face line above the top but within r of it meets the top
## corner (circle against a point; the previous rule took it as a face hit at its equator). Zero
## gravity, level: contact at x = face - sqrt(r^2 - d^2) (d = centre above the top), normal from
## the corner to the centre, the impact = closed form. Earth: the contact time against a brute-force
## search of |centre(t) - corner| = r. A centre below the top meets the face (as before); a ball
## clearing the top by more than r flies over. The drawn boards on the throw line end at the
## model's top, and no post stands on the throw line (2026-10-23 review).
func check_fence_corner() -> void:
	var lab: Experiment = await _lab("projectile")
	var r: float = lab.BALL_RADIUS
	var top: float = lab.FENCE_HEIGHT
	var face: float = lab.FENCE_X
	var e: float = lab.BOUNCE
	var mu: float = lab.BALL_FRICTION
	var body := RigidBody3D.new()
	body.mass = 1.0
	tree.root.add_child(body)
	var details := []
	# Zero gravity, level at 5 m/s, centre 0.1 m above the top.
	var d := 0.1
	var v := 5.0
	var m := _fenced_model(lab)
	body.global_position = Vector3(0.0, top + d, 0.0)
	d = body.global_position.y - top   # (the body's float32 height)
	m.release(body, Vector3(v, 0.0, 0.0), 0.0)
	var reach := sqrt(r * r - d * d)
	var t_c := (face - reach - body.global_position.x) / v
	var want := _one_contact(v, 0.0, 0.0, -reach / r, d / r, e, mu, r)
	var got: PackedFloat64Array = PackedFloat64Array()
	var zero_ok := absf(m.fence_time - t_c) <= 1e-9
	if zero_ok:
		m._start()
		got = m.state_at(t_c + 0.05)
		zero_ok = m.wall_kinds.size() == 1 and m.wall_kinds[0] == RollingContact.CORNER and absf(got[2] - want[0]) <= 1e-9 \
			and absf(got[3] - want[1]) <= 1e-9 and absf(got[4] - want[2]) <= 1e-9
	details.append("zero g corner: contact %.6f s (closed form %.6f s), after (%.4f, %.4f) m/s, omega %.4f (closed form (%.4f, %.4f), %.4f)" % [
		m.fence_time, t_c, got[2] if got.size() > 0 else NAN, got[3] if got.size() > 0 else NAN, got[4] if got.size() > 0 else NAN, want[0], want[1], want[2]])
	# Earth: from x 7 m, 2.9 m up (centre), (4, 1) m/s; the centre crosses the face line at ~1.91 m.
	var x0 := 7.0
	var y0 := 2.9
	var vx := 4.0
	var vy := 1.0
	var g := 9.81
	m = _fenced_model(lab)
	body.global_position = Vector3(x0, y0, 0.0)
	y0 = body.global_position.y
	m.release(body, Vector3(vx, vy, 0.0), g)
	var y_at_face := y0 + vy * (face - r - x0) / vx - 0.5 * g * pow((face - r - x0) / vx, 2)
	var dist := func(t: float) -> float:
		var dx := x0 + vx * t - face
		var dy := y0 + vy * t - 0.5 * g * t * t - top
		return sqrt(dx * dx + dy * dy) - r   # (64-bit: a Vector2 is float32)
	var lo := 0.0
	var step := 1e-5
	while dist.call(lo + step) > 0.0 and lo < 2.0:
		lo += step
	var hi := lo + step
	for i in 100:
		var mid := 0.5 * (lo + hi)
		if dist.call(mid) > 0.0:
			lo = mid
		else:
			hi = mid
	m._start()
	var earth_ok: bool = y_at_face > top and y_at_face < top + r and absf(m.fence_time - hi) <= 1e-9 and m.wall_kinds.size() >= 1 and m.wall_kinds[0] == RollingContact.CORNER
	details.append("earth corner: centre at the face line %.3f m (top %.1f m), contact %.9f s (brute force %.9f s)" % [y_at_face, top, m.fence_time, hi])
	# Below the top: the face, at x = face - r; more than r above: no contact.
	m = _fenced_model(lab)
	body.global_position = Vector3(0.0, top - 0.01, 0.0)
	m.release(body, Vector3(v, 0.0, 0.0), 0.0)
	m._start()
	var face_ok: bool = absf(m.fence_time - (face - r) / v) <= 1e-9 and m.wall_kinds[0] == RollingContact.FACE
	m = _fenced_model(lab)
	body.global_position = Vector3(0.0, top + r + 0.01, 0.0)
	m.release(body, Vector3(v, 0.0, 0.0), 0.0)
	var over_ok := not is_finite(m.fence_time)
	body.queue_free()
	# The drawn fence on the ball's path (triangles reaching |z| <= r): its top = the model's
	# wall_top; the posts (all that stands above the boards) clear of it.
	var line_top := -INF
	var post_gap := INF
	var fence_mesh: Mesh = lab.props.fence.mesh
	var xf: Transform3D = lab.props.fence.global_transform
	for surface in fence_mesh.get_surface_count():
		var arrays := fence_mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if index.is_empty():
			for i in verts.size():
				index.append(i)
		for i in range(0, index.size(), 3):
			var tri := [xf * verts[index[i]], xf * verts[index[i + 1]], xf * verts[index[i + 2]]]
			var z_lo := minf(tri[0].z, minf(tri[1].z, tri[2].z))
			var z_hi := maxf(tri[0].z, maxf(tri[1].z, tri[2].z))
			var y_hi := maxf(tri[0].y, maxf(tri[1].y, tri[2].y))
			if z_lo <= r and z_hi >= -r:
				line_top = maxf(line_top, y_hi)
			if y_hi > top + 1e-4:
				post_gap = minf(post_gap, minf(absf(z_lo), absf(z_hi)) if z_lo * z_hi > 0.0 else 0.0)
	var mesh_ok: bool = line_top <= top + 1e-5 and line_top >= top - 1e-4 and post_gap >= ProjectileProps.POST_CLEAR and ProjectileProps.POST_CLEAR > r
	details.append("drawn top on the throw line %.4f m (model %.2f m), nearest post side %.3f m from z = 0" % [line_top, top, post_gap])
	expect.call(zero_ok and earth_ok and face_ok and over_ok and mesh_ok,
		"ball fences: a ball passing the face line above the top but within r meets the top corner (circle-point, closed form / brute force), below the top the face, higher nothing; the drawn boards end at the model's top on the throw line, no post on it",
		"; ".join(details))
	await _free(lab)


## A ball on the floor with backspin slides into the fence face: the face's friction presses it into
## the floor, and the floor pushes back with its own friction, both in the same impact (velocity
## Coulomb at both contacts, Newton e at the face, no floor penetration). Two closed forms
## (2026-10-23 review; the previous rule dropped the floor's push but kept the whole spin change):
##   strong backspin (v 3 m/s, omega 60 rad/s): both slip, the floor's friction against the
##   approach: face push N = (1 + e) v / (1 + mu^2), omega' = omega - (5 / 2r) mu (1 + mu) N,
##   less backspin (omega 20 rad/s): the floor's friction turns: T_w = mu (1 + e) v / (1 - mu^2),
##   omega' = omega - (5 / 2r)(1 - mu) T_w;
## both: v_x' = -e v, v_y' = 0 (the ball stays on the floor).
func check_fence_on_floor_backspin() -> void:
	var lab: Experiment = await _lab("projectile")
	var r: float = lab.BALL_RADIUS
	var e: float = lab.BOUNCE
	var mu: float = lab.BALL_FRICTION
	var body := RigidBody3D.new()
	body.mass = 1.0
	tree.root.add_child(body)
	var details := []
	var ok := true
	var v := 3.0
	for w: float in [60.0, 20.0]:
		var want_w: float
		if w == 60.0:
			want_w = w - 2.5 / r * mu * (1.0 + mu) * (1.0 + e) * v / (1.0 + mu * mu)
		else:
			want_w = w - 2.5 / r * (1.0 - mu) * mu * (1.0 + e) * v / (1.0 - mu * mu)
		var m := _fenced_model(lab)
		body.global_position = Vector3(lab.FENCE_X - r, r, 0.0)   # touching the face, on the floor
		m.release(body, Vector3(v, 0.0, 0.0), lab.g, w)
		m._start()
		var after: PackedFloat64Array = m.state_at(1e-12)
		var this_ok: bool = m.wall_kinds.size() == 1 and m.wall_kinds[0] == RollingContact.FACE and absf(after[2] + e * v) <= 1e-9 \
			and absf(after[3]) <= 1e-9 and after[1] == 0.0 and absf(after[4] - want_w) <= 1e-9 and m._ground
		ok = ok and this_ok
		details.append("omega %.0f: after v (%.6f, %.6f) m/s, omega %.6f (closed form %.6f)%s" % [w, after[2], after[3], after[4], want_w, "" if this_ok else " DIFFERS"])
	body.queue_free()
	expect.call(ok, "ball fences: a backspinning ball on the floor meets the face and the floor at once (both frictions, no floor penetration) = closed forms", "; ".join(details))
	await _free(lab)


## mu = 0: a slipping ball on the floor keeps v and omega (no friction; rolling resistance only
## acts on a rolling ball): x = v t, omega constant, it neither rolls nor stops (2026-10-23 review).
func check_frictionless_slide() -> void:
	var body := RigidBody3D.new()
	body.mass = 1.0
	tree.root.add_child(body)
	var m := RollingContact.new()
	m.mu = 0.0
	m.mu_roll = 0.05
	body.global_position = Vector3(0.0, m.radius, 0.0)
	m.release(body, Vector3(4.0, 0.0, 0.0), 9.81, 3.0)
	m._start()
	var s: PackedFloat64Array = m.state_at(2.0)
	body.queue_free()
	expect.call(absf(s[0] - 8.0) <= 1e-9 and s[1] == 0.0 and s[2] == 4.0 and s[4] == 3.0 and absf(s[5] - 6.0) <= 1e-9 and m.roll_time < 0.0 and m.stop_time < 0.0,
		"ball rolling: with mu 0 a slipping ball slides on unchanged (v and omega constant, no rolling resistance)",
		"x %.6f m, v %.6f m/s, omega %.6f rad/s, turn %.6f rad, roll %.2f, stop %.2f" % [s[0], s[2], s[4], s[5], m.roll_time, m.stop_time])


## Zero gravity (2026-10-23 review): a fence below the straight flight is met all the same (passing
## through a board would not be physics). From x -6 m, 0.5 m, 9 m/s:
##   0 deg: the face at t1 = (9.25 + 6) / 9 s, then the ball goes back and forth between the faces,
##   e times slower each pass (no floor, no field: nothing else stops it), at the closed-form times;
##   the panel stays at the fence time, "울타리에 맞음", the ball on the island;
##   2 deg: the face at t1, then the friction impulse leaves it rising; it clears the other fence's
##   top and leaves the island: "섬 밖으로 날아감";
##   15 deg: over the right fence (no contact): "무중력: 곧게 날아가요", then off the island.
## The engine ball never reaches into a board.
func check_zero_gravity_fences() -> void:
	var lab: Experiment = await _lab("projectile")
	var r: float = lab.BALL_RADIUS
	var e: float = lab.BOUNCE
	var details := []
	var ok := true
	for angle: float in [0.0, 2.0, 15.0]:
		_throw(lab, angle, 9.0, 0.5, "zero")
		var vx: float = lab.launch_velocity().x
		var vy: float = lab.launch_velocity().y
		var x0: float = lab.ball_center().x
		var t1: float = (lab.FENCE_X - r - x0) / vx
		var span: float = (lab.FENCE_X - r) - (lab.FENCE_LEFT_X + r)
		var rec := _recorder(lab, lab.ball)
		lab.release()
		var c: UniformFieldCorrector = lab.corrector()
		var model: RollingContact = c.rolling
		var states := {}
		var seconds := 11.0 if angle == 0.0 else 8.0
		while c.steps - 1 < roundi(seconds * STEP_HZ) and not lab.out_of_bounds:
			await tree.physics_frame
			if not states.has("first") and lab.clock() > 1.0:
				states.first = lab.status()
			if lab.clock() >= t1 + 0.1 and not states.has("hit"):
				states.hit = lab.observations()
		var deepest := 0.0
		for p in rec.positions:
			deepest = maxf(deepest, _overlap(lab, p.x, p.y))
		rec.queue_free()
		var end: Dictionary = lab.observations()
		var this_ok := deepest <= 1e-4
		match angle:
			0.0:
				var t2 := t1 + span / (e * vx)
				var t3 := t2 + span / (e * e * vx)
				this_ok = this_ok and model.wall_times.size() >= 3 and absf(model.wall_times[0] - t1) <= 1e-9 and absf(model.wall_times[1] - t2) <= 1e-9 \
					and absf(model.wall_times[2] - t3) <= 1e-9 and absf(model.wall_speeds[2] - e * e * vx) <= 1e-9 \
					and end.state == "울타리에 맞음" and absf(float(end.time) - t1) <= 1e-9 and not lab.out_of_bounds and not lab.ball.freeze
				details.append("0°: faces at %s s (closed form %.4f, %.4f, %.4f), panel '%s' at %.4f s" % [str(Array(model.wall_times).map(func(t: float) -> String: return "%.4f" % t)), t1, t2, t3, end.state, float(end.time)])
			2.0:
				this_ok = this_ok and model.wall_times.size() >= 1 and absf(model.wall_times[0] - t1) <= 1e-9 and model.wall_kinds[0] == RollingContact.FACE \
					and states.get("hit", {}).get("state", "") == "울타리에 맞음" and lab.out_of_bounds and end.state == "섬 밖으로 날아감"
				details.append("2°: contacts %s at %s s (face closed form %.4f), then '%s'" % [str(model.wall_kinds), str(Array(model.wall_times).map(func(t: float) -> String: return "%.4f" % t)), t1, end.state])
			15.0:
				this_ok = this_ok and not is_finite(model.fence_time) and model.wall_times.is_empty() and states.get("first", "") == "floating" and lab.out_of_bounds and end.state == "섬 밖으로 날아감"
				details.append("15°: no contact, '%s' then '%s'" % [states.get("first", ""), end.state])
		if not this_ok:
			details.append("(%.0f° FAILED, deepest %s m)" % [angle, String.num_scientific(deepest)])
		ok = ok and this_ok
		lab.run_action("reset")
	expect.call(ok, "ball fences: in zero gravity a low throw meets the fence (face / corner, closed-form times), goes back and forth e times slower or clears a top and leaves; a high one flies over; never into a board",
		"; ".join(details))
	await _free(lab)


## The launch preview (2026-10-23 review): the dots end where the flight meets a fence (the last dot
## at the contact, none beyond the face), and the landing ring shows only a formula landing the ball
## reaches between the fences. Moon 75 deg 7.5 m/s from 1 m at x -8 m: dots to the face, no ring;
## the default earth throw: dots to the landing, ring at x0 + R; a moon throw over the top (60 deg
## 9 m/s, 3 m, x -3 m) lands behind the right fence: dots go on, no ring.
func check_fence_preview() -> void:
	var lab: Experiment = await _lab("projectile")
	var r: float = lab.BALL_RADIUS
	var details := []
	var ok := true
	for run in [["moon", 75.0, 7.5, 1.0, -8.0, "fence"], ["earth", 45.0, 9.0, 0.5, -6.0, "ring"], ["moon", 60.0, 9.0, 3.0, -3.0, "over"]]:
		lab.set_control("gravity", run[0])
		lab.set_control("angle", run[1])
		lab.set_control("speed", run[2])
		lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(run[4], run[3] + r, 0.0)))
		var points: PackedVector3Array = lab.formula_path()
		var shown_count: int = lab.props.path.multimesh.visible_instance_count
		var ring: MeshInstance3D = lab.props.ring
		var center: Vector3 = lab.ball_center()
		var t_f: float = lab.fence_time_for(center.x, lab.launch_vx(), lab.launch_vy(), lab.launch_height())
		var last: Vector3 = lab.props.path_end   # the last dot drawn
		var this_ok: bool = shown_count == points.size() and last.is_equal_approx(points[-1])
		match run[5]:
			"fence":
				var at: Vector2 = lab.formula_point(t_f)
				this_ok = this_ok and is_finite(t_f) and not ring.visible and last.distance_to(Vector3(center.x + at.x, at.y + r, center.z)) <= 1e-4
				for p in points:
					this_ok = this_ok and p.x <= lab.FENCE_X - r + 1e-4
			"ring":
				this_ok = this_ok and not is_finite(t_f) and ring.visible and absf(ring.position.x - (center.x + lab.flight_range())) <= 1e-4
			"over":
				var land_x: float = center.x + lab.flight_range()
				this_ok = this_ok and not is_finite(t_f) and not ring.visible and land_x > lab.FENCE_X and last.x > lab.FENCE_X
		ok = ok and this_ok
		details.append("%s %.0f° %.1f m/s: fence %s s, last dot x %.3f m, ring %s%s" % [run[0], run[1], run[2], "%.4f" % t_f if is_finite(t_f) else "—", last.x,
			"x %.3f m" % ring.position.x if ring.visible else "hidden", "" if this_ok else " (FAILED)"])
	expect.call(ok, "projectile preview: the formula dots stop at a fence the flight meets, and the landing ring shows only a landing between the fences", "; ".join(details))
	await _free(lab)


# --- 4. the mesh is the body ------------------------------------------------------------------

func check_mesh_is_body() -> void:
	var lab: Experiment = await _lab("projectile")
	_throw(lab, 0.0, 6.0, 0.0)
	lab.release()
	var worst := 0.0
	var turned := 0.0
	var visual: MeshInstance3D = lab._ball_visual
	for i in 90:
		await tree.physics_frame
		await tree.process_frame
		var m: Basis = visual.transform.basis
		# The juice only scales the mesh (a symmetric matrix): no turn of its own.
		for a in 3:
			for b in 3:
				worst = maxf(worst, absf(m[a][b] - m[b][a]))
		turned = maxf(turned, visual.global_basis.get_rotation_quaternion().get_angle())
	var same: bool = visual.get_parent() == lab.ball and lab.props.juice.round_body
	expect.call(same and worst <= 1e-5 and turned > 1.0 and not lab.ball.lock_rotation,
		"ball spin: the turning seen is the body's (the mesh is its child and the juice only squashes it, round)", "max asymmetry %s, mesh turned up to %.2f rad" % [String.num_scientific(worst), turned])
	await _free(lab)


# --- 5. free fall -------------------------------------------------------------------------------

func check_free_fall_no_spin() -> void:
	var lab: Experiment = await _lab("free-fall")
	var recs := {}
	for id in lab.ORDER:
		recs[id] = _recorder(lab, lab.balls[id])
	lab.release()
	await _frames(4 * STEP_HZ)
	var worst := 0.0
	var drift := 0.0
	var contacts := 0
	for id in lab.ORDER:
		var rec: Recorder = recs[id]
		for i in rec.steps.size():
			worst = maxf(worst, rec.spins[i].length())
			worst = maxf(worst, rec.bases[i].get_rotation_quaternion().get_angle())
			drift = maxf(drift, Vector2(rec.positions[i].x - lab.starts[id].x, rec.positions[i].z - lab.starts[id].z).length())
		contacts += lab.corrector_of(id).rolling.impact_times.size()
	expect.call(worst <= 1e-6 and drift <= 1e-6 and contacts > 0,
		"ball spin: free-fall balls never turn and do not drift sideways through their bounces (4 s)", "omega/turn %s, drift %s m, impacts %d" % [str(worst), str(drift), contacts])
	await _free(lab)


# --- 6. collision lab ---------------------------------------------------------------------------

func check_collision_mesh_rolls() -> void:
	var lab: Experiment = await _lab("collision")
	lab.run_action("release")
	var worst := 0.0
	var moved := 0.0
	for i in 3 * STEP_HZ:
		await tree.physics_frame
		lab._process(0.0)   # the props turn the meshes in _process (from the balls' positions now)
		var da: float = lab.ball_a.global_position.x - lab.start_a
		var db: float = lab.ball_b.global_position.x - lab.start_b
		# The balls roll on their look radii (2026-10-28: the look follows the mass).
		worst = maxf(worst, absf(wrapf(lab.props.spin_a.rotation.z + da / lab.props.look.x, -PI, PI)))
		worst = maxf(worst, absf(wrapf(lab.props.spin_b.rotation.z + db / lab.props.look.y, -PI, PI)))
		moved = maxf(moved, absf(da))
	expect.call(worst <= 1e-5 and moved > 1.0,
		"ball spin: the collision lab's balls (model driven) turn by travel / radius: rolling, v = omega r", "max %s rad over %.2f m" % [String.num_scientific(worst), moved])
	await _free(lab)


# --- 7. colours ---------------------------------------------------------------------------------

const COLOUR_WORDS := {"red": ["빨강", "빨간"], "yellow": ["노랑", "노란"], "purple": ["보라", "보라"]}
const COLOURS := {"red": ArtPalette.RED, "yellow": ArtPalette.YELLOW, "purple": ArtPalette.VIOLET}
# The free fall's light ball keeps the id "yellow" but is PINK (2026-10-29: yellow was hard to see on the grass).
const FF_WORDS := {"red": ["빨강", "빨간"], "yellow": ["분홍", "분홍"]}
const FF_COLOURS := {"red": ArtPalette.RED, "yellow": ArtPalette.PINK}


## Brightest coloured (not white) vertex colour of a mesh in sRGB (the builder stores linear colours; the baked shading only
## darkens the palette colour).
static func _mesh_colour(mesh: Mesh) -> Color:
	var best := Color.BLACK
	for surface in mesh.get_surface_count():
		for c: Color in mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
			if c.s < 0.2:
				continue   # the white band / white top
			if c.get_luminance() > best.get_luminance():
				best = c
	return best.linear_to_srgb()


## Highest sRGB saturation of the mesh's vertex colours (white / grey stay under 0.3, the ball and
## pad yellow is 0.9).
static func _max_saturation(mesh: Mesh) -> float:
	var top := 0.0
	for surface in mesh.get_surface_count():
		for c: Color in mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
			top = maxf(top, c.linear_to_srgb().s)
	return top


## The mesh has a yellow vertex (the yellow ball's colour).
static func _has_yellow(mesh: Mesh) -> bool:
	for surface in mesh.get_surface_count():
		for c: Color in mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
			var v := c.linear_to_srgb()
			if v.s > 0.5 and v.h > 0.08 and v.h < 0.2:
				return true
	return false


## A ball's colour: the yarn ball's tint times the texture's mean (Task 4g: the texture is grey and
## the tint is divided by its mean, so this is the ball's average colour).
static func _ball_colour(visual: MeshInstance3D) -> Color:
	var m := visual.material_override as ShaderMaterial
	if m == null:
		return Color.BLACK
	var t: Vector4 = m.get_shader_parameter("tint")   # linear
	var lin := Color(t.x, t.y, t.z)
	var k := ArtKit._yarn_mean(m.get_shader_parameter("albedo_texture"))
	return Color(lin.r * k, lin.g * k, lin.b * k).linear_to_srgb()


## "" when `visual` is the yarn ball: the yarn model's mesh (at most 400 triangles) with the textured
## island light, its extent the ball's diameter (what is seen is the physics size: within 2 %, no
## thread sticking out).
static func _yarn_problem(visual: MeshInstance3D, radius: float) -> String:
	var mesh := visual.mesh
	if mesh != ArtKit.yarn_mesh() or mesh.surface_get_array_index_len(0) / 3 > 400:
		return "not the yarn mesh"
	var m := visual.material_override as ShaderMaterial
	if m == null or m.shader != ArtKit.TEXTURE_SHADER or m.get_shader_parameter("albedo_texture") == null:
		return "not the yarn material"
	# A yarn ball that is a body's mesh (free fall, projectile: radius 0.25) carries the juice's
	# squash in its scale; a scaled one (collision, spring) sits under the juice's node.
	var size := mesh.get_aabb().size * (Vector3.ONE if visual.get_parent() is RigidBody3D else visual.scale)
	for a in 3:
		if absf(size[a] - 2.0 * radius) > 0.04 * radius:
			return "size %s" % size
	return ""


## Same colour to the 8-bit linear vertex colours (dark channels lose up to ~5/255 in sRGB).
static func _near(a: Color, b: Color) -> bool:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) <= 6.0 / 255.0


func check_ball_colours() -> void:
	var lab: Experiment = await _lab("free-fall")
	var definition: Dictionary = lab.definition.raw
	var problems := []
	var series := {}
	for entry in definition.graph.series:
		series[entry.id] = entry
	var labels := {}
	for entry in definition.observations:
		labels[entry.id] = entry.label
	for id in lab.ORDER:
		var words: Array = FF_WORDS[id]
		var colour: Color = FF_COLOURS[id]
		if lab.BALLS[id].color != colour or lab.BALLS[id].name != words[0]:
			problems.append("%s: BALLS %s %s" % [id, lab.BALLS[id].name, lab.BALLS[id].color.to_html(false)])
		var mesh_colour := _ball_colour(lab.balls[id].get_node("Visual") as MeshInstance3D)
		if not _near(mesh_colour, colour):
			problems.append("%s: mesh %s" % [id, mesh_colour.to_html(false)])
		if Color(series[id].color) != Color(colour.to_html(false)) or series[id].label != "%s 공" % words[1]:
			problems.append("%s: graph %s %s" % [id, series[id].label, series[id].color])
		if not str(labels["height_" + id]).begins_with("%s 공" % words[1]):
			problems.append("%s: observation %s" % [id, labels["height_" + id]])
	for option in definition.controls[2].options:
		for id in lab.ORDER:
			if not str(option.note).contains("%s 공" % FF_WORDS[id][1]):
				problems.append("note %s lacks %s" % [option.note, id])
	var text: String = lab.measured_landings()
	lab.release()
	for i in 2 * STEP_HZ:
		await tree.physics_frame
	text = lab.measured_landings()
	for id in lab.ORDER:
		if not text.contains(FF_WORDS[id][0]):
			problems.append("landings '%s' lacks %s" % [text, FF_WORDS[id][0]])
	for old in ["노랑", "노란", "주황", "ffc61a", "ff7a1a"]:
		if JSON.stringify(definition).contains(old):
			problems.append("free-fall definition still has %s" % old)
	# Every ball is a yarn ball (the strands show the turn); the drop pads are white / grey, no ball colour.
	for id in lab.ORDER:
		var yarn := _yarn_problem(lab.balls[id].get_node("Visual") as MeshInstance3D, lab.BALL_RADIUS)
		if yarn != "":
			problems.append("%s: %s" % [id, yarn])
		if _max_saturation((lab.props.pads[id] as MeshInstance3D).mesh) > 0.3 or _has_yellow((lab.props.pads[id] as MeshInstance3D).mesh):
			problems.append("%s: the pad is coloured" % id)
	await _free(lab)
	var pj: Experiment = await _lab("projectile")
	var pj_yarn := _yarn_problem(pj._ball_visual, pj.BALL_RADIUS)   # (no launch pad since Task 4g)
	if pj_yarn != "" or not _near(_ball_colour(pj._ball_visual), ArtPalette.RED):
		problems.append("projectile ball: %s %s" % [pj_yarn, _ball_colour(pj._ball_visual).to_html(false)])
	await _free(pj)
	# The other balls are yarn balls too (2026-10-23 user decision "공은 다 털실로"), in their colours.
	var col: Experiment = await _lab("collision")
	for pair in [[col.props.spin_a, col.RADIUS_A, ArtPalette.BLUE], [col.props.spin_b, col.RADIUS_B, ArtPalette.ORANGE]]:
		var yarn_c := _yarn_problem(pair[0], pair[1])
		if yarn_c != "" or not _near(_ball_colour(pair[0]), pair[2]):
			problems.append("collision ball: %s %s" % [yarn_c, _ball_colour(pair[0]).to_html(false)])
	await _free(col)
	var spring: Experiment = await _lab("spring")
	var spring_yarn: MeshInstance3D = spring.ball.get_node("Visual/Yarn")
	var yarn_s := _yarn_problem(spring_yarn, spring.BALL_RADIUS)
	if yarn_s != "" or not _near(_ball_colour(spring_yarn), ArtPalette.ORANGE):
		problems.append("spring ball: %s" % yarn_s)
	await _free(spring)
	# Pendulum bobs and the orbit's planet too (2026-10-23 user decision), in their colours.
	var pend: Experiment = await _lab("constraints")
	for i in pend.SHOWN:   # the lab view's bobs (2026-10-29: the rope pendulum only)
		var bob_yarn: MeshInstance3D = pend.bobs[i].get_node("Visual/Yarn")
		var yarn_p := _yarn_problem(bob_yarn, pend.BOB_RADIUS)
		if yarn_p != "" or not _near(_ball_colour(bob_yarn), [ArtPalette.BLUE, ArtPalette.ORANGE][i]):
			problems.append("pendulum bob %d: %s %s" % [i, yarn_p, _ball_colour(bob_yarn).to_html(false)])
	await _free(pend)
	var orbit: Experiment = await _lab("orbit")
	var planet_yarn: MeshInstance3D = orbit.planet.get_node("Visual/Yarn")
	var yarn_o := _yarn_problem(planet_yarn, orbit.PLANET_RADIUS)
	if yarn_o != "" or not _near(_ball_colour(planet_yarn), ArtPalette.BLUE):
		problems.append("orbit planet: %s %s" % [yarn_o, _ball_colour(planet_yarn).to_html(false)])
	await _free(orbit)
	var dev: Experiment = await _lab("manipulation-dev")
	for entry in dev.definition.observations():
		var id: String = entry.id
		if COLOURS.has(id):
			if not str(entry.label).begins_with("%s 상자" % COLOUR_WORDS[id][1]):
				problems.append("dev label %s" % entry.label)
			var box_mat := (dev.bodies[id].get_node("Visual") as MeshInstance3D).material_override as ShaderMaterial
			var accent_v: Vector4 = box_mat.get_shader_parameter("accent") if box_mat != null else Vector4.ZERO
			var box_colour := Color(accent_v.x, accent_v.y, accent_v.z).linear_to_srgb()   # its parcel tape (Task 4g; linear)
			if not _near(box_colour, dev.BOXES[id][1]) or dev.BOXES[id][1] != COLOURS[id]:
				problems.append("dev box %s colour %s" % [id, box_colour.to_html(false)])
	await _free(dev)
	expect.call(problems.is_empty(),
		"ball colours: free-fall balls red / pink (development boxes red / yellow / violet), and every name, label, graph series and note matches the mesh colour",
		"; ".join(problems))
