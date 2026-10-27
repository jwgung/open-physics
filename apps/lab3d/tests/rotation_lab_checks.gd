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
## 11. second review: a restored layout (fulcrum 1.5, load 1.0) is the same after a screen rebuild, the
##    lift / lowering reactions also follow hand changes, the hand-held load is not measured as an engine
##    deviation, a NaN mass mid-press changes nothing, the press line is reused.
## 10. review fixes: every condition can be lifted (the handle's scale fits the required force), the
##    rolling graph stays bounded with a stopped clock, a NaN / infinite mass is refused, the markers
##    follow every point, the engine bodies are only moved when the pose changes.
extends RefCounted

const VECTORS_PATH := "res://tests/rotation_lab_vectors.json"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60
const ENGINE_TOLERANCE := 1e-4
const REACH_TEST := 0.9            # m of press that lifts the default case

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
	check_liftable_everywhere()
	await check_liftable_on_the_lab()
	check_rolling_graph()
	await check_review_fixes()
	await check_review_fixes_2()


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
	host.size = Vector2(1560, 720)
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
		and int(roundf(float(consts.REACH) / snap)) == 50 and int(consts.MAX_CELLS) == 50
		and LeverLabModel.LIFT_ANGLE == PhysicsLaws.LEVER_LIFT_ANGLE and LeverModelDriver.LIFT_ANGLE == PhysicsLaws.LEVER_LIFT_ANGLE,
		"rotation: the start = the TS start case (20 kg, the middle of the web's 3 points); lift angle 0.18 rad = the web's (one source); the handle = 5 N per 2 cm to start with", "")


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
	lab.auto_force_step = false   # the TS vectors press with the web-like 5 N per cell
	lab.model.force_step = LeverLabModel.FORCE_STEP
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
	lab.clock_steps = 60   # the clock is running: the changes below are new points
	lab._add_graph_point()
	var points: int = lab.graph.size()
	lab.set_control("mass", 10.0)
	var lighter := absf(float(lab.observations().required) - 10.0 * 9.81 * 2.0 / 2.1) < 1e-9
	lab.set_control("effort", "far")
	var far := absf(float(lab.observations().effort_arm) - 3.15) < 1e-12 and absf(float(lab.observations().required) - 10.0 * 9.81 * 2.0 / 3.15) < 1e-9
	var series: Dictionary = lab.graph_series()
	# Two changes at one time keep the value before and after (a vertical step), the second overwrites the first.
	var stepped: bool = lab.graph.size() == points + 1 and series.required.size() == points + 1 and series.required[-1].x == series.required[-2].x \
		and absf(series.required[-1].y - 10.0 * 9.81 * 2.0 / 3.15) < 1e-3
	lab.set_control("effort", "elbow")
	lab.set_control("mass", 99.0)
	lab.set_control("nope", 1.0)
	expect.call(lighter and far and stepped and lab.effort_id == "far" and lab.model.mass == 20.0,
		"rotation: mass and the effort point change the required force at once and add a graph point at the same time (a step); unknown ids are ignored, the mass stays within 1-20 kg",
		"%s %s %s %s (%d, %d)" % [lighter, far, stepped, lab.model.mass, lab.graph.size(), points])
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
	expect.call(draw_nodes <= 24, "rotation: at most 24 drawn 3D nodes (art budget: 16 + the bread cat's 7 + its stand, 2026-10-27)", "%d" % draw_nodes)
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
	# Hold it lifted for 13 s (past the 10 s graph window): the engine beam stays at the lift angle
	# every step and the graph window slides.
	var worst_hold := 0.0
	for i in 13 * STEP_HZ:
		await tree.physics_frame
		worst_hold = maxf(worst_hold, absf(lab.driver.engine_angle() + 0.18))
	var series: Dictionary = lab.graph_series()
	var slid: bool = series.applied.size() >= 95 and series.applied[0].x >= -1e-6 and absf(series.applied[-1].x - 10.0) < 0.2 and lab.clock_time() > 13.0
	var clock_runs: bool = lab.clock_steps == clock + 13 * STEP_HZ and slid and worst_hold <= 1e-6 and absf(series.applied[-1].y - float(shown.required)) < 1e-3
	_touch(screen, _at(screen, rest + Vector3(0.0, -0.9, 0.0)), false)
	await tree.physics_frame
	await tree.physics_frame
	var level: bool = lab.status() == "ready" and absf(lab.driver.engine_angle()) < 1e-6 and lab.model.cells == 0 and handle.global_position.distance_to(rest) < 1e-5
	var still: int = lab.clock_steps
	await tree.physics_frame
	expect.call(waiting.state == "힘점을 골라 빨간 손잡이를 아래로 눌러 보세요" and held and cells == 45 and lifted
		and absf(float(shown.applied) - float(shown.required)) < 1e-12 and absf(float(shown.net_torque)) < 1e-9 and clock_runs and level and lab.clock_steps == still,
		"rotation (fresh screen): pressing the handle 0.9 m down (225 N) lifts the beam at the required force and holds it there 13 s (graph window slides); the graph clock runs only while held; letting go puts it back level",
		"cells %d, F %.2f N, held %s, lifted %s, clock %s, level %s (%s, %s, %s, %s), still %s, waiting %s" % [cells, shown.applied, held, lifted, clock_runs, level, lab.status(), lab.driver.engine_angle(), lab.model.cells, handle.global_position.distance_to(rest), lab.clock_steps == still, waiting.state])
	# Since 2026-10-27 the handle is the lab's one drag: the load and the fulcrum are not picked up
	# (the grip point is the picture buttons' condition). Their places stay the lab's (a restored
	# placement): the 0.25 m grid, the arms follow, the fulcrum never within 0.5 m of the load.
	var load_body: RigidBody3D = lab.load_body
	var picked := []
	_swipe(screen, _at(screen, load_body.global_position), _at(screen, load_body.global_position + Vector3(1.07, 0.0, 0.0)))
	picked.append(m.active_id)
	_touch(screen, _at(screen, load_body.global_position), false)
	await tree.process_frame
	var stand: StaticBody3D = lab.stand
	var grip := Vector3(0.0, -0.2, 0.3)
	_swipe(screen, _at(screen, stand.global_position + grip), _at(screen, stand.global_position + grip + Vector3(-0.27, 0.0, 0.0)))
	picked.append(m.active_id)
	_touch(screen, _at(screen, stand.global_position + grip), false)
	await tree.process_frame
	var untouched: bool = lab.model.load_x == lab.DEFAULT_LOAD and lab.model.pivot_x == lab.DEFAULT_PIVOT and lab.placements().is_empty()
	lab.manipulation_placed("load", Transform3D(Basis(), load_body.global_position + Vector3(1.07, 0.0, 0.0)))
	var load_moved: bool = lab.model.load_x == -1.5 and absf(float(lab.observations().load_arm) - 1.0) < 1e-12
	lab.manipulation_placed("fulcrum", Transform3D(Basis(), stand.global_position + Vector3(-0.27, 0.0, 0.0)))
	var fulcrum_moved: bool = lab.model.pivot_x == -0.75 and absf(float(lab.observations().effort_arm) - 0.6 * 3.75) < 1e-12
	var blocked: bool = not lab.placement_allowed("fulcrum", Transform3D(Basis(), Vector3(-1.25, 0.0, 0.0)))
	expect.call(picked == ["", ""] and untouched and load_moved and fulcrum_moved and blocked and lab.placements().size() == 2,
		"rotation: a finger does not drag the load or the fulcrum; their places (a restored placement) keep the 0.25 m grid, the arms follow, the fulcrum stays 0.5 m from the load",
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


# --- 10. review fixes ---------------------------------------------------------------------------

## Every mass, effort point, fulcrum and load place the lab offers: the full press (50 cells) of the
## fitted scale reaches the required force, so the beam can always be lifted - and the scale is the
## smallest one that does.
func check_liftable_everywhere() -> void:
	var count := 0
	var unliftable := 0
	var not_smallest := 0
	var worst_required := 0.0
	var steps_used := {}
	var fractions := [0.35, 0.6, 0.9]
	var pivot := -1.5
	while pivot <= 1.5 + 1e-9:
		var load_x := -2.75
		while load_x <= pivot - 0.5 + 1e-9:
			for fraction in fractions:
				for mass in range(1, 21):
					var m := LeverLabModel.new()
					m.pivot_x = pivot
					m.load_x = load_x
					m.fraction = fraction
					m.mass = float(mass)
					m.fit_force_step(50)
					m.cells = 50
					count += 1
					worst_required = maxf(worst_required, m.required())
					steps_used[m.force_step] = true
					if not m.lifting() or m.max_hand_force(50) < m.required():
						unliftable += 1
					var index := LeverLabModel.FORCE_STEPS.find(m.force_step)
					if index > 0 and 50 * LeverLabModel.FORCE_STEPS[index - 1] >= m.required():
						not_smallest += 1
			load_x += 0.25
		pivot += 0.25
	expect.call(unliftable == 0 and not_smallest == 0 and count > 5000 and worst_required > 1500.0 and steps_used.size() == LeverLabModel.FORCE_STEPS.size(),
		"rotation: in every condition (mass 1-20 kg, 3 effort points, every fulcrum and load place) the full press lifts the load, on the smallest scale that can (5 / 10 / 20 / 50 N per 2 cm)",
		"%d conditions, %d unliftable, %d not smallest, max required %.0f N, scales %s" % [count, unliftable, not_smallest, worst_required, str(steps_used.keys())])


## The hardest condition on the real lab: 20 kg close to the fulcrum, the fulcrum far right, the load
## far left (1588 N): the press all the way down lifts the beam, the panel shows the scale and the
## force = the required force; an easy condition stays on the 5 N scale.
func check_liftable_on_the_lab() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	lab.set_control("mass", 20.0)
	lab.set_control("effort", "near")
	lab.set_layout(1.5, -2.75)
	var hard: Dictionary = lab.observations()
	# The handle is pressed all the way down (the press line's full 1.0 m) through the lab's own
	# manipulation calls: this far-right handle is outside the test screen's view.
	var rest: Vector3 = lab.handle.global_position
	lab.manipulation_started("handle")
	lab.handle.global_position = rest + Vector3(0.0, -lab.REACH, 0.0)
	for i in 3:
		await tree.physics_frame
	var shown: Dictionary = lab.observations()
	var lifted: bool = lab.status() == "lifted" and absf(lab.driver.engine_angle() + LeverLabModel.LIFT_ANGLE) < 1e-6 and lab.model.cells == 50
	var equal: bool = absf(float(shown.applied) - float(shown.required)) < 1e-9 and float(shown.required) > 1500.0
	lab.manipulation_placed("handle", lab.handle.global_transform)
	await tree.physics_frame
	lab.set_control("effort", "far")
	lab.set_control("mass", 5.0)
	lab.set_layout(-0.5, -2.5)
	var easy: Dictionary = lab.observations()
	expect.call(lifted and equal and float(hard.force_step) == 50.0 and float(easy.force_step) == 5.0 and lab.model.max_hand_force(50) >= lab.model.required(),
		"rotation: the hardest condition (20 kg, close, fulcrum 1.5 m, load -2.75 m: %.0f N) is lifted by pressing the handle all the way (50 N per 2 cm shown); an easy one stays on 5 N" % float(shown.required),
		"scale %s, easy %s, status %s" % [str(hard.force_step), str(easy.force_step), lab.status()])
	await _close(screen)


## RollingGraph with a stopped clock: repeated adds at one time keep two samples (before / after)
## and overwrite after that; the cap holds for any times; the window still slides.
func check_rolling_graph() -> void:
	var g := RollingGraph.new(["a", "b"] as Array[String], 10.0)
	g.add(0.0, [1.0, 2.0])
	for i in 5000:
		g.add(0.0, [float(i), 2.0 * i])
	var same_time: int = g.size()
	var last: Dictionary = g.series()
	var first_kept: bool = last.a[0].y == 1.0 and last.a[-1].y == 4999.0 and last.b[-1].y == 9998.0
	g.add(0.5, [7.0, 8.0])
	for i in 100:
		g.add(0.5, [9.0, 9.0])
	var then: int = g.size()
	var wide := RollingGraph.new(["a"] as Array[String], 1e9)
	for i in 5000:
		wide.add(i * 0.1, [float(i)])
	var slid := RollingGraph.new(["a"] as Array[String], 10.0)
	for i in 400:
		slid.add(i * 0.1, [float(i)])
	var series: Dictionary = slid.series()
	expect.call(same_time == 2 and first_kept and then == 4 and wide.size() == RollingGraph.MAX_SAMPLES and slid.size() == 101 and absf(series.a[-1].x - 10.0) < 1e-9 and series.a[0].x >= -1e-9,
		"rolling graph: a stopped clock keeps two samples per time (not 5000), the sample count is capped (%d), the window still slides" % RollingGraph.MAX_SAMPLES,
		"same time %d, then %d, capped %d, window %d" % [same_time, then, wide.size(), slid.size()])


func check_review_fixes() -> void:
	var lab: Experiment = await _lab()
	# A bad number changes nothing: NaN and infinity are refused, a big finite one is clamped.
	lab.set_control("mass", 10.0)
	lab.set_control("mass", NAN)
	var after_nan: float = lab.model.mass
	lab.set_control("mass", INF)
	var after_inf: float = lab.model.mass
	lab.set_control("mass", -INF)
	var after_minus_inf: float = lab.model.mass
	lab.set_control("mass", 1e30)
	var clamped: float = lab.model.mass
	expect.call(after_nan == 10.0 and after_inf == 10.0 and after_minus_inf == 10.0 and clamped == 20.0 and is_finite(float(lab.observations().required)),
		"rotation: a NaN or infinite mass is refused (the mass stays), a huge finite one is clamped to 20 kg", "%s %s %s %s" % [after_nan, after_inf, after_minus_inf, clamped])
	# The marker mesh is rebuilt when any of the three points (also the middle one) changes.
	var props: RotationProps = lab.props
	props.show_markers([-1.0, 0.0, 1.0] as Array[float], 0, 0.22, 0.6)
	var first_mesh: Mesh = props.markers.mesh
	props.show_markers([-1.0, 0.0, 1.0] as Array[float], 0, 0.22, 0.6)
	var same_mesh: bool = props.markers.mesh == first_mesh
	props.show_markers([-1.0, 0.5, 1.0] as Array[float], 0, 0.22, 0.6)
	var middle_mesh: bool = props.markers.mesh != first_mesh
	expect.call(same_mesh and middle_mesh, "rotation: the effort markers are rebuilt when only the middle point moved, kept when nothing changed", "")
	# The bodies are only moved when the pose changes.
	lab.set_cells(0)
	await tree.physics_frame
	var writes: int = lab.driver.pose_writes
	for i in 30:
		await tree.physics_frame
	var idle: bool = lab.driver.pose_writes == writes
	lab.set_cells(50)   # lifts: the angle changes once
	await tree.physics_frame
	await tree.physics_frame
	var lift_write: bool = lab.driver.pose_writes == writes + 1
	for i in 30:
		await tree.physics_frame
	var held: bool = lab.driver.pose_writes == writes + 1 and absf(lab.driver.engine_angle() + LeverLabModel.LIFT_ANGLE) < 1e-6
	lab.set_layout(-0.5, -2.0)   # a condition change poses again (forced)
	var moved: bool = lab.driver.pose_writes == writes + 2 and absf(lab.load_body.global_position.x - lab.model.beam_x(-2.0, lab.model.load_up)) < 1e-4
	expect.call(idle and lift_write and held and moved,
		"rotation: the driver moves the beam and the load only when the pose changes (none in 30 idle steps, one at the lift, none while held, one on a new condition)",
		"writes %d -> %d; idle %s lift %s held %s moved %s" % [writes, lab.driver.pose_writes, idle, lift_write, held, moved])
	await _free(lab)


# --- 11. second review ----------------------------------------------------------------------------

func check_review_fixes_2() -> void:
	# The saved layout is restored in the screen's order (placements() order), so the load is not
	# limited by the default fulcrum.
	var lab: Experiment = await _lab()
	lab.manipulation_placed("fulcrum", Transform3D(Basis(), Vector3(1.5, 0.0, 0.0)))
	lab.manipulation_placed("load", Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)))
	var saved: Dictionary = lab.placements()
	var pivot: float = lab.model.pivot_x
	var load_at: float = lab.model.load_x
	var torque: float = lab.model.load_torque()
	await _free(lab)
	var rebuilt: Experiment = await _lab()
	rebuilt.begin_batch()
	for id in saved:
		rebuilt.manipulation_placed(id, saved[id])
	rebuilt.end_batch()
	var restored: bool = pivot == 1.5 and load_at == 1.0 and rebuilt.model.pivot_x == 1.5 and rebuilt.model.load_x == 1.0 \
		and rebuilt.model.load_torque() == torque and rebuilt.placements().keys() == saved.keys()
	expect.call(restored, "rotation: a layout with the fulcrum at 1.5 m and the load at 1.0 m is the same after a screen rebuild (positions and torque)",
		"saved %s; pivot %s load %s torque %s -> %s" % [str(saved.keys()), rebuilt.model.pivot_x, rebuilt.model.load_x, torque, rebuilt.model.load_torque()])
	# Reactions follow the beam: pressing lifts (stretch), letting go by hand lowers it (settle),
	# although the hand changes only update the status quietly.
	var juice: ArtJuice = rebuilt.props.juice
	juice.process_mode = Node.PROCESS_MODE_DISABLED
	juice._squash_v = 0.0
	rebuilt.manipulation_started("handle")
	rebuilt.handle.global_position = rebuilt.handle_rest() + Vector3(0.0, -REACH_TEST, 0.0)
	for i in 5:
		await tree.physics_frame
	var stretched: float = juice._squash_v
	var lifted: bool = rebuilt.model.lifting()
	# The press line is built once for the manipulator and the lab.
	var line: Object = rebuilt.manipulation_surface("press")
	var reused: bool = line == rebuilt.manipulation_surface("press") and rebuilt._press == line
	# A NaN mass in the middle of the press changes nothing: no graph point, same numbers.
	var graph_size: int = rebuilt.graph.size()
	var mass: float = rebuilt.model.mass
	var required: float = rebuilt.model.required()
	rebuilt.set_control("mass", NAN)
	var nan_same: bool = rebuilt.model.mass == mass and rebuilt.model.required() == required and rebuilt.graph.size() == graph_size and rebuilt.model.lifting()
	juice._squash_v = 0.0
	rebuilt.manipulation_placed("handle", rebuilt.handle.global_transform)
	var lowered: float = juice._squash_v
	expect.call(lifted and stretched > 0.0 and lowered < 0.0 and reused and nan_same,
		"rotation: lifting stretches and a hand letting go settles the beam (also on the quiet status path); the press line is built once; a NaN mass mid-press changes nothing",
		"lifted %s, stretch %s, lower %s, reused %s, nan same %s" % [lifted, stretched, lowered, reused, nan_same])
	# Holding the load by hand is not an engine deviation: the frozen load moves with the finger.
	rebuilt.driver.reset()
	rebuilt.manipulation_started("load")
	rebuilt.load_body.global_position += Vector3(0.7, 0.4, 0.0)
	for i in 10:
		await tree.physics_frame
	var held_worst: float = rebuilt.driver.worst_position
	rebuilt.manipulation_cancelled("load")
	for i in 10:
		await tree.physics_frame
	expect.call(held_worst <= ENGINE_TOLERANCE and rebuilt.driver.worst_position <= ENGINE_TOLERANCE,
		"rotation: steps while the finger holds the load are not measured as engine deviation (worst position %s m)" % String.num_scientific(held_worst), "")
	await _free(rebuilt)

