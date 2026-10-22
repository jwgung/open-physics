## Headless checks of the pulley lab (Phase 1 Task 4e), run by run_tests.gd. Expected values are the
## TS-core vectors in tests/pulley_lab_vectors.json (tools/pulley-lab-vectors.test.ts: the web's
## PulleyAdvantageChallenge, strokes of 5 cm cells, the 2.4 m top; mechanics.ts work and energy).
## Physics first: the engine load is checked step by step, not only the panel.
## 1. definition: valid, listed, shared texts and app tip; the defaults = the TS start case (one
##    strand, 20 kg); the 5 cm grid, the top, n per option.
## 2. model = TS (no engine): required force, rope per metre, and at every sample the pulled rope,
##    the lift, the stroke limit and the work / energy (5 cases, rel 1e-9).
## 3. engine = TS: the lab through its own fixed steps, one cell per step; the engine load = TS at
##    every sample, panel = TS.
## 4. physics from the engine bodies: the engine load rises 1/n of the rope the grip pulled (the
##    handle's travel through the input path), the rope length (n strands + pull strand + coiled
##    rope) stays the same, and the hand's work F d equals m g h of the engine load.
## 5. conditions: strands start the pull again, mass keeps the lift; unknown ids are ignored; the
##    panel holds only formula values.
## 6. art: visual only, draw-node budget, the strands reach from the fixed block to the hook.
## 7-8. the real input path on a fresh screen: hand-over-hand strokes, the ratchet, a cancelled pull.
## 9. the measurement demo (--auto-drag) pulls the grip and starts again.
extends RefCounted

const VECTORS_PATH := "res://tests/pulley_lab_vectors.json"
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
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find("pulley"))
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


func _strands_id(n: int) -> String:
	return {1: "one", 2: "two", 4: "four"}.get(n, "?")


func _model_for(c: Dictionary) -> PulleyLabModel:
	var m := PulleyLabModel.new()
	m.g = vectors.g
	m.max_lift = vectors.max_lift
	m.strands = int(c.strands)
	m.mass = c.mass
	return m


func _open() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(720, 1560)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("pulley"))
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


func _drag(screen: Control, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	screen.view._gui_input(event)


## Rope length from the bodies: n strands (fixed block -> hook), the pull strand (guide -> grip top)
## and the coiled rope of earlier strokes.
func _rope_length(lab: Experiment) -> float:
	var hook: float = lab.load_body.global_position.y + lab.HOOK_UP
	var grip_top: float = lab.handle.global_position.y + lab.HANDLE_SIZE.y * 0.5
	return lab.model.strands * (lab.TOP_Y - hook) + (lab.GUIDE.y - grip_top) + lab.model.cells_before / float(PulleyLabModel.CELLS_PER_M)


# --- 1. definition ----------------------------------------------------------------------------

func check_definition() -> void:
	var definition := ExperimentRegistry.find("pulley")
	var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	var shared: Dictionary = ExperimentRegistry.shared_labs().get("pulley", {})
	expect.call(problems.is_empty() and listed.has("pulley") and definition.get("title") == shared.get("title")
		and definition.get("tip", "") == shared.get("app", {}).get("tip", "") and definition.tip.contains("1/n"),
		"pulley: definition valid, listed, texts and the app tip from the shared content", ", ".join(problems))
	var start := _case("one")
	var defaults := {}
	var ns := []
	for control in definition.controls:
		defaults[control.id] = control.default
		if control.id == "strands":
			for option in control.options:
				ns.append(int(option.n))
	var consts: Dictionary = (load(definition.scene) as GDScript).get_script_constant_map()
	var snap: float = Manipulator.parse_rules(definition).handle.snap
	expect.call(defaults.strands == _strands_id(int(start.strands)) and float(defaults.mass) == float(start.mass) and ns == [1, 2, 4]
		and float(consts.MAX_LIFT) == float(vectors.max_lift) and PulleyLabModel.CELLS_PER_M == int(vectors.cells_per_m) and snap * PulleyLabModel.CELLS_PER_M == 1.0,
		"pulley: the start = the TS start case (1 strand, the web's 20 kg); 1 / 2 / 4 strands, 5 cm cells, 2.4 m top", "")


# --- 2. model = TS ----------------------------------------------------------------------------

func check_model_cases() -> void:
	var worst := 0.0
	var count := 0
	for c in vectors.cases:
		var m := _model_for(c)
		worst = maxf(worst, maxf(_err(m.required(), c.required), maxf(_err(m.pull_per_metre(), c.pull_per_metre), _err(m.weight(), c.weight))))
		var stroke := -1
		for s in c.samples:
			if int(s.stroke) != stroke:
				m.let_go()
				stroke = int(s.stroke)
				if m.stroke_limit() != int(s.limit):
					worst = INF
			m.stroke_cells = int(s.cells)
			count += 1
			for pair in [[m.pulled(), s.pulled], [m.lift(), s.lift], [m.work_in(), s.work_in], [m.work_out(), s.work_out]]:
				worst = maxf(worst, _err(pair[0], pair[1]))
	expect.call(worst <= tolerance, "pulley model: required force, rope per metre, and every sample's pulled rope, lift, stroke limit, work and energy = TS",
		"%d samples, max rel err %s" % [count, String.num_scientific(worst)])


# --- 3. engine = TS ---------------------------------------------------------------------------

func check_engine_cases() -> void:
	var lab: Experiment = await _lab()
	var worst := 0.0
	var worst_shown := 0.0
	for c in vectors.cases:
		lab.set_control("strands", _strands_id(int(c.strands)))
		lab.set_control("mass", float(c.mass))
		var stroke := -1
		for s in c.samples:
			if int(s.stroke) != stroke:
				lab.let_go()
				stroke = int(s.stroke)
			lab.set_stroke(int(s.cells))
			await tree.physics_frame
			worst = maxf(worst, absf(lab.driver.engine_lift() - float(s.lift)))
			var shown: Dictionary = lab.observations()
			for pair in [[shown.pulled, s.pulled], [shown.lift, s.lift], [shown.work_in, s.work_in], [shown.work_out, s.work_out],
					[shown.required, c.required], [shown.per_metre, c.pull_per_metre], [shown.weight, c.weight], [shown.strands, c.strands]]:
				worst_shown = maxf(worst_shown, _err(pair[0], pair[1]))
			if float(s.pulled) > 0.0:
				worst_shown = maxf(worst_shown, _err(shown.applied, c.required))
		lab.let_go()
	expect.call(worst <= ENGINE_TOLERANCE and lab.driver.worst_position <= ENGINE_TOLERANCE,
		"pulley: engine load lift = TS at every sample (5 cases, hand-over-hand strokes to the top)", "max %s m" % String.num_scientific(worst))
	expect.call(worst_shown <= tolerance, "pulley: panel (pulled rope, lift, work, energy, forces, rope per metre) = TS at every sample", "max rel err %s" % String.num_scientific(worst_shown))
	await _free(lab)


# --- 5. conditions ----------------------------------------------------------------------------

func check_conditions() -> void:
	var lab: Experiment = await _lab()
	lab.set_stroke(30)
	lab.let_go()
	await tree.physics_frame
	var lifted: bool = absf(lab.driver.engine_lift() - 1.5) < 1e-5
	lab.set_control("mass", 8.0)
	await tree.physics_frame
	var kept: bool = absf(lab.driver.engine_lift() - 1.5) < 1e-5 and absf(float(lab.observations().required) - 8.0 * 9.81) < 1e-9
	lab.set_control("strands", "four")
	await tree.physics_frame
	var restarted: bool = absf(lab.driver.engine_lift()) < 1e-6 and lab.model.pulled() == 0.0 and absf(float(lab.observations().required) - 8.0 * 9.81 / 4.0) < 1e-12
	var points: int = lab.graph.size()
	lab.set_control("strands", "six")
	lab.set_control("mass", 0.0)
	lab.set_control("nope", 1.0)
	expect.call(lifted and kept and restarted and lab.strands_id == "four" and lab.model.mass == 1.0 and lab.graph.size() == points + 1,
		"pulley: changing the strands lowers the load and starts the pull again (the web's), the mass keeps the lift; unknown ids are ignored, the mass stays within 1-20 kg", "")
	var labels_ok := true
	var ids := []
	var shown: Dictionary = lab.observations()
	for item in lab.definition.observations:
		labels_ok = labels_ok and not str(item.label).contains("시뮬레이션")
		ids.append(item.id)
	expect.call(labels_ok and ids.all(func(id): return shown.has(id)) and ids.size() == shown.size(),
		"pulley: the panel shows only formula-model values (no 'simulation' reading of the posed engine load)", "%d values" % ids.size())
	await _free(lab)


# --- 6. art -----------------------------------------------------------------------------------

func check_art() -> void:
	var lab: Experiment = await _lab()
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append("%s:%s" % [node.name, node.get_class()])
	bodies.sort()
	var load_body: RigidBody3D = lab.load_body
	expect.call(bodies == ["Floor:StaticBody3D", "Handle:StaticBody3D", "Load:RigidBody3D"] and load_body.collision_mask == 0 and load_body.freeze
		and load_body.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC,
		"pulley art adds no collision objects; the load is kinematic and touches nothing (the formula moves it)", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.run_action("reset")
		for k in 30:
			lab.set_stroke(k)
			await tree.physics_frame
		runs.append({"y": lab.load_body.global_position.y, "obs": str(lab.observations())})
	lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(absf(runs[0].y - runs[1].y) < 1e-6 and runs[0].obs == runs[1].obs, "pulley: same lift and panel with and without the reactions", "%.4f m" % runs[0].y)
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 16, "pulley: at most 16 drawn 3D nodes (art budget)", "%d" % draw_nodes)
	var worst := 0.0
	for n in [1, 2, 4]:
		lab.set_control("strands", _strands_id(n))
		lab.set_stroke(12 * n)
		await tree.physics_frame
		lab._show()
		# Every strand of the strands mesh ends at the hook: its lowest vertex, through the node's scale.
		var strands: MeshInstance3D = lab.props.strands
		var lowest := INF
		var xs: Array[float] = []
		for v in strands.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			lowest = minf(lowest, (strands.global_transform * v).y)
			xs.append(v.x)
		worst = maxf(worst, absf(lowest - (lab.load_body.global_position.y + lab.HOOK_UP)))
		# n strands: the vertices fall in n groups along x (strands 0.26 m apart, 0.03 m thick).
		xs.sort()
		var groups := 1
		for k in range(1, xs.size()):
			if xs[k] - xs[k - 1] > 0.1:
				groups += 1
		worst = maxf(worst, absf(float(groups - n)))
	expect.call(worst < 1e-4, "pulley: n strands are drawn from the fixed block down to the moving hook for n = 1, 2, 4", "gap %s m" % String.num_scientific(worst))
	await _free(lab)


# --- 7-8. input path on a fresh screen --------------------------------------------------------

func check_input_path() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var handle: StaticBody3D = lab.handle
	var waiting: Dictionary = lab.observations()
	lab.set_control("strands", "two")
	var top: Vector3 = handle.global_position
	var rope0 := _rope_length(lab)
	# Stroke 1: pull the grip 1.0 m down (20 cells): the engine load rises 0.5 m while the hand holds it.
	var travel := 0.0
	var worst_rope := 0.0
	_touch(screen, _at(screen, top), true)
	for i in range(1, 11):
		_drag(screen, _at(screen, top + Vector3(0.0, -0.1 * i, 0.0)))
		await tree.physics_frame
		await tree.physics_frame
		worst_rope = maxf(worst_rope, absf(_rope_length(lab) - rope0))
	var held: bool = m.mode == "drag" and m.active_id == "handle" and lab.status() == "pulling"
	var pull_shown: float = lab.observations().applied
	var grip_low: float = handle.global_position.y
	_touch(screen, _at(screen, top + Vector3(0.0, -1.0, 0.0)), false)
	travel += top.y - grip_low
	await tree.physics_frame
	await tree.physics_frame
	var ratchet: bool = lab.status() == "held" and absf(lab.driver.engine_lift() - 0.5) < 1e-5 and handle.global_position.distance_to(top) < 1e-5 and float(lab.observations().applied) == 0.0
	worst_rope = maxf(worst_rope, absf(_rope_length(lab) - rope0))
	# Stroke 2: another 0.6 m.
	_touch(screen, _at(screen, top), true)
	for i in range(1, 7):
		_drag(screen, _at(screen, top + Vector3(0.0, -0.1 * i, 0.0)))
		await tree.physics_frame
		await tree.physics_frame
		worst_rope = maxf(worst_rope, absf(_rope_length(lab) - rope0))
	grip_low = handle.global_position.y
	_touch(screen, _at(screen, top + Vector3(0.0, -0.6, 0.0)), false)
	travel += top.y - grip_low
	await tree.physics_frame
	await tree.physics_frame
	var lift: float = lab.driver.engine_lift()
	var shown: Dictionary = lab.observations()
	expect.call(waiting.state == "빨간 손잡이를 아래로 당겨 짐을 올려요" and held and absf(pull_shown - 20.0 * 9.81 / 2.0) < 1e-9 and ratchet
		and absf(travel - 1.6) < 1e-5 and absf(lift * 2.0 - travel) < 1e-4 and absf(float(shown.pulled) - 1.6) < 1e-12,
		"pulley (fresh screen, 2 strands): two strokes of the grip (1.0 m + 0.6 m) lift the engine load 0.8 m = 1/2 of the rope; the ratchet holds it between strokes and the grip goes back up",
		"travel %.4f m, lift %.4f m, held %s, ratchet %s" % [travel, lift, held, ratchet])
	var energy_ok: bool = absf(float(shown.work_in) - 20.0 * 9.81 * lift) < 1e-3 and absf(float(shown.work_in) - float(shown.work_out)) < 1e-9
	expect.call(worst_rope <= 1e-4 and energy_ok,
		"pulley: the rope length (2 strands + pull strand + coiled rope) stays the same through the strokes; the hand's work F d = m g h of the engine load",
		"rope change %s m, W %.3f J" % [String.num_scientific(worst_rope), shown.work_in])
	# A cancelled pull (a second finger) does not count: the grip and the load go back.
	_touch(screen, _at(screen, top), true)
	_drag(screen, _at(screen, top + Vector3(0.0, -0.4, 0.0)))
	await tree.physics_frame
	await tree.physics_frame
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.position = _at(screen, top) + Vector2(80, 0)
	second.pressed = true
	screen.view._gui_input(second)
	second.pressed = false
	screen.view._gui_input(second)
	_touch(screen, _at(screen, top + Vector3(0.0, -0.4, 0.0)), false)
	await tree.physics_frame
	await tree.physics_frame
	expect.call(absf(lab.driver.engine_lift() - 0.8) < 1e-5 and lab.model.pulled() == 1.6 and handle.global_position.distance_to(top) < 1e-5,
		"pulley: a cancelled pull (second finger) does not count: the grip and the load go back", "lift %.4f m" % lab.driver.engine_lift())
	await _close(screen)


# --- 9. demo ----------------------------------------------------------------------------------

func check_demo() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	screen.manipulator.start_demo(0.2)
	var strokes := 0
	var was := false
	var lifts := {}
	for i in 8 * STEP_HZ:
		await tree.physics_frame
		if lab.holding and not was:
			strokes += 1
		was = lab.holding
		lifts[snappedf(lab.model.lift(), 0.05)] = true
	screen.manipulator.start_demo(0.0)
	expect.call(strokes >= 2 and lifts.size() >= 10, "pulley: the measurement demo (--auto-drag) pulls the grip and starts again", "%d strokes, %d lifts" % [strokes, lifts.size()])
	await _close(screen)
