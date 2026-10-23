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
## 4. what is seen turning is the body: the mesh (white band) is its child with no turn of its own.
## 5. free fall: the three balls never turn and do not drift sideways through their bounces.
## 6. collision lab (model driven): each ball's mesh turns by its travel over its radius (v = omega r).
## 7. colours (2026-10-23 user request): the free-fall balls and the development scene's boxes are
##    red / yellow / violet, and every label (ball names, observations, graph series and colours,
##    option notes) names the colour the mesh has; the balls have a white band, the drop pads are
##    white / grey.
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
	while c.steps - 1 < ceili((t_wall + hop) * STEP_HZ) + 2:
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
		details.append("%s: %d fence hits, rests at x %.2f m after %.2f s%s" % [run[0], cc.rolling.wall_times.size(), x, cc.rolling.stop_time, "" if on else " (NOT ON THE ISLAND)"])
	expect.call(wall_ok and worst_hop <= 1e-4 and rest_ok,
		"ball fences: a roll meets the fence at the closed-form time and speed, bounces back at e v and hops by the Coulomb impulse; the default and farthest throws rest on the island",
		"hop vs closed form %s m; %s" % [String.num_scientific(worst_hop), "; ".join(details)])
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
		worst = maxf(worst, absf(wrapf(lab.props.spin_a.rotation.z + da / lab.RADIUS_A, -PI, PI)))
		worst = maxf(worst, absf(wrapf(lab.props.spin_b.rotation.z + db / lab.RADIUS_B, -PI, PI)))
		moved = maxf(moved, absf(da))
	expect.call(worst <= 1e-5 and moved > 1.0,
		"ball spin: the collision lab's balls (model driven) turn by travel / radius: rolling, v = omega r", "max %s rad over %.2f m" % [String.num_scientific(worst), moved])
	await _free(lab)


# --- 7. colours ---------------------------------------------------------------------------------

const COLOUR_WORDS := {"red": ["빨강", "빨간"], "yellow": ["노랑", "노란"], "purple": ["보라", "보라"]}
const COLOURS := {"red": ArtPalette.RED, "yellow": ArtPalette.YELLOW, "purple": ArtPalette.VIOLET}


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


## The mesh has white vertices (a white band).
static func _has_white(mesh: Mesh) -> bool:
	for surface in mesh.get_surface_count():
		for c: Color in mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
			if c.s < 0.05 and c.linear_to_srgb().v > 0.9:
				return true
	return false


## Same colour to the 8-bit linear vertex colours (dark channels lose up to ~5/255 in sRGB).
static func _near(a: Color, b: Color) -> bool:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) <= 6.0 / 255.0


func check_ball_colours() -> void:
	var lab: Experiment = await _lab("free-fall")
	var definition: Dictionary = lab.definition
	var problems := []
	var series := {}
	for entry in definition.graph.series:
		series[entry.id] = entry
	var labels := {}
	for entry in definition.observations:
		labels[entry.id] = entry.label
	for id in lab.ORDER:
		var words: Array = COLOUR_WORDS[id]
		var colour: Color = COLOURS[id]
		if lab.BALLS[id].color != colour or lab.BALLS[id].name != words[0]:
			problems.append("%s: BALLS %s %s" % [id, lab.BALLS[id].name, lab.BALLS[id].color.to_html(false)])
		var mesh_colour := _mesh_colour((lab.balls[id].get_node("Visual") as MeshInstance3D).mesh)
		if not _near(mesh_colour, colour):
			problems.append("%s: mesh %s" % [id, mesh_colour.to_html(false)])
		if Color(series[id].color) != Color(colour.to_html(false)) or series[id].label != "%s 공" % words[1]:
			problems.append("%s: graph %s %s" % [id, series[id].label, series[id].color])
		if not str(labels["height_" + id]).begins_with("%s 공" % words[1]):
			problems.append("%s: observation %s" % [id, labels["height_" + id]])
	for option in definition.controls[2].options:
		for id in lab.ORDER:
			if not str(option.note).contains("%s 공" % COLOUR_WORDS[id][1]):
				problems.append("note %s lacks %s" % [option.note, id])
	var text: String = lab.measured_landings()
	lab.release()
	for i in 2 * STEP_HZ:
		await tree.physics_frame
	text = lab.measured_landings()
	for id in lab.ORDER:
		if not text.contains(COLOUR_WORDS[id][0]):
			problems.append("landings '%s' lacks %s" % [text, COLOUR_WORDS[id][0]])
	for old in ["분홍", "주황", "ff4fa3", "ff7a1a"]:
		if JSON.stringify(definition).contains(old):
			problems.append("free-fall definition still has %s" % old)
	# Every ball has its white band (the turn is seen); the drop pads are white / grey, no ball colour.
	for id in lab.ORDER:
		if not _has_white((lab.balls[id].get_node("Visual") as MeshInstance3D).mesh):
			problems.append("%s: no white band" % id)
		if _max_saturation((lab.props.pads[id] as MeshInstance3D).mesh) > 0.3 or _has_yellow((lab.props.pads[id] as MeshInstance3D).mesh):
			problems.append("%s: the pad is coloured" % id)
	await _free(lab)
	var pj: Experiment = await _lab("projectile")
	if not _has_white(pj._ball_visual.mesh) or _has_yellow(pj.props.pad.mesh):   # (its arm is blue)
		problems.append("projectile ball band / pad colour")
	await _free(pj)
	var dev: Experiment = await _lab("manipulation-dev")
	for entry in dev.definition.observations:
		var id: String = entry.id
		if COLOURS.has(id):
			if not str(entry.label).begins_with("%s 상자" % COLOUR_WORDS[id][1]):
				problems.append("dev label %s" % entry.label)
			var box_colour := _mesh_colour((dev.bodies[id].get_node("Visual") as MeshInstance3D).mesh)   # the lighter top face
			if not (_near(box_colour, dev.BOXES[id][1]) or _near(box_colour, dev.BOXES[id][2])) or dev.BOXES[id][1] != COLOURS[id]:
				problems.append("dev box %s colour %s" % [id, box_colour.to_html(false)])
	await _free(dev)
	expect.call(problems.is_empty(),
		"ball colours: free-fall balls red / yellow / violet (development boxes too), and every name, label, graph series and note matches the mesh colour",
		"; ".join(problems))
