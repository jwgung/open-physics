## Headless checks of the lever lab (Phase 1 Task 4e), run by run_tests.gd. Expected values are the
## TS-core vectors in tests/rotation_lab_vectors.json (tools/rotation-lab-vectors.test.ts: the web's
## LeverChallenge, its force cap and lift angle, rotation.ts torque).
## Physics first: the engine beam and load are checked step by step, not only the panel.
## 1. definition: valid, listed, shared texts and app tip; the defaults = the TS start case (20 kg,
##    the middle point, fulcrum -0.5 m, load -2.5 m); geometry, lift angle and the handle's 5 N / 2 cm.
## 2. model = TS (no engine): required force, advantage, weight, torques, and for every press the
##    force on the beam, lifting, angle and the load / beam poses (6 cases x 51 presses, rel 1e-9).
## 3. engine = TS: the lab through its own fixed steps, one press per step; engine beam angle and load
##    / beam centres = TS at every step, panel = TS.
## 4. physics from the engine bodies: the beam tilts exactly from the first press with F r_effort >=
##    m g r_load (the torque balance), the load stays on the rigid beam, the torques cancel lifted.
## 5. conditions: mass and the effort point change the lever and add a graph point; unknown ids are
##    ignored; the panel holds only formula values.
## 6. art: visual only, draw-node budget, the handle rod reaches the effort point.
## 7-8. the real input path on a fresh screen: pressing the handle down lifts the beam at the
##    required force, the graph's clock runs while it is held, letting go puts it back level;
##    dragging the load and the fulcrum (0.25 m grid, the load stays left of the fulcrum).
## 9. the measurement demo (--auto-drag) presses the handle and lets go.
extends RefCounted

const VECTORS_PATH := "res://tests/rotation_lab_vectors.json"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60
const ENGINE_TOLERANCE := 1e-4

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
	await check_conditions()
	await check_art()
	await check_input_path()
	await check_demo()


# --- helpers ----------------------------------------------------------------------------------

func _lab() -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find("rotation"))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


func _err(value: Variant, want: float) -> float:
	if not (value is float or value is int):
		return INF
	return absf(float(value) - want) / maxf(1.0, absf(want))


func _case(name: String) -> Dictionary:
	for c in vectors.cases:
		if c.name == name:
			return c
	return {}


func _effort_id(fraction: float) -> String:
	return {0.35: "near", 0.6: "mid", 0.9: "far"}.get(fraction, "?")


func _set_case(lab: Experiment, c: Dictionary) -> void:
	lab.set_control("mass", float(c.mass))
	lab.set_control("effort", _effort_id(float(c.fraction)))
	lab.set_layout(float(c.pivot), float(c.load_x))


func _model_for(c: Dictionary) -> LeverLabModel:
	var m := LeverLabModel.new()
	m.beam_half = vectors.beam_half
	m.pivot_y = vectors.pivot_y
	m.load_up = vectors.load_up
	m.g = vectors.g
	m.mass = c.mass
	m.pivot_x = c.pivot
	m.load_x = c.load_x
	m.fraction = c.fraction
	return m


func _open() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(720, 1560)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("rotation"))
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


# --- 1. definition ----------------------------------------------------------------------------

func check_definition() -> void:
	var definition := ExperimentRegistry.find("rotation")
	var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	var shared: Dictionary = ExperimentRegistry.shared_labs().get("rotation", {})
	expect.call(problems.is_empty() and listed.has("rotation") and definition.get("title") == shared.get("title")
		and definition.get("tip", "") == shared.get("app", {}).get("tip", "") and definition.tip.contains("손잡이"),
		"rotation: definition valid, listed, texts and the app tip from the shared content", ", ".join(problems))
	var start := _case("start")
	var consts: Dictionary = (load(definition.scene) as GDScript).get_script_constant_map()
	var defaults := {}
	var fractions := []
	for control in definition.controls:
		defaults[control.id] = control.default
		if control.id == "effort":
			for option in control.options:
				fractions.append(float(option.fraction))
	var snap: float = Manipulator.parse_rules(definition).handle.snap
	expect.call(float(defaults.mass) == float(start.mass) and defaults.effort == _effort_id(float(start.fraction)) and fractions == [0.35, 0.6, 0.9]
		and float(consts.DEFAULT_PIVOT) == float(start.pivot) and float(consts.DEFAULT_LOAD) == float(start.load_x)
		and float(consts.BEAM_HALF) == float(vectors.beam_half) and float(consts.PIVOT_Y) == float(vectors.pivot_y)
		and is_equal_approx(float(consts.BEAM_THICK) * 0.5 + float(consts.LOAD_SIZE) * 0.5, float(vectors.load_up))
		and LeverLabModel.LIFT_ANGLE == float(vectors.lift_angle) and LeverLabModel.FORCE_STEP == float(vectors.force_step) and snap == 0.02
		and int(roundf(float(consts.REACH) / snap)) == 50,
		"rotation: the start = the TS start case (20 kg, the middle of the web's 3 points); lift angle 0.18 rad = the web's; the handle = 5 N per 2 cm up to 250 N", "")


# --- 2. model = TS ----------------------------------------------------------------------------

func check_model_cases() -> void:
	var worst := 0.0
	var count := 0
	for c in vectors.cases:
		var m := _model_for(c)
		for pair in [[m.load_arm(), c.load_arm], [m.effort_arm(), c.effort_arm], [m.required(), c.required], [m.advantage(), c.advantage],
				[m.weight(), c.weight], [m.load_torque(), c.load_torque]]:
			worst = maxf(worst, _err(pair[0], pair[1]))
		for p in c.presses:
			m.cells = int(p.cells)
			count += 1
			if m.lifting() != bool(p.lifting):
				worst = INF
			for pair in [[m.applied(), p.applied], [m.angle(), p.angle], [m.effort_torque(), p.effort_torque],
					[m.beam_x(m.load_x, m.load_up), p.load[0]], [m.beam_y(m.load_x, m.load_up), p.load[1]],
					[m.beam_x(0.0, 0.0), p.beam[0]], [m.beam_y(0.0, 0.0), p.beam[1]]]:
				worst = maxf(worst, _err(pair[0], pair[1]))
	expect.call(worst <= tolerance, "rotation model: required force, advantage, weight, torques and every press (force on the beam, lifting, angle, load and beam poses) = TS",
		"%d presses, max rel err %s" % [count, String.num_scientific(worst)])


# --- 3-4. engine = TS, physics from the engine ------------------------------------------------

func check_engine_cases() -> void:
	var lab: Experiment = await _lab()
	var worst_pose := 0.0
	var worst_angle := 0.0
	var worst_shown := 0.0
	var worst_rigid := 0.0
	var thresholds := []
	var threshold_ok := true
	var balance := 0.0
	for c in vectors.cases:
		_set_case(lab, c)
		var lifted_at := -1
		for p in c.presses:
			lab.set_cells(int(p.cells))
			await tree.physics_frame
			var beam: RigidBody3D = lab.beam
			var load_body: RigidBody3D = lab.load_body
			var a: float = lab.driver.engine_angle()
			worst_angle = maxf(worst_angle, absf(a - float(p.angle)))
			worst_pose = maxf(worst_pose, maxf(absf(load_body.global_position.x - float(p.load[0])), absf(load_body.global_position.y - float(p.load[1]))))
			worst_pose = maxf(worst_pose, maxf(absf(beam.global_position.x - float(p.beam[0])), absf(beam.global_position.y - float(p.beam[1]))))
			var shown: Dictionary = lab.observations()
			for pair in [[shown.applied, p.applied], [shown.required, c.required], [shown.load_arm, c.load_arm], [shown.effort_arm, c.effort_arm],
					[shown.weight, c.weight], [shown.advantage, c.advantage], [shown.load_torque, absf(float(c.load_torque))], [shown.effort_torque, absf(float(p.effort_torque))],
					[shown.net_torque, float(c.load_torque) + float(p.effort_torque)]]:
				worst_shown = maxf(worst_shown, _err(pair[0], pair[1]))
			# The engine load rides on the rigid beam: its distance from the fulcrum axis is fixed.
			var d := Vector2(load_body.global_position.x - float(c.pivot), load_body.global_position.y - float(vectors.pivot_y))
			worst_rigid = maxf(worst_rigid, absf(d.length() - Vector2(float(c.load_arm), float(vectors.load_up)).length()))
			if lifted_at < 0 and a < -0.1:
				lifted_at = int(p.cells)
				balance = maxf(balance, absf(float(shown.net_torque)))
		# From the engine beam: it tilts at the first press whose force times r_effort reaches m g r_load.
		var torque_load: float = float(c.weight) * float(c.load_arm)
		if lifted_at >= 0:
			threshold_ok = threshold_ok and lifted_at * 5.0 * float(c.effort_arm) >= torque_load and (lifted_at - 1) * 5.0 * float(c.effort_arm) < torque_load
		else:
			threshold_ok = threshold_ok and 50 * 5.0 * float(c.effort_arm) < torque_load
		thresholds.append("%s %s" % [c.name, "-" if lifted_at < 0 else "%d N" % (lifted_at * 5)])
	expect.call(worst_pose <= ENGINE_TOLERANCE and worst_angle <= 1e-6 and lab.driver.worst_position <= ENGINE_TOLERANCE and lab.driver.worst_angle <= 1e-6,
		"rotation: engine beam angle and load / beam centres = TS at every step (6 cases x 51 presses)",
		"max %s m, %s rad" % [String.num_scientific(worst_pose), String.num_scientific(worst_angle)])
	expect.call(worst_shown <= tolerance, "rotation: panel (force, required force, arms, weight, advantage, torques) = TS at every step", "max rel err %s" % String.num_scientific(worst_shown))
	expect.call(threshold_ok and balance <= 1e-9 and worst_rigid <= 2e-6,
		"rotation: the engine beam tilts exactly from the first press with F r_effort >= m g r_load (the torque balance; net torque 0 when lifted); the load stays on the rigid beam",
		"%s; rigid %s m" % [", ".join(thresholds), String.num_scientific(worst_rigid)])
	await _free(lab)


# --- 5. conditions ----------------------------------------------------------------------------

func check_conditions() -> void:
	var lab: Experiment = await _lab()
	var points: int = lab.graph.size()
	lab.set_control("mass", 10.0)
	var lighter := absf(float(lab.observations().required) - 10.0 * 9.81 * 2.0 / 2.1) < 1e-9
	lab.set_control("effort", "far")
	var far := absf(float(lab.observations().effort_arm) - 3.15) < 1e-12 and absf(float(lab.observations().required) - 10.0 * 9.81 * 2.0 / 3.15) < 1e-9
	var series: Dictionary = lab.graph_series()
	var stepped: bool = lab.graph.size() == points + 2 and series.required.size() == points + 2 and series.required[-1].x == series.required[-2].x
	lab.set_control("effort", "elbow")
	lab.set_control("mass", 99.0)
	lab.set_control("nope", 1.0)
	expect.call(lighter and far and stepped and lab.effort_id == "far" and lab.model.mass == 20.0,
		"rotation: mass and the effort point change the required force at once and add a graph point at the same time (a step); unknown ids are ignored, the mass stays within 1-20 kg", "")
	var labels_ok := true
	var ids := []
	var shown: Dictionary = lab.observations()
	for item in lab.definition.observations:
		labels_ok = labels_ok and not str(item.label).contains("시뮬레이션")
		ids.append(item.id)
	expect.call(labels_ok and ids.all(func(id): return shown.has(id)) and ids.size() == shown.size(),
		"rotation: the panel shows only formula-model values (no 'simulation' reading of the posed engine bodies)", "%d values" % ids.size())
	await _free(lab)


# --- 6. art -----------------------------------------------------------------------------------

func check_art() -> void:
	var lab: Experiment = await _lab()
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append("%s:%s" % [node.name, node.get_class()])
	bodies.sort()
	var kinematic := true
	for body in [lab.beam, lab.load_body]:
		kinematic = kinematic and body.collision_mask == 0 and body.freeze and body.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC
	expect.call(bodies == ["Beam:RigidBody3D", "Floor:StaticBody3D", "Fulcrum:StaticBody3D", "Handle:StaticBody3D", "Load:RigidBody3D"] and kinematic,
		"rotation art adds no collision objects; the beam and the load are kinematic and touch nothing (the formula moves them)", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.set_cells(0)
		await tree.physics_frame
		lab.set_cells(45)
		for i in 20:
			await tree.physics_frame
		runs.append({"load": lab.load_body.global_transform, "obs": str(lab.observations())})
	lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(runs[0].load.origin.distance_to(runs[1].load.origin) < 1e-6 and runs[0].load.basis.is_equal_approx(runs[1].load.basis) and runs[0].obs == runs[1].obs,
		"rotation: same lever and panel with and without the reactions", str(runs[0].load.origin))
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 16, "rotation: at most 16 drawn 3D nodes (art budget)", "%d" % draw_nodes)
	lab._show()
	var rod_end: Vector3 = lab.props.rod.global_transform * Vector3(0.0, -1.0, 0.0)
	var effort := Vector3(lab.model.beam_x(lab.model.effort_x(), lab.BEAM_THICK * 0.5), lab.model.beam_y(lab.model.effort_x(), lab.BEAM_THICK * 0.5), 0.0)
	expect.call(rod_end.distance_to(effort) < 1e-4 and lab.status() == "lifted",
		"rotation: the handle rod reaches the effort point on the (lifted) beam", "gap %s m" % String.num_scientific(rod_end.distance_to(effort)))
	await _free(lab)


# --- 7-8. input path on a fresh screen --------------------------------------------------------

func check_input_path() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var handle: StaticBody3D = lab.handle
	var waiting: Dictionary = lab.observations()
	var rest: Vector3 = handle.global_position
	# Press 0.9 m (45 cells, 225 N >= 186.86 N): the beam lifts while the finger holds it there.
	_swipe(screen, _at(screen, rest), _at(screen, rest + Vector3(0.0, -0.9, 0.0)), 12)
	for i in 3:
		await tree.physics_frame
	var held: bool = m.mode == "drag" and m.active_id == "handle"
	var cells: int = lab.model.cells
	var lifted: bool = lab.status() == "lifted" and absf(lab.driver.engine_angle() + 0.18) < 1e-6
	var shown: Dictionary = lab.observations()
	var clock: int = lab.clock_steps
	for i in 12:
		await tree.physics_frame
	var clock_runs: bool = lab.clock_steps == clock + 12 and lab.graph.size() >= 3
	_touch(screen, _at(screen, rest + Vector3(0.0, -0.9, 0.0)), false)
	await tree.physics_frame
	await tree.physics_frame
	var level: bool = lab.status() == "ready" and absf(lab.driver.engine_angle()) < 1e-6 and lab.model.cells == 0 and handle.global_position.distance_to(rest) < 1e-5
	var still: int = lab.clock_steps
	await tree.physics_frame
	expect.call(waiting.state == "힘점을 골라 빨간 손잡이를 아래로 눌러 보세요" and held and cells == 45 and lifted
		and absf(float(shown.applied) - float(shown.required)) < 1e-12 and absf(float(shown.net_torque)) < 1e-9 and clock_runs and level and lab.clock_steps == still,
		"rotation (fresh screen): pressing the handle 0.9 m down (225 N) lifts the beam at the required force; the graph clock runs only while held; letting go puts it back level",
		"cells %d, F %.2f N, held %s, lifted %s, clock %s, level %s (%s, %s, %s, %s), still %s, waiting %s" % [cells, shown.applied, held, lifted, clock_runs, level, lab.status(), lab.driver.engine_angle(), lab.model.cells, handle.global_position.distance_to(rest), lab.clock_steps == still, waiting.state])
	# Drag the load right (0.25 m grid) and the fulcrum left; the fulcrum cannot pass the load + 0.5 m.
	var load_body: RigidBody3D = lab.load_body
	var picked := []
	_swipe(screen, _at(screen, load_body.global_position), _at(screen, load_body.global_position + Vector3(1.07, 0.0, 0.0)))
	picked.append(m.active_id)
	_touch(screen, _at(screen, load_body.global_position), false)
	await tree.process_frame
	var load_moved: bool = lab.model.load_x == -1.5 and absf(float(lab.observations().load_arm) - 1.0) < 1e-12
	# The stand is picked on its front face below the beam (where a finger sees it).
	var stand: StaticBody3D = lab.stand
	var grip := Vector3(0.0, -0.2, 0.3)
	_swipe(screen, _at(screen, stand.global_position + grip), _at(screen, stand.global_position + grip + Vector3(-0.27, 0.0, 0.0)))
	picked.append(m.active_id)
	_touch(screen, _at(screen, stand.global_position + grip), false)
	await tree.process_frame
	var fulcrum_moved: bool = lab.model.pivot_x == -0.75 and absf(float(lab.observations().effort_arm) - 0.6 * 3.75) < 1e-12
	# -1.25 m is inside the fulcrum's range but within 0.5 m of the load (-1.5 m): not allowed.
	var too_close := stand.global_position + grip + Vector3(-0.5, 0.0, 0.0)
	_swipe(screen, _at(screen, stand.global_position + grip), _at(screen, too_close))
	picked.append(m.active_id)
	var refused: bool = not m.valid and is_equal_approx(m.target.x, -1.25)
	_touch(screen, _at(screen, too_close), false)
	await tree.process_frame
	var blocked: bool = refused and lab.model.pivot_x == -0.75 and stand.global_position.x == -0.75
	expect.call(load_moved and fulcrum_moved and blocked and picked == ["load", "fulcrum", "fulcrum"] and lab.placements().size() == 2,
		"rotation: dragging the load and the fulcrum moves them on the 0.25 m grid (the arms follow); the fulcrum cannot pass within 0.5 m of the load",
		"load %.2f, fulcrum %.2f, picked %s" % [lab.model.load_x, lab.model.pivot_x, str(picked)])
	await _close(screen)


# --- 9. demo ----------------------------------------------------------------------------------

func check_demo() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	screen.manipulator.start_demo(0.2)
	var lifts := 0
	var was := false
	var forces := {}
	for i in 8 * STEP_HZ:
		await tree.physics_frame
		var now: bool = lab.status() == "lifted"
		if now and not was:
			lifts += 1
		was = now
		if lab.holding == "handle":
			forces[lab.model.cells] = true
	screen.manipulator.start_demo(0.0)
	expect.call(lifts >= 1 and forces.size() >= 10, "rotation: the measurement demo (--auto-drag) presses the handle (lifting at full press) and lets go", "%d lifts, %d forces" % [lifts, forces.size()])
	await _close(screen)
