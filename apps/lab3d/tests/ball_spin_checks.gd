## Headless checks of the balls' spin and rolling (Phase 1 Task 4f), run by run_tests.gd. The ball
## is a solid sphere (I = 2/5 m r^2) and every expected value is a textbook formula (PhysicsLaws):
## 1. flight: no torque, so omega stays what it was (0 when thrown without spin; a given spin turns
##    the body by omega dt every step), the flight positions are unchanged.
## 2. a ball thrown level along the floor without spin slides with v = v0 - mu g t, omega =
##    5 mu g t / (2 r), and rolls after t* = 2 v0 / (7 mu g) at 5/7 v0 = omega r, then keeps that
##    speed (no rolling resistance); engine positions and turn angles against the closed forms, for
##    three fields and two speeds.
## 3. a bounce: the friction impulse is the Coulomb one for the engine's normal impulse j (stick:
##    5/7 vx and rolling; small mu: dv = -mu j, domega = 5 mu j / (2 r)); a rolling ball bounces on
##    without friction. The engine's vertical bounce against the restitution law is measured.
## 4. what is seen turning is the body: the mesh is its child with no turn of its own.
## 5. free fall: the three balls never turn and do not drift sideways through their bounces.
## 6. collision lab (model driven): each ball's mesh turns by its travel over its radius (v = omega r).
## 7. colours (2026-10-23 user request): the free-fall balls and the development scene's boxes are
##    red / yellow / violet, and every label (ball names, observations, graph series and colours,
##    option notes) names the colour the mesh has.
extends RefCounted

const STEP_HZ := 60

## Records a ball's state after its corrector ran (after the friction of the last step was put back
## into that step), once per physics frame.
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

var tree: SceneTree
var expect: Callable   # (ok: bool, label: String, detail: String)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_flight_spin()
	await check_slide_to_roll()
	await check_bounce_friction()
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
	expect.call(worst == 0.0 and c.rolling.contact_steps == 0,
		"ball spin: a ball thrown without spin does not turn in the air (omega 0, body unturned up to the landing)", "max %s over %d steps" % [str(worst), rec.steps.size()])
	# With a spin: the same flight, the body turns by omega dt every step, omega constant.
	rec.clear()
	lab.release()
	var spin := Vector3(0.0, 0.0, 7.5)
	c.rolling.release(lab.ball, lab.launch_velocity(), spin)
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


# --- 2. slide to roll --------------------------------------------------------------------------

## Level throw along the floor (angle 0, height 0): the textbook slide -> roll.
func check_slide_to_roll() -> void:
	var lab: Experiment = await _lab("projectile")
	var rec := _recorder(lab, lab.ball)
	var r: float = lab.BALL_RADIUS
	var mu: float = lab.BALL_FRICTION
	var worst_x := 0.0          # sliding steps before t*
	var worst_turn := 0.0
	var beyond_x := 0.0         # every step, beyond the kink step's bound
	var beyond_turn := 0.0
	var worst_roll := 0.0
	var worst_time := 0
	var worst_after := 0.0
	var details := []
	# Speeds that roll before the island's edge (the moon's slide is long: t* = 2 v0 / (7 mu g)).
	for run in [["moon", 3.0], ["moon", 1.5], ["earth", 9.0], ["earth", 4.0], ["jupiter", 9.0], ["jupiter", 4.0]]:
		var gravity: String = run[0]
		var v0: float = run[1]
		_throw(lab, 0.0, v0, 0.0, gravity)
		rec.clear()
		lab.release()
		var c: UniformFieldCorrector = lab.corrector()
		var g: float = lab.g
		var t_roll := PhysicsLaws.slide_to_roll_time(v0, mu, g)
		var v_roll := PhysicsLaws.rolling_speed_after_slip(v0, v0)
		var a := mu * g
		var alpha := 5.0 * mu * g / (2.0 * r)   # = r F / I with I = 2/5 m r^2
		var end_step := mini(ceili((t_roll + 1.0) * STEP_HZ), ceili((lab.BOUNDS_X.y - lab.ball_center().x) / v0 * STEP_HZ) - 2)
		while c.steps - 1 < end_step and not lab.ball.freeze:
			await tree.physics_frame
		var x0: float = lab.ball_center().x
		var turn := 0.0
		var first_roll := -1
		# Bounds of the one step with the kink at t* (the engine step velocity is constant in a step).
		var kink_x := a / (2.0 * STEP_HZ * STEP_HZ)
		var kink_turn := alpha / (2.0 * STEP_HZ * STEP_HZ)
		for i in rec.steps.size():
			var k := rec.steps[i]
			var t := k / float(STEP_HZ)
			var x_formula := v0 * t - 0.5 * a * t * t if t <= t_roll else v0 * t_roll - 0.5 * a * t_roll * t_roll + v_roll * (t - t_roll)
			var turn_formula := -(0.5 * alpha * t * t if t <= t_roll else 0.5 * alpha * t_roll * t_roll + v_roll / r * (t - t_roll))
			if i > 0:
				turn += _turn_z(rec.bases[i - 1], rec.bases[i])
			var err_x := absf(rec.positions[i].x - x0 - x_formula)
			var err_turn := absf(turn - turn_formula)
			if t < t_roll - 1.0 / STEP_HZ:
				worst_x = maxf(worst_x, err_x)
				worst_turn = maxf(worst_turn, err_turn)
			beyond_x = maxf(beyond_x, err_x - kink_x)
			beyond_turn = maxf(beyond_turn, err_turn - kink_turn)
			if first_roll < 0 and absf(rec.velocities[i].x + rec.spins[i].z * r) < 1e-5:
				first_roll = k
			if first_roll >= 0:
				worst_roll = maxf(worst_roll, absf(rec.velocities[i].x - v_roll))
				worst_roll = maxf(worst_roll, absf(PhysicsLaws.rolling_speed(r, -rec.spins[i].z) - rec.velocities[i].x))
				if t > t_roll + 0.5:
					worst_after = maxf(worst_after, absf((rec.positions[i].x - rec.positions[i - 1].x) * STEP_HZ - v_roll))
		# The velocity recorded at step k is that of the k-th step, v((k - 1/2) dt) (leapfrog: half
		# the friction in the first step): it is the rolling speed from the step whose midpoint
		# passes t*.
		worst_time = maxi(worst_time, absi(first_roll - ceili(t_roll * STEP_HZ + 0.5)) if first_roll >= 0 else 999)
		details.append("%s %.1f m/s: t* %.4f s (rolls from step %d), 5/7 v0 %.4f" % [gravity, v0, t_roll, first_roll, v_roll])
	expect.call(worst_x <= 1e-4 and worst_turn <= 1e-4 and beyond_x <= 1e-4 and beyond_turn <= 1e-4,
		"ball rolling: sliding without spin, engine x = v0 t - mu g t^2 / 2 and turn = 5 mu g t^2 / (4 r) up to t* = 2 v0 / (7 mu g), then 5/7 v0 t (3 fields, 6 throws)",
		"sliding: x %s m, turn %s rad; after t*, beyond the kink step's bound (mu g dt^2 / 2, 5 mu g dt^2 / (4 r)): x %s m, turn %s rad; %s" % [
			String.num_scientific(worst_x), String.num_scientific(worst_turn), String.num_scientific(beyond_x), String.num_scientific(beyond_turn), "; ".join(details)])
	expect.call(worst_time <= 1 and worst_roll <= 1e-5 and worst_after <= 1e-4,
		"ball rolling: rolls (v = omega r) from t* on at 5/7 v0 and keeps that speed (no rolling resistance)",
		"time %d steps, |v - 5/7 v0|, |omega r - v| %s m/s, step speed after t* + 0.5 s %s m/s" % [worst_time, String.num_scientific(worst_roll), String.num_scientific(worst_after)])
	await _free(lab)


# --- 3. bounce -----------------------------------------------------------------------------------

func check_bounce_friction() -> void:
	var lab: Experiment = await _lab("projectile")
	var r: float = lab.BALL_RADIUS
	var details := []
	var ok := true
	for mu in [lab.BALL_FRICTION, 0.02]:
		lab.run_action("reset")
		lab.release()
		var c: UniformFieldCorrector = lab.corrector()
		var rolling: RollingContact = c.rolling
		rolling.mu = mu
		var vx: float = lab.launch_vx()
		# Resumes before the frame's _physics_process: the step that found the bounce has run once
		# the count moved (its friction is in, and one engine step after it).
		while rolling.contact_steps == 0 and c.steps < 400:
			await tree.physics_frame
		var j := rolling.last_normal
		var stick: float = 2.0 / 7.0 * vx   # impulse per mass that ends the slip (no spin before)
		var dv: float = minf(stick, mu * j)
		var want_v: float = vx - dv
		var want_w: float = -5.0 * dv / (2.0 * r)
		var got_v: float = lab.ball.linear_velocity.x
		var got_w: float = lab.ball.angular_velocity.z
		ok = ok and absf(got_v - want_v) <= 1e-5 and absf(got_w - want_w) <= 1e-4 and absf(rolling.last_friction - dv) <= 1e-6   # (the release velocity is a 32-bit Vector3)
		if mu == lab.BALL_FRICTION:
			ok = ok and rolling.slip() == 0.0 and absf(got_v - PhysicsLaws.rolling_speed_after_slip(vx, vx)) <= 1e-5
			# The engine's vertical bounce against the restitution law at the formula landing.
			var v_land := absf(PhysicsLaws.constant_acceleration_velocity(lab.launch_vy(), -lab.g, lab.flight_time()))
			var want_up: float = lab.BOUNCE * v_land
			var got_up: float = lab.ball.linear_velocity.y + lab.g / STEP_HZ   # back to the step's start
			details.append("bounce: j %.4f m/s (formula (1+e)|v| + g dt = %.4f), rebound %.4f m/s (e |v| = %.4f, %+.2f %%)" % [j,
				(1.0 + lab.BOUNCE) * v_land + lab.g / STEP_HZ, got_up, want_up, (got_up / want_up - 1.0) * 100.0])
			# A rolling ball bounces on without friction: later bounces leave v and omega alone.
			var before := rolling.contact_steps
			for i in 2 * STEP_HZ:
				await tree.physics_frame
			ok = ok and rolling.contact_steps > before and absf(lab.ball.linear_velocity.x - want_v) <= 1e-5 and absf(lab.ball.angular_velocity.z - want_w) <= 1e-4
		details.append("mu %.2f: j %.4f m/s, v %.5f (want %.5f), omega %.4f (want %.4f)" % [mu, j, got_v, want_v, got_w, want_w])
	expect.call(ok, "ball bounce: the friction impulse is Coulomb's for the engine's normal impulse (mu 0.6: rolls at 5/7 vx after the first bounce, later bounces keep it; mu 0.02: dv = mu j, domega = 5 mu j / (2 r))",
		"; ".join(details))
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
		contacts += lab.corrector_of(id).rolling.contact_steps
	expect.call(worst <= 1e-6 and drift <= 1e-6 and contacts > 0,
		"ball spin: free-fall balls never turn and do not drift sideways through their bounces (4 s)", "omega/turn %s, drift %s m, contact steps %d" % [str(worst), str(drift), contacts])
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


## Brightest vertex colour of a mesh in sRGB (the builder stores linear colours; the baked shading only
## darkens the palette colour).
static func _mesh_colour(mesh: Mesh) -> Color:
	var best := Color.BLACK
	for surface in mesh.get_surface_count():
		for c: Color in mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
			if c.get_luminance() > best.get_luminance():
				best = c
	return best.linear_to_srgb()


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
	await _free(lab)
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
