## Headless checks of the uniform-field labs (Phase 1 Task 4a: free fall, projectile), run by
## run_tests.gd. Expected values are the TS-core vectors in tests/uniform_labs_vectors.json
## (tools/uniform-labs-vectors.test.ts); motion is measured from the balls' engine positions.
## 1. free fall: the displayed numbers at fixed steps and at the landing = TS (1e-9), the step
##    positions = h0 - g t^2 / 2 (1e-4 m), the three masses fall together (1e-6 m), the engine landing
##    = TS landing time +-2 steps; red mass 0.5 vs 3 kg gives the same motion; no field: nothing falls.
## 2. projectile: step positions = TS x(t), y(t) (1e-4 m), displayed position / velocity / flight time
##    / range / apex = TS (1e-9), engine landing time +-2 steps and distance +-2 steps of travel,
##    highest measured point = apex; no field: the ball leaves the island and is stopped.
## 3. the art is visual only (collision objects, juice on the mesh, same run without the reactions).
## 5. landing rules (review of PR #9): the release contacts come from the first released step (a
##    fresh lab's first throw / drop from the floor), landings on the floor only, a ball let go on
##    the floor in a field has landed (no field: it has not, the time runs), one drop line per ball,
##    one launch height for the engine, the graph and the formulas; "landed" is the formula's (clock
##    at the formula landing time, or an engine report): a short hop from the floor and a drop from a
##    few mm land, get a measured value and add no graph point after the formula landing, and at
##    120 Hz the state does not flicker after the release.
## 4. manipulation through the real input path: free fall ball drag + height handle, projectile ball
##    on its launch line + height, the arrow knob's polar snap (15 deg, 0.5 m/s), blocked directions.
extends RefCounted

const VECTORS_PATH := "res://tests/uniform_labs_vectors.json"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60

var tree: SceneTree
var expect: Callable   # (ok: bool, label: String, detail: String)
var vectors: Dictionary
var tolerance := 1e-9


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn
	vectors = JSON.parse_string(FileAccess.get_file_as_string(VECTORS_PATH))
	tolerance = vectors.tolerance


func run() -> void:
	check_definitions()
	await check_free_fall_cases()
	await check_free_fall_mass()
	await check_free_fall_zero_g()
	await check_free_fall_art()
	await check_projectile_cases()
	await check_projectile_zero_g()
	await check_projectile_settles()
	await check_projectile_landed_roll_off()
	await check_projectile_unknown_control()
	await check_free_fall_height_clamp()
	await check_first_release_from_floor()
	await check_free_fall_neighbours()
	await check_free_fall_zero_g_on_floor()
	await check_free_fall_drop_lines()
	await check_projectile_level_from_floor()
	await check_short_hop_from_floor()
	await check_drop_from_mm()
	await check_release_at_120_hz()
	await check_projectile_height_grid()
	await check_projectile_art()
	check_arrow_surface()
	await check_free_fall_manipulation()
	await check_projectile_manipulation()


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


## Waits until the corrector's last recorded sample is the one after `k` steps (clock = k dt).
func _until_step(corrector: UniformFieldCorrector, k: int) -> void:
	var guard := 0
	while corrector.steps - 1 < k and guard < 2000:
		await tree.physics_frame
		guard += 1


## Every free-fall ball has its engine landing report (the formula "landed" can come first).
func _engine_landed(lab: Experiment) -> bool:
	return lab.ORDER.all(func(id: String) -> bool: return lab.corrector_of(id).landed_step >= 0)


## Relative error (absolute below 1).
func _err(value: Variant, want: float) -> float:
	if not (value is float or value is int):
		return INF
	return absf(float(value) - want) / maxf(1.0, absf(want))


func _open(definition: Dictionary) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(1560, 720)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame


func _at(screen: Control, world: Vector3) -> Vector2:
	var view: View3D = screen.view
	return view.rig.unproject_position(world) / (Vector2(view.viewport.size) / view.size)


func _touch(screen: Control, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	screen.view._gui_input(event)


func _swipe(screen: Control, from: Vector2, to: Vector2, steps := 8) -> void:
	_touch(screen, 0, from, true)
	for i in range(1, steps + 1):
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = from.lerp(to, float(i) / steps)
		screen.view._gui_input(event)


# --- definitions ------------------------------------------------------------------------------

func check_definitions() -> void:
	var ok := true
	var detail := []
	for id in ["free-fall", "projectile"]:
		var definition := ExperimentRegistry.find(id)
		var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
		ok = ok and problems.is_empty() and definition.get("content") == id and definition.has("tip")
		detail.append("%s: %s" % [id, ", ".join(problems)])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	expect.call(ok and listed.has("free-fall") and listed.has("projectile"),
		"uniform labs: free-fall and projectile definitions valid, listed, texts from the shared content", "; ".join(detail))


# --- free fall --------------------------------------------------------------------------------

func check_free_fall_cases() -> void:
	var lab: Experiment = await _lab("free-fall")
	var worst_display := 0.0
	var worst_motion := 0.0
	var worst_spread := 0.0
	var worst_landing := 0
	var worst_land_display := 0.0
	var states_ok := true
	var graph_worst := 0.0
	var details := []
	for case in vectors.free_fall:
		lab.set_control("gravity", case.gravity)
		lab.set_control("height", float(case.height))
		lab.set_control("mass", "heavy")
		lab.release()
		var red: UniformFieldCorrector = lab.corrector_of("red")
		for sample in case.samples:
			await _until_step(red, int(sample.step))
			var shown: Dictionary = lab.observations()
			for key in ["height", "speed", "momentum", "kinetic", "potential"]:
				var field: String = "height_red" if key == "height" else key
				worst_display = maxf(worst_display, _err(shown[field], float(sample[key])))
			worst_display = maxf(worst_display, _err(shown.time, float(sample.t)))
			worst_display = maxf(worst_display, maxf(_err(shown.height_orange, float(sample.height)), _err(shown.height_pink, float(sample.height))))
			var k := int(sample.step)
			var want := float(sample.height) - float(case.height)
			for id in lab.ORDER:
				var c: UniformFieldCorrector = lab.corrector_of(id)
				worst_motion = maxf(worst_motion, absf(c.samples[k] - want))
				worst_spread = maxf(worst_spread, absf(c.samples[k] - red.samples[k]))
		# Until every ball has landed and the engine reported each landing (4 s at most).
		for i in 4 * STEP_HZ:
			if lab.status() == "landed" and _engine_landed(lab):
				break
			await tree.physics_frame
		var landing := float(case.landing_time)
		for id in lab.ORDER:
			var step: int = lab.corrector_of(id).landed_step
			worst_landing = maxi(worst_landing, absi(step - roundi(landing * STEP_HZ)) if step >= 0 else 999)
		var shown: Dictionary = lab.observations()
		worst_land_display = maxf(worst_land_display, maxf(_err(shown.time, landing), _err(shown.fall_time, landing)))
		worst_land_display = maxf(worst_land_display, maxf(_err(shown.speed, float(case.landing.speed)), _err(shown.momentum, float(case.landing.momentum))))
		worst_land_display = maxf(worst_land_display, maxf(_err(shown.kinetic, float(case.landing.kinetic)), _err(shown.height_red, 0.0) + _err(shown.potential, 0.0)))
		states_ok = states_ok and shown.state == "모두 바닥에 닿음" and str(shown.landing).count(".") == 3
		# Graph: measured points on the formula line (both are heights of the balls' bottoms).
		var series: Dictionary = lab.graph_series()
		for p in series.measured:
			graph_worst = maxf(graph_worst, absf(p.y - lab.formula_height("red", p.x)))
		details.append("%s h %.1f: T %.4f s, landed %s" % [case.gravity, case.height, landing,
			str(lab.ORDER.map(func(id: String) -> int: return lab.corrector_of(id).landed_step))])
	expect.call(worst_display <= tolerance, "free fall: displayed t, heights, v, p, K, U at fixed steps = TS core (6 cases)", "max rel err %s" % String.num_scientific(worst_display))
	expect.call(worst_motion <= 1e-4, "free fall: ball positions = h0 - g t^2 / 2 at the step points (3 balls, 6 cases)", "max |diff| %s m" % String.num_scientific(worst_motion))
	expect.call(worst_spread <= 1e-6, "free fall: 0.5, 1 and 3 kg balls fall together", "max spread %s m" % String.num_scientific(worst_spread))
	expect.call(worst_landing <= 2, "free fall: each ball's engine landing = TS landing time ±2 steps", "worst %d steps; %s" % [worst_landing, "; ".join(details)])
	expect.call(worst_land_display <= tolerance, "free fall: after the landing the panel shows the formula landing (t = T, v, p, K; h = U = 0)", "max rel err %s" % String.num_scientific(worst_land_display))
	expect.call(states_ok, "free fall: state '모두 바닥에 닿음' and three measured landing times", "")
	expect.call(graph_worst <= 1e-4, "free fall: graph's simulation points lie on the formula line", "max |diff| %s m" % String.num_scientific(graph_worst))
	await _free(lab)


## The red ball's mass does not change the motion (0.5 kg vs 3 kg).
func check_free_fall_mass() -> void:
	var lab: Experiment = await _lab("free-fall")
	var runs := []
	for mass in ["light", "heavy"]:
		lab.set_control("gravity", "earth")
		lab.set_control("height", 5.0)
		lab.set_control("mass", mass)
		lab.release()
		await _until_step(lab.corrector_of("red"), 80)
		var c: UniformFieldCorrector = lab.corrector_of("red")
		runs.append({"samples": c.samples.duplicate(), "landed": c.landed_step, "mass": lab.mass_of("red")})
	var diff := 0.0
	for k in mini(runs[0].samples.size(), runs[1].samples.size()):
		diff = maxf(diff, absf(runs[0].samples[k] - runs[1].samples[k]))
	expect.call(runs[0].mass == 0.5 and runs[1].mass == 3.0 and diff <= 1e-6 and runs[0].landed == runs[1].landed,
		"free fall: the red ball at 0.5 kg and 3 kg falls the same way (mass control)", "max diff %s m, landed %d / %d" % [String.num_scientific(diff), runs[0].landed, runs[1].landed])
	await _free(lab)


func check_free_fall_zero_g() -> void:
	var lab: Experiment = await _lab("free-fall")
	lab.set_control("gravity", "zero")
	lab.set_control("height", 5.0)
	lab.release()
	await _until_step(lab.corrector_of("red"), STEP_HZ)
	var moved := 0.0
	for id in lab.ORDER:
		moved = maxf(moved, absf(lab.corrector_of(id).samples[STEP_HZ]))
	var shown: Dictionary = lab.observations()
	expect.call(moved <= 1e-6 and shown.state == "무중력: 떠 있어요" and shown.fall_time == "닿지 않아요" and absf(float(shown.time) - 1.0) < 1e-9 and float(shown.height_red) == 5.0,
		"free fall: no field, the balls stay where they were let go (time runs, no landing)", "moved %s m, %s" % [String.num_scientific(moved), str(shown)])
	await _free(lab)


func check_free_fall_art() -> void:
	var lab: Experiment = await _lab("free-fall")
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append(node.get_class())
	bodies.sort()
	var juices_ok := true
	for id in lab.ORDER:
		var juice: ArtJuice = lab.props.juices[id]
		var children: Array[String] = []
		for child in lab.balls[id].get_children():
			children.append(child.get_class())
		children.sort()
		juices_ok = juices_ok and juice.mesh.get_parent() == lab.balls[id] and children == ["CollisionShape3D", "MeshInstance3D"] and not lab.balls[id].is_ancestor_of(juice)
	expect.call(bodies == ["RigidBody3D", "RigidBody3D", "RigidBody3D", "StaticBody3D"] and juices_ok,
		"free fall art adds no collision objects (floor + 3 balls); reactions act on each ball's mesh only", ", ".join(bodies))
	var runs := []
	var deformed := 0.0
	for with_juice in [true, false]:
		for juice: ArtJuice in lab.props.juices.values():
			juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.set_control("height", 2.5)
		lab.release()
		while lab.corrector_of("red").steps <= 2 * STEP_HZ:
			await tree.physics_frame
			if with_juice:
				var s: Vector3 = lab.props.juices.red.mesh_scale() - Vector3.ONE
				deformed = maxf(deformed, s.abs()[s.abs().max_axis_index()])
		var samples := []
		for id in lab.ORDER:
			samples.append(lab.corrector_of(id).samples.duplicate())
		runs.append({"samples": samples, "obs": str(lab.observations()), "graph": lab.graph_series().measured})
	for juice: ArtJuice in lab.props.juices.values():
		juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(deformed > 0.05 and runs[0].samples == runs[1].samples and runs[0].obs == runs[1].obs and runs[0].graph == runs[1].graph,
		"free fall: same motion, panel and graph with and without the ball reactions (which do deform the meshes)", "max |scale - 1| %.3f" % deformed)
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 16, "free fall: at most 16 drawn 3D nodes (art budget)", "%d" % draw_nodes)
	await _free(lab)


# --- projectile ------------------------------------------------------------------------------

func _place_launch(lab: Experiment, height: float) -> void:
	lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(lab.START_X, height + lab.BALL_RADIUS, 0.0)))


func check_projectile_cases() -> void:
	var lab: Experiment = await _lab("projectile")
	var worst_motion := 0.0
	var worst_display := 0.0
	var worst_summary := 0.0
	var worst_landing := 0
	var worst_range := 0.0
	var worst_apex := 0.0
	var landed_display := 0.0
	var details := []
	for case in vectors.projectile:
		lab.set_control("gravity", case.gravity)
		lab.set_control("angle", float(case.angle))
		lab.set_control("speed", float(case.speed))
		_place_launch(lab, float(case.height))
		var before: Dictionary = lab.observations()
		for key in ["flight_time", "range", "apex"]:
			worst_summary = maxf(worst_summary, _err(before[key], float(case[key])))
		lab.release()
		var c: UniformFieldCorrector = lab.corrector()
		for sample in case.samples:
			var k := int(sample.step)
			await _until_step(c, k)
			var shown: Dictionary = lab.observations()
			for key in ["x", "y", "vx", "vy"]:
				worst_display = maxf(worst_display, _err(shown[key], float(sample[key])))
			worst_display = maxf(worst_display, _err(shown.time, float(sample.t)))
			var offset: Vector3 = c.offsets[k]
			worst_motion = maxf(worst_motion, maxf(absf(offset.x - float(sample.x)), absf(offset.y + float(case.height) - float(sample.y))))
		for i in 4 * STEP_HZ:
			if c.landed_step >= 0:
				break
			await tree.physics_frame
		var flight := float(case.flight_time)
		var dx := absf(float(case.speed) * cos(deg_to_rad(float(case.angle))))
		worst_landing = maxi(worst_landing, absi(c.landed_step - roundi(flight * STEP_HZ)) if c.landed_step >= 0 else 999)
		var measured: Variant = lab.measured_range()
		worst_range = maxf(worst_range, absf(float(measured) - float(case.range)) / (2.0 * dx / STEP_HZ + 1e-3) if measured is float else INF)
		var top := -INF
		for k in mini(c.landed_step, c.offsets.size()):
			top = maxf(top, c.offsets[k].y)
		worst_apex = maxf(worst_apex, absf(top + float(case.height) - float(case.apex)))
		var after: Dictionary = lab.observations()
		landed_display = maxf(landed_display, maxf(_err(after.time, flight), _err(after.x, float(case.range))))
		landed_display = maxf(landed_display, _err(after.y, 0.0) if after.state == "바닥에 닿음" else INF)
		details.append("%s %d° %.1f m/s h %.1f: T %.3f s (landed step %d), R %.3f m (measured %s)" % [case.gravity, case.angle, case.speed, case.height,
			flight, c.landed_step, case.range, str(measured)])
	expect.call(worst_summary <= tolerance, "projectile: displayed flight time, range and apex = TS core (6 throws)", "max rel err %s" % String.num_scientific(worst_summary))
	expect.call(worst_display <= tolerance, "projectile: displayed t, x, y, vx, vy at fixed steps = TS core", "max rel err %s" % String.num_scientific(worst_display))
	expect.call(worst_motion <= 1e-4, "projectile: ball positions (x, y)(t) = TS constantAccelerationDisplacement at the step points", "max |diff| %s m" % String.num_scientific(worst_motion))
	expect.call(worst_landing <= 2, "projectile: engine landing = TS flight time ±2 steps", "worst %d steps; %s" % [worst_landing, "; ".join(details)])
	expect.call(worst_range <= 1.0, "projectile: measured landing distance = TS range within 2 steps of travel (+1 mm)", "worst %.2f of the allowance" % worst_range)
	expect.call(worst_apex <= 2e-3, "projectile: highest measured point = TS apex (step sampling, ≤ 2 mm)", "max |diff| %s m" % String.num_scientific(worst_apex))
	expect.call(landed_display <= tolerance, "projectile: after the landing the panel shows the formula landing (t = T, x = R, y = 0)", "max rel err %s" % String.num_scientific(landed_display))
	await _free(lab)


## No field: the ball flies straight, never lands, leaves the island and is stopped and hidden;
## "처음으로" brings it back.
func check_projectile_zero_g() -> void:
	var lab: Experiment = await _lab("projectile")
	lab.set_control("gravity", "zero")
	lab.set_control("angle", 15.0)
	lab.set_control("speed", 9.0)
	lab.release()
	for i in 4 * STEP_HZ:
		if lab.out_of_bounds:
			break
		await tree.physics_frame
	var shown: Dictionary = lab.observations()
	var hidden: bool = not lab._ball_visual.visible and lab.ball.freeze
	var t_before: float = shown.time
	await _until_step(lab.corrector(), 0)
	for i in 30:
		await tree.physics_frame
	var t_after: float = lab.observations().time
	lab.run_action("reset")
	expect.call(lab.out_of_bounds == false and lab._ball_visual.visible and hidden and shown.state == "섬 밖으로 날아감" and shown.range == "닿지 않아요"
		and shown.flight_time == "닿지 않아요" and shown.apex == "계속 올라가요" and t_after > t_before,
		"projectile: no field, the ball flies straight off the island, is stopped there (time keeps running), reset brings it back", str(shown))
	await _free(lab)


## After the landing the ball rolls on (Task 4f: the first bounce turns it until v = omega r, no
## rolling resistance) until the island's box stops it, and a second throw flies exactly like the
## first (the reset restores every state, also the ball's turn).
func check_projectile_settles() -> void:
	var lab: Experiment = await _lab("projectile")
	lab.release()
	var c: UniformFieldCorrector = lab.corrector()
	await _until_step(c, roundi(lab.flight_time() * STEP_HZ) + 30)
	var rolling: RollingContact = c.rolling
	var roll_speed: float = lab.ball.linear_velocity.x
	var spin: float = lab.ball.angular_velocity.z
	var want := PhysicsLaws.rolling_speed_after_slip(lab.launch_vx(), lab.launch_vx())   # no spin before: 5/7 vx
	for i in 4 * STEP_HZ:
		await tree.physics_frame
	var landed := c.landed_step
	var first: PackedVector3Array = c.offsets.slice(0, landed)
	var stopped: bool = lab.ball.freeze and not lab._ball_visual.visible and lab.status() == "landed"
	lab.release()   # the same corrector again: its history restarts
	var turned_back: bool = lab.ball.global_basis.is_equal_approx(Basis())
	await _until_step(c, landed)
	var again: PackedVector3Array = c.offsets.slice(0, landed)
	var diff := INF if first.size() != again.size() else 0.0
	for k in mini(first.size(), again.size()):
		diff = maxf(diff, (first[k] - again[k]).length())
	expect.call(absf(roll_speed - want) <= 1e-5 and absf(PhysicsLaws.rolling_speed(lab.BALL_RADIUS, -spin) - roll_speed) <= 1e-5 and rolling.slip() == 0.0
		and stopped and not lab.out_of_bounds and turned_back and diff <= 1e-6,
		"projectile: the landed ball rolls on at 5/7 vx = omega r until the island's edge stops it ('landed'); the next throw starts unturned and flies the same",
		"roll %.5f m/s (5/7 vx %.5f), omega r %.5f, flight diff %s m (%d / %d samples)" % [roll_speed, want, -spin * lab.BALL_RADIUS, str(diff), first.size(), again.size()])
	await _free(lab)


## A ball that landed and then rolls (or is carried) past the island's box is stopped and hidden, but
## it did not "fly off the island": the status stays "landed" (only a ball still in flight is "out").
func check_projectile_landed_roll_off() -> void:
	var lab: Experiment = await _lab("projectile")
	lab.release()
	var c: UniformFieldCorrector = lab.corrector()
	for i in 4 * STEP_HZ:
		await tree.physics_frame
	var landed_first: bool = c.landed_step >= 0 and lab.status() == "landed"
	lab.ball.global_position = Vector3(lab.BOUNDS_X.y + 1.0, 0.25, 0.0)
	for i in 5:
		await tree.physics_frame
	var shown: Dictionary = lab.observations()
	expect.call(landed_first and lab.status() == "landed" and not lab.out_of_bounds and lab.ball.freeze and not lab._ball_visual.visible
		and shown.state == "바닥에 닿음",
		"projectile: a landed ball that leaves the island's box is stopped and hidden but stays 'landed' (not 'out')", str(shown.state))
	await _free(lab)


## A control id the lab does not know is ignored: it does not put a running throw back.
func check_projectile_unknown_control() -> void:
	var lab: Experiment = await _lab("projectile")
	lab.release()
	for i in 10:
		await tree.physics_frame
	lab.set_control("no_such_control", 1.0)
	var kept: bool = lab.released
	lab.set_control("angle", 30.0)
	expect.call(kept and not lab.released, "projectile: an unknown control id leaves the throw alone; a known one puts the ball back", "released %s" % str(kept))
	await _free(lab)


## The free-fall height is limited to the slider's range (--ctl-height=-5 would otherwise start the
## balls underground).
func check_free_fall_height_clamp() -> void:
	var lab: Experiment = await _lab("free-fall")
	lab.set_control("height", -5.0)
	var low: float = lab.height
	var low_starts: bool = lab.starts.red.y == low and lab.starts.pink.y == low
	lab.set_control("height", 99.0)
	var high: float = lab.height
	lab.set_control("height", 3.0)
	expect.call(low == 0.5 and high == 8.0 and low_starts and lab.height == 3.0 and lab.control_value("height") == 3.0,
		"free fall: the height condition is limited to the slider's range (0.5..8 m)", "low %.1f, high %.1f" % [low, high])
	await _free(lab)


# --- landing rules ------------------------------------------------------------------------------

## A lab opened fresh (no earlier run, so no contact report to reuse): the first throw from the
## floor (height 0, 45 deg) flies its formula time, and a ball let go on the floor is not an engine
## landing on the first step while the others drop and land on it at their formula times.
func check_first_release_from_floor() -> void:
	var lab: Experiment = await _lab("projectile")
	lab.set_control("angle", 45.0)
	_place_launch(lab, 0.0)
	lab.release()
	var c: UniformFieldCorrector = lab.corrector()
	await _until_step(c, 10)
	var early: int = c.landed_step
	for i in 3 * STEP_HZ:
		if c.landed_step >= 0:
			break
		await tree.physics_frame
	var flight: float = lab.flight_time()
	expect.call(early < 0 and c.landed_step > 2 and absi(c.landed_step - roundi(flight * STEP_HZ)) <= 2,
		"landing: a fresh projectile lab's first throw from the floor (45 deg) lands at its flight time, not on the first step",
		"landed step %d (at step 10: %d), formula %.3f s" % [c.landed_step, early, flight])
	await _free(lab)
	lab = await _lab("free-fall")
	lab.manipulation_placed("red", Transform3D(Basis(), Vector3(1.5, lab.BALL_RADIUS, 0.0)))
	lab.release()
	var orange: UniformFieldCorrector = lab.corrector_of("orange")
	for i in 2 * STEP_HZ:
		if orange.landed_step >= 0:
			break
		await tree.physics_frame
	var want := roundi(PhysicsLaws.landing_time(0.0, -9.81, 5.0) * STEP_HZ)
	expect.call(lab.corrector_of("red").landed_step < 0 and lab.has_landed("red") and absi(orange.landed_step - want) <= 2,
		"landing: a fresh free-fall lab with a ball on the floor reports no engine landing for it; the dropped ones land at their formula time",
		"red %d, orange %d (formula %d)" % [lab.corrector_of("red").landed_step, orange.landed_step, want])
	await _free(lab)
	# 1 mm up: the floor is touched inside the first (seeding) step, so the engine reports nothing and
	# the formula clock decides.
	lab = await _lab("free-fall")
	lab.manipulation_placed("red", Transform3D(Basis(), Vector3(1.5, lab.BALL_RADIUS + 0.001, 0.0)))
	lab.release()
	for i in 10:
		await tree.physics_frame
	expect.call(lab.has_landed("red"), "landing: a ball let go 1 mm above the floor counts as landed (the formula clock passes its landing time)", "")
	await _free(lab)


## Balls side by side (touching at the release, one beside a higher one) land on the floor at their
## own formula times and fall as the formula says: balls do not collide with each other, and their
## landings are on the floor (corrector.surfaces) only.
func check_free_fall_neighbours() -> void:
	var lab: Experiment = await _lab("free-fall")
	lab.manipulation_placed("pink", Transform3D(Basis(), Vector3(-0.5, 5.0 + lab.BALL_RADIUS, 0.0)))
	lab.manipulation_placed("red", Transform3D(Basis(), Vector3(0.5, 3.0 + lab.BALL_RADIUS, 0.0)))
	lab.release()
	var ball_contacts := 0   # balls are on their own layer, out of each other's mask
	for i in 3 * STEP_HZ:
		if lab.status() == "landed" and _engine_landed(lab):
			break
		await tree.physics_frame
		for id in lab.ORDER:
			for other in lab.balls[id].get_colliding_bodies():
				ball_contacts += 1 if lab.balls.values().has(other) else 0
	var worst_landing := 0
	var worst_motion := 0.0
	var ground := true
	var detail := []
	for id in lab.ORDER:
		var c: UniformFieldCorrector = lab.corrector_of(id)
		var landing: float = lab.landing_time(id)
		worst_landing = maxi(worst_landing, absi(c.landed_step - roundi(landing * STEP_HZ)) if c.landed_step >= 0 else 999)
		for k in mini(c.samples.size(), int(landing * STEP_HZ) - 2):
			worst_motion = maxf(worst_motion, absf(c.samples[k] - PhysicsLaws.constant_acceleration_displacement(0.0, -9.81, k / float(STEP_HZ))))
		ground = ground and c.surfaces == [lab.floor_body]
		detail.append("%s %d" % [id, c.landed_step])
	expect.call(ground and ball_contacts == 0 and worst_landing <= 2 and worst_motion <= 1e-4,
		"landing: balls side by side never touch each other, land on the floor only, at their formula times (±2 steps)",
		"ball contacts %d, worst %d steps, motion %s m; %s" % [ball_contacts, worst_landing, String.num_scientific(worst_motion), ", ".join(detail)])
	await _free(lab)


## No field, every ball on the floor: nobody lands, the shown time is the clock (not INF).
func check_free_fall_zero_g_on_floor() -> void:
	var lab: Experiment = await _lab("free-fall")
	lab.set_control("gravity", "zero")
	for id in lab.ORDER:
		lab.manipulation_placed(id, Transform3D(Basis(), Vector3(lab.BALLS[id].x, lab.BALL_RADIUS, 0.0)))
	lab.release()
	await _until_step(lab.corrector_of("red"), STEP_HZ)
	var shown: Dictionary = lab.observations()
	expect.call(absf(float(shown.time) - 1.0) < 1e-9 and shown.state == "무중력: 떠 있어요" and shown.fall_time == "닿지 않아요",
		"landing: no field with every ball on the floor, the time is the clock (1 s after 60 steps), not INF", str(shown.time))
	# In a field the same balls have landed at the release: time 0, the graph stops at once.
	lab.set_control("gravity", "earth")
	lab.release()
	await _until_step(lab.corrector_of("red"), 2 * lab.GRAPH_EVERY_STEPS)
	var revision: int = lab.graph_revision()
	await _until_step(lab.corrector_of("red"), 4 * lab.GRAPH_EVERY_STEPS)
	shown = lab.observations()
	expect.call(float(shown.time) == 0.0 and shown.state == "모두 바닥에 닿음" and lab.graph_revision() == revision and lab.graph_series().measured.size() == 3,
		"landing: in a field balls let go on the floor have landed (time 0); the graph revision stays while no point is added",
		"time %s, state %s, revision %d -> %d" % [str(shown.time), shown.state, revision, lab.graph_revision()])
	await _free(lab)


## One ball per drop line: a ball cannot be put straight above or below another (they would collide
## in the air); the next 0.5 m grid point (sides touching) is allowed.
func check_free_fall_drop_lines() -> void:
	var screen: Control = await _open(ExperimentRegistry.find("free-fall"))
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var pink: RigidBody3D = lab.balls.pink
	var above_orange := Vector3(0.0, pink.global_position.y, 0.0)
	lab.manipulation_placed("orange", Transform3D(Basis(), Vector3(0.0, 2.0 + lab.BALL_RADIUS, 0.0)))
	_swipe(screen, _at(screen, pink.global_position), _at(screen, above_orange))
	var blocked: bool = m.active_id == "pink" and not m.valid
	var beside := Vector3(-0.5, pink.global_position.y, 0.0)
	var event := InputEventScreenDrag.new()   # the same finger moves on (no new press)
	event.index = 0
	event.position = _at(screen, beside)
	screen.view._gui_input(event)
	var allowed: bool = m.active_id == "pink" and m.valid
	_touch(screen, 0, _at(screen, beside), false)
	expect.call(blocked and allowed and is_equal_approx(lab.starts.pink.x, -0.5)
		and not lab.placement_allowed("red", Transform3D(Basis(), Vector3(0.0, 6.0, 0.0))),
		"landing: a ball cannot be placed on another ball's drop line (above or below); beside it is allowed", "blocked %s, allowed %s, pink x %.2f, selected %s" % [blocked, allowed, lab.starts.pink.x, m.selected_id])
	await _close(screen)


## A level throw from the floor (height 0, angle 0) has flight time 0: it has landed at the release
## (it slides on the floor) instead of "flying" for ever.
func check_projectile_level_from_floor() -> void:
	var lab: Experiment = await _lab("projectile")
	lab.set_control("angle", 0.0)
	_place_launch(lab, 0.0)
	lab.release()
	await _until_step(lab.corrector(), 30)
	var shown: Dictionary = lab.observations()
	expect.call(lab.status() == "landed" and shown.state == "바닥에 닿음" and float(shown.time) == 0.0 and float(shown.flight_time) == 0.0
		and lab.graph_series().measured.size() == 1,
		"landing: a level throw from the floor has landed at the release (time 0), not '날아가는 중'", str(shown))
	await _free(lab)


## A short hop from the floor (15 deg, 1 m/s: about 3 steps of flight) lands at its formula flight
## time whether or not the engine reports it (the floor contact may never end), the state goes
## "flying" -> "landed" once, the measured distance is the engine x at the landing and the graph
## gets no point after the formula landing.
func check_short_hop_from_floor() -> void:
	var lab: Experiment = await _lab("projectile")
	lab.set_control("angle", 15.0)
	lab.set_control("speed", 1.0)
	_place_launch(lab, 0.0)
	var flight: float = lab.flight_time()
	var landing_step := ceili(flight * STEP_HZ)   # the first step whose clock reaches T
	lab.release()
	var c: UniformFieldCorrector = lab.corrector()
	var states := [lab.status()]
	while c.steps - 1 < 4 * lab.GRAPH_EVERY_STEPS:
		await tree.physics_frame
		if states[-1] != lab.status():
			states.append(lab.status())
	var landed_at := -1
	lab.release()
	while c.steps - 1 < landing_step + 1:
		if landed_at < 0 and lab.status() == "landed":
			landed_at = c.steps - 1
		await tree.physics_frame
	await _until_step(c, 4 * lab.GRAPH_EVERY_STEPS)
	var shown: Dictionary = lab.observations()
	var dx := 1.0 * cos(deg_to_rad(15.0))
	var measured: Variant = shown.landing
	expect.call(states == ["flying", "landed"] and landed_at == landing_step and shown.state == "바닥에 닿음" and float(shown.time) == flight
		and measured is float and absf(measured - lab.flight_range()) <= 2.0 * dx / STEP_HZ + 1e-3 and lab.graph_series().measured.size() == 1,
		"landing: a short hop from the floor (15 deg, 1 m/s) lands at its formula time, once, with a measured distance and no graph point after it",
		"states %s, landed at step %d (want %d, T %.4f s), engine step %d, measured %s (formula %.4f), %d graph points" % [str(states), landed_at, landing_step,
			flight, c.landed_step, str(measured), lab.flight_range(), lab.graph_series().measured.size()])
	await _free(lab)


## A drop from 5 mm (under 2 steps) lands by the formula, shows a measured landing time and adds no
## graph point after its formula landing (the two balls at 5 m add theirs).
func check_drop_from_mm() -> void:
	var lab: Experiment = await _lab("free-fall")
	lab.manipulation_placed("red", Transform3D(Basis(), Vector3(1.5, lab.BALL_RADIUS + 0.005, 0.0)))
	var landing: float = lab.landing_time("red")
	lab.release()
	var red: UniformFieldCorrector = lab.corrector_of("red")
	await _until_step(red, ceili(landing * STEP_HZ))
	var landed: bool = lab.has_landed("red")
	await _until_step(red, 5 * lab.GRAPH_EVERY_STEPS + 3)
	var text: String = lab.observations().landing
	var want := "%s %.2f" % [lab.BALLS.red.name, roundi(landing * STEP_HZ) / float(STEP_HZ)] if red.landed_step < 0 else "%s %.2f" % [lab.BALLS.red.name, red.landed_step / float(STEP_HZ)]
	var points: int = lab.graph_series().measured.size()
	expect.call(landed and text.contains(want) and points == 3 + 2 * 5,
		"landing: a drop from 5 mm lands by the formula, has a measured landing time and no graph point after the formula landing",
		"T %.4f s, engine step %d, readout %s (want %s), %d graph points (want 13)" % [landing, red.landed_step, text, want, points])
	await _free(lab)


## At 120 Hz a ball let go 1 mm above the floor (formula landing between one and two 120 Hz steps)
## goes from "not landed" to "landed" once, and the corrector's step length is the real one from the
## release on (not the 60 Hz default before its first step).
func check_release_at_120_hz() -> void:
	var ticks := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 120
	var lab: Experiment = await _lab("free-fall")
	lab.manipulation_placed("red", Transform3D(Basis(), Vector3(1.5, lab.BALL_RADIUS + 0.001, 0.0)))
	lab.release()
	var dt: float = lab.corrector_of("red").dt   # before the first step
	var seen := [lab.has_landed("red")]
	for i in 12:
		await tree.physics_frame
		if seen[-1] != lab.has_landed("red"):
			seen.append(lab.has_landed("red"))
	await _free(lab)
	Engine.physics_ticks_per_second = ticks
	expect.call(seen == [false, true] and dt == 1.0 / 120.0,
		"landing: at 120 Hz a ball let go 1 mm up turns 'landed' once after the release (no flicker)", "landed sequence %s, corrector dt %s" % [str(seen), str(dt)])


## A launch height off the 1 mm grid is snapped where it is set: the engine start, the graph's
## points and the formulas use the same height.
func check_projectile_height_grid() -> void:
	var lab: Experiment = await _lab("projectile")
	_place_launch(lab, 1.2504)
	var height: float = lab.launch_height()
	var engine_bottom: float = lab.ball.global_position.y - lab.BALL_RADIUS
	lab.release()
	var c: UniformFieldCorrector = lab.corrector()
	await _until_step(c, 30)
	var series: Dictionary = lab.graph_series()
	var worst := 0.0
	for p in series.measured:
		worst = maxf(worst, absf(p.y - lab.formula_y(p.x)))
	expect.call(lab.start.y == 1.25 and height == 1.25 and absf(engine_bottom - 1.25) < 1e-6 and series.measured[0].y == height
		and series.measured.size() > 2 and worst <= 1e-4,
		"projectile: an off-grid launch height (1.2504 m) is snapped to 1.250 m for the engine, the graph and the formulas",
		"start %.4f, engine %.6f, graph vs formula %s m" % [lab.start.y, engine_bottom, String.num_scientific(worst)])
	await _free(lab)


func check_projectile_art() -> void:
	var lab: Experiment = await _lab("projectile")
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append(node.get_class())
	bodies.sort()
	var knob: StaticBody3D = lab.knob
	expect.call(bodies == ["RigidBody3D", "StaticBody3D", "StaticBody3D"] and knob.collision_layer == 2 and knob.collision_mask == 0 and lab.ball.collision_mask == 1,
		"projectile art adds no collision objects (floor, ball, arrow knob on its own layer the ball never hits)", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.release()
		while lab.corrector().steps <= 2 * STEP_HZ:
			await tree.physics_frame
		runs.append({"offsets": lab.corrector().offsets.duplicate(), "obs": str(lab.observations())})
	lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(runs[0].offsets == runs[1].offsets and runs[0].obs == runs[1].obs, "projectile: same motion and panel with and without the ball reactions", "")
	# (The headless renderer keeps no MultiMesh transforms: the dots are checked where they are made.)
	lab.run_action("reset")
	var path: MultiMesh = lab.props.path.multimesh
	var points: PackedVector3Array = lab.formula_path()
	var t1 := minf(lab.flight_time(), lab.PATH_MAX_S) / ProjectileProps.PATH_DOTS
	var want: Vector2 = lab.formula_point(t1)
	var center: Vector3 = lab.ball_center()
	expect.call(path.visible_instance_count == points.size() and points.size() > 10 and points.size() <= ProjectileProps.PATH_DOTS
		and points[0].distance_to(Vector3(center.x + want.x, want.y + lab.BALL_RADIUS, center.z)) < 1e-4,
		"projectile: the formula path is at most %d dots on x(t), y(t) (one MultiMesh)" % ProjectileProps.PATH_DOTS, "%d dots" % path.visible_instance_count)
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 16, "projectile: at most 16 drawn 3D nodes (art budget)", "%d" % draw_nodes)
	await _free(lab)


func check_arrow_surface() -> void:
	var tip := ArrowSurface.tip(60.0, 6.0)
	var back := ArrowSurface.polar(tip)
	var snapped := ArrowSurface.snap_polar(ArrowSurface.tip(52.0, 9.12))
	var capped := ArrowSurface.snap_polar(ArrowSurface.tip(30.0, 14.0))
	var plane := ArrowSurface.new(Vector3(-6.0, 0.75, 0.0), 0.15)
	expect.call(absf(back.x - 60.0) < 1e-4 and absf(back.y - 6.0) < 1e-4 and snapped == Vector2(45.0, 9.0) and capped == Vector2(30.0, 9.0)
		and plane.contains(ArrowSurface.tip(90.0, 3.0)) and not plane.contains(ArrowSurface.tip(120.0, 3.0)) and not plane.contains(ArrowSurface.tip(-20.0, 3.0))
		and plane.pose(tip, 0.15).origin.is_equal_approx(Vector3(-6.0 + tip.x, 0.75 - tip.y, 0.0)),
		"arrow knob plane: polar snap like the web arrow (15 deg, 0.5 m/s, capped at 9 m/s), directions outside 0..90 deg blocked",
		"web default 52° 9.12 m/s -> %s, 14 m/s -> %s" % [str(snapped), str(capped)])


# --- manipulation through the input path -----------------------------------------------------------

func check_free_fall_manipulation() -> void:
	var screen: Control = await _open(ExperimentRegistry.find("free-fall"))
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var red: RigidBody3D = lab.balls.red
	var goal := Vector3(2.4, red.global_position.y, 0.0)   # -> x 2.5 on the 0.5 m grid of the floor line, same height
	_swipe(screen, _at(screen, red.global_position), _at(screen, goal))
	_touch(screen, 0, _at(screen, goal), false)
	var placed: bool = red.global_position.is_equal_approx(Vector3(2.5, 5.0 + lab.BALL_RADIUS, 0.0)) and red.freeze
	expect.call(placed and m.selected_id == "red" and m._knob.visible, "free fall: a ball held 5 m up dragged along its floor line keeps its height, snaps to 0.5 m and shows its height handle", str(red.global_position))
	# Height handle down by about 2 m: only the red ball's start changes.
	var knob_at := _at(screen, m._knob.global_position)
	var down := _at(screen, m._knob.global_position + Vector3(0, -2.0, 0))
	_swipe(screen, knob_at, down, 6)
	_touch(screen, 0, down, false)
	var h: float = lab.starts.red.y
	expect.call(absf(h - 3.0) < 0.26 and is_equal_approx(fmod(h, 0.5), 0.0) and lab.starts.orange.y == 5.0 and is_equal_approx(red.global_position.x, 2.5),
		"free fall: the height handle sets one ball's drop height in 0.5 m steps", "red %.2f m, orange %.2f m" % [h, lab.starts.orange.y])
	# Drop: the red ball lands first, at the TS landing time of its own height (±2 steps).
	screen.experiment_action("release")
	for i in 3 * STEP_HZ:
		if lab.status() == "landed" and _engine_landed(lab):
			break
		await tree.physics_frame
	var red_land: int = lab.corrector_of("red").landed_step
	var orange_land: int = lab.corrector_of("orange").landed_step
	var want := roundi(PhysicsLaws.landing_time(0.0, -9.81, h) * STEP_HZ)
	expect.call(red_land > 0 and absi(red_land - want) <= 2 and orange_land > red_land and float(lab.observations().fall_time) == PhysicsLaws.landing_time(0.0, -9.81, h),
		"free fall: after the handle the lower ball lands first at its own formula time", "red step %d (formula %d), orange %d" % [red_land, want, orange_land])
	# Picking up a landed ball puts every ball back at its start (the picked one at its own height).
	_swipe(screen, _at(screen, red.global_position), _at(screen, red.global_position + Vector3(0.05, 0, 0)), 2)
	var reset_ok: bool = not lab.released and lab.balls.orange.global_position.is_equal_approx(lab.starts.orange + Vector3.UP * lab.BALL_RADIUS)
	_touch(screen, 0, _at(screen, red.global_position), false)
	expect.call(reset_ok and absf(red.global_position.y - (h + lab.BALL_RADIUS)) < 1e-5, "free fall: picking up a landed ball stops the run and lifts it from its start height", str(red.global_position))
	# The height slider lines all three up again.
	screen._set_control("height", 4.0)
	expect.call(lab.starts.red.y == 4.0 and lab.starts.pink.y == 4.0 and is_equal_approx(red.global_position.x, 2.5),
		"free fall: the height condition lines the three balls up again (positions kept)", str(lab.starts))
	await _close(screen)


func check_projectile_manipulation() -> void:
	var screen: Control = await _open(ExperimentRegistry.find("projectile"))
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	# Arrow knob from (45 deg, 9 m/s) to the tip of (60 deg, 6 m/s), a little off the grid.
	var center: Vector3 = lab.ball_center()
	var target := ArrowSurface.tip(58.0, 6.2)
	var goal := center + Vector3(target.x, -target.y, 0.0)
	_swipe(screen, _at(screen, lab.knob.global_position), _at(screen, goal))
	var preview: Vector3 = lab.props.arrow.rotation
	await tree.process_frame   # the arrow preview follows the held knob (process_frame comes before _process)
	await tree.process_frame
	var turned: float = rad_to_deg(lab.props.arrow.rotation.z)
	_touch(screen, 0, _at(screen, goal), false)
	var synced: bool = screen._control_widgets.angle.slider.value == 60.0 and screen._control_widgets.speed.slider.value == 6.0
	var tip := ArrowSurface.tip(60.0, 6.0)
	expect.call(lab.angle_deg == 60.0 and lab.speed == 6.0 and synced and lab.knob.global_position.is_equal_approx(center + Vector3(tip.x, -tip.y, 0.0))
		and is_equal_approx(preview.z, deg_to_rad(45.0)) and is_equal_approx(turned, 60.0),
		"projectile: dragging the arrow knob sets direction and speed on the web arrow's grid (preview while held, sliders follow)",
		"angle %.1f, speed %.1f, preview %.1f°" % [lab.angle_deg, lab.speed, turned])
	# A direction behind the throw (120 deg) cannot be placed: the knob goes back.
	var back_tip := ArrowSurface.tip(120.0, 5.0)
	var back := center + Vector3(back_tip.x, -back_tip.y, 0.0)
	var knob_before: Vector3 = lab.knob.global_position
	_swipe(screen, _at(screen, lab.knob.global_position), _at(screen, back))
	var blocked: bool = not m.valid
	_touch(screen, 0, _at(screen, back), false)
	expect.call(blocked and lab.angle_deg == 60.0 and lab.knob.global_position.is_equal_approx(knob_before),
		"projectile: a direction outside 0..90 deg is shown as blocked and the knob goes back", "")
	# The ball moves along its launch line (0.5 m grid) and its height handle raises the launch.
	var ball: RigidBody3D = lab.ball
	var line_goal := Vector3(-4.1, ball.global_position.y, 0.0)
	_swipe(screen, _at(screen, ball.global_position), _at(screen, line_goal))
	_touch(screen, 0, _at(screen, line_goal), false)
	var on_line: bool = is_equal_approx(lab.start.x, -4.0) and is_equal_approx(lab.start.y, 0.5)
	var knob_at := _at(screen, m._knob.global_position)
	var up := _at(screen, m._knob.global_position + Vector3(0, 1.0, 0))
	_swipe(screen, knob_at, up, 6)
	_touch(screen, 0, up, false)
	var tip_now := ArrowSurface.tip(60.0, 6.0)
	var arrow_follows: bool = lab.knob.global_position.is_equal_approx(lab.ball_center() + Vector3(tip_now.x, -tip_now.y, 0.0))
	expect.call(on_line and absf(lab.start.y - 1.5) < 0.13 and is_equal_approx(fmod(lab.start.y, 0.25), 0.0) and arrow_follows,
		"projectile: the ball moves on its launch line and its handle sets the launch height; the arrow follows", "start %s" % str(lab.start))
	var shown: Dictionary = lab.observations()
	var vy := 6.0 * sin(deg_to_rad(60.0))
	expect.call(float(shown.flight_time) == PhysicsLaws.landing_time(vy, -9.81, lab.start.y) and float(shown.launch_height) == lab.start.y,
		"projectile: the panel's flight time follows the new launch (formula from the new height)", str(shown.flight_time))
	await _close(screen)
