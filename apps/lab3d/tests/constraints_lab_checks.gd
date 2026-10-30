## Headless checks of the string / rod pendulum lab (Phase 1 Task 4e), run by run_tests.gd. Expected
## values are the TS-core vectors in tests/constraints_lab_vectors.json
## (tools/constraints-lab-vectors.test.ts: the web PendulumModel's equation, RK4 x4 per 60 Hz step).
## Physics first: the engine bobs are checked step by step, not only the panel.
## 1. definition: valid, listed, texts and app tip; the defaults = the TS start case (2 m,
##    earth, the web's angles and damping, 1 kg bobs).
## 2. model = TS (no engine): angle, angular velocity, bob offset, tension, measured period at every
##    sample step and the small-angle period, 7 cases (rel 1e-9).
## 3. engine = TS: the lab through its own fixed steps; engine bob centres = TS at every sample step
##    (<= 1e-4 m), every step on the model state with the model's step velocity, panel = TS (1e-9),
##    the 60 s run past the history window.
## 4. physics from the engine bobs alone: anchor-bob distance = L at every step (the constraint),
##    period from zero crossings = 2 pi sqrt(L / g) for small swings and the exact large-angle
##    period, energy kept without damping and decaying like e^(-b t) with it.
## 5. conditions: gravity, length and damping restart the run at the angles; no gravity = no swing;
##    unknown ids are ignored; the panel holds only formula values.
## 6. art: visual only (bodies, the same run without reactions), draw-node budget, string and rod
##    reach from the anchors to the bobs.
## 7. a freshly opened screen: "놓기" gives the TS start motion from the first step; the angle graph.
## 8. the real input path: dragging a bob keeps it on its circle (5 deg grid); letting go releases
##    both from rest; the run = formula; picking it up stops the run.
## 9. the measurement demo (--auto-drag) drags a bob and releases.
extends RefCounted

const VECTORS_PATH := "res://tests/constraints_lab_vectors.json"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60
const ENGINE_TOLERANCE := 1e-4
const SIDES := ["rope", "rod"]

var tree: SceneTree
var expect: Callable
var vectors: Dictionary
var tolerance := 1e-9


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn
	vectors = JSON.parse_string(FileAccess.get_file_as_string(VECTORS_PATH))
	tolerance = vectors.tolerance


func run() -> void:
	check_definition()
	check_model_cases()
	await check_engine_cases()
	await check_engine_physics()
	await check_conditions()
	await check_art()
	await check_first_release_screen()
	await check_input_path()
	await check_demo()


# --- helpers ----------------------------------------------------------------------------------

func _lab() -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find("constraints"))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


func _until(lab: Experiment, k: int) -> void:
	var guard := 0
	while lab.models[0].steps < k and guard < 8000:
		await tree.physics_frame
		guard += 1


func _err(value: Variant, want: float) -> float:
	if not (value is float or value is int):
		return INF
	return absf(float(value) - want) / maxf(1.0, absf(want))


func _case(name: String) -> Dictionary:
	for c in vectors.cases:
		if c.name == name:
			return c
	return {}


func _gravity_id(g: float) -> String:
	return {0.0: "zero", 1.62: "moon", 9.81: "earth", 24.79: "jupiter"}.get(g, "?")


## The lab set to a vector case and released.
func _start(lab: Experiment, c: Dictionary) -> void:
	lab.begin_batch()
	lab.set_control("gravity", _gravity_id(float(c.g)))
	lab.set_control("length", float(c.length))
	lab.set_control("damping", "none" if float(c.rope.damping) == 0.0 else "web")
	lab.start_angles.assign([float(c.rope.angle), float(c.rod.angle)])
	lab.end_batch()
	lab.reset_run()
	lab.release()


func _model_for(c: Dictionary, side: String) -> PendulumLabModel:
	var model := PendulumLabModel.new()
	model.length = c.length
	model.g = c.g
	model.damping = c[side].damping
	model.mass = vectors.bob_mass
	model.reset(c[side].angle)
	return model


## Worst relative error of a model against a vector sample of one side.
func _model_error(m: PendulumLabModel, v: Dictionary) -> float:
	var o := m.offset()
	var worst := 0.0
	for pair in [[m.angle, v.angle], [m.omega, v.omega], [o[0], v.x], [o[1], v.y], [m.tension(), v.tension], [m.period, v.period]]:
		worst = maxf(worst, _err(pair[0], pair[1]))
	return worst


func _open() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(1560, 720)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("constraints"))
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


func _touch(screen: Control, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	screen.view._gui_input(event)


func _swipe(screen: Control, from: Vector2, to: Vector2, steps := 8) -> void:
	_touch(screen, from, true)
	for i in range(1, steps + 1):
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = from.lerp(to, float(i) / steps)
		screen.view._gui_input(event)


## World centre of bob `i` at `angle` (rad) for the lab's length.
func _bob_at(lab: Experiment, i: int, angle: float) -> Vector3:
	return lab.anchor(i) + Vector3(lab.length * sin(angle), -lab.length * cos(angle), 0.0)


# --- 1. definition ----------------------------------------------------------------------------

func check_definition() -> void:
	var definition := ExperimentRegistry.find("constraints")
	var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	expect.call(problems.is_empty() and listed.has("constraints") and definition.get("title", "") != ""
		and definition.get("tip", "") != "" and definition.tip.contains("5°"),
		"constraints: definition valid, listed, its texts and the app tip in the experiment file", ", ".join(problems))
	var start := _case("start")
	var defaults := {}
	for control in definition.controls:
		defaults[control.id] = control.default
	var consts: Dictionary = (load(definition.scene) as GDScript).get_script_constant_map()
	var web_option := {}
	for control in definition.controls:
		if control.id == "damping":
			for option in control.options:
				if option.id == "web":
					web_option = option
	var angles: Array = consts.WEB_ANGLES
	expect.call(float(defaults.length) == float(start.length) and defaults.gravity == "earth" and defaults.damping == "web"
		and angles[0] == float(vectors.web.rope.angle) and angles[1] == float(vectors.web.rod.angle)
		and float(web_option.rope_b) == float(vectors.web.rope.damping) and float(web_option.rod_b) == float(vectors.web.rod.damping)
		and float(consts.BOB_MASS) == float(vectors.bob_mass) and PendulumLabModel.SUBSTEPS == int(vectors.substeps),
		"constraints: the start = the TS start case (2 m, earth); angles 0.62 / -0.5 rad, damping 0.06 / 0.03 /s and 1 kg bobs = the web's", "")


# --- 2. model = TS ----------------------------------------------------------------------------

func check_model_cases() -> void:
	var worst := 0.0
	var worst_small := 0.0
	var dt := 1.0 / float(vectors.step_hz)
	for c in vectors.cases:
		for side in SIDES:
			var model := _model_for(c, side)
			if c.small_angle_period != null:
				worst_small = maxf(worst_small, _err(model.small_angle_period(), c.small_angle_period))
			for s in c.samples:
				while model.steps < int(s.step):
					model.step(dt)
				worst = maxf(worst, _model_error(model, s[side]))
	expect.call(worst <= tolerance and worst_small <= tolerance,
		"constraints model: angle, angular velocity, bob offset, tension and measured period at every sample step = TS (7 cases x string and rod, 60 s)",
		"max rel err %s, T0 %s" % [String.num_scientific(worst), String.num_scientific(worst_small)])


# --- 3. engine = TS ---------------------------------------------------------------------------

func check_engine_cases() -> void:
	var lab: Experiment = await _lab()
	var worst_x := 0.0
	var worst_shown := 0.0
	var worst_step_x := 0.0
	var worst_step_v := 0.0
	var past_history := false
	for c in vectors.cases:
		_start(lab, c)
		for s in c.samples:
			var k := int(s.step)
			if k == 0:
				continue
			await _until(lab, k)
			if lab.models[0].steps != k:
				worst_x = INF
				break
			var shown: Dictionary = lab.observations()
			# The rod pendulum's numbers are not shown since 2026-10-29 (one ball in the view): its model's.
			var rod_model: PendulumLabModel = lab.models[1]
			shown.merge({"rod_angle": rad_to_deg(rod_model.angle), "rod_tension": rod_model.tension(), "rod_distance": rod_model.distance(),
				"rod_period": rod_model.period if rod_model.period > 0.0 else "—"})
			for i in 2:
				var v: Dictionary = s[SIDES[i]]
				var want: Vector3 = lab.anchor(i) + Vector3(float(v.x), -float(v.y), 0.0)
				var at: Vector3 = lab.bobs[i].global_position
				worst_x = maxf(worst_x, maxf(absf(at.x - want.x), maxf(absf(at.y - want.y), absf(at.z - want.z))))
				worst_shown = maxf(worst_shown, _err(shown[SIDES[i] + "_angle"], rad_to_deg(float(v.angle))))
				worst_shown = maxf(worst_shown, _err(shown[SIDES[i] + "_tension"], v.tension))
				worst_shown = maxf(worst_shown, _err(shown[SIDES[i] + "_distance"], c.length))
				if float(v.period) > 0.0:
					worst_shown = maxf(worst_shown, _err(shown[SIDES[i] + "_period"], v.period))
				elif not shown[SIDES[i] + "_period"] is String:
					worst_shown = INF
		worst_step_x = maxf(worst_step_x, lab.driver.worst_position())
		worst_step_v = maxf(worst_step_v, lab.driver.worst_velocity())
		if c.name == "long":
			var member: BodyModelDriver = lab.driver.members[0]
			past_history = member.engine.size() == member.history_steps and lab.models[0].steps > member.history_steps * 5
	expect.call(worst_x <= ENGINE_TOLERANCE, "constraints: engine bob centres = TS at every sample step (7 cases, string and rod, 60 s run included, <= 1e-4 m)",
		"max |d| %s m" % String.num_scientific(worst_x))
	expect.call(worst_step_x <= ENGINE_TOLERANCE and worst_step_v <= ENGINE_TOLERANCE and past_history,
		"constraints: every engine step lands on the formula state with the formula's step velocity, also past the history window (60 s)",
		"max %s m, %s m/s" % [String.num_scientific(worst_step_x), String.num_scientific(worst_step_v)])
	expect.call(worst_shown <= tolerance, "constraints: panel (angles, tensions, distances, measured periods) = TS at every sample step", "max rel err %s" % String.num_scientific(worst_shown))
	await _free(lab)


# --- 4. physics from the engine bobs ----------------------------------------------------------

## Engine bob positions relative to the anchors over `steps` steps (index k = after k steps).
func _engine_run(lab: Experiment, gravity: String, length: float, damping: String, angles: Array, steps: int) -> Array:
	lab.begin_batch()
	lab.set_control("gravity", gravity)
	lab.set_control("length", length)
	lab.set_control("damping", damping)
	lab.start_angles.assign(angles)
	lab.end_batch()
	lab.reset_run()
	lab.release()
	var runs := [PackedVector3Array(), PackedVector3Array()]
	for i in 2:
		runs[i].append(lab.bobs[i].global_position - lab.anchor(i))
	while lab.models[0].steps < steps:
		await tree.physics_frame
		for i in 2:
			runs[i].append(lab.bobs[i].global_position - lab.anchor(i))
	return runs


## Period from the zero crossings of the bob's x (same direction, linear interpolation).
func _period(xs: PackedVector3Array, dt: float) -> float:
	var ups: Array[float] = []
	for k in range(1, xs.size()):
		if xs[k - 1].x < 0.0 and xs[k].x >= 0.0:
			ups.append((k - 1 + xs[k - 1].x / (xs[k - 1].x - xs[k].x)) * dt)
	return (ups[-1] - ups[0]) / (ups.size() - 1) if ups.size() >= 2 else 0.0


func check_engine_physics() -> void:
	var lab: Experiment = await _lab()
	var dt := 1.0 / STEP_HZ
	# The constraint: the anchor-bob distance of the engine bobs is L at every step (both bobs, 30 s).
	var worst_length := 0.0
	for length in [1.0, 2.0, 3.5]:
		var runs: Array = await _engine_run(lab, "earth", length, "web", [deg_to_rad(70.0), deg_to_rad(-45.0)], 30 * STEP_HZ)
		for i in 2:
			for d in runs[i]:
				worst_length = maxf(worst_length, absf(d.length() - length))
	expect.call(worst_length <= 2e-6, "constraints: the engine bobs stay L from their anchors at every step (string and rod, 1 / 2 / 3.5 m, 30 s): the fixed-length constraint",
		"max |d - L| %s m" % String.num_scientific(worst_length))
	# Period: small swings = 2 pi sqrt(L / g); large swings = the exact large-angle period (TS AGM).
	var details := []
	var worst_small := 0.0
	for setting in [["earth", 1.0, 9.81], ["earth", 2.5, 9.81], ["moon", 2.0, 1.62], ["jupiter", 1.5, 24.79]]:
		var runs: Array = await _engine_run(lab, setting[0], setting[1], "none", [deg_to_rad(4.0), deg_to_rad(-4.0)], 25 * STEP_HZ)
		var measured := _period(runs[0], dt)
		var want := TAU * sqrt(float(setting[1]) / float(setting[2]))
		worst_small = maxf(worst_small, absf(measured - want) / want)
		details.append("%s %.2f m %.4f/%.4f s" % [setting[0], setting[1], measured, want])
	var long := _case("long")
	var runs_long: Array = await _engine_run(lab, "earth", float(long.length), "none", [float(long.rope.angle), float(long.rod.angle)], 60 * STEP_HZ)
	var worst_large := 0.0
	for i in 2:
		var want: float = long.large_angle_period[SIDES[i]]
		worst_large = maxf(worst_large, absf(_period(runs_long[i], dt) - want) / want)
	expect.call(worst_small <= 1e-3 and worst_large <= 1e-4,
		"constraints: the engine bobs' period (zero crossings) = 2 pi sqrt(L / g) for 4 deg swings (4 settings, <= 0.1 %: the small-angle law) and the exact period of 75 / 40 deg swings (<= 1e-4)",
		"%s; 75/40 deg rel %s" % ["; ".join(details), String.num_scientific(worst_large)])
	# Energy of the engine bobs alone (v by central difference): kept without damping; with the
	# web's damping it decays like e^(-b t) for small swings (dE/dt = -b m v^2).
	var runs_free: Array = await _engine_run(lab, "earth", 2.0, "none", [0.62, -0.5], 30 * STEP_HZ)
	var runs_damped: Array = await _engine_run(lab, "earth", 2.0, "web", [deg_to_rad(10.0), deg_to_rad(-10.0)], 40 * STEP_HZ)
	var worst_energy := 0.0
	for i in 2:
		var xs: PackedVector3Array = runs_free[i]
		var e0 := 9.81 * 2.0 * (1.0 - cos(0.62 if i == 0 else -0.5))
		for k in range(1, xs.size() - 1, 7):
			var v := (xs[k + 1] - xs[k - 1]) / (2.0 * dt)
			var e := 9.81 * (2.0 + xs[k].y) + 0.5 * v.length_squared()
			worst_energy = maxf(worst_energy, absf(e - e0) / e0)
	var decay := []
	var worst_decay := 0.0
	for i in 2:
		var xs: PackedVector3Array = runs_damped[i]
		var energy := func(k: int) -> float:
			var v: Vector3 = (xs[k + 1] - xs[k - 1]) / (2.0 * dt)
			return 9.81 * (2.0 + xs[k].y) + 0.5 * v.length_squared()
		var e_start := 0.0
		var e_end := 0.0
		for k in range(1, 3 * STEP_HZ):
			e_start = maxf(e_start, energy.call(k))
		for k in range(37 * STEP_HZ, 40 * STEP_HZ - 1):
			e_end = maxf(e_end, energy.call(k))
		var b: float = lab.damping(i)
		var ratio := e_end / e_start
		var want := exp(-b * 37.0)
		worst_decay = maxf(worst_decay, absf(ratio - want) / want)
		decay.append("%s %.4f/%.4f" % [SIDES[i], ratio, want])
	expect.call(worst_energy <= 1e-3 and worst_decay <= 0.02,
		"constraints: energy from the engine bobs (central-difference v) is kept for 30 s without damping (<= 0.1 %) and decays like e^(-b t) with the web's damping (37 s, <= 2 %)",
		"no damping max %s; damped %s" % [String.num_scientific(worst_energy), ", ".join(decay)])
	await _free(lab)


# --- 5. conditions ----------------------------------------------------------------------------

func check_conditions() -> void:
	var lab: Experiment = await _lab()
	lab.release()
	await _until(lab, 40)
	var moved: bool = lab.bobs[0].global_position.distance_to(_bob_at(lab, 0, 0.62)) > 0.05
	lab.set_control("length", 3.0)
	var back: bool = not lab.released and lab.bobs[0].global_position.distance_to(_bob_at(lab, 0, 0.62)) < 1e-5 \
		and lab.bobs[1].global_position.distance_to(_bob_at(lab, 1, -0.5)) < 1e-5 and lab.graph_series().rope.is_empty()
	var shown: Dictionary = lab.observations()
	var t0_ok := absf(float(shown.small_period) - TAU * sqrt(3.0 / 9.81)) < 1e-12 and float(shown.length) == 3.0 and absf(float(shown.rope_distance) - 3.0) < 1e-12
	lab.set_control("gravity", "moon")
	var moon_ok := absf(float(lab.observations().small_period) - TAU * sqrt(3.0 / 1.62)) < 1e-12
	lab.set_control("damping", "none")
	var undamped: bool = lab.models[0].damping == 0.0 and lab.models[1].damping == 0.0
	lab.set_control("damping", "web")
	var damped: bool = lab.models[0].damping == 0.06 and lab.models[1].damping == 0.03
	lab.set_control("damping", "honey")
	lab.set_control("gravity", "pluto")
	lab.set_control("nope", 1.0)
	lab.set_control("length", 99.0)
	expect.call(moved and back and t0_ok and moon_ok and undamped and damped and lab.damping_id == "web" and lab.gravity_id == "moon"
		and lab.length == 3.5 and lab.status() == "ready",
		"constraints: gravity, length and damping change the conditions and put both bobs back at their angles; unknown ids are ignored, the length stays within 1-3.5 m", "")
	# No gravity: released bobs stay where they were let go; the period rows say why there is none.
	lab.set_control("gravity", "zero")
	lab.release()
	await _until(lab, 120)
	var still: bool = lab.bobs[0].global_position.distance_to(_bob_at(lab, 0, 0.62)) < 1e-6 and lab.status() == "weightless"
	var weightless: Dictionary = lab.observations()
	expect.call(still and weightless.small_period is String and weightless.rope_period is String and absf(float(weightless.rope_tension)) < 1e-12,
		"constraints: without gravity the released bobs stay where they are (no swing, no period, no pull)", str(weightless.small_period))
	var labels_ok := true
	var ids := []
	for item in lab.definition.observations():
		labels_ok = labels_ok and not str(item.label).contains("시뮬레이션")
		ids.append(item.id)
	expect.call(labels_ok and ids.all(func(id): return weightless.has(id)) and ids.size() == weightless.size(),
		"constraints: the panel shows only formula-model values (no 'simulation' reading of the posed engine bobs)", "%d values" % ids.size())
	await _free(lab)


# --- 6. art -----------------------------------------------------------------------------------

func check_art() -> void:
	var lab: Experiment = await _lab()
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append("%s:%s" % [node.name, node.get_class()])
	bodies.sort()
	var kinematic := true
	for bob in lab.bobs:
		kinematic = kinematic and bob.collision_mask == 0 and bob.freeze and bob.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC
	expect.call(bodies == ["Floor:StaticBody3D", "RodBob:RigidBody3D", "StringBob:RigidBody3D"] and kinematic and lab.bobs[1].collision_layer == 0,
		"constraints art adds no collision objects; the bobs are kinematic and touch nothing (the formula moves them); the rod bob (not shown since 2026-10-29) cannot be picked", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		for juice in lab.props.juices:
			juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.release()
		await _until(lab, 150)
		runs.append({"at": [lab.bobs[0].global_position, lab.bobs[1].global_position], "basis": lab.bobs[0].global_basis, "obs": str(lab.observations())})
	for juice in lab.props.juices:
		juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(runs[0].at == runs[1].at and runs[0].obs == runs[1].obs and runs[0].basis == Basis(),
		"constraints: same motion and panel with and without the reactions; the bobs' bodies never turn", str(runs[0].at))
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 28, "constraints: at most 28 drawn 3D nodes (art budget: 16 + the bread cat's 7 + its stand, 2026-10-27; + the turtle clock's 5: body, pendulum, door, the piece's 2, 2026-10-29)", "%d" % draw_nodes)
	# The string reaches from the anchor to the bob centre (its mesh's far end). The lab view shows the
	# rope pendulum only (2026-10-29 user "흔들 추 하나만"): no rod, rod ball, rod path or rod stand.
	lab._show()
	var worst := 0.0
	var one_ball: bool = lab.props.links.size() == 1 and lab.props.paths.size() == 1 and lab.props.juices.size() == 1 \
		and not lab.bobs[1].has_node("Visual") and lab.find_children("Rod", "", true, false).is_empty()
	for i in 1:
		var link: MeshInstance3D = lab.props.links[i]
		var end: Vector3 = link.global_transform * Vector3(0.0, -1.0, 0.0)
		worst = maxf(worst, end.distance_to(lab.bobs[i].global_position))
	var path_ok: bool = lab.props.paths[0].mesh != null and lab.props._path_length == lab.length
	expect.call(worst < 1e-4 and path_ok and one_ball, "constraints: the string reaches from its anchor to the bob; the dotted path is the circle of radius L; the rod pendulum is not drawn (one ball)",
		"max gap %s m" % String.num_scientific(worst))
	await _free(lab)


# --- 7. fresh screen --------------------------------------------------------------------------

func check_first_release_screen() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var c := _case("start")
	var waiting: Dictionary = lab.observations()
	screen.experiment_action("release")
	var worst := 0.0
	for s in c.samples:
		var k := int(s.step)
		if k == 0 or k > 120:
			continue
		await _until(lab, k)
		for i in 2:
			var v: Dictionary = s[SIDES[i]]
			worst = maxf(worst, lab.bobs[i].global_position.distance_to(lab.anchor(i) + Vector3(float(v.x), -float(v.y), 0.0)))
	var reference := _model_for(c, "rope")
	reference.anchor_x = lab.anchor(0).x
	reference.anchor_y = lab.anchor(0).y
	reference.anchor_z = lab.anchor(0).z
	reference.reset(0.62)
	reference.step(1.0 / STEP_HZ)
	var member: BodyModelDriver = lab.driver.members[0]
	var first_step_ok: bool = member.engine.size() > 1 and member.engine[1].distance_to(reference.position()) < ENGINE_TOLERANCE
	expect.call(waiting.state == "놓기 전 · 추를 끌어 각도를 정해요" and absf(float(waiting.rope_angle) - rad_to_deg(0.62)) < 1e-9 and waiting.rope_period is String
		and worst <= ENGINE_TOLERANCE and first_step_ok and lab.status() == "swinging",
		"constraints (fresh screen): 놓기 → both engine bobs follow the TS start motion from the first step", "|d| %s m" % String.num_scientific(worst))
	await _until(lab, 360)
	var series: Dictionary = lab.graph_series()
	var signs := 0
	for i in range(1, series.rope.size()):
		if signf(series.rope[i].y) != signf(series.rope[i - 1].y):
			signs += 1
	var rod_line: PackedVector2Array = lab.rod_graph()
	expect.call(series.rope.size() >= 55 and absf(series.rope[0].y - rad_to_deg(0.62)) < 1e-4 and not series.has("rod") and absf(rod_line[0].y - rad_to_deg(-0.5)) < 1e-4
		and signs >= 3 and GraphView.y_top(lab.definition.graph(), series) == 90.0 and lab.definition.graph().y.signed,
		"constraints: the graph shows the rope pendulum's angle over time on a fixed signed +-90 deg axis, swinging through zero (the rod's, kept for the web's two pendulums, is not drawn)", "%d points, %d sign changes" % [series.rope.size(), signs])
	await _close(screen)


# --- 8. input path ----------------------------------------------------------------------------

func check_input_path() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var bob: RigidBody3D = lab.bobs[0]
	var goal := _bob_at(lab, 0, deg_to_rad(21.0))
	# The finger ends inside the circle (70 % of L from the anchor, at 21 deg): the bob stays on it.
	var finger: Vector3 = lab.anchor(0).lerp(goal, 0.7)
	_swipe(screen, _at(screen, bob.global_position), _at(screen, finger))
	await tree.process_frame
	await tree.process_frame
	var held: bool = m.mode == "drag" and m.active_id == "rope" and lab.status() == "held"
	var on_circle := absf(bob.global_position.distance_to(lab.anchor(0)) - lab.length) < 1e-4
	var link_follows: bool = (lab.props.links[0].global_transform * Vector3(0.0, -1.0, 0.0)).distance_to(bob.global_position) < 1e-3
	var shown_angle: float = lab.observations().rope_angle
	var rod_waits: bool = lab.bobs[1].global_position.distance_to(_bob_at(lab, 1, -0.5)) < 1e-5
	_touch(screen, _at(screen, finger), false)
	await tree.process_frame
	var released: bool = lab.released and absf(lab.start_angles[0] - deg_to_rad(20.0)) < 1e-12 and absf(lab.models[0].start_angle - deg_to_rad(20.0)) < 1e-12
	expect.call(held and on_circle and link_follows and rod_waits and absf(shown_angle - 20.0) < 1e-6 and released
		and absf(lab.angle_at(0, _bob_at(lab, 0, deg_to_rad(88.0))) - deg_to_rad(75.0)) < 1e-12,
		"constraints: dragging the string bob keeps it on its circle (distance L, 5 deg grid, +-75 deg) with the string following; letting go releases both from rest",
		"held %s, on circle %s, link %s, rod waits %s, released %s, angle %.2f deg" % [held, on_circle, link_follows, rod_waits, released, shown_angle])
	var reference := PendulumLabModel.new()
	reference.length = lab.length
	reference.damping = 0.06
	reference.anchor_x = lab.anchor(0).x
	reference.anchor_y = lab.anchor(0).y
	reference.anchor_z = lab.anchor(0).z
	reference.reset(deg_to_rad(20.0))
	var worst := 0.0
	for k in 90:
		await tree.physics_frame
		while reference.steps < lab.models[0].steps:
			reference.step(1.0 / STEP_HZ)
		worst = maxf(worst, bob.global_position.distance_to(reference.position()))
	expect.call(worst <= ENGINE_TOLERANCE and lab.driver.worst_position() <= ENGINE_TOLERANCE,
		"constraints: the run after letting go follows the formula from rest at 20 deg", "|d| %s m" % String.num_scientific(worst))
	# The rod bob is not shown (2026-10-29): touching where it is picks nothing and the run goes on.
	_swipe(screen, _at(screen, lab.bobs[1].global_position), _at(screen, lab.bobs[1].global_position + Vector3(0.02, 0, 0)), 2)
	var still_running: bool = lab.released and lab.status() == "swinging" and lab.manipulation_body("rod") == null
	_touch(screen, _at(screen, lab.bobs[1].global_position), false)
	await tree.process_frame
	expect.call(still_running and lab.released, "constraints: the hidden rod bob cannot be picked up (no rod in the lab view)", "")
	await _close(screen)


# --- 9. demo ----------------------------------------------------------------------------------

func check_demo() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	screen.manipulator.start_demo(0.2)
	var runs := 0
	var was := false
	var angles := {}
	for i in 8 * STEP_HZ:
		await tree.physics_frame
		if lab.released and not was:
			runs += 1
			angles[snappedf(rad_to_deg(lab.start_angles[0]), 0.1)] = true
		was = lab.released
	screen.manipulator.start_demo(0.0)
	expect.call(runs >= 2 and angles.size() >= 2, "constraints: the measurement demo (--auto-drag) drags the string bob to new angles and lets go", "%d runs, angles %s" % [runs, str(angles.keys())])
	await _close(screen)
