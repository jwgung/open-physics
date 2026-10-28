## Headless checks of the push friction lab (Phase 1 Task 4b), run by run_tests.gd. Expected values
## are the TS-core vectors in tests/friction_lab_vectors.json (tools/friction-lab-vectors.test.ts:
## PushFrictionLaw in the web's px units, the app's stepping rule); motion is measured from the
## engine box.
## 1. definition: valid, listed, texts from the shared content, materials and the start box = the TS
##    vectors (the kid boxes are heavier than the web's, KID_MASSES; the law runs on the web's masses).
## 2. force schedules (4 materials x masses): the panel (state, F, friction, v, distance, heat, K)
##    after fixed steps = TS (1e-9); the engine box follows the formula displacement (1e-4 m); heat =
##    mu_k m g x distance slid, and the applied force's work = K + heat (within the step error).
## 3. threshold: at and just below the maximum static friction the box holds 2 s (<= 1 mm), 0.01 N
##    above it slides from the first step and follows the formula.
## 4. conditions: material and mass change the readouts and put the box back; unknown ids ignored;
##    the state is the formula's, not the engine corrector's.
## 5. track end: the box stops at a bumper (formula stop, engine frozen), a new press on the box frees it.
## 6. art: visual only (bodies, the same run without the reactions), draw-node budget.
## 7. press and hold on the box through the real input path, in a freshly opened screen (2026-10-28):
##    the push grows PUSH_RATE N/s from 0, the gauge shows its share of PUSH_MAX, the box starts on
##    the first step the ramped force passes mu_s m g (and holds before it), pushed towards +x;
##    letting go sets the force to 0 at once and the box slides to a stop; the graph.
## 8. the measurement demo (--auto-drag) holds the box and resets it.
extends RefCounted

const VECTORS_PATH := "res://tests/friction_lab_vectors.json"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60
## The kid boxes (2026-10-28 user decision "너무 쉽게 밀려"): heavier than the web's 0.5 / 1 / 3 kg.
const KID_MASSES := {"light": 2.0, "normal": 5.0, "heavy": 10.0}

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
	await check_push_cases()
	await check_thresholds()
	await check_conditions()
	await check_state_is_formula()
	await check_track_end()
	await check_art()
	await check_first_pull_input()
	await check_demo()


# --- helpers ----------------------------------------------------------------------------------

func _lab() -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find("friction"))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


## Waits until `k` fixed steps since the lab's reset are done (engine included): the caller then runs
## before step k + 1, so a force set now acts from that step on.
func _until(lab: Experiment, k: int) -> void:
	var guard := 0
	while lab.frames < k and guard < 4000:
		await tree.physics_frame
		guard += 1


## Relative error (absolute below 1).
func _err(value: Variant, want: float) -> float:
	if not (value is float or value is int):
		return INF
	return absf(float(value) - want) / maxf(1.0, absf(want))


func _open() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(1560, 720)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("friction"))
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
	var definition := ExperimentRegistry.find("friction")
	var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	var shared: Dictionary = ExperimentRegistry.shared_labs().get("friction", {})
	expect.call(problems.is_empty() and listed.has("friction") and definition.get("content") == "friction"
		and definition.get("title") == shared.get("title") and definition.get("tip", "") == shared.get("app", {}).get("tip", "") and definition.tip.contains("상자") and not definition.tip.contains("손잡이"),
		"friction: definition valid, listed, texts and the app tip from the shared content", ", ".join(problems))
	var ok := true
	var materials := {}
	for case in vectors.push:
		materials[case.material] = [case.mu_s, case.mu_k]
	var masses: Dictionary = vectors.masses
	for control in definition.get("controls", []):
		for option in control.get("options", []):
			if control.id == "material":
				var want: Array = materials.get(option.id, [NAN, NAN])
				ok = ok and absf(float(option.mu_s) - float(want[0])) < 1e-9 and absf(float(option.mu_k) - float(want[1])) < 1e-9
			elif control.id == "mass":
				# The start box is the web's; the kid boxes are heavier than the web's mass buttons
				# (2026-10-28 user decision "너무 쉽게 밀려"): the law's parity runs on the web's masses
				# (set_box_mass), not on these presets.
				ok = ok and float(option.kg) == float(KID_MASSES.get(option.id, masses.get(option.id, NAN)))
	expect.call(ok and materials.size() == 4 and masses.size() == 4, "friction: material options = the TS vectors (web MATERIALS); the start box = the web's 8 kg, the kid boxes 2 / 5 / 10 kg (not the web's 0.5 / 1 / 3 kg buttons)", str(materials))


# --- 2. force schedules -----------------------------------------------------------------------

func check_push_cases() -> void:
	var lab: Experiment = await _lab()
	var worst_display := 0.0
	var worst_engine := 0.0
	var states_ok := true
	var heat_worst := 0.0
	var balance_worst := 0.0
	var details := []
	for case in vectors.push:
		lab.set_control("material", case.material)
		lab.set_box_mass(float(case.mass) if case.has("mass") else float(vectors.masses[case.mass_id]))
		await _until(lab, 0)
		var samples := {}
		for sample in case.samples:
			samples[int(sample.step)] = sample
		var k := 0
		var applied_work := 0.0
		var previous_x := 0.0
		for segment in case.schedule:
			for i in int(segment[1]):
				lab.set_applied_force(float(segment[0]))
				await _until(lab, k + 1)
				k += 1
				var model: PushFrictionModel = lab.model
				applied_work += float(segment[0]) * (model.displacement - previous_x)
				previous_x = model.displacement
				if not samples.has(k):
					continue
				var want: Dictionary = samples[k]
				var shown: Dictionary = lab.observations()
				for key in ["applied", "friction", "speed", "heat"]:
					worst_display = maxf(worst_display, _err(shown[key], absf(float(want[key]))))
				worst_display = maxf(worst_display, _err(shown.distance, absf(float(want.displacement))))
				worst_display = maxf(worst_display, _err(model.displacement, float(want.displacement)))
				worst_display = maxf(worst_display, _err(model.kinetic_energy(), float(want.kinetic)))
				worst_display = maxf(worst_display, _err(shown.max_static, float(case.max_static)) + _err(shown.kinetic, float(case.kinetic_friction)))
				states_ok = states_ok and lab.status() == want.state
				worst_engine = maxf(worst_engine, absf(lab.engine_displacement() - model.displacement))
		var last: PushFrictionModel = lab.model
		heat_worst = maxf(heat_worst, _err(last.heat, last.kinetic_friction() * last.path))
		balance_worst = maxf(balance_worst, absf(applied_work - last.heat - last.kinetic_energy()) / maxf(1.0, applied_work))
		details.append("%s %.1f kg: heat %.3f J, moved %.3f m" % [case.material, case.mass, last.heat, last.displacement])
	expect.call(worst_display <= tolerance, "friction: panel F, friction, v, distance, heat, K, limits after fixed steps = TS core (4 schedules)", "max rel err %s" % String.num_scientific(worst_display))
	expect.call(states_ok, "friction: state (버팀 / 움직임) at every sample = the TS law", "")
	expect.call(worst_engine <= 1e-4, "friction: the engine box follows the formula displacement", "max |diff| %s m; %s" % [String.num_scientific(worst_engine), "; ".join(details)])
	expect.call(heat_worst <= tolerance, "friction: heat = kinetic friction x distance slid (friction work)", "max rel err %s" % String.num_scientific(heat_worst))
	expect.call(balance_worst <= 0.05, "friction: the applied force's work = kinetic energy + heat (within the 60 Hz step error, 5 %)", "max rel %s" % String.num_scientific(balance_worst))
	await _free(lab)


# --- 3. threshold -----------------------------------------------------------------------------

func check_thresholds() -> void:
	var lab: Experiment = await _lab()
	var holds_ok := true
	var slides_ok := true
	var details := []
	for case in vectors.thresholds:
		for i in 3:
			lab.set_control("material", case.material)
			lab.set_box_mass(float(case.mass) if case.has("mass") else float(vectors.masses[case.mass_id]))
			await _until(lab, 0)
			var force := float(case.forces[i])
			lab.set_applied_force(force)
			await _until(lab, 1)
			var first_state: String = lab.status()
			var first_x: float = lab.model.displacement
			var moved := 0.0
			var frames := 2 * STEP_HZ if case.holding[i] else STEP_HZ
			for k in range(2, frames + 1):
				await _until(lab, k)
				moved = maxf(moved, absf(lab.engine_displacement()))
			var shown: Dictionary = lab.observations()
			if case.holding[i]:
				holds_ok = holds_ok and first_state == "holding" and lab.status() == "holding" and moved <= 0.001 and float(shown.friction) == absf(force) \
					and shown.state == "버티는 중 · 마찰이 막고 있어요"
			else:
				var t := 1.0
				var a: float = (force - lab.model.kinetic_friction()) / lab.model.mass
				slides_ok = slides_ok and first_state == "sliding" and first_x > 0.0 and lab.status() == "sliding" \
					and absf(lab.model.displacement - 0.5 * a * t * t) <= 1e-9 * maxf(1.0, lab.model.displacement) \
					and absf(lab.engine_displacement() - lab.model.displacement) <= 1e-4 and shown.state == "움직여요 · 주는 힘이 마찰을 이겼어요"
				details.append("%s: s(1 s) %.5f m (a %.4f)" % [case.material, lab.model.displacement, a])
	expect.call(holds_ok, "friction: at and 0.01 N below the maximum static friction the box holds 2 s (<= 1 mm, friction = F)", "")
	expect.call(slides_ok, "friction: 0.01 N above it the box slides from the first step, s = (F - mu_k m g) t^2 / 2m", "; ".join(details))
	lab.set_applied_force(0.0)
	await _free(lab)


# --- 4. conditions ----------------------------------------------------------------------------

func check_conditions() -> void:
	var lab: Experiment = await _lab()
	lab.set_applied_force(40.0)
	await _until(lab, 30)
	lab.set_applied_force(0.0)
	var moved_before: float = lab.box.global_position.x
	lab.set_control("material", "clay")
	var after_material: Dictionary = lab.observations()
	var back: bool = is_equal_approx(lab.box.global_position.x, lab.START_X) and moved_before > lab.START_X + 0.01
	lab.set_control("mass", "heavy")
	var after_mass: Dictionary = lab.observations()
	lab.set_control("mass", "nope")
	lab.set_control("material", "glass")
	var want_material := PhysicsLaws.push_max_static_force(0.76, 8.0, 9.81)
	var want_mass := PhysicsLaws.push_max_static_force(0.76, 10.0, 9.81)
	expect.call(back and float(after_material.max_static) == want_material and float(after_material.heat) == 0.0 and float(after_mass.max_static) == want_mass
		and lab.box.mass == 10.0 and lab.mass_id == "heavy" and lab.material_id == "clay" and lab.graph_series().applied.is_empty(),
		"friction: material and mass change the limit and the box mass, put the box back and clear the run; unknown ids are ignored",
		"clay 8 kg %.3f N, clay 10 kg %.3f N" % [float(after_material.max_static), float(after_mass.max_static)])
	await _free(lab)


## The state shown is the formula's (PushFrictionLaw on the model), not the engine's: with the engine
## box held still (frozen, the corrector does not run) a force above the limit still reads "sliding".
func check_state_is_formula() -> void:
	var lab: Experiment = await _lab()
	lab.box.freeze = true
	lab.set_applied_force(40.0)
	await _until(lab, 10)
	var engine_status: String = lab.corrector.status
	var shown: Dictionary = lab.observations()
	expect.call(lab.status() == "sliding" and engine_status == "holding" and shown.state == "움직여요 · 주는 힘이 마찰을 이겼어요" and lab.model.displacement > 0.0,
		"friction: the state is the formula's (engine box held still: the panel still says sliding)", "engine %s" % engine_status)
	lab.set_applied_force(0.0)
	# The same gravity as the engine's (the formulas' g is the project setting, not a copy).
	expect.call(lab.model.g == lab.engine_g and lab.engine_g == float(vectors.get("g", lab.engine_g)),
		"friction: the model's g is the engine's gravity (and the TS vectors' g)", "%s vs %s" % [lab.model.g, lab.engine_g])
	# A reset while the box is held keeps the hold and counts the push from 0 again.
	lab.hold_started("box")
	await _until(lab, lab.frames + 12)   # 12 steps at 25 N/s: 5 N
	var before: float = lab.applied_force()
	lab.reset_box()
	expect.call(before == 5.0 and lab.push.held and lab.applied_force() == 0.0,
		"friction: a reset while the box is held keeps the hold and restarts the push at 0 N", "before %.2f N, after %.2f N" % [before, lab.applied_force()])
	lab.hold_ended("box")
	await _free(lab)


# --- 5. track end -----------------------------------------------------------------------------

func check_track_end() -> void:
	var lab: Experiment = await _lab()
	lab.set_control("material", "steel")
	lab.set_control("mass", "light")
	lab.set_applied_force(80.0)
	var k := 0
	while lab.status() != "end" and k < 3 * STEP_HZ:
		k += 1
		await _until(lab, k)
	await _until(lab, k + 3)
	var high: float = lab.TRACK_HALF - lab.BOX * 0.5
	var engine_x: float = lab.box.global_position.x
	var stopped: bool = lab.status() == "end" and lab.box.freeze and absf(lab.model.velocity) == 0.0 \
		and absf(engine_x - (high - lab.END_PADDING)) <= 1e-5 and absf(engine_x - lab.formula_x()) <= 1e-5
	var shown: Dictionary = lab.observations()
	expect.call(stopped and shown.state == "바닥 끝에 닿았어요" and float(shown.speed) == 0.0,
		"friction: the box stops at the track end (formula stop; the engine box is frozen there)", "x %.3f (formula %.3f), state %s" % [engine_x, lab.formula_x(), shown.state])
	lab.hold_started("box")
	var freed: bool = not lab.ended and not lab.box.freeze and lab.status() == "holding"
	lab.hold_ended("box")
	lab.set_applied_force(-8.0)   # past the 2 kg steel box's 5.1 N
	var start: int = lab.frames
	await _until(lab, start + 30)
	expect.call(freed and lab.status() == "sliding" and lab.box.global_position.x < engine_x - 0.01,
		"friction: a new press on the box frees it at the end; a push back moves it", "x %.3f" % lab.box.global_position.x)
	lab.set_applied_force(0.0)
	await _free(lab)
	# Picked up in the very step the end was reached (the freeze is still pending): nothing freezes
	# the engine box afterwards, it follows the formula again.
	lab = await _lab()
	lab.set_control("material", "steel")
	lab.set_control("mass", "light")
	lab.set_applied_force(80.0)
	k = 0
	while not lab.ended and k < 3 * STEP_HZ:
		k += 1
		await _until(lab, k)
	var pending: bool = lab.ended and lab._freeze_next
	lab.hold_started("box")
	lab.hold_ended("box")
	lab.set_applied_force(-8.0)
	start = lab.frames
	await _until(lab, start + 30)
	expect.call(pending and not lab._freeze_next and not lab.box.freeze and lab.status() == "sliding"
		and absf(lab.box.global_position.x - lab.formula_x()) <= 1e-3,
		"friction: a press on the box in the step the end is reached leaves no pending freeze (engine box follows the formula)",
		"freeze %s, engine %.4f formula %.4f" % [lab.box.freeze, lab.box.global_position.x, lab.formula_x()])
	lab.set_applied_force(0.0)
	await _free(lab)


# --- 6. art -----------------------------------------------------------------------------------

func check_art() -> void:
	var lab: Experiment = await _lab()
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append("%s:%s" % [node.name, node.get_class()])
	bodies.sort()
	expect.call(bodies == ["Box:RigidBody3D", "Floor:StaticBody3D"] and lab.find_children("*Handle*", "", true, false).is_empty() and lab.find_children("Rod*", "", true, false).is_empty(),
		"friction art adds no collision objects (floor and box; no handle, no rod since 2026-10-28)", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.run_action("reset")
		await _until(lab, 0)
		lab.set_applied_force(36.0)
		await _until(lab, 60)
		lab.set_applied_force(0.0)
		await _until(lab, 120)
		runs.append({"x": lab.box.global_position.x, "obs": str(lab.observations())})
	lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(runs[0].x == runs[1].x and runs[0].obs == runs[1].obs, "friction: same motion and panel with and without the box reactions", str(runs[0].x))
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 17, "friction: at most 17 drawn 3D nodes (art budget: 10 + the bread cat's 7, Task 4g)", "%d" % draw_nodes)
	await _free(lab)


# --- 7. press and hold on the box through the input path -------------------------------------

func check_first_pull_input() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var limit: float = lab.model.max_static()   # 8 kg wood: 31.39 N
	var press := _at(screen, lab.box.global_position)
	_touch(screen, press, true)
	var held: bool = m.mode == "hold" and m.active_id == "box" and lab.push.held
	var start: int = lab.frames
	# Step by step until the box starts: the push is rate x held time, the box holds while it is at
	# or below mu_s m g and starts on the first step above it.
	var forces := []
	var started := -1
	var gauge_ok := true
	while started < 0 and lab.frames < start + 4 * STEP_HZ:
		await _until(lab, lab.frames + 1)
		forces.append(lab.model.applied)
		if not lab.model.holding:
			started = forces.size()
		var want: float = lab.PUSH_RATE * forces.size() / float(STEP_HZ)
		if absf(lab.model.applied - want) > 1e-9:
			gauge_ok = false
	await tree.process_frame
	var gauge: ForceGauge = lab.props.gauge
	# The gauge was filled in the last frame's _process (a step may have run since).
	var fill_ok: bool = gauge.visible and absf(gauge.fraction * lab.PUSH_MAX - lab.applied_force()) <= lab.PUSH_RATE / STEP_HZ + 1e-6
	var at_start: float = forces[started - 1] if started > 0 else -1.0
	var before_start: float = forces[started - 2] if started > 1 else -1.0
	expect.call(held and gauge_ok and started > 0 and at_start > limit and before_start <= limit and fill_ok
		and started == ceili(limit / lab.PUSH_RATE * STEP_HZ + 1e-9),
		"friction (press and hold in a fresh screen): the push grows 25 N/s from 0 (gauge = push / 80 N); the box starts on the first step above mu_s m g = %.2f N (step %d, %.2f s)" % [limit, started, started / float(STEP_HZ)],
		"held %s, ramp %s, start step %d: %.3f N (before %.3f N), gauge %s %.3f" % [held, gauge_ok, started, at_start, before_start, gauge.visible, gauge.fraction])
	await _until(lab, lab.frames + 20)
	var shown: Dictionary = lab.observations()
	var engine_ok: bool = absf(lab.engine_displacement() - lab.model.displacement) <= 1e-4
	expect.call(shown.state == "움직여요 · 주는 힘이 마찰을 이겼어요" and engine_ok and lab.model.velocity > 0.0 and lab.box.global_position.x > lab.START_X,
		"friction: while held the push keeps growing, the box slides towards +x and the engine follows the formula", "x %.3f m" % lab.box.global_position.x)
	var peak_now: float = lab.applied_force()
	_touch(screen, press, false)
	await tree.process_frame
	var let_go: bool = not lab.push.held and lab.applied_force() == 0.0 and m.mode == ""
	await tree.process_frame
	var gauge_gone: bool = not lab.props.gauge.visible
	var guard := 0
	while lab.status() != "holding" and guard < 6 * STEP_HZ:
		await tree.physics_frame
		guard += 1
	await tree.physics_frame
	var model: PushFrictionModel = lab.model
	var stopped: Dictionary = lab.observations()
	expect.call(let_go and gauge_gone and lab.status() == "holding" and float(stopped.speed) < 1e-9 and stopped.state == "멈춰 있어요"
		and absf(model.heat - model.kinetic_friction() * model.path) <= 1e-9 * model.heat and model.heat > 1.0,
		"friction: letting go sets the push to 0 at once (gauge gone) and the box slides to a stop; heat = mu_k m g x distance",
		"heat %.3f J over %.3f m" % [model.heat, model.path])
	var series: Dictionary = lab.graph_series()
	var peak := 0.0
	for p in series.applied:
		peak = maxf(peak, p.y)
	expect.call(series.applied.size() > 10 and peak <= peak_now + 1e-9 and peak > limit and absf(series.max_static[0].y - lab.model.max_static()) <= 1e-4 and series.applied[-1].x <= lab.graph_x_max() + 1e-6,
		"friction: the graph shows the growing push, the maximum static friction and friction over time", "%d points, peak %.2f N" % [series.applied.size(), peak])
	# A short press (0.5 s: 12.5 N, below the limit) holds the box; friction matches the push.
	var x_before: float = lab.box.global_position.x
	press = _at(screen, lab.box.global_position)
	_touch(screen, press, true)
	var held_at: int = lab.frames
	await _until(lab, held_at + 30)
	var pushed: Dictionary = lab.observations()
	_touch(screen, press, false)
	expect.call(lab.status() == "holding" and float(pushed.applied) == 12.5 and float(pushed.friction) == 12.5 and pushed.state == "버티는 중 · 마찰이 막고 있어요"
		and absf(lab.box.global_position.x - x_before) <= 0.001,
		"friction: a short press (12.5 N, below the limit) is held by static friction", str(pushed.applied))
	await _close(screen)


# --- 8. measurement demo ----------------------------------------------------------------------

func check_demo() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	screen.manipulator.start_demo(0.2)
	var peak := 0.0
	var moved := 0.0
	var reset_seen := false
	for i in 6 * STEP_HZ:   # 1 s before the first press, a 3.2 s hold, the reset 0.4 s later
		await tree.physics_frame
		peak = maxf(peak, lab.applied_force())
		moved = maxf(moved, lab.box.global_position.x - lab.START_X)
		reset_seen = reset_seen or (moved > 0.5 and lab.box.global_position.x == lab.START_X)
	screen.manipulator.start_demo(0.0)
	expect.call(peak >= lab.PUSH_RATE * 1.4 and moved > 0.5 and reset_seen,
		"friction: the measurement demo (--auto-drag) holds the box (the push grows past mu_s m g) and resets it after letting go", "peak %.1f N, moved %.2f m" % [peak, moved])
	await _close(screen)
