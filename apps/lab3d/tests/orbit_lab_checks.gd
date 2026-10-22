## Headless checks of the orbit lab (Phase 1 Task 4d), run by run_tests.gd. Expected values are the
## TS-core vectors in tests/orbit_lab_vectors.json (tools/orbit-lab-vectors.test.ts: the web's
## PointGravityField on a 1 kg planet, 8 velocity Verlet substeps at 60 Hz, and the web's
## OrbitChallenge prediction). Physics first: the engine planet is checked step by step.
## 1. definition: valid, listed, shared texts and app tip; the start = the TS circular case; GM, the
##    collision and far radii and the substeps = the vectors.
## 2. model = TS (no engine): position, velocity, radius, speeds, circular period, swept angle at every
##    sample step, outcome, first lap time and the OrbitChallenge prediction, 8 cases (rel 1e-9).
## 3. engine = TS: the lab through its own fixed steps; engine planet = TS at every sample step
##    (<= 1e-4 m), every step on the model state with its step velocity (<= 1e-4), panel = TS, also
##    the 60 s run past the history window.
## 4. Newton and Kepler from the engine planet alone: the circular orbit keeps its radius and turns in
##    2 pi sqrt(r^3 / GM) (3 m and 5 m: T^2 ~ r^3), energy kept, a launch above the escape speed leaves
##    and one below it comes back, a slow one crashes on the star's surface.
## 5. conditions: speed, direction and radius restart the run with a new prediction; "원 궤도 속력";
##    unknown ids are ignored; the panel holds only formula values.
## 6. art: visual only (bodies, the same run without reactions), draw-node budget, the path dots in
##    the prediction's colour, the guide at the start radius.
## 7. a freshly opened screen: "발사" gives the TS circular motion from the first step; the graph's
##    speed stays on the circular speed line.
## 8. the real input path: dragging the knob (5 deg, 0.1 m/s grid; preview of the path while held,
##    sliders follow) and the planet (0.5 m grid); the launch = formula.
## 9. the measurement demo (--auto-drag) drags the planet and launches.
extends RefCounted

const VECTORS_PATH := "res://tests/orbit_lab_vectors.json"
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
	await check_kepler()
	await check_conditions()
	await check_art()
	await check_first_launch_screen()
	await check_input_path()
	await check_demo()


# --- helpers ----------------------------------------------------------------------------------

func _lab() -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find("orbit"))
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


func _start(lab: Experiment, c: Dictionary) -> void:
	lab.begin_batch()
	lab.set_control("radius", float(c.radius))
	lab.set_control("direction", float(c.angle))
	lab.end_batch()
	lab.speed = float(c.speed)   # 64-bit (the 5 m case's circular speed is not on the slider's grid)
	lab.reset_run()
	lab.launch()


func _model_for(c: Dictionary) -> OrbitModel:
	var model := OrbitModel.new()
	model.mu = vectors.mu
	model.crash_radius = vectors.crash_radius
	model.far_radius = vectors.far_radius
	model.reset(c.radius, c.vx, c.vz)
	return model


func _open() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(720, 1560)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("orbit"))
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
	var definition := ExperimentRegistry.find("orbit")
	var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	var shared: Dictionary = ExperimentRegistry.shared_labs().get("orbit", {})
	expect.call(problems.is_empty() and listed.has("orbit") and definition.get("title") == shared.get("title")
		and definition.get("tip", "") == shared.get("app", {}).get("tip", "") and definition.tip.contains("노란 손잡이"),
		"orbit: definition valid, listed, texts and the app tip from the shared content", ", ".join(problems))
	var start := _case("circular")
	var defaults := {}
	for control in definition.controls:
		defaults[control.id] = control.default
	var consts: Dictionary = (load(definition.scene) as GDScript).get_script_constant_map()
	expect.call(float(defaults.radius) == float(start.radius) and float(defaults.speed) == float(start.speed) and float(defaults.direction) == float(start.angle)
		and float(consts.MU) == float(vectors.mu) and float(consts.CRASH_RADIUS) == float(vectors.crash_radius) and float(consts.FAR_RADIUS) == float(vectors.far_radius)
		and OrbitModel.SUBSTEPS == int(vectors.substeps),
		"orbit: the start = the TS circular case (3 m, 3 m/s counter-clockwise); GM 27, collision radius 1.2 m, far 12 m and the substeps = the vectors", "")


# --- 2. model = TS ----------------------------------------------------------------------------

func check_model_cases() -> void:
	var worst := 0.0
	var outcomes_ok := true
	var predicted_worst := 0.0
	var dt := 1.0 / float(vectors.step_hz)
	for c in vectors.cases:
		var model := _model_for(c)
		for s in c.samples:
			while model.steps < int(s.step):
				model.step(dt)
			for pair in [[model.x, s.x], [model.z, s.z], [model.vx, s.vx], [model.vz, s.vz], [model.radius(), s.radius], [model.speed(), s.speed],
					[model.circular_speed(), s.circular_speed], [model.escape_speed(), s.escape_speed], [model.circular_period(), s.circular_period], [model.swept, s.swept]]:
				worst = maxf(worst, _err(pair[0], pair[1]))
		outcomes_ok = outcomes_ok and model.outcome == c.outcome and (c.first_lap < 0.0 and model.first_lap_time < 0.0 or _err(model.first_lap_time, c.first_lap) <= tolerance)
		var prediction := PhysicsLaws.orbit_analyze(c.radius, 0.0, c.vx, c.vz, 0.0, 0.0, vectors.mu, vectors.crash_radius)
		var p: Dictionary = c.predicted
		outcomes_ok = outcomes_ok and prediction.outcome == p.outcome and prediction.path.size() / 2 == int(p.path_points)
		predicted_worst = maxf(predicted_worst, maxf(_err(prediction.speed, p.speed), maxf(_err(prediction.circular_speed, p.circular_speed), _err(prediction.escape_speed, p.escape_speed))))
		predicted_worst = maxf(predicted_worst, maxf(_err(prediction.path[-2], p.path_last.x), _err(prediction.path[-1], p.path_last.y)))
	expect.call(worst <= tolerance, "orbit model: position, velocity, radius, speeds, circular period and swept angle at every sample step = TS (8 cases)",
		"max rel err %s" % String.num_scientific(worst))
	expect.call(outcomes_ok and predicted_worst <= tolerance, "orbit model: outcomes (crash, far), first lap times and the OrbitChallenge prediction (outcome, speeds, path) = TS",
		"max rel err %s" % String.num_scientific(predicted_worst))
	# A clockwise launch (swept < 0) times its first lap too: the circular orbit's lap = the formula period.
	var cw := OrbitModel.new()
	var orbit_script: GDScript = load("res://experiments/orbit/orbit.gd")
	var cw_v: PackedFloat64Array = orbit_script.launch_velocity(270.0, 3.0)
	cw.reset(3.0, cw_v[0], cw_v[1])
	var ccw := OrbitModel.new()
	var ccw_v: PackedFloat64Array = orbit_script.launch_velocity(90.0, 3.0)
	ccw.reset(3.0, ccw_v[0], ccw_v[1])
	for k in 600:
		cw.step(1.0 / float(STEP_HZ))
		ccw.step(1.0 / float(STEP_HZ))
	expect.call(cw.swept < -TAU and cw.first_lap_time > 0.0 and absf(cw.first_lap_time - cw.circular_period()) < 1e-5 and absf(cw.first_lap_time - ccw.first_lap_time) < 1e-9,
		"orbit model: a clockwise launch gets its first lap time = the formula period (like the counter-clockwise one)",
		"%s s, period %s s, ccw %s s" % [cw.first_lap_time, cw.circular_period(), ccw.first_lap_time])


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
		var prediction: Dictionary = c.predicted
		for s in c.samples:
			var k := int(s.step)
			if k == 0:
				continue
			await _until(lab, k)
			if lab.model.steps != k:
				worst_x = INF
				break
			worst_x = maxf(worst_x, maxf(absf(lab.planet.global_position.x - float(s.x)), absf(lab.planet.global_position.z - float(s.z))))
			var shown: Dictionary = lab.observations()
			for pair in [[shown.radius, s.radius], [shown.speed, s.speed], [shown.period, s.circular_period], [shown.launch_speed, prediction.speed],
					[shown.circular_speed, prediction.circular_speed], [shown.escape_speed, prediction.escape_speed]]:
				worst_shown = maxf(worst_shown, _err(pair[0], pair[1]))
		worst_step_x = maxf(worst_step_x, lab.driver.worst_position)
		worst_step_v = maxf(worst_step_v, lab.driver.worst_velocity)
		if c.name == "long":
			past_history = lab.driver.engine.size() == lab.driver.history_steps and lab.model.steps > lab.driver.history_steps * 2
	expect.call(worst_x <= ENGINE_TOLERANCE, "orbit: engine planet = TS at every sample step (8 cases, 60 s run included, <= 1e-4 m)",
		"max |dx| %s m" % String.num_scientific(worst_x))
	expect.call(worst_step_x <= ENGINE_TOLERANCE and worst_step_v <= ENGINE_TOLERANCE and past_history,
		"orbit: every engine step lands on the formula state with the formula's step velocity, also past the history window (60 s)",
		"max %s m, %s m/s" % [String.num_scientific(worst_step_x), String.num_scientific(worst_step_v)])
	expect.call(worst_shown <= tolerance, "orbit: panel (radius, speed, circular period, launch / circular / escape speeds) = TS at every sample step",
		"max rel err %s" % String.num_scientific(worst_shown))
	await _free(lab)


# --- 4. Newton and Kepler from the engine planet ----------------------------------------------

## Runs a launch for `steps` steps and returns the engine positions (x, z) after every step.
func _engine_run(lab: Experiment, radius: float, launch_speed: float, direction: float, steps: int) -> PackedVector2Array:
	lab.begin_batch()
	lab.set_control("radius", radius)
	lab.set_control("direction", direction)
	lab.end_batch()
	lab.speed = launch_speed
	lab.reset_run()
	lab.launch()
	var points := PackedVector2Array([Vector2(lab.planet.global_position.x, lab.planet.global_position.z)])
	while lab.model.steps < steps:
		await tree.physics_frame
		points.append(Vector2(lab.planet.global_position.x, lab.planet.global_position.z))
	return points


## Time (s) of the first full counter-clockwise turn of engine positions (interpolated between steps).
func _engine_lap(points: PackedVector2Array) -> float:
	var swept := 0.0
	for k in range(1, points.size()):
		var turned := wrapf(atan2(-points[k].y, points[k].x) - atan2(-points[k - 1].y, points[k - 1].x), -PI, PI)
		if swept + turned >= TAU:
			return (k - 1 + (TAU - swept) / turned) / STEP_HZ
		swept += turned
	return -1.0


func check_kepler() -> void:
	var lab: Experiment = await _lab()
	var mu: float = vectors.mu
	var worst_r := 0.0
	var laps := []
	for r in [3.0, 5.0]:
		var points := await _engine_run(lab, r, sqrt(mu / r), 90.0, 60 * STEP_HZ)
		for p in points:
			worst_r = maxf(worst_r, absf(p.length() - r))
		laps.append(_engine_lap(points))
	var t3 := TAU * sqrt(27.0 / mu)
	var t5 := TAU * sqrt(125.0 / mu)
	expect.call(worst_r <= ENGINE_TOLERANCE and absf(laps[0] - t3) / t3 <= 1e-4 and absf(laps[1] - t5) / t5 <= 1e-4
		and absf(laps[1] / laps[0] - pow(5.0 / 3.0, 1.5)) <= 1e-4,
		"orbit: the engine planet on a circular orbit keeps its radius for 60 s and turns in 2 pi sqrt(r^3 / GM) at 3 m and 5 m (Kepler T^2 ~ r^3)",
		"|dr| %s m, T %.5f / %.5f s, %.5f / %.5f s" % [String.num_scientific(worst_r), laps[0], t3, laps[1], t5])
	# Energy from the engine planet alone (central-difference speed) on the ellipse.
	var points := await _engine_run(lab, 3.0, 2.4, 90.0, 30 * STEP_HZ)
	var energies := PackedFloat64Array()
	for k in range(2, points.size() - 2, 10):
		# Five-point derivative (error ~ (omega dt)^4, below the float32 position noise).
		var v := (points[k - 2] - points[k - 1] * 8.0 + points[k + 1] * 8.0 - points[k + 2]) * (STEP_HZ / 12.0)
		energies.append(v.length_squared() * 0.5 - mu / points[k].length())
	var spread := 0.0
	for e in energies:
		spread = maxf(spread, absf(e - energies[0]))
	expect.call(spread <= 1e-4 * absf(energies[0]), "orbit: the energy v^2 / 2 - GM / r of the engine planet (speed from its positions) stays the same on the ellipse for 30 s (1e-4)",
		"max |dE| %s of %.4f J/kg" % [String.num_scientific(spread), energies[0]])
	# Escape: just above the escape speed it leaves (12 m); 0.85 of it comes back.
	var v_esc := sqrt(2.0 * mu / 3.0)
	points = await _engine_run(lab, 3.0, v_esc * 1.01, 90.0, 20 * STEP_HZ)
	var escaped: bool = lab.model.outcome == "far" and lab.status() == "far" and points[-1].length() >= 11.99 and lab.observations().predicted == "이탈"
	points = await _engine_run(lab, 3.0, v_esc * 0.85, 90.0, 60 * STEP_HZ)
	var farthest := 0.0
	for p in points:
		farthest = maxf(farthest, p.length())
	var e := (v_esc * 0.85) ** 2 * 0.5 - mu / 3.0
	var a := -mu / (2.0 * e)
	var apoapsis := 2.0 * a - 3.0
	expect.call(escaped and lab.model.outcome == "" and absf(farthest - apoapsis) <= 1e-3 and points[-1].length() < farthest - 1.0 and lab.observations().predicted == "공전",
		"orbit: launched just above the escape speed sqrt(2GM / r) the engine planet leaves; at 0.85 of it it turns back at the apoapsis 2a - r",
		"farthest %.4f m vs %.4f m" % [farthest, apoapsis])
	points = await _engine_run(lab, 3.0, 1.0, 90.0, 10 * STEP_HZ)
	expect.call(lab.model.outcome == "crash" and absf(points[-1].length() - float(vectors.crash_radius)) <= ENGINE_TOLERANCE and lab.status() == "crash"
		and lab.observations().predicted == "충돌" and lab.crashes >= 1,
		"orbit: launched slowly the engine planet falls and stops on the star's surface (collision radius 1.2 m)", "r %.6f m" % points[-1].length())
	await _free(lab)


# --- 5. conditions ----------------------------------------------------------------------------

func check_conditions() -> void:
	var lab: Experiment = await _lab()
	lab.launch()
	await _until(lab, 40)
	var moved: bool = absf(lab.planet.global_position.z) > 0.5
	lab.set_control("speed", 1.5)
	var back: bool = not lab.released and is_equal_approx(lab.planet.global_position.x, 3.0) and lab.graph_series().speed.is_empty() and lab.prediction.outcome == "crash"
	lab.set_control("radius", 4.0)
	lab.run_action("circular")
	var circular: bool = lab.speed == sqrt(27.0 / 4.0) and lab.direction == 90.0 and lab.prediction.outcome == "orbit" and is_equal_approx(lab.planet.global_position.x, 4.0)
	lab.set_control("direction", 370.0)
	var wrapped: bool = lab.direction == 10.0
	lab.set_control("nope", 1.0)
	var shown: Dictionary = lab.observations()
	expect.call(moved and back and circular and wrapped and lab.status() == "ready" and shown.lap == "—",
		"orbit: speed, direction and radius change the launch and put the planet back with a new prediction; 원 궤도 속력 = sqrt(GM / r); unknown ids are ignored", "")
	var labels_ok := true
	var ids := []
	for item in lab.definition.observations:
		labels_ok = labels_ok and not str(item.label).contains("시뮬레이션")
		ids.append(item.id)
	expect.call(labels_ok and ids.all(func(id): return shown.has(id)) and ids.size() == shown.size(),
		"orbit: the panel shows only formula-model values (no 'simulation' reading of the posed engine planet)", "%d values" % ids.size())
	await _free(lab)


# --- 6. art -----------------------------------------------------------------------------------

func check_art() -> void:
	var lab: Experiment = await _lab()
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append("%s:%s" % [node.name, node.get_class()])
	bodies.sort()
	expect.call(bodies == ["Floor:StaticBody3D", "Knob:StaticBody3D", "Planet:RigidBody3D"] and lab.planet.collision_mask == 0 and lab.planet.freeze
		and lab.planet.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC,
		"orbit art adds no collision objects; the planet is kinematic and touches nothing (the formula moves it)", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.launch()
		await _until(lab, 150)
		runs.append({"p": lab.planet.global_position, "basis": lab.planet.global_basis, "obs": str(lab.observations())})
	lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(runs[0].p == runs[1].p and runs[0].obs == runs[1].obs and runs[0].basis == Basis(),
		"orbit: same motion and panel with and without the reactions; the planet's body never turns", str(runs[0].p))
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 16, "orbit: at most 16 drawn 3D nodes (art budget)", "%d" % draw_nodes)
	var props: OrbitProps = lab.props
	var colours := []
	for s in [1.0, 3.0, 4.5]:
		lab.set_control("speed", s)
		colours.append(props.path.multimesh.mesh == props._dots[lab.prediction.outcome] and props.path.multimesh.visible_instance_count > 1)
	var last_dot: Vector3 = props.dots[-1]
	expect.call(colours == [true, true, true] and lab.prediction.outcome == "escape" and is_equal_approx(last_dot.y, lab.ORBIT_Y) and props.dots.size() == props.path.multimesh.visible_instance_count
		and props._guide_radius == 3.0,
		"orbit: the predicted path dots take the prediction's colour (crash red, orbit green, escape purple) in the orbit plane; the guide circle is at the start radius",
		"%s, %s, last dot y %.3f, guide %.2f" % [str(colours), lab.prediction.outcome, last_dot.y, props._guide_radius])
	await _free(lab)


# --- 7. fresh screen --------------------------------------------------------------------------

func check_first_launch_screen() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var c := _case("circular")
	var waiting: Dictionary = lab.observations()
	# The velocity arrow keeps its length through the launch (same speed, same length) and ends at the
	# knob's near face before it.
	await tree.process_frame
	var before: float = lab.props.velocity_arrow._built_length
	var knob_gap: float = (lab.knob.global_position - lab.planet.global_position).length()
	screen.experiment_action("launch")
	await tree.process_frame
	await tree.process_frame
	var after: float = lab.props.velocity_arrow._built_length
	expect.call(lab.released and absf(before - after) < 1e-9 and absf(before - (knob_gap - lab.KNOB_SIZE * 0.5)) < 0.02 and before > 0.0,
		"orbit: the velocity arrow has the same length before and after the launch and ends at the knob's near face", "%.3f m -> %.3f m (knob %.3f m out)" % [before, after, knob_gap])
	screen.experiment_action("launch")
	var worst := 0.0
	for s in c.samples:
		var k := int(s.step)
		if k == 0 or k > 120:
			continue
		await _until(lab, k)
		worst = maxf(worst, maxf(absf(lab.planet.global_position.x - float(s.x)), absf(lab.planet.global_position.z - float(s.z))))
	var first_ok: bool = lab.driver.engine.size() > 1 and lab.driver.engine[1].z < 0.0
	expect.call(waiting.predicted == "공전" and waiting.state == "발사 전 · 예상 길을 먼저 봐요" and absf(float(waiting.circular_speed) - 3.0) < 1e-12
		and absf(float(waiting.escape_speed) - sqrt(18.0)) < 1e-12 and worst <= ENGINE_TOLERANCE and first_ok and lab.status() == "orbiting",
		"orbit (fresh screen): 발사 → the engine planet follows the TS circular orbit from the first step", "|dx| %s m" % String.num_scientific(worst))
	await _until(lab, 360)
	var series: Dictionary = lab.graph_series()
	var on_line := true
	for i in series.speed.size():
		on_line = on_line and absf(series.speed[i].y - series.circular[i].y) < 1e-4 and series.escape[i].y > series.speed[i].y
	expect.call(series.speed.size() >= 60 and on_line, "orbit: the graph shows the speed on the circular speed line, under the escape speed", "%d points" % series.speed.size())
	await _close(screen)


# --- 8. input path ----------------------------------------------------------------------------

func check_input_path() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var knob: StaticBody3D = lab.knob
	# Knob to about 4.52 m/s at 92 deg: snaps to 4.5 m/s, 90 deg; the preview turns purple (escape) while held.
	var a := deg_to_rad(92.0)
	var length: float = OrbitArrowSurface.OFFSET + 4.52 * OrbitArrowSurface.SCALE
	var goal := Vector3(3.0 + cos(a) * length, knob.global_position.y, -sin(a) * length)
	_swipe(screen, _at(screen, knob.global_position), _at(screen, goal), 10)
	await tree.process_frame
	await tree.process_frame
	var held: bool = m.mode == "drag" and m.active_id == "arrow"
	var preview_escape: bool = lab.props.path.multimesh.mesh == lab.props._dots.escape
	_touch(screen, _at(screen, goal), false)
	await tree.process_frame
	var synced: bool = screen._control_widgets.speed.slider.value == 4.5 and screen._control_widgets.direction.slider.value == 90.0
	expect.call(held and preview_escape and lab.speed == 4.5 and lab.direction == 90.0 and synced and lab.prediction.outcome == "escape",
		"orbit: dragging the knob sets the launch on the 5 deg / 0.1 m/s grid (path previewed while held, sliders follow)",
		"held %s, %.2f m/s at %.0f deg" % [held, lab.speed, lab.direction])
	var grid := OrbitArrowSurface.launch_of(PolarArrowSurface.tip_point(-37.0, 2.34, OrbitArrowSurface.OFFSET, OrbitArrowSurface.SCALE))
	var capped := OrbitArrowSurface.launch_of(PolarArrowSurface.tip_point(10.0, 9.0, OrbitArrowSurface.OFFSET, OrbitArrowSurface.SCALE))
	expect.call(grid[0] == 325.0 and grid[1] == 2.3 and capped[1] == 6.0, "orbit: knob -> (direction 0-360 deg on 5 deg, speed on 0.1 m/s cells, at most 6 m/s)", str(grid))
	screen.experiment_action("launch")
	var reference := OrbitModel.new()
	reference.reset(3.0, 4.5 * cos(PI / 2.0), -4.5)
	var worst := 0.0
	for k in 150:
		await tree.physics_frame
		while reference.steps < lab.model.steps:
			reference.step(1.0 / STEP_HZ)
		worst = maxf(worst, Vector2(lab.planet.global_position.x - reference.x, lab.planet.global_position.z - reference.z).length())
	expect.call(worst <= ENGINE_TOLERANCE and lab.model.radius() > 4.0, "orbit: the launch after dragging the knob follows the formula (leaving)", "|dx| %s m" % String.num_scientific(worst))
	# The planet along its line: 0.5 m grid, 2-5 m; the knob follows; picking it up in flight stops the
	# flight and puts it on the line under the finger.
	var planet: RigidBody3D = lab.planet
	_swipe(screen, _at(screen, planet.global_position), _at(screen, Vector3(4.1, planet.global_position.y, 0.0)), 8)
	var stopped: bool = not lab.released
	_touch(screen, _at(screen, Vector3(4.1, planet.global_position.y, 0.0)), false)
	await tree.process_frame
	await tree.process_frame
	expect.call(stopped and lab.start_radius == 4.0 and is_equal_approx(planet.global_position.x, 4.0) and screen._control_widgets.radius.slider.value == 4.0
		and is_equal_approx(knob.global_position.x, 4.0) and lab.radius_at(9.0) == 5.0 and lab.radius_at(0.0) == 2.0,
		"orbit: dragging the planet sets the start radius on the 0.5 m grid (2-5 m); the knob follows; picking it up stops a flight", "r %.2f" % lab.start_radius)
	await _close(screen)


# --- 9. demo ----------------------------------------------------------------------------------

func check_demo() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	screen.manipulator.start_demo(1.0)   # longer than the 0.4 s launch delay after a placement
	var launches := 0
	var was := false
	var radii := {}
	for i in 8 * STEP_HZ:
		await tree.physics_frame
		if lab.released and not was:
			launches += 1
			radii[lab.start_radius] = true
		was = lab.released
	screen.manipulator.start_demo(0.0)
	expect.call(launches >= 2 and radii.size() >= 2, "orbit: the measurement demo (--auto-drag) moves the planet and launches it", "%d launches, radii %s" % [launches, str(radii.keys())])
	await _close(screen)
