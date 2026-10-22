## Headless checks of the buoyancy lab (Phase 1 Task 4d), run by run_tests.gd. Expected values are the
## TS-core vectors in tests/buoyancy_lab_vectors.json (tools/buoyancy-lab-vectors.test.ts: the web's
## BuoyancyRegionLaw and UniformGravity on the 3D drum, 4 semi-implicit Euler substeps at 60 Hz, the
## web's floor rule). Physics first: the engine drum is checked step by step, not only the panel.
## 1. definition: valid, listed, shared texts and app tip; the start = the TS start case; tank and
##    drum sizes = the vectors.
## 2. model = TS (no engine): height, velocity, fraction, depth, forces at every sample step, floor
##    hits and water entries, density ratio, floating depth and judgement, 7 cases (rel 1e-9).
## 3. engine = TS: the lab through its own fixed steps; engine drum centre = TS at every sample step
##    (<= 1e-4 m), every step on the model state with its step velocity (<= 1e-4), panel = TS, also
##    the 60 s run past the history window.
## 4. Archimedes from the engine drum alone: it floats at rho / rho_water of its height (buoyant force
##    = weight), the same share for the same density in the smaller drum, a denser one rests on the
##    tank floor fully under water, a neutral one stays where it stopped under water.
## 5. conditions: mass and volume (the drum's shape) restart the run; unknown ids are ignored; the panel
##    holds only formula values.
## 6. art: visual only (bodies, the same run without reactions), draw-node budget, the water ring and
##    the force arrows follow the formula.
## 7. a freshly opened screen: "놓기" gives the TS start motion from the first step, a splash on the
##    TS entry step; graph depth and the floating level.
## 8. the real input path: dragging the drum down into the water (0.05 m grid, upright while held) and
##    letting go releases it from rest there; the run = formula.
## 9. the measurement demo (--auto-drag) drags the drum and releases it.
extends RefCounted

const VECTORS_PATH := "res://tests/buoyancy_lab_vectors.json"
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
	await check_archimedes()
	await check_conditions()
	await check_art()
	await check_first_release_screen()
	await check_input_path()
	await check_demo()


# --- helpers ----------------------------------------------------------------------------------

func _lab() -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find("buoyancy"))
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


func _volume_id(c: Dictionary) -> String:
	return "big" if float(c.volume) == 0.1 else "small"


func _start(lab: Experiment, c: Dictionary) -> void:
	lab.begin_batch()
	lab.set_control("mass", float(c.mass))
	lab.set_control("volume", _volume_id(c))
	lab.start_bottom = float(c.centre) - float(c.height) * 0.5
	lab.end_batch()
	lab.reset_run()
	lab.release()


func _model_for(c: Dictionary) -> BuoyancyModel:
	var model := BuoyancyModel.new()
	model.mass = c.mass
	model.displaced_mass = c.displaced_mass
	model.height = c.height
	model.waterline = vectors.waterline
	model.floor_y = vectors.floor
	model.g = vectors.g
	model.drag = vectors.drag
	model.reset(c.centre, 0.0, 0.0)
	return model


func _sample_error(values: Dictionary, s: Dictionary) -> float:
	var worst := 0.0
	worst = maxf(worst, _err(values.depth, s.depth))
	worst = maxf(worst, _err(values.buoyant, s.buoyant))
	worst = maxf(worst, _err(values.weight, s.weight))
	worst = maxf(worst, _err(values.net, s.net))
	worst = maxf(worst, _err(values.speed, absf(float(s.vy))))
	return worst


func _open() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(720, 1560)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("buoyancy"))
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
	var definition := ExperimentRegistry.find("buoyancy")
	var problems := ExperimentRegistry.validate(definition) if not definition.is_empty() else PackedStringArray(["missing"])
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	var shared: Dictionary = ExperimentRegistry.shared_labs().get("buoyancy", {})
	expect.call(problems.is_empty() and listed.has("buoyancy") and definition.get("title") == shared.get("title")
		and definition.get("tip", "") == shared.get("app", {}).get("tip", "") and definition.tip.contains("부력"),
		"buoyancy: definition valid, listed, texts and the app tip from the shared content", ", ".join(problems))
	var start := _case("start")
	var small := _case("small same density")
	var defaults := {}
	var options := {}
	for control in definition.controls:
		defaults[control.id] = control.default
		for option in control.get("options", []):
			options[option.id] = option
	var consts: Dictionary = (load(definition.scene) as GDScript).get_script_constant_map()
	var model := BuoyancyModel.new()
	expect.call(float(defaults.mass) == float(start.mass) and defaults.volume == "big" and float(options.big.volume) == float(start.volume)
		and float(options.big.height) == float(start.height) and float(options.small.volume) == float(small.volume) and float(options.small.height) == float(small.height)
		and float(consts.WATERLINE) == float(vectors.waterline) and float(consts.FLOOR_Y) == float(vectors.floor)
		and float(consts.WATERLINE) + float(consts.START_ABOVE) + float(start.height) * 0.5 == float(start.centre)
		and float(consts.WATER_DENSITY) == float(vectors.water_density) and model.drag == float(vectors.drag) and BuoyancyModel.SUBSTEPS == int(vectors.substeps)
		and BuoyancyModel.FLOOR_RESTITUTION == float(vectors.restitution) and BuoyancyModel.REBOUND_MIN == float(vectors.rebound_min),
		"buoyancy: the start = the TS start case (100 L, 70 kg, 0.3 m above the water); tank, drums, drag, substeps and floor rule = the vectors", "")


# --- 2. model = TS ----------------------------------------------------------------------------

func check_model_cases() -> void:
	var worst := 0.0
	var counts_ok := true
	var formula_worst := 0.0
	var dt := 1.0 / float(vectors.step_hz)
	for c in vectors.cases:
		var model := _model_for(c)
		var hits := 0
		var entries := 0
		for s in c.samples:
			while model.steps < int(s.step):
				model.step(dt)
				hits += 1 if model.hit_floor else 0
				entries += 1 if model.entered else 0
			worst = maxf(worst, maxf(_err(model.y, s.y), _err(model.vy, s.vy)))
			worst = maxf(worst, _err(model.fraction(), s.fraction))
			worst = maxf(worst, _sample_error({"depth": model.depth(), "buoyant": model.buoyant_force(), "weight": model.weight(),
				"net": model.net_force(), "speed": absf(model.vy)}, s))
		counts_ok = counts_ok and hits == int(c.floor_hits) and entries == int(c.entries) and model.judgement() == c.judgement
		formula_worst = maxf(formula_worst, maxf(_err(model.density_ratio(), c.density_ratio), _err(model.floating_depth(), c.floating_depth)))
		formula_worst = maxf(formula_worst, _err(PhysicsLaws.density(model.mass, float(c.volume)), c.density))
	expect.call(worst <= tolerance and counts_ok, "buoyancy model: height, velocity, fraction, depth, forces at every sample step, floor hits and water entries = TS (7 cases)",
		"max rel err %s" % String.num_scientific(worst))
	expect.call(formula_worst <= tolerance, "buoyancy model: density, rho / rho_water, floating depth and judgement (floats / neutral / sinks) = TS",
		"max rel err %s" % String.num_scientific(formula_worst))


# --- 3. engine = TS ---------------------------------------------------------------------------

func check_engine_cases() -> void:
	var lab: Experiment = await _lab()
	var worst_y := 0.0
	var worst_shown := 0.0
	var worst_step_x := 0.0
	var worst_step_v := 0.0
	var past_history := false
	var formula_shown := 0.0
	for c in vectors.cases:
		_start(lab, c)
		for s in c.samples:
			var k := int(s.step)
			if k == 0:
				continue
			await _until(lab, k)
			if lab.model.steps != k:
				worst_y = INF
				break
			worst_y = maxf(worst_y, absf(lab.drum.global_position.y - float(s.y)))
			worst_shown = maxf(worst_shown, _sample_error(lab.observations(), s))
		var shown: Dictionary = lab.observations()
		formula_shown = maxf(formula_shown, maxf(_err(shown.density, c.density), _err(shown.floating_depth, c.floating_depth)))
		worst_step_x = maxf(worst_step_x, lab.driver.worst_position)
		worst_step_v = maxf(worst_step_v, lab.driver.worst_velocity)
		if c.name == "long":
			past_history = lab.driver.engine.size() == lab.driver.history_steps and lab.model.steps > lab.driver.history_steps * 5
	expect.call(worst_y <= ENGINE_TOLERANCE, "buoyancy: engine drum centre = TS at every sample step (7 cases, 60 s run included, <= 1e-4 m)",
		"max |dy| %s m" % String.num_scientific(worst_y))
	expect.call(worst_step_x <= ENGINE_TOLERANCE and worst_step_v <= ENGINE_TOLERANCE and past_history,
		"buoyancy: every engine step lands on the formula state with the formula's step velocity, also past the history window (60 s)",
		"max %s m, %s m/s" % [String.num_scientific(worst_step_x), String.num_scientific(worst_step_v)])
	expect.call(worst_shown <= tolerance and formula_shown <= tolerance, "buoyancy: panel (depth, buoyant force, weight, net force, speed, density, floating depth) = TS",
		"max rel err %s" % String.num_scientific(maxf(worst_shown, formula_shown)))
	await _free(lab)


# --- 4. Archimedes from the engine drum -------------------------------------------------------

func _settle(lab: Experiment, mass: float, volume: String, bottom: float, steps: int) -> void:
	lab.begin_batch()
	lab.set_control("mass", mass)
	lab.set_control("volume", volume)
	lab.start_bottom = bottom
	lab.end_batch()
	lab.reset_run()
	lab.release()
	await _until(lab, steps)


## Depth of the engine drum's bottom below the waterline (m), from its centre.
func _engine_depth(lab: Experiment) -> float:
	return lab.WATERLINE - (lab.drum.global_position.y - lab.drum_height() * 0.5)


func check_archimedes() -> void:
	var lab: Experiment = await _lab()
	var g: float = vectors.g
	await _settle(lab, 70.0, "big", lab.WATERLINE + 0.3, 40 * STEP_HZ)
	var big_depth := _engine_depth(lab)
	var big_ok: bool = absf(big_depth - 0.7 * 0.5) <= ENGINE_TOLERANCE and lab.status() == "floating"
	var buoyant := 1000.0 * g * 0.1 * big_depth / 0.5
	await _settle(lab, 35.0, "small", lab.WATERLINE + 0.3, 40 * STEP_HZ)
	var small_share := _engine_depth(lab) / 0.4
	await _settle(lab, 20.0, "big", lab.FLOOR_Y, 60 * STEP_HZ)
	var light_ok: bool = absf(_engine_depth(lab) - 0.2 * 0.5) <= ENGINE_TOLERANCE
	expect.call(big_ok and absf(buoyant - 70.0 * g) <= 70.0 * g * 1e-3 and absf(small_share - 0.7) <= ENGINE_TOLERANCE * 3.0 and light_ok,
		"buoyancy: the engine drum floats at rho / rho_water of its height (70 kg in 100 L: 0.35 m, buoyant force = weight), the same share in 50 L at the same density, 20 kg from the floor at 0.1 m",
		"0.35 m vs %.6f m, small share %.6f, F_b %.2f N vs mg %.2f N" % [big_depth, small_share, buoyant, 70.0 * g])
	await _settle(lab, 150.0, "big", lab.WATERLINE + 0.3, 10 * STEP_HZ)
	var bottom: float = lab.drum.global_position.y - 0.25
	expect.call(absf(bottom - lab.FLOOR_Y) <= ENGINE_TOLERANCE and lab.status() == "sunk" and lab.observations().judgement == "가라앉음 (물보다 무거움)",
		"buoyancy: a drum denser than water (150 kg in 100 L) sinks and rests on the tank floor, fully under water", "bottom %.6f m" % bottom)
	await _settle(lab, 100.0, "big", lab.FLOOR_Y + 0.4, 6 * STEP_HZ)
	var y0: float = lab.drum.global_position.y
	await _until(lab, 12 * STEP_HZ)
	expect.call(absf(lab.drum.global_position.y - y0) <= ENGINE_TOLERANCE and lab.status() == "staying" and absf(float(lab.observations().net)) < 1e-9,
		"buoyancy: a drum as dense as water released under water stays where it is (no net force)", "moved %s m" % String.num_scientific(absf(lab.drum.global_position.y - y0)))
	# Touching the tank floor does not make it "sunk": the judgement (the densities) decides, so a neutral drum
	# on the floor is staying.
	await _settle(lab, 100.0, "big", lab.FLOOR_Y, 6 * STEP_HZ)
	var floor_bottom: float = lab.drum.global_position.y - 0.25
	expect.call(absf(floor_bottom - lab.FLOOR_Y) <= ENGINE_TOLERANCE and lab.model.judgement() == "neutral" and lab.status() == "staying",
		"buoyancy: a drum as dense as water resting on the tank floor is staying, not sunk (the densities decide)", "status %s, bottom %.6f m" % [lab.status(), floor_bottom])
	await _free(lab)


# --- 5. conditions ----------------------------------------------------------------------------

func check_conditions() -> void:
	var lab: Experiment = await _lab()
	lab.release()
	await _until(lab, 40)
	var start_y: float = lab.WATERLINE + lab.START_ABOVE + 0.25
	var moved: bool = absf(lab.drum.global_position.y - start_y) > 0.1
	lab.set_control("mass", 50.0)
	var back: bool = not lab.released and is_equal_approx(lab.drum.global_position.y, start_y) and lab.graph_series().depth.is_empty()
	lab.set_control("volume", "small")
	var shape: CylinderShape3D = lab._shape
	var resized: bool = is_equal_approx(shape.height, 0.4) and absf(PI * shape.radius * shape.radius * shape.height - 0.05) < 1e-6 \
		and is_equal_approx(lab.drum.global_position.y, lab.WATERLINE + lab.START_ABOVE + 0.2)
	lab.set_control("volume", "barrel")
	lab.set_control("nope", 1.0)
	var shown: Dictionary = lab.observations()
	expect.call(moved and back and resized and lab.volume_id == "small" and float(shown.density) == 1000.0 and shown.judgement == "물속에 머묾 (물과 같음)"
		and lab.status() == "ready" and absf(float(shown.floating_depth) - 0.4) < 1e-12,
		"buoyancy: mass and volume change the conditions (the drum's shape too) and put it back; unknown ids are ignored", "")
	var labels_ok := true
	var ids := []
	for item in lab.definition.observations:
		labels_ok = labels_ok and not str(item.label).contains("시뮬레이션")
		ids.append(item.id)
	expect.call(labels_ok and ids.all(func(id): return shown.has(id)) and ids.size() == shown.size(),
		"buoyancy: the panel shows only formula-model values (no 'simulation' reading of the posed engine drum)", "%d values" % ids.size())
	await _free(lab)


# --- 6. art -----------------------------------------------------------------------------------

func check_art() -> void:
	var lab: Experiment = await _lab()
	var bodies: Array[String] = []
	for node in lab.find_children("*", "CollisionObject3D", true, false):
		bodies.append("%s:%s" % [node.name, node.get_class()])
	bodies.sort()
	expect.call(bodies == ["Drum:RigidBody3D", "Floor:StaticBody3D", "TankFloor:StaticBody3D"] and lab.drum.collision_mask == 0 and lab.drum.freeze
		and lab.drum.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC,
		"buoyancy art adds no collision objects; the drum is kinematic and touches nothing (the formula moves it)", ", ".join(bodies))
	var runs := []
	for with_juice in [true, false]:
		lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT if with_juice else Node.PROCESS_MODE_DISABLED
		lab.release()
		await _until(lab, 150)
		runs.append({"y": lab.drum.global_position.y, "basis": lab.drum.global_basis, "obs": str(lab.observations())})
	lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(runs[0].y == runs[1].y and runs[0].obs == runs[1].obs and runs[0].basis == Basis(),
		"buoyancy: same motion and panel with and without the reactions; the drum's body never turns", str(runs[0].y))
	var draw_nodes := lab.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(draw_nodes <= 16, "buoyancy: at most 16 drawn 3D nodes (art budget)", "%d" % draw_nodes)
	# Floating partly under water: the ring sits on the waterline; the arrows = the formula forces.
	lab._process(0.0)
	var props: BuoyancyProps = lab.props
	var full: float = lab.model.displaced_mass * lab.model.g
	var weight_len: float = props.weight_arrow._built_length
	var buoyant_len: float = props.buoyant_arrow._built_length
	expect.call(props.ring.visible and is_equal_approx(props.ring.position.y, lab.WATERLINE)
		and absf(weight_len - maxf(VelocityArrow.MIN_LENGTH, snappedf(lab.model.weight() / full * BuoyancyProps.ARROW_PER_FULL, 0.02))) < 1e-6
		and absf(buoyant_len - maxf(VelocityArrow.MIN_LENGTH, snappedf(lab.model.buoyant_force() / full * BuoyancyProps.ARROW_PER_FULL, 0.02))) < 1e-6,
		"buoyancy: the water ring sits on the waterline around a floating drum; the weight and buoyant force arrows = the formula forces",
		"weight %.2f m, buoyant %.2f m" % [weight_len, buoyant_len])
	await _free(lab)


# --- 7. fresh screen --------------------------------------------------------------------------

func check_first_release_screen() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var c := _case("start")
	var waiting: Dictionary = lab.observations()
	screen.experiment_action("release")
	var worst := 0.0
	var entry_step := -1
	var reference := _model_for(c)
	for k in range(1, 121):
		await _until(lab, k)
		reference.step(1.0 / STEP_HZ)
		if reference.entered and entry_step < 0:
			entry_step = k
		worst = maxf(worst, absf(lab.drum.global_position.y - reference.y))
	for s in c.samples:
		if int(s.step) == 120:
			worst = maxf(worst, absf(lab.drum.global_position.y - float(s.y)))
	expect.call(waiting.state == "놓기 전 · 통을 끌어 물에 넣어요" and float(waiting.depth) == 0.0 and worst <= ENGINE_TOLERANCE and lab.splashes == 1 and entry_step > 0,
		"buoyancy (fresh screen): 놓기 → the engine drum follows the TS start motion from the first step, one splash on entering the water",
		"|dy| %s m, entry step %d" % [String.num_scientific(worst), entry_step])
	await _until(lab, 300)
	var series: Dictionary = lab.graph_series()
	expect.call(series.depth.size() >= 50 and series.depth[0].y == 0.0 and series.floating.size() == 2 and is_equal_approx(series.floating[0].y, 0.35)
		and absf(series.depth[-1].y - 0.35) < 0.05,
		"buoyancy: the graph shows the submerged depth over time approaching the formula's floating depth line", "%d points" % series.depth.size())
	await _close(screen)


# --- 8. input path ----------------------------------------------------------------------------

func check_input_path() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var drum: RigidBody3D = lab.drum
	var goal := Vector3(0.0, 0.82, 0.0)
	_swipe(screen, _at(screen, drum.global_position), _at(screen, goal), 12)
	await tree.process_frame
	var held: bool = m.mode == "drag" and m.active_id == "drum" and lab.status() == "held" and drum.global_basis == Basis()
	_touch(screen, _at(screen, goal), false)
	await tree.process_frame
	var placed: bool = lab.released and absf(lab.start_bottom - 0.55) < 1e-12 and lab.model.steps <= 1
	expect.call(held and placed and lab.bottom_at(0.83) == 0.6 and lab.bottom_at(9.0) == lab.WATERLINE + lab.HOLD_ABOVE and lab.bottom_at(-3.0) == lab.FLOOR_Y,
		"buoyancy: dragging the drum down into the water (0.05 m grid, upright while held) and letting go releases it from rest there",
		"held %s, bottom %.3f m" % [held, lab.start_bottom])
	var reference := BuoyancyModel.new()
	reference.reset(0.55 + 0.25, 0.0, 0.0)
	var worst := 0.0
	for k in 120:
		await tree.physics_frame
		while reference.steps < lab.model.steps:
			reference.step(1.0 / STEP_HZ)
		worst = maxf(worst, absf(drum.global_position.y - reference.y))
	expect.call(worst <= ENGINE_TOLERANCE and lab.driver.worst_position <= ENGINE_TOLERANCE and drum.global_position.y > 0.8 + 0.1,
		"buoyancy: the drum let go under water rises by the formula", "|dy| %s m" % String.num_scientific(worst))
	await _close(screen)


# --- 9. demo ----------------------------------------------------------------------------------

func check_demo() -> void:
	var screen: Control = await _open()
	var lab: Experiment = screen.experiment
	screen.manipulator.start_demo(0.2)
	var runs := 0
	var was := false
	var bottoms := {}
	for i in 8 * STEP_HZ:
		await tree.physics_frame
		if lab.released and not was:
			runs += 1
			bottoms[lab.start_bottom] = true
		was = lab.released
	screen.manipulator.start_demo(0.0)
	expect.call(runs >= 2 and bottoms.size() >= 2, "buoyancy: the measurement demo (--auto-drag) drags the drum to new heights and lets it go", "%d runs, bottoms %s" % [runs, str(bottoms.keys())])
	await _close(screen)
