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
## 4. physics from the engine bodies: the engine load rises 1/n of the rope pulled (the rope end's
##    travel through the input path), the rope length (n strands + pull strand + coiled rope) stays
##    the same, and the hand's work F d equals m g h of the engine load.
## 5. conditions: strands start the pull again, mass keeps the lift; unknown ids are ignored; the
##    panel holds only formula values.
## 6. art: visual only, draw-node budget, the strands reach from the fixed block to the hook.
## 7-8. the real input path on a fresh screen (2026-10-28 press and hold): the hand's force ramps
##    PULL_RATE N/s (the gauge), the rope moves on the first step it reaches F = m g / n, ROPE_SPEED
##    m/s on the 5 cm grid; hand-over-hand strokes, the ratchet, a cancelled hold.
## 9. the measurement demo (--auto-drag) holds the rope and starts again.
## 11. second review: lift-off reaction while the rope is held (quiet status), a batch restore does not
##    reset at once, a NaN mass changes nothing mid-pull, the coiled rope grows while pulling, the cell
##    size follows the definition's snap.
## 10. review fixes: changing the strands while the rope is held starts the run again (load down, no
##    jump, clock and graph restarted), the engine load is only moved when the lift changes.
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
	await check_restart_while_held()
	await check_review_fixes_2()


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
	host.size = Vector2(1560, 720)
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


## Rope length from the bodies: n strands (fixed block -> hook), the pull strand (guide -> the rope
## end's knot top) and the coiled rope of earlier strokes.
func _rope_length(lab: Experiment) -> float:
	var hook: float = lab.load_body.global_position.y + lab.HOOK_UP
	var grip_top: float = lab.rope_end.global_position.y + PulleyProps.KNOT_RADIUS
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
	var rule: Dictionary = Manipulator.parse_rules(definition).rope
	expect.call(defaults.strands == _strands_id(int(start.strands)) and float(defaults.mass) == float(start.mass) and ns == [1, 2, 4]
		and float(consts.MAX_LIFT) == float(vectors.max_lift) and PulleyLabModel.CELLS_PER_M == int(vectors.cells_per_m) and rule.snap * PulleyLabModel.CELLS_PER_M == 1.0
		and rule.hold and float(consts.PULL_RATE) == 65.0 and float(consts.PULL_MAX) == 250.0 and float(consts.ROPE_SPEED) == 1.0,
		"pulley: the start = the TS start case (1 strand, the web's 20 kg); 1 / 2 / 4 strands, 5 cm cells, 2.4 m top; the rope end is pressed and held (65 N/s, at most 250 N, the rope 1 m/s)", "")


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
	expect.call(bodies == ["Floor:StaticBody3D", "Load:RigidBody3D", "RopeEnd:StaticBody3D"] and load_body.collision_mask == 0 and load_body.freeze
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
	expect.call(draw_nodes <= 26, "pulley: at most 26 drawn 3D nodes (art budget: 16 + the bread cat's 7, 2026-10-27; + the shelf, the chest's bars and the piece's 2, 2026-10-29)", "%d" % draw_nodes)
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

## Holds the rope end until the stroke has pulled `cells`, then lets go; `check` gets the hold's step
## when the rope started to move (the hand at F), the applied force shown before and then, the gauge.
func _stroke(screen: Control, lab: Experiment, cells: int, check: Dictionary) -> void:
	var press := _at(screen, lab.rope_end.global_position)
	_touch(screen, press, true)
	check.held = screen.manipulator.mode == "hold" and screen.manipulator.active_id == "rope" and lab.status() == "pulling"
	check.moved_at = -1
	check.before = -1.0
	for i in 8 * STEP_HZ:
		await tree.physics_frame
		check.worst_rope = maxf(check.worst_rope, absf(_rope_length(lab) - check.rope0))
		if check.moved_at < 0 and lab._moving_steps > 0:
			check.moved_at = lab.hand.steps
			check.shown = float(lab.observations().applied)
		elif check.moved_at < 0:
			check.before = float(lab.observations().applied)
			check.gauge = lab.gauge != null and absf(lab.gauge.fraction - lab.model.hand / lab.PULL_MAX) < 1e-6
		if lab.model.stroke_cells >= cells:
			break
	_touch(screen, press, false)
	await tree.physics_frame
	await tree.physics_frame


func check_input_path() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var waiting: Dictionary = lab.observations()
	lab.set_control("strands", "two")
	var top: Vector3 = lab.rope_end.global_position
	var check := {"rope0": _rope_length(lab), "worst_rope": 0.0}
	var required: float = lab.model.required()   # 2 strands, 20 kg: 98.1 N
	# Stroke 1: hold until 1.0 m of rope (20 cells) came down: the engine load rises 0.5 m.
	await _stroke(screen, lab, 20, check)
	var want_step := ceili(required / lab.PULL_RATE * STEP_HZ - 1e-9)
	var ramp: bool = check.held and check.moved_at == want_step and check.before < required and check.before > 0.0 and absf(check.shown - required) < 1e-9 and check.gauge
	var ratchet: bool = lab.status() == "held" and absf(lab.driver.engine_lift() - 0.5) < 1e-5 and lab.rope_end.global_position.distance_to(top) < 1e-5 \
		and float(lab.observations().applied) == 0.0 and not lab.gauge.visible and m.mode == ""
	var series: Dictionary = lab.graph_series()
	var top_pull := 0.0
	for p in series.applied:
		top_pull = maxf(top_pull, p.y)
	var graph_ok: bool = series.applied.size() >= 10 and absf(top_pull - required) < 1e-3 and series.applied[1].y < required and series.applied[-1].y == 0.0
	# Stroke 2: another 0.6 m.
	await _stroke(screen, lab, 12, check)
	var lift: float = lab.driver.engine_lift()
	var shown: Dictionary = lab.observations()
	expect.call(waiting.state == "줄 끝을 꾹 눌러 짐을 올려요" and ramp and ratchet and graph_ok
		and absf(lift - 0.8) < 1e-5 and absf(float(shown.pulled) - 1.6) < 1e-12,
		"pulley (fresh screen, 2 strands): holding the rope end ramps the hand's force 65 N/s (gauge = force / 250 N, the load stays down below F); the rope moves on step %d (%.2f s) at F = %.1f N and two strokes (1.0 m + 0.6 m) lift the engine load 0.8 m = 1/2 of the rope; the ratchet holds it between strokes and the rope end goes back up" % [want_step, want_step / float(STEP_HZ), required],
		"held %s, moved at %d (want %d), before %.2f N, shown %.2f N, gauge %s, ratchet %s, graph %s, lift %.4f m" % [check.held, check.moved_at, want_step, check.before, check.get("shown", -1.0), check.get("gauge", false), ratchet, graph_ok, lift])
	var energy_ok: bool = absf(float(shown.work_in) - 20.0 * 9.81 * lift) < 1e-3 and absf(float(shown.work_in) - float(shown.work_out)) < 1e-9
	expect.call(check.worst_rope <= 1e-4 and energy_ok,
		"pulley: the rope length (2 strands + pull strand + coiled rope) stays the same through the strokes; the hand's work F d = m g h of the engine load",
		"rope change %s m, W %.3f J" % [String.num_scientific(check.worst_rope), shown.work_in])
	# A hold cancelled before the rope moved (a second finger after 0.5 s, 32.5 N < 98.1 N): nothing
	# was pulled, the force is 0 again.
	var press := _at(screen, lab.rope_end.global_position)
	_touch(screen, press, true)
	for i in 30:
		await tree.physics_frame
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.position = press + Vector2(80, 0)
	second.pressed = true
	screen.view._gui_input(second)
	second.pressed = false
	screen.view._gui_input(second)
	_touch(screen, press, false)
	await tree.physics_frame
	await tree.physics_frame
	expect.call(absf(lab.driver.engine_lift() - 0.8) < 1e-5 and lab.model.pulled() == 1.6 and lab.rope_end.global_position.distance_to(top) < 1e-5
		and not lab.holding and m.mode == "" and float(lab.observations().applied) == 0.0,
		"pulley: a hold cancelled before the force reached F (a second finger) pulls nothing; the force is 0 again", "lift %.4f m" % lab.driver.engine_lift())
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
	expect.call(strokes >= 2 and lifts.size() >= 4, "pulley: the measurement demo (--auto-drag) holds the rope (the load rises) and starts again", "%d strokes, %d lifts" % [strokes, lifts.size()])
	await _close(screen)


# --- 10. review fixes ---------------------------------------------------------------------------

## The strands change while the grip is still held (no cancel from the screen): the same restart as
## the reset button - the grip lets go (its stroke does not count), the load goes down and stays
## there (no jump to the old stroke), the clock and the graph start again. Idle steps do not move the
## engine load.
func check_restart_while_held() -> void:
	var lab: Experiment = await _lab()
	lab.set_control("mass", 4.0)   # 39.24 N: the rope moves after 0.6 s
	lab.hold_started("rope")
	for i in 120:
		await tree.physics_frame
	var running: bool = lab.holding and lab.clock_steps >= 90 and lab.graph.size() > 5 and lab.driver.engine_lift() > 0.5
	lab.set_control("strands", "two")
	var worst_lift := 0.0
	for i in 20:
		await tree.physics_frame
		worst_lift = maxf(worst_lift, absf(lab.driver.engine_lift()))
	var restarted: bool = not lab.holding and not lab.model.holding and lab.clock_steps == 0 and lab.graph.size() == 1 and lab.model.pulled() == 0.0 \
		and worst_lift <= 1e-6 and lab.rope_end.global_position.is_equal_approx(lab.end_top()) and lab.status() == "ground"
	lab.hold_ended("rope")   # the screen's cancel arrives later: harmless
	await tree.physics_frame
	var after: bool = lab.clock_steps == 0 and lab.graph.size() <= 2 and lab.model.pulled() == 0.0 and absf(lab.driver.engine_lift()) < 1e-6
	# The reset button does the same from a pull that is no longer held.
	lab.set_stroke(30)
	lab.let_go()
	await tree.physics_frame
	lab.run_action("reset")
	var reset: bool = lab.clock_steps == 0 and lab.graph.size() == 1 and absf(lab.driver.engine_lift()) < 1e-6
	var writes: int = lab.driver.pose_writes
	for i in 30:
		await tree.physics_frame
	var idle: bool = lab.driver.pose_writes == writes
	lab.set_stroke(10)
	await tree.physics_frame
	await tree.physics_frame
	var one_write: bool = lab.driver.pose_writes == writes + 1
	expect.call(running and restarted and after and reset and idle and one_write,
		"pulley: changing the strands while the rope is held restarts the run like the reset button (hold let go, load down without a jump, clock and graph start again); the engine load is only moved when the lift changes",
		"running %s, restarted %s, after %s, reset %s, idle %s, one write %s (worst lift %s)" % [running, restarted, after, reset, idle, one_write, str(worst_lift)])
	await _free(lab)


# --- 11. second review ----------------------------------------------------------------------------

func check_review_fixes_2() -> void:
	var lab: Experiment = await _lab()
	lab.props.juice.process_mode = Node.PROCESS_MODE_DISABLED   # the reactions' kicks stay readable
	lab.props.juice._squash_v = 0.0
	# Lift-off while the rope is held: the hold updates the status quietly (ground -> pulling), the
	# load leaving the ground still stretches it.
	lab.set_control("mass", 4.0)
	lab.props.juice._squash_v = 0.0
	lab.hold_started("rope")
	var kicked_early: float = lab.props.juice._squash_v
	for i in 90:   # 0.6 s to F, then 0.5 m of rope
		await tree.physics_frame
	var stretched: float = lab.props.juice._squash_v
	# The coiled rope grows while the rope is pulled (not only after the stroke), pulled() long.
	await tree.process_frame
	var pile_y: float = lab.props.pile.scale.y
	var pile_ok: bool = absf(pile_y - (0.04 + minf(lab.model.pulled(), 10.0) * 0.03)) < 1e-6 and lab.model.pulled() > 0.4
	# A NaN mass in the middle of the pull changes nothing: no restart, no graph point, same numbers.
	var graph_size: int = lab.graph.size()
	var mass: float = lab.model.mass
	var pulled: float = lab.model.pulled()
	lab.set_control("mass", NAN)
	lab.set_control("mass", INF)
	var nan_same: bool = lab.model.mass == mass and lab.graph.size() == graph_size and lab.model.pulled() == pulled and lab.holding
	expect.call(kicked_early == 0.0 and stretched > 0.0 and pile_ok and nan_same,
		"pulley: the load lifting off the ground stretches it also when the rope was held quietly; the coiled rope grows with the pull; a NaN / infinite mass mid-pull changes nothing",
		"kick %s then %s, pile %s (pulled %s), nan same %s" % [kicked_early, stretched, pile_y, pulled, nan_same])
	lab.hold_ended("rope")
	lab.run_action("reset")
	await tree.physics_frame
	# A restore batch: the strands set inside it do not reset the pull at once, end_batch does once.
	lab.set_stroke(20, false)
	lab.let_go()
	await tree.physics_frame
	var before: float = lab.model.pulled()
	lab.begin_batch()
	lab.set_control("strands", "two")
	await tree.physics_frame
	var kept: bool = before == 1.0 and lab.model.pulled() == 1.0 and lab.model.strands == 2
	lab.end_batch()
	await tree.physics_frame
	var reset_once: bool = lab.model.pulled() == 0.0 and absf(lab.driver.engine_lift()) < 1e-6 and lab.props.moving_block.mesh != null
	expect.call(kept and reset_once, "pulley: inside a restore batch a changed strand count does not reset the pull; end_batch restarts it once",
		"kept %s, reset once %s" % [kept, reset_once])
	await _free(lab)
	# The cell size is the definition's snap: a different snap changes the model with it.
	var definition: Dictionary = ExperimentRegistry.find("pulley").duplicate(true)
	definition.manipulation.objects[0].snap = 0.1
	var other := ExperimentRegistry.instantiate(definition)
	tree.root.add_child(other)
	await tree.process_frame
	var from_snap: bool = other.model.cells_per_m == 10 and other.model.stroke_limit() == 24
	var default_lab: Experiment = await _lab()
	var snap: float = Manipulator.parse_rules(default_lab.definition).rope.snap
	var same_source: bool = default_lab.model.cells_per_m == roundi(1.0 / snap) and default_lab.model.cells_per_m == int(vectors.cells_per_m)
	expect.call(from_snap and same_source, "pulley: the cell size comes from the definition's rope snap (0.05 -> 20 per metre, 0.1 -> 10)",
		"default %d, snap 0.1 -> %d" % [default_lab.model.cells_per_m, other.model.cells_per_m])
	await _free(other)
	await _free(default_lab)
