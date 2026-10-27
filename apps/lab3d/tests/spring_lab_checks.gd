## Headless checks of the spring lab (Phase 1 Task 4d), run by run_tests.gd. Expected values are the
## TS-core vectors in tests/spring_lab_vectors.json (tools/spring-lab-vectors.test.ts: the motion of
## the web's AnchoredSpringLaw, harmonicDisplacement / harmonicVelocity without damping, 60 Hz).
## Physics first: the engine ball is checked step by step, not only the panel.
## 1. definition: valid, listed, shared texts and app tip; the defaults = the TS start case (1 kg,
##    no damping, 1.2 m); k, the web damping and the rest length = the vectors.
## 2. model = TS (no engine): extension, velocity, force, K, U, K + U at every sample step, period,
##    6 cases (rel 1e-9), the PhysicsLaws damped form against the vectors.
## 3. engine = TS: the lab through its own fixed steps; engine ball centre = TS at every sample step
##    (<= 1e-4 m), every step on the model state with the model's step velocity (<= 1e-4 m, m/s),
##    panel = TS (1e-9), also the 60 s run past the history window.
## 4. physics from the engine ball alone: period from its zero crossings = 2 pi sqrt(m / k) (3 masses),
##    energy from its positions (central-difference speed) kept without damping, only falling with it.
## 5. conditions: mass and damping restart the run at the pull; unknown ids are ignored; the panel
##    holds only formula values.
## 6. art: visual only (bodies, the same run without reactions), draw-node budget, coil and energy
##    stack follow the formula.
## 7. a freshly opened screen: "놓기" gives the TS start motion from the first step; graph K % / U %.
## 8. the real input path: dragging the ball along the rod (0.1 m grid) and letting go releases it
##    from rest there; the run = formula; picking it up stops the run.
## 9. the measurement demo (--auto-drag) drags the ball and releases it.
extends RefCounted

const VECTORS_PATH := "res://tests/spring_lab_vectors.json"
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
	await check_engine_physics()
	await check_conditions()
	await check_art()
	await check_first_release_screen()
	await check_input_path()
	await check_demo()


# --- helpers ----------------------------------------------------------------------------------

func _lab() -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find("spring"))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


func _until(lab: Experiment, k: int) -> void:
	var guard := 0
	while lab.model.steps < k and guard < 8000:
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


func _damping_id(b: float) -> String:
	return "none" if b == 0.0 else "web"


## The lab set to a vector case and released.
func _start(lab: Experiment, c: Dictionary) -> void:
	lab.begin_batch()
	lab.set_control("mass", float(c.mass))
	lab.set_control("damping", _damping_id(float(c.damping)))
	lab.pull = float(c.x0)
	lab.end_batch()
	lab.reset_run()
	lab.release()


func _model_for(c: Dictionary) -> SpringModel:
	var model := SpringModel.new()
	model.stiffness = vectors.stiffness
	model.rest_length = vectors.rest_length
	model.mass = c.mass
	model.damping = c.damping
	model.reset(c.x0, 1.0, 0.0)
	return model


func _sample_error(values: Dictionary, s: Dictionary) -> float:
	var worst := 0.0
	worst = maxf(worst, _err(values.extension, s.x))
	worst = maxf(worst, _err(values.speed, absf(float(s.v))))
	worst = maxf(worst, _err(values.force, s.force))
	worst = maxf(worst, _err(values.kinetic, s.kinetic))
	worst = maxf(worst, _err(values.spring, s.potential))
	worst = maxf(worst, _err(values.total, s.total))
	return worst


func _open() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(1560, 720)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("spring"))
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
	var definition := ExperimentRegistry.find("spring")
	var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	var shared: Dictionary = ExperimentRegistry.shared_labs().get("spring", {})
	expect.call(problems.is_empty() and listed.has("spring") and definition.get("title") == shared.get("title")
		and definition.get("tip", "") == shared.get("app", {}).get("tip", "") and definition.tip.contains("막대"),
		"spring: definition valid, listed, texts and the app tip from the shared content", ", ".join(problems))
	var start := _case("start")
	var defaults := {}
	for control in definition.controls:
		defaults[control.id] = control.default
	var consts: Dictionary = (load(definition.scene) as GDScript).get_script_constant_map()
	var model := SpringModel.new()
	var web_b := 0.0
	for control in definition.controls:
		if control.id == "damping":
			for option in control.options:
				if option.id == "web":
					web_b = float(option.b)
	expect.call(float(defaults.mass) == float(start.mass) and defaults.damping == "none" and float(consts.DEFAULT_PULL) == float(start.x0)
		and model.stiffness == float(vectors.stiffness) and float(consts.REST_LENGTH) == float(vectors.rest_length) and web_b == float(vectors.web_damping),
		"spring: the start = the TS start case (1 kg, no damping, 1.2 m); k = 5 N/m and the damping b = 0.45 = the web's", "")


# --- 2. model = TS ----------------------------------------------------------------------------

func check_model_cases() -> void:
	var worst := 0.0
	var worst_period := 0.0
	var dt := 1.0 / float(vectors.step_hz)
	for c in vectors.cases:
		var model := _model_for(c)
		worst_period = maxf(worst_period, _err(model.period(), c.period))
		for s in c.samples:
			while model.steps < int(s.step):
				model.step(dt)
			var values := {"extension": model.extension, "speed": absf(model.velocity), "force": model.force(),
				"kinetic": model.kinetic_energy(), "spring": model.spring_energy(), "total": model.total_energy()}
			worst = maxf(worst, _sample_error(values, s))
			worst = maxf(worst, _err(model.velocity, s.v))
	expect.call(worst <= tolerance and worst_period <= tolerance,
		"spring model: extension, velocity, force, K, U, K + U at every sample step and the period = TS (6 cases, with and without damping, 60 s)",
		"max rel err %s, period %s" % [String.num_scientific(worst), String.num_scientific(worst_period)])
	# Without damping the model's K + U is the release energy at every step (no integrator drift).
	var model := _model_for(_case("long"))
	var e0: float = _case("long").release_energy
	var drift := 0.0
	for k in 3600:
		model.step(dt)
		drift = maxf(drift, absf(model.total_energy() - e0))
	expect.call(drift <= 1e-12 * e0 * 10.0, "spring model: without damping K + U = k x0^2 / 2 at every step for 60 s", "max |dE| %s J" % String.num_scientific(drift))


# --- 3. engine = TS ---------------------------------------------------------------------------

func check_engine_cases() -> void:
	var lab: Experiment = await _lab()
	var worst_x := 0.0
	var worst_shown := 0.0
	var worst_step_x := 0.0
	var worst_step_v := 0.0
	var rest_x: float = lab.ANCHOR_X + float(vectors.rest_length)
	var past_history := false
	for c in vectors.cases:
		_start(lab, c)
		for s in c.samples:
			var k := int(s.step)
			if k == 0:
				continue
			await _until(lab, k)
			if lab.model.steps != k:
				worst_x = INF
				break
			worst_x = maxf(worst_x, absf(lab.ball.global_position.x - (rest_x + float(s.x))))
			worst_shown = maxf(worst_shown, _sample_error(lab.observations(), s))
		worst_step_x = maxf(worst_step_x, lab.driver.worst_position)
		worst_step_v = maxf(worst_step_v, lab.driver.worst_velocity)
		if c.name == "long":
			past_history = lab.driver.engine.size() == lab.driver.history_steps and lab.model.steps > lab.driver.history_steps * 5
	expect.call(worst_x <= ENGINE_TOLERANCE, "spring: engine ball centre = TS at every sample step (6 cases, 60 s run included, <= 1e-4 m)",
		"max |dx| %s m" % String.num_scientific(worst_x))
	expect.call(worst_step_x <= ENGINE_TOLERANCE and worst_step_v <= ENGINE_TOLERANCE and past_history,
		"spring: every engine step lands on the formula state with the formula's step velocity, also past the history window (60 s)",
		"max %s m, %s m/s" % [String.num_scientific(worst_step_x), String.num_scientific(worst_step_v)])
	expect.call(worst_shown <= tolerance, "spring: panel (x, speed, F, K, U, K + U) = TS at every sample step", "max rel err %s" % String.num_scientific(worst_shown))
	await _free(lab)


# --- 4. physics from the engine ball ----------------------------------------------------------

## Zero crossings of the engine extension (linear interpolation between steps) over `steps` steps.
func _engine_run(lab: Experiment, mass: float, damping: String, pull: float, steps: int) -> Dictionary:
	lab.begin_batch()
	lab.set_control("mass", mass)
	lab.set_control("damping", damping)
	lab.pull = pull
	lab.end_batch()
	lab.reset_run()
	lab.release()
	var rest_x: float = lab.ANCHOR_X + lab.REST_LENGTH
	var xs := PackedFloat64Array([lab.ball.global_position.x - rest_x])
	while lab.model.steps < steps:
		await tree.physics_frame
		xs.append(lab.ball.global_position.x - rest_x)
	return {"x": xs}


func check_engine_physics() -> void:
	var lab: Experiment = await _lab()
	var dt := 1.0 / STEP_HZ
	var worst_period := 0.0
	var details := []
	for mass in [0.5, 1.0, 3.0]:
		var xs: PackedFloat64Array = (await _engine_run(lab, mass, "none", 1.2, 20 * STEP_HZ)).x
		var crossings: Array[float] = []
		for k in range(1, xs.size()):
			if xs[k - 1] > 0.0 and xs[k] <= 0.0 or xs[k - 1] < 0.0 and xs[k] >= 0.0:
				crossings.append((k - 1 + xs[k - 1] / (xs[k - 1] - xs[k])) * dt)
		var measured := 2.0 * (crossings[-1] - crossings[0]) / (crossings.size() - 1)
		var want := TAU * sqrt(mass / 5.0)
		worst_period = maxf(worst_period, absf(measured - want) / want)
		details.append("%.1f kg %.5f/%.5f s" % [mass, measured, want])
	expect.call(worst_period <= 1e-4, "spring: the engine ball's period (zero crossings over 20 s) = 2 pi sqrt(m / k) for 0.5, 1, 3 kg (<= 1e-4)",
		"; ".join(details))
	# Energy of the engine ball alone: v from its positions (central difference), x from its centre.
	var energies := []
	for damping in ["none", "web"]:
		var xs: PackedFloat64Array = (await _engine_run(lab, 1.0, damping, 1.2, 30 * STEP_HZ)).x
		var e0 := 0.5 * 5.0 * 1.2 * 1.2
		var worst := 0.0
		var rising := 0.0
		var previous := INF
		for k in range(1, xs.size() - 1, 15):
			var v := (xs[k + 1] - xs[k - 1]) / (2.0 * dt)
			var e := 0.5 * 1.0 * v * v + 0.5 * 5.0 * xs[k] * xs[k]
			worst = maxf(worst, absf(e - e0) / e0)
			rising = maxf(rising, e - previous)
			previous = e
		energies.append([worst, rising, previous / e0])
	expect.call(energies[0][0] <= 1e-3 and energies[1][1] <= 1e-3 and energies[1][2] < 0.01,
		"spring: energy measured from the engine ball (central-difference v) stays k x0^2 / 2 for 30 s without damping (<= 0.1 %) and only falls with the web's damping",
		"no damping max %s, damped end %.4f of E0" % [String.num_scientific(energies[0][0]), energies[1][2]])
	await _free(lab)


# --- 5. conditions ----------------------------------------------------------------------------

func check_conditions() -> void:
	var lab: Experiment = await _lab()
	lab.release()
	await _until(lab, 40)
	var moved: bool = absf(lab.ball.global_position.x - (lab.ANCHOR_X + lab.REST_LENGTH + 1.2)) > 0.1
	lab.set_control("mass", 3.0)
	var back: bool = not lab.released and is_equal_approx(lab.ball.global_position.x, lab.ANCHOR_X + lab.REST_LENGTH + 1.2) and lab.graph_series().kinetic.is_empty()
	var period: float = lab.observations().period
	lab.set_control("damping", "web")
	var damped: bool = lab.model.damping == 0.45
	lab.set_control("damping", "honey")
	lab.set_control("nope", 1.0)
	var shown: Dictionary = lab.observations()
	# Damped (web, b = 0.45): the labelled natural period T0 = 2 pi sqrt(m / k) is unchanged, the real period is 2 pi / wd.
	var w0 := sqrt(5.0 / 3.0)
	var wd := sqrt(w0 * w0 - pow(0.45 / (2.0 * 3.0), 2.0))
	expect.call(absf(float(shown.natural_period) - TAU * sqrt(3.0 / 5.0)) < 1e-12 and absf(float(shown.period) - TAU / wd) < 1e-12 and float(shown.period) > float(shown.natural_period),
		"spring: with damping the panel shows the natural period 2 pi sqrt(m / k) and the longer damped period 2 pi / wd on separate rows", "T0 %.4f s, T %.4f s" % [shown.natural_period, shown.period])
	expect.call(moved and back and absf(period - TAU * sqrt(3.0 / 5.0)) < 1e-12 and absf(float(lab.observations().natural_period) - period) < 1e-12 and damped and lab.damping_id == "web" and lab.status() == "ready"
		and absf(float(shown.total) - 3.6) < 1e-12 and absf(float(shown.force) + 6.0) < 1e-12,
		"spring: mass and damping change the conditions and put the ball back at its pull; unknown ids are ignored", "T %.4f s" % period)
	var labels_ok := true
	var ids := []
	for item in lab.definition.observations:
		labels_ok = labels_ok and not str(item.label).contains("시뮬레이션")
		ids.append(item.id)
	expect.call(labels_ok and ids.all(func(id): return shown.has(id)) and ids.size() == shown.size(),
		"spring: the panel shows only formula-model values (no 'simulation' reading of the posed engine ball)", "%d values" % ids.size())
	await _free(lab)


# --- 6. art -----------------------------------------------------------------------------------

func check_art() -> void:
	var lab: Experiment = await _lab()
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append("%s:%s" % [node.name, node.get_class()])
	bodies.sort()
	expect.call(bodies == ["Ball:RigidBody3D", "Floor:StaticBody3D"] and lab.ball.collision_mask == 0 and lab.ball.freeze
		and lab.ball.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC,
		"spring art adds no collision objects; the ball is kinematic and touches nothing (the formula moves it)", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.release()
		await _until(lab, 150)
		runs.append({"x": lab.ball.global_position.x, "basis": lab.ball.global_basis, "obs": str(lab.observations())})
	lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(runs[0].x == runs[1].x and runs[0].obs == runs[1].obs and runs[0].basis == Basis(),
		"spring: same motion and panel with and without the reactions; the ball's body never turns", str(runs[0].x))
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 23, "spring: at most 23 drawn 3D nodes (art budget: 16 + the bread cat's 7, 2026-10-27)", "%d" % draw_nodes)
	# The coil reaches from the post face to the ball; the stack = K and U of the model (sum = mark without damping).
	lab._show()
	var props: SpringProps = lab.props
	var coil_end: float = props.coil.position.x + props._coil_base * props.coil.scale.x
	var k: float = lab.model.kinetic_energy()
	var u: float = lab.model.spring_energy()
	var e0: float = 0.5 * 5.0 * 1.2 * 1.2
	var stack_top: float = props.bar_spring.position.y + (props.bar_spring.scale.y if props.bar_spring.visible else 0.0)
	expect.call(absf(coil_end - (lab.ball.global_position.x - lab.BALL_RADIUS)) < 1e-4
		and absf(props.bar_kinetic.scale.y - k / e0 * SpringProps.BAR_MAX) < 1e-4 and absf(stack_top - props.bar_mark.position.y) < 2e-3,
		"spring: the coil reaches the ball; the energy stack is K (blue) + U (purple) of the formula and reaches the release-energy mark",
		"K %.3f J, U %.3f J, top %.4f / mark %.4f" % [k, u, stack_top, props.bar_mark.position.y])
	await _free(lab)


# --- 7. fresh screen --------------------------------------------------------------------------

func check_first_release_screen() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var c := _case("start")
	var waiting: Dictionary = lab.observations()
	screen.experiment_action("release")
	var worst := 0.0
	var rest_x: float = lab.ANCHOR_X + lab.REST_LENGTH
	for s in c.samples:
		var k := int(s.step)
		if k == 0 or k > 120:
			continue
		await _until(lab, k)
		worst = maxf(worst, absf(lab.ball.global_position.x - (rest_x + float(s.x))))
	var first_step_ok: bool = lab.driver.engine.size() > 1 and absf(lab.driver.engine[1].x - (rest_x + PhysicsLaws.harmonic_displacement(1.2, sqrt(5.0), 1.0 / STEP_HZ, 0.0))) < ENGINE_TOLERANCE
	expect.call(waiting.state == "놓기 전 · 공을 끌어 당겨요" and float(waiting.extension) == 1.2 and float(waiting.speed) == 0.0
		and worst <= ENGINE_TOLERANCE and first_step_ok and lab.status() == "moving",
		"spring (fresh screen): 놓기 → the engine ball follows the TS start motion from the first step", "|dx| %s m" % String.num_scientific(worst))
	await _until(lab, 240)
	var series: Dictionary = lab.graph_series()
	var sums_ok := true
	var top_kinetic := 0.0
	for i in series.kinetic.size():
		sums_ok = sums_ok and absf(series.kinetic[i].y + series.spring[i].y - 100.0) < 1e-4   # float32 points
		top_kinetic = maxf(top_kinetic, series.kinetic[i].y)
	expect.call(series.kinetic.size() >= 40 and series.spring[0].y == 100.0 and series.kinetic[0].y == 0.0 and sums_ok
		and top_kinetic > 99.0 and GraphView.y_top(lab.definition.graph, series) == 100.0,
		"spring: the graph shows the kinetic and spring shares (%) over time on a fixed 0-100 % axis: 100 % spring at the release, they trade and add to 100 %", "%d points" % series.kinetic.size())
	await _close(screen)


# --- 8. input path ----------------------------------------------------------------------------

func check_input_path() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var ball: RigidBody3D = lab.ball
	var rest_x: float = lab.ANCHOR_X + lab.REST_LENGTH
	var goal := Vector3(rest_x + 0.72, ball.global_position.y, 0.0)
	_swipe(screen, _at(screen, ball.global_position), _at(screen, goal))
	await tree.process_frame
	await tree.process_frame   # the frame's _process (coil) runs after its process_frame signal
	var held: bool = m.mode == "drag" and m.active_id == "ball" and lab.status() == "held"
	var coil_end: float = lab.props.coil.position.x + lab.props._coil_base * lab.props.coil.scale.x
	var coil_follows := absf(coil_end - (ball.global_position.x - lab.BALL_RADIUS)) < 1e-3
	_touch(screen, _at(screen, goal), false)
	await tree.process_frame
	var released: bool = lab.released and lab.pull == 0.7 and lab.model.x0 == 0.7
	expect.call(held and coil_follows and released and lab.extension_at(rest_x + 0.72) == 0.7 and lab.extension_at(rest_x + 9.0) == 2.5
		and lab.extension_at(rest_x - 9.0) == -1.5,
		"spring: dragging the ball along the rod (0.1 m grid, -1.5..2.5 m) stretches the coil with it; letting go releases it from rest there",
		"held %s, pull %.3f" % [held, lab.pull])
	var reference := SpringModel.new()
	reference.mass = 1.0
	reference.reset(0.7, 1.0, 0.0)
	var worst := 0.0
	for k in 90:
		await tree.physics_frame
		while reference.steps < lab.model.steps:
			reference.step(1.0 / STEP_HZ)
		worst = maxf(worst, absf(ball.global_position.x - reference.x))
	expect.call(worst <= ENGINE_TOLERANCE and lab.driver.worst_position <= ENGINE_TOLERANCE,
		"spring: the run after letting go follows the formula from rest at 0.7 m", "|dx| %s m" % String.num_scientific(worst))
	_swipe(screen, _at(screen, ball.global_position), _at(screen, ball.global_position + Vector3(0.02, 0, 0)), 2)
	var stopped: bool = not lab.released and lab.status() == "held"
	_touch(screen, _at(screen, ball.global_position), false)
	await tree.process_frame
	expect.call(stopped and lab.released, "spring: picking the ball up stops the run; putting it down releases it again", "")
	await _close(screen)


# --- 9. demo ----------------------------------------------------------------------------------

func check_demo() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	screen.manipulator.start_demo(0.2)
	var runs := 0
	var was := false
	var pulls := {}
	for i in 8 * STEP_HZ:
		await tree.physics_frame
		if lab.released and not was:
			runs += 1
			pulls[lab.pull] = true
		was = lab.released
	screen.manipulator.start_demo(0.0)
	expect.call(runs >= 2 and pulls.size() >= 2, "spring: the measurement demo (--auto-drag) pulls the ball to new places and lets it go", "%d runs, pulls %s" % [runs, str(pulls.keys())])
	await _close(screen)
