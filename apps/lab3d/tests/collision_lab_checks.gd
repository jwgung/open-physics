## Headless checks of the collision lab (Phase 1 Task 4c), run by run_tests.gd. Expected values are
## the TS-core vectors in tests/collision_lab_vectors.json (tools/collision-lab-vectors.test.ts: the
## web's PhysicsSimulation with the collision preset's damping and the rail's walls, 60 Hz).
## Physics first (the user's priority): the balls' engine motion is checked step by step, not only the
## numbers on the panel.
## 1. definition: valid, listed, texts from the shared content; materials' e = TS MATERIALS; the start
##    (1 kg / 2 kg rubber, 3.4 / -1.7 m/s, 8 m apart) = the TS "web start" case.
## 2. model = TS (no engine): positions, velocities and momenta at every sample step, the first
##    collision (step, velocities before / after, e, impulses, momentum and kinetic energy sums) and
##    the collision count, 7 cases (rel 1e-9).
## 3. engine = TS: the lab run through its own fixed steps; engine ball centres = TS at every sample
##    step (<= 1e-4 m); every step: engine centre = the model state it was posed on, engine step
##    velocity (displacement / dt) = model velocity (<= 1e-4 m/s); panel after the first collision =
##    TS (1e-9); momentum conserved, kinetic energy not gained; equal masses e = 1 exchange velocities;
##    e per material (0.88, 0.5, 0.72, 0.08, 0 below 1 m/s).
## 4. conditions: mass / material / velocity change the run and put the balls back; unknown ids ignored.
## 5. art: visual only (bodies, the same run without reactions), draw-node budget.
## 6. a freshly opened screen: "출발" gives the first collision on the TS step with the TS outcome, the
##    engine balls on the TS positions; the graph shows both momenta (signed).
## 7. the real input path: dragging ball A (0.5 m grid on its half) and its arrow knob (0.5 m/s grid,
##    preview while held, slider follows), then a run = formula.
## 8. the measurement demo (--auto-drag) drags ball A and starts runs that collide.
extends RefCounted

const VECTORS_PATH := "res://tests/collision_lab_vectors.json"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60
const ENGINE_TOLERANCE := 1e-4   # m and m/s: engine balls against the formula

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
	check_definition()
	check_model_cases()
	await check_engine_cases()
	await check_conditions()
	await check_art()
	await check_first_collision_screen()
	await check_input_path()
	await check_demo()


# --- helpers ----------------------------------------------------------------------------------

func _lab() -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find("collision"))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


## Waits until the lab's model has made `k` steps (its engine step k is done too).
func _until(lab: Experiment, k: int) -> void:
	var guard := 0
	while lab.model.steps < k and guard < 4000:
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


## Model with a vector case's conditions, reset at its start.
func _model_for(c: Dictionary) -> CollisionModel:
	var model := CollisionModel.new()
	model.mass_a = c.a.mass
	model.mass_b = c.b.mass
	model.radius_a = c.a.radius
	model.radius_b = c.b.radius
	model.restitution_a = c.a.restitution
	model.restitution_b = c.b.restitution
	model.threshold = vectors.threshold
	model.damping = vectors.damping
	model.sleep_speed = vectors.sleep_speed
	model.wall = vectors.wall
	model.reset(c.a.x, c.b.x, c.a.v, c.b.v)
	return model


## Puts a vector case's conditions on the lab (materials by their e; a numeric material = override).
func _setup_lab(lab: Experiment, c: Dictionary) -> void:
	lab.restitution_override = Vector2(-1.0, -1.0)
	if c.a.material is String:
		lab.set_control("material_a", c.a.material)
		lab.set_control("material_b", c.b.material)
	else:
		lab.restitution_override = Vector2(c.a.restitution, c.b.restitution)
	lab.set_control("mass_a", c.a.mass)
	lab.set_control("mass_b", c.b.mass)
	lab.set_control("velocity_a", c.a.v)
	lab.set_control("velocity_b", c.b.v)
	lab.start_a = c.a.x
	lab.start_b = c.b.x
	lab.reset_run()


## Worst relative error of the first-collision values shown by `values` (observations) against TS.
func _first_error(shown: Dictionary, first: Dictionary) -> float:
	var worst := 0.0
	worst = maxf(worst, _err(shown.before_a, first.before[0]))
	worst = maxf(worst, _err(shown.before_b, first.before[1]))
	worst = maxf(worst, _err(shown.after_a, first.after[0]))
	worst = maxf(worst, _err(shown.after_b, first.after[1]))
	worst = maxf(worst, _err(shown.restitution, first.restitution))
	worst = maxf(worst, _err(shown.impulse_a, first.impulse[0]))
	worst = maxf(worst, _err(shown.impulse_b, first.impulse[1]))
	worst = maxf(worst, _err(shown.p_before, first.momentum[0]))
	worst = maxf(worst, _err(shown.p_after, first.momentum[1]))
	worst = maxf(worst, _err(shown.k_before, first.kinetic[0]))
	worst = maxf(worst, _err(shown.k_after, first.kinetic[1]))
	return worst


func _open() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(720, 1560)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("collision"))
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
	var definition := ExperimentRegistry.find("collision")
	var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	var shared: Dictionary = ExperimentRegistry.shared_labs().get("collision", {})
	expect.call(problems.is_empty() and listed.has("collision") and definition.get("content") == "collision"
		and definition.get("title") == shared.get("title") and definition.get("tip", "") == shared.get("app", {}).get("tip", "") and definition.tip.contains("노란 손잡이"),
		"collision: definition valid, listed, texts and the app tip from the shared content", ", ".join(problems))
	# Materials: every vector case's (material, e) pair is the option's e.
	var ok := true
	var seen := {}
	for c in vectors.cases:
		for side in ["a", "b"]:
			var ball: Dictionary = c[side]
			if not ball.material is String:
				continue
			seen[ball.material] = true
			for id in ["material_a", "material_b"]:
				for control in definition.controls:
					if control.id != id:
						continue
					for option in control.options:
						if option.id == ball.material:
							ok = ok and float(option.e) == float(ball.restitution)
	var start := _case("web start")
	var defaults := {}
	for control in definition.controls:
		defaults[control.id] = control.default
	var lab_script: GDScript = load(definition.scene)
	var consts := lab_script.get_script_constant_map()
	expect.call(ok and seen.size() == 4 and float(defaults.mass_a) == float(start.a.mass) and float(defaults.mass_b) == float(start.b.mass)
		and float(defaults.velocity_a) == float(start.a.v) and float(defaults.velocity_b) == float(start.b.v) and defaults.material_a == start.a.material
		and float(consts.START_A) == float(start.a.x) and float(consts.START_B) == float(start.b.x) and float(consts.RADIUS_A) == float(start.a.radius)
		and float(consts.RADIUS_B) == float(start.b.radius) and float(consts.WALL) == float(vectors.wall),
		"collision: material e = TS MATERIALS (4), the start = the TS web start (1 / 2 kg rubber, 3.4 / -1.7 m/s), radii and walls = the vectors", str(seen.keys()))


# --- 2. model = TS ----------------------------------------------------------------------------

func check_model_cases() -> void:
	var worst := 0.0
	var first_worst := 0.0
	var steps_ok := true
	for c in vectors.cases:
		var model := _model_for(c)
		var samples := {}
		for s in c.samples:
			samples[int(s.step)] = s
		var dt := 1.0 / float(vectors.step_hz)
		for k in range(1, int(c.steps) + 1):
			model.step(dt)
			if not samples.has(k):
				continue
			var s: Dictionary = samples[k]
			worst = maxf(worst, maxf(_err(model.xa, s.x[0]), _err(model.xb, s.x[1])))
			worst = maxf(worst, maxf(_err(model.va, s.v[0]), _err(model.vb, s.v[1])))
			worst = maxf(worst, maxf(_err(model.momentum_a(), s.p[0]), _err(model.momentum_b(), s.p[1])))
			steps_ok = steps_ok and model.collisions == int(s.collisions)
		var first: Dictionary = c.first
		steps_ok = steps_ok and model.first_step == int(first.step) and model.collisions == int(c.collisions)
		first_worst = maxf(first_worst, maxf(_err(model.before[0], first.before[0]), _err(model.before[1], first.before[1])))
		first_worst = maxf(first_worst, maxf(_err(model.after[0], first.after[0]), _err(model.after[1], first.after[1])))
		first_worst = maxf(first_worst, _err(model.restitution_used, first.restitution))
		first_worst = maxf(first_worst, maxf(_err(model.impulse_a(), first.impulse[0]), _err(model.impulse_b(), first.impulse[1])))
	expect.call(worst <= tolerance, "collision model: positions, velocities and momenta at every sample step = TS world (7 cases)", "max rel err %s" % String.num_scientific(worst))
	expect.call(first_worst <= tolerance and steps_ok, "collision model: first collision (step, before / after, e, impulses) and collision counts = TS world",
		"max rel err %s" % String.num_scientific(first_worst))


# --- 3. engine = TS ---------------------------------------------------------------------------

func check_engine_cases() -> void:
	var lab: Experiment = await _lab()
	var worst_x := 0.0
	var worst_shown := 0.0
	var worst_step_x := 0.0
	var worst_step_v := 0.0
	var conserved := 0.0
	var energy_ok := true
	var details := []
	var outcomes := {}
	for c in vectors.cases:
		_setup_lab(lab, c)
		lab.release()
		var first: Dictionary = c.first
		var shown_first := {}
		for s in c.samples:
			var k := int(s.step)
			await _until(lab, k)
			if lab.model.steps != k:
				worst_x = INF
				break
			worst_x = maxf(worst_x, maxf(absf(lab.ball_a.global_position.x - float(s.x[0])), absf(lab.ball_b.global_position.x - float(s.x[1]))))
			if lab.model.collided and shown_first.is_empty():
				shown_first = lab.observations()
		worst_step_x = maxf(worst_step_x, lab.driver.worst_position)
		worst_step_v = maxf(worst_step_v, lab.driver.worst_velocity)
		worst_shown = maxf(worst_shown, _first_error(shown_first, first) if not shown_first.is_empty() else INF)
		conserved = maxf(conserved, absf(float(shown_first.get("p_after", INF)) - float(shown_first.get("p_before", 0.0))))
		energy_ok = energy_ok and float(shown_first.get("k_after", INF)) <= float(shown_first.get("k_before", 0.0)) + 1e-12
		outcomes[c.name] = shown_first
		details.append("%s e %.2f" % [c.name, float(shown_first.get("restitution", NAN))])
	expect.call(worst_x <= ENGINE_TOLERANCE, "collision: engine ball centres = TS world at every sample step, before, at and after the hits (7 cases, <= 1e-4 m)",
		"max |dx| %s m" % String.num_scientific(worst_x))
	expect.call(worst_step_x <= ENGINE_TOLERANCE and worst_step_v <= ENGINE_TOLERANCE,
		"collision: every engine step lands on the formula state (centre <= 1e-4 m, step velocity <= 1e-4 m/s)",
		"max %s m, %s m/s" % [String.num_scientific(worst_step_x), String.num_scientific(worst_step_v)])
	expect.call(worst_shown <= tolerance, "collision: panel after the first collision (v before / after, e, J, p and K sums) = TS world",
		"max rel err %s" % String.num_scientific(worst_shown))
	expect.call(conserved <= 1e-12 and energy_ok, "collision: momentum sum conserved in the hit, kinetic energy never gained", "max |dp| %s" % String.num_scientific(conserved))
	var elastic: Dictionary = outcomes.get("equal elastic", {})
	expect.call(not elastic.is_empty() and absf(float(elastic.after_a) - float(elastic.before_b)) <= 1e-12 and absf(float(elastic.after_b) - float(elastic.before_a)) <= 1e-12
		and float(elastic.after_a) == 0.0,
		"collision: equal masses, e = 1: the balls exchange velocities (A stops, B leaves with A's speed)", str(elastic.get("after_b", "")))
	var e_ok: bool = absf(float(outcomes["web start"].restitution) - 0.88) < 1e-12 and absf(float(outcomes["wood light"].restitution) - 0.5) < 1e-12 \
		and absf(float(outcomes["catch up"].restitution) - 0.72) < 1e-12 and absf(float(outcomes["clay heavy"].restitution) - 0.08) < 1e-12 \
		and float(outcomes["slow"].restitution) == 0.0 and absf(float(outcomes["slow"].after_a) - float(outcomes["slow"].after_b)) < 1e-12
	expect.call(e_ok, "collision: restitution per material (rubber 0.88, wood 0.5, steel 0.72, clay-steel 0.08 = min) and e = 0 below 1 m/s (they move on together)", "; ".join(details))
	await _free(lab)


# --- 4. conditions ----------------------------------------------------------------------------

func check_conditions() -> void:
	var lab: Experiment = await _lab()
	lab.release()
	await _until(lab, 40)
	var moved: bool = absf(lab.ball_a.global_position.x - lab.START_A) > 1.0
	lab.set_control("mass_a", 3.0)
	var back: bool = not lab.released and is_equal_approx(lab.ball_a.global_position.x, lab.START_A) and lab.graph_series().momentum_a.is_empty()
	var shown: Dictionary = lab.observations()
	lab.set_control("material_b", "clay")
	lab.set_control("velocity_b", 0.0)
	lab.set_control("material_a", "glass")
	lab.set_control("nope", 1.0)
	var shown2: Dictionary = lab.observations()
	expect.call(moved and back and float(shown.p_before) == 3.0 * 3.4 + 2.0 * -1.7 and lab.model.restitution_b == 0.08 and lab.material_a == "rubber"
		and float(shown2.before_b) == 0.0 and shown2.after_a == "—" and lab.status() == "ready",
		"collision: mass, material and velocity change the conditions and put the balls back; unknown ids are ignored", str(shown2.p_before))
	await _free(lab)


# --- 5. art -----------------------------------------------------------------------------------

func check_art() -> void:
	var lab: Experiment = await _lab()
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append("%s:%s" % [node.name, node.get_class()])
	bodies.sort()
	expect.call(bodies == ["BallA:RigidBody3D", "BallB:RigidBody3D", "Floor:StaticBody3D", "KnobA:StaticBody3D", "KnobB:StaticBody3D"]
		and lab.ball_a.collision_mask == 0 and lab.knob_a.collision_mask == 0 and lab.ball_a.get_collision_exceptions().has(lab.ball_b),
		"collision art adds no collision objects; the balls touch nothing in the engine (the formula owns the hit)", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		for juice in [lab.props.juice_a, lab.props.juice_b]:
			juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.release()
		await _until(lab, 150)
		runs.append({"x": [lab.ball_a.global_position.x, lab.ball_b.global_position.x], "basis": lab.ball_a.global_basis, "obs": str(lab.observations())})
	for juice in [lab.props.juice_a, lab.props.juice_b]:
		juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(runs[0].x == runs[1].x and runs[0].obs == runs[1].obs and runs[0].basis == Basis(),
		"collision: same motion and panel with and without the reactions; rolling and squash never turn a body", str(runs[0].x))
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 16, "collision: at most 16 drawn 3D nodes (art budget)", "%d" % draw_nodes)
	await _free(lab)


# --- 6. fresh screen: first collision ---------------------------------------------------------

func check_first_collision_screen() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var c := _case("web start")
	var first: Dictionary = c.first
	var waiting: Dictionary = lab.observations()
	screen.experiment_action("release")
	var hit := int(first.step)
	await _until(lab, hit - 1)
	var before_hit: bool = not lab.model.collided and lab.status() == "moving"
	await _until(lab, hit)
	var shown: Dictionary = lab.observations()
	var sample := {}
	for s in c.samples:
		if int(s.step) >= hit:
			sample = s
			break
	await _until(lab, int(sample.step))
	var dx: float = maxf(absf(lab.ball_a.global_position.x - float(sample.x[0])), absf(lab.ball_b.global_position.x - float(sample.x[1])))
	expect.call(before_hit and lab.model.first_step == hit and _first_error(shown, first) <= tolerance and shown.state == "충돌! 충격량이 전달됐어요" and dx <= ENGINE_TOLERANCE
		and waiting.state == "출발 전 · 화살표로 속도를 정해요" and float(waiting.before_a) == 3.4,
		"collision (fresh screen): 출발 → the first collision on the TS step %d with the TS outcome, engine balls on the TS positions" % hit,
		"after %.4f / %.4f m/s, |dx| %s m" % [float(shown.after_a), float(shown.after_b), String.num_scientific(dx)])
	await _until(lab, 240)
	var series: Dictionary = lab.graph_series()
	var signs: bool = series.momentum_a[0].y > 0.0 and series.momentum_b[0].y < 0.0 and series.momentum_a[-1].y < 0.0 and series.momentum_b[-1].y > 0.0
	expect.call(series.momentum_a.size() >= 40 and absf(series.momentum_a[0].y - 3.4) < 1e-6 and signs and screen._graph.spec.y.get("signed", false),
		"collision: the graph shows both momenta over time, signed (A right then left, B the other way)", "%d points" % series.momentum_a.size())
	await _close(screen)


# --- 7. input path ----------------------------------------------------------------------------

func check_input_path() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var ball: RigidBody3D = lab.ball_a
	var goal := Vector3(-2.1, ball.global_position.y, 0.0)
	_swipe(screen, _at(screen, ball.global_position), _at(screen, goal))
	var held: bool = m.mode == "drag" and m.active_id == "ball_a"
	_touch(screen, _at(screen, goal), false)
	await tree.process_frame
	var knob: StaticBody3D = lab.knob_a
	var placed: bool = lab.start_a == -2.0 and is_equal_approx(ball.global_position.x, -2.0) and is_equal_approx(knob.global_position.x, -2.0 + 3.4 * lab.ARROW_SCALE)
	expect.call(held and placed, "collision: dragging ball A puts it on its half of the rail on the 0.5 m grid; its knob follows",
		"held %s, start %.3f, ball %.3f, knob %.3f" % [held, lab.start_a, ball.global_position.x, knob.global_position.x])
	# Knob to about 5.1 m/s: snaps to 5 m/s; the arrow previews the snapped value while held.
	var knob_goal := Vector3(-2.0 + 5.1 * lab.ARROW_SCALE, knob.global_position.y, 0.0)
	_swipe(screen, _at(screen, knob.global_position), _at(screen, knob_goal))
	await tree.process_frame
	await tree.process_frame
	var preview_length: float = lab.props.arrow_a.mesh.get_aabb().size.x if lab.props.arrow_a.mesh else 0.0
	_touch(screen, _at(screen, knob_goal), false)
	await tree.process_frame
	var synced: bool = screen._control_widgets.velocity_a.slider.value == 5.0
	expect.call(lab.velocity_a == 5.0 and synced and is_equal_approx(knob.global_position.x, -2.0 + 5.0 * lab.ARROW_SCALE)
		and absf(preview_length - (5.0 * lab.ARROW_SCALE - lab.KNOB_SIZE * 0.5)) < 0.05,
		"collision: dragging the arrow knob sets the velocity on the 0.5 m/s grid (preview while held, slider follows)", "v %.2f, arrow %.3f m" % [lab.velocity_a, preview_length])
	var grid_ok: bool = lab.knob_velocity(5.1 * lab.ARROW_SCALE) == 5.0 and lab.knob_velocity(0.3 * lab.ARROW_SCALE) == 0.5 \
		and lab.knob_velocity(-1.24 * lab.ARROW_SCALE) == -1.0 and lab.knob_velocity(20.0) == 9.0 and lab.knob_velocity(0.2 * lab.ARROW_SCALE) == 0.0
	expect.call(grid_ok, "collision: knob offset -> velocity on the 0.5 m/s grid, capped at 9 m/s (the web arrow's cap)", "")
	# A run from there follows the formula: the outcome = world_collision_velocities of the velocities before.
	screen.experiment_action("release")
	var guard := 0
	while not lab.model.collided and guard < 600:
		await tree.physics_frame
		guard += 1
	var model: CollisionModel = lab.model
	var want := PhysicsLaws.world_collision_velocities(1.0, 2.0, model.before[0], 0.0, model.before[1], 0.0, 1.0, 0.0, 0.88, 0.88, 1.0)
	expect.call(model.collided and model.after[0] == want[0] and model.after[1] == want[2] and absf(model.momentum_of(model.after[0], model.after[1]) - model.momentum_of(model.before[0], model.before[1])) < 1e-12
		and lab.driver.worst_position <= ENGINE_TOLERANCE,
		"collision: the run after dragging collides by the formula (TS world outcome, momentum kept, engine on the formula)", "step %d" % model.first_step)
	# Picking a ball up while it rolls stops the run (both back at their starts).
	_swipe(screen, _at(screen, lab.ball_b.global_position), _at(screen, lab.ball_b.global_position + Vector3(0.02, 0, 0)), 2)
	var stopped: bool = not lab.released
	_touch(screen, _at(screen, lab.ball_b.global_position), false)
	expect.call(stopped and is_equal_approx(lab.ball_a.global_position.x, -2.0), "collision: picking a ball up stops the run and puts both back", "")
	await _close(screen)


# --- 8. demo ----------------------------------------------------------------------------------

func check_demo() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	screen.manipulator.start_demo(0.2)
	var runs := 0
	var hits := 0
	var was := false
	for i in 8 * STEP_HZ:
		await tree.physics_frame
		if lab.released and not was:
			runs += 1
		if lab.model.collided and lab.status() == "impact":
			hits += 1
		was = lab.released
	screen.manipulator.start_demo(0.0)
	expect.call(runs >= 2 and hits > 0 and lab.start_a != lab.START_A,
		"collision: the measurement demo (--auto-drag) drags ball A and starts runs that collide", "%d runs" % runs)
	await _close(screen)
