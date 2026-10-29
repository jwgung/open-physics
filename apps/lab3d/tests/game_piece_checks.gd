## The piece game (2026-10-29 user: "실제 실험을 통해서 조각을 꺼내거나, 받거나 하는 식이면 좋겠어 …
## 게임스럽게 녹여내자"): batch A, six labs. Per lab the stage's game is judged on the formula (the
## physics is not changed: tests/lab_mission_checks.gd compares every step with and without the round):
## - the judge functions: the projectile's crate hit (the formula path against the crate's box), the
##   collision's speed of B after the hit (CollisionModel), the free fall's landing together
##   (|√(2h₁/g) − √(2h₂/g)| ≤ one step), the slide's speed at its end (v = √(2ad)), the spring's
##   period near the beat (T = 2π√(m/k), the same for every pull), MissionTracker's "near" / "also";
## - each stage reachable with its fitting picture buttons (or throws) and not with a non-fitting one
##   where that is the lesson;
## - the piece in its object from the start, still there after stages 1 and 2, released by the last
##   stamp only, and handed to the bread cat from where it lies; a finished spot has no piece.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const TABLET := Vector2(1152, 720)
const GOALS := "res://tests/goal_mission_checks.gd"
const PIECE_LABS := ["projectile", "collision", "free-fall", "friction", "incline-friction", "spring", "rotation", "pulley", "constraints", "buoyancy", "orbit"]


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_tracker_near_also()
	await check_projectile()
	await check_projectile_round()
	await check_collision()
	await check_free_fall()
	await check_incline()
	await check_spring()
	await check_lever()
	await check_pulley()
	await check_pendulum_beat()
	await check_drum()
	await check_orbit_piece()
	await check_pieces()
	await check_found_piece_flies()
	check_words()


# --- helpers ---------------------------------------------------------------------------------------

func _goals() -> GDScript:
	return load(GOALS)


## The stage's rule beaten by `value` (shown number) for a stage's main observe.
func _beats(definition: Dictionary, stage: int, value: float) -> bool:
	var entry: Dictionary = MissionTracker.missions(definition).stages[stage]
	var how := MissionTracker.rule(definition, stage)
	return MissionTracker.beats(definition, how.observe, how.compare, entry, {how.observe: value})


func _lab(id: String) -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find(id))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _open(definition: Dictionary) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame
		await tree.process_frame


# --- MissionTracker: near and also ------------------------------------------------------------------

func check_tracker_near_also() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var definition := {"id": "near-test", "observations": [{"id": "t", "digits": 2}, {"id": "x", "digits": 2}],
		"missions": {"observe": "t", "judge_on": ["moving"], "stages": [
			{"compare": "near", "threshold": 2.8, "tolerance": 0.2, "also": [{"observe": "x", "compare": "greater", "threshold": 2.0}], "text": "a"},
			{"compare": "near", "threshold": 4.9, "tolerance": 0.2, "text": "b"},
			{"compare": "near", "threshold": 2.8, "tolerance": 0.2, "also": [{"observe": "x", "compare": "greater", "threshold": 0.05}, {"observe": "x", "compare": "less", "threshold": 1.0}], "text": "c"}]}}
	var lab := Experiment.new()
	tree.root.add_child(lab)
	var tracker := MissionTracker.new()
	tracker.definition = definition
	var seen := []
	for case in [[2.81, 1.2], [3.44, 2.4], [2.81, 2.0], [2.81, 2.1], [4.44, 1.0], [5.26, 1.0], [4.87, 1.0], [2.81, 1.5], [2.81, 0.0], [2.81, 0.6]]:
		seen.append(tracker.on_run_ended("moving", lab, {"t": case[0], "x": case[1]}))
	# The edges as shown (one decimal): 2.6 and 3.0 are near 2.8 (±0.2), 2.5 and 3.1 are not.
	var edges := [2.6, 3.0, 2.54, 3.06].map(func(v: float) -> bool:
		return MissionTracker.beats(definition, "t", "near", definition.missions.stages[0], {"t": v}))
	lab.free()
	DirAccess.remove_absolute(ProgressStore.path)
	var registry := ExperimentRegistry._validate_missions({"observe": "t", "stages": [{"compare": "near", "threshold": 2.8, "text": "a"}]}, definition.observations)
	var registry_also := ExperimentRegistry._validate_missions({"observe": "t", "stages": [{"threshold": 2.8, "also": [{"observe": "nope", "threshold": 1.0}], "text": "a"}]}, definition.observations)
	expect.call(seen == [false, false, false, true, false, false, true, false, false, true] and tracker.stamps == 3
		and edges == [true, true, false, false] and not registry.is_empty() and not registry_also.is_empty(),
		"piece game: a stage's \"near\" holds within its tolerance of the shown number and every \"also\" rule must hold too (the pull past 2 m with the 2.8 s beat; the 4.9 s beat; a little pull with the 2.8 s beat); the registry wants a tolerance and known also ids",
		"%s, edges %s, registry %s / %s" % [str(seen), str(edges), str(registry), str(registry_also)])


# --- projectile: hit the crate ----------------------------------------------------------------------

func check_projectile() -> void:
	var definition := ExperimentRegistry.find("projectile")
	var lab: Experiment = await _lab("projectile")
	var problems := []
	# The speed is fixed (2026-10-29 "세기는 고정하는거로 하자"): no speed control, the lab throws 8 m/s.
	if definition.controls.any(func(c: Dictionary) -> bool: return c.id == "speed") or absf(lab.speed - 8.0) > 1e-12:
		problems.append("the speed is not fixed at 8 m/s (%s)" % lab.speed)
	var bands := [[], [], []]
	for angle in range(0, 91, 5):
		lab.set_control("angle", float(angle))
		var values: Dictionary = lab.observations()
		for i in 3:
			var hit: bool = _beats(definition, i, float(values["hit_%d" % (i + 1)]))
			if hit != is_finite(lab.hit_times()[i]):
				problems.append("%d° crate %d: judged %s, hit time %s" % [angle, i + 1, hit, lab.hit_times()[i]])
			if hit:
				bands[i].append(angle)
	# Three angle bands: low (near crate), slanted (far crate), steep (high crate); no angle hits two.
	var want := [[0, 5, 10, 15, 20, 80], [35, 40, 45, 50, 55], [60, 65, 70]]
	if bands != want:
		problems.append("bands %s (want %s)" % [str(bands), str(want)])
	for i in 3:
		for j in range(i + 1, 3):
			if (bands[i] as Array).any(func(a: int) -> bool: return a in bands[j]):
				problems.append("an angle hits crates %d and %d" % [i + 1, j + 1])
	# The slingshot sets the angle only: a short and a long pull the same way throw the same 8 m/s.
	var spec: Dictionary = lab.slingshot_setup()
	var value: Callable = spec.get("value", Callable())
	var short: Vector2 = value.call(Vector2(-0.4, 0.4)) if value.is_valid() else Vector2.ZERO   # pulled down-left (plane z = world down)
	var long: Vector2 = value.call(Vector2(-1.6, 1.6)) if value.is_valid() else Vector2.ZERO
	if spec.controls != ["angle"] or short != long or absf(short.y - 8.0) > 1e-9 or absf(short.x - 45.0) > 1e-9:
		problems.append("slingshot: controls %s, short pull %s, long pull %s" % [str(spec.get("controls")), short, long])
	if lab.angle_words(Vector2(10.0, 8.0)) != "낮게" or lab.angle_words(Vector2(45.0, 8.0)) != "비스듬히" or lab.angle_words(Vector2(65.0, 8.0)) != "높이":
		problems.append("the readout words")
	# The judge function itself: a straight path along y = 1 hits a crate exactly when the ball's edge
	# reaches its box (no gravity); a level path just over the top by more than the radius misses.
	var box := ProjectileGame.target_box(1)
	var r := 0.25
	var t_side := ProjectileGame.hit_time(1, Vector2(box.position.x - 2.0, box.position.y + 0.3), 2.0, 0.0, 0.0, r, 5.0)
	var over := ProjectileGame.hit_time(1, Vector2(box.position.x - 2.0, box.end.y + r + 0.01), 2.0, 0.0, 0.0, r, 5.0)
	var grazing := ProjectileGame.hit_time(1, Vector2(box.position.x - 2.0, box.end.y + r - 0.01), 2.0, 0.0, 0.0, r, 5.0)
	var before_end := ProjectileGame.hit_time(1, Vector2(box.position.x - 2.0, box.position.y + 0.3), 2.0, 0.0, 0.0, r, 0.5)
	if absf(t_side - (2.0 - r) / 2.0) > ProjectileGame.SAMPLE_DT + 1e-9 or is_finite(over) or not is_finite(grazing) or is_finite(before_end):
		problems.append("hit_time: side %.4f (want %.4f), over %s, grazing %s, cut at 0.5 s %s" % [t_side, (2.0 - r) / 2.0, over, grazing, before_end])
	lab.queue_free()
	expect.call(problems.is_empty(),
		"piece game (throw, the angle game): the speed is fixed at 8 m/s and the slingshot sets only the angle; crate n is hit when the formula path (x0 + vx t, y0 + vy t − ½gt²) comes within the ball's radius of its box before the landing: the near crate by low throws (0–20°, and 80°), the far one by slanted ones (35–55°), the high one on the branch by steep ones (60–70°), no angle hits two",
		"; ".join(problems))


## The throw round on the real screen: a miss earns nothing and leaves the crates; a hit on the
## stage's crate tips it at the formula time and stamps at the landing; the piece stays on the high
## crate until its hit, which drops it on g.
func check_projectile_round() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _open(ExperimentRegistry.find("projectile"))
	screen._end_question()
	var lab: Experiment = screen.experiment
	var game: ProjectileGame = lab.game
	var problems := []
	var piece_start: Vector3 = game.piece.global_position
	var throws := [[30.0, 8.0, 0], [10.0, 8.0, 1], [10.0, 8.0, 1], [45.0, 8.0, 2], [65.0, 8.0, 3]]
	for throw in throws:
		screen._set_control("angle", throw[0])
		screen.experiment_action("release")
		var tipped_at := -1.0
		for k in 240:
			await tree.physics_frame
			await tree.process_frame
			var i: int = mini(screen._missions.stamps, 2)
			if tipped_at < 0.0 and game._tipped[mini(throw[2], 3) - 1 if throw[2] > 0 else 0] and throw[2] > 0:
				tipped_at = lab.clock()
			if screen._missions.stamps >= throw[2] and lab.status() in ["landed", "out", "fence"] and k > 60:
				break
		var stamps: int = screen._missions.stamps
		if stamps != throw[2]:
			problems.append("%s: stamps %d (want %d)" % [str(throw), stamps, throw[2]])
		if throw[2] > 0 and throw != throws[2]:
			var want: float = lab.hit_times()[throw[2] - 1]
			if tipped_at < 0.0 or tipped_at < want - 1e-9 or tipped_at > want + 2.0 / 60.0:
				problems.append("%s: crate %d tipped at %.3f s (the formula hit %.3f s)" % [str(throw), throw[2], tipped_at, want])
		if stamps < 3 and (game.piece_state != "held" or game.piece.global_position.distance_to(piece_start) > 1e-4):
			problems.append("%s: the piece left the high crate early" % str(throw))
		if throw[2] == 0 and game._tipped.has(true):
			problems.append("a miss tipped a crate")
	await _frames(20)
	var fell: bool = game.piece_state in ["flying", "out"]
	await _frames(90)
	var rest: Vector3 = game.piece.global_position
	if not (fell and game.piece_state == "out" and absf(rest.y - game.piece_size) < 0.06):
		problems.append("the high crate's hit did not drop the piece to the ground (%s at %s)" % [game.piece_state, rest])
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(),
		"piece game (throw): a miss (30°) earns nothing; a hit on the stage's crate tips it at the formula hit time and the landing stamps it (near 10° → far 45° → high 65°); the same throw again earns nothing; the piece rides the high crate until that hit drops it to the ground",
		"; ".join(problems))


# --- collision: a hard enough push on the orange ball breaks the ice --------------------------------

## The push the orange ball B gets in the first hit, J_B = m_B Δv_B (the lab's own CollisionModel run:
## its starts, the rolling balls, rubber, B coming at −1.7 m/s), read when the lab reports the hit.
func impulse_b(lab: Experiment, ma: float, mb: float, va: float) -> float:
	lab.set_control("mass_a", ma)
	lab.set_control("mass_b", mb)
	lab.set_control("velocity_a", va)
	lab.run_action("release")
	for k in 600:
		await tree.physics_frame
		if lab.status() == "collided":
			var values: Dictionary = lab.observations()
			var closed: float = (1.0 + values.restitution) * ma * mb / (ma + mb) * (values.before_a - values.before_b)
			if absf(values.impulse_b - closed) > 1e-6 or absf(values.impulse_b - mb * (values.after_b - values.before_b)) > 1e-6:
				return NAN   # not J = Δp = (1 + e) m_A m_B / (m_A + m_B) (u_A − u_B)
			return values.impulse_b
	return -INF


func check_collision() -> void:
	var definition := ExperimentRegistry.find("collision")
	var stages: Array = MissionTracker.missions(definition).stages
	var lab: Experiment = await _lab("collision")
	var problems := []
	var pulls := []   # the slowest pull (0.5 m/s grid, from 5 m/s) that clears each stage with its fitting balls
	for i in stages.size():
		var want: Dictionary = stages[i].conditions
		var ma := float(want.mass_a.get("min", 1.0)) if want.mass_a is Dictionary else float(want.mass_a)
		var mb := float(want.mass_b)
		var first := -1.0
		for k in range(10, 19):
			var j: float = await impulse_b(lab, ma, mb, 0.5 * k)
			if is_nan(j):
				problems.append("J_B is not m_B Δv_B = (1 + e) μ Δu at %s on %s" % [ma, mb])
			if _beats(definition, i, j):
				first = 0.5 * k
				break
		pulls.append(first)
	# The lesson's other buttons never get there, even at the fastest pull (9 m/s): a lighter orange ball
	# (stage 1), a light blue ball or a lighter orange one (stage 2), a lighter orange or a light blue (stage 3).
	var never := [[0, 1.0, 0.5], [1, 1.0, 1.0], [1, 3.0, 0.5], [2, 3.0, 1.0], [2, 3.0, 0.5], [2, 1.0, 2.0]]
	for case in never:
		var j: float = await impulse_b(lab, case[1], case[2], 9.0)
		if _beats(definition, case[0], j):
			problems.append("stage %d: %s kg on %s kg at 9 m/s gets there (%.2f)" % [case[0] + 1, case[1], case[2], j])
	if _beats(definition, 0, await impulse_b(lab, 1.0, 2.0, 3.4)):
		problems.append("the start clears stage 1")
	lab.queue_free()
	# The kid card is a bar (no N·s on the kid screen), the number lives in 자세히.
	if ExperimentRegistry.card_bar(definition, "impulse_b") <= 0.0 or ExperimentRegistry.shown_cards(definition, 0) != ["impulse_b"]:
		problems.append("the impulse card is not a bar")
	expect.call(problems.is_empty() and pulls == [6.5, 8.0, 7.5],
		"piece game (bump): the ice cracks when the orange ball gets a push J_B = m_B Δv_B = (1 + e) m_A m_B / (m_A + m_B) Δu past 6.5 → 12 → 18 N·s: two 1 kg balls from a 6.5 m/s pull, a 3 kg blue on 1 kg from 8, a 3 kg blue on the 2 kg orange from 7.5; never a lighter orange or a light blue, even at 9 m/s; the kid card is a bar",
		"pulls %s; %s" % [str(pulls), "; ".join(problems)])


# --- free fall: two balls together on their buttons ------------------------------------------------------

func check_free_fall() -> void:
	var definition := ExperimentRegistry.find("free-fall")
	var goals := _goals()
	var heights: Array = goals.call("grid", definition, "height")
	var problems := []
	var lab: Experiment = await _lab("free-fall")
	# The lab's value: the common formula landing when the two land within one step, else words.
	var together := func(world: String, mass: String, h_red: float, h_yellow: float) -> Variant:
		lab.set_control("gravity", world)
		lab.set_control("mass", mass)
		lab.manipulation_placed("drop_red", Transform3D(Basis(), Vector3(lab.starts.red.x, h_red + lab.BALL_RADIUS, 0.0)))
		lab.manipulation_placed("drop_yellow", Transform3D(Basis(), Vector3(lab.starts.yellow.x, h_yellow + lab.BALL_RADIUS, 0.0)))
		lab.release()
		var steps := 0
		while lab.status() != "landed" and steps < 700:
			await tree.physics_frame
			steps += 1
		return lab.observations().together_time
	var level: Variant = await together.call("earth", "heavy", 5.0, 5.0)
	var light: Variant = await together.call("earth", "light", 5.0, 5.0)
	var apart: Variant = await together.call("earth", "heavy", 8.0, 7.5)
	var dragged_one: bool = absf(lab.starts.purple.y - 4.0) < 1e-9   # the drag moved its own ball only (purple opens at 4 m)
	if not (level is float and absf(level - sqrt(2.0 * 5.0 / 9.81)) < 1e-9 and light is float and absf(light - level) < 1e-12 and apart is String and dragged_one):
		problems.append("the lab: level %s, light %s, 8 vs 7.5 m %s, purple kept %s" % [level, light, apart, dragged_one])
	lab.queue_free()
	# The formula on the grid: two different heights never land within a step (Jupiter's 7.5 and 8 m
	# are the closest pair: 0.026 s), the same height always does.
	var g := {"earth": 9.81, "moon": 1.62, "jupiter": 24.79}
	var closest := INF
	for world in g:
		for a in heights:
			for b in heights:
				if a != b:
					closest = minf(closest, absf(sqrt(2.0 * a / g[world]) - sqrt(2.0 * b / g[world])))
	if closest <= lab.TOGETHER_S:
		problems.append("two grid heights land within a step (%.4f s)" % closest)
	# Stage 2 (the Moon, past 3 s): only both at 8 m; never on the earth or Jupiter. Stage 3 (Jupiter,
	# under 1 s): from every height; the Moon never; the earth not from 5 m up.
	var fall := func(world: String, h: float) -> float: return sqrt(2.0 * h / g[world])
	var moon: Array = heights.filter(func(h: float) -> bool: return _beats(definition, 1, fall.call("moon", h)))
	if moon != [8.0] or heights.any(func(h: float) -> bool: return _beats(definition, 1, fall.call("earth", h)) or _beats(definition, 1, fall.call("jupiter", h))):
		problems.append("stage 2: the Moon from %s" % str(moon))
	if not heights.all(func(h: float) -> bool: return _beats(definition, 2, fall.call("jupiter", h))) \
			or heights.filter(func(h: float) -> bool: return h >= 1.0).any(func(h: float) -> bool: return _beats(definition, 2, fall.call("moon", h))) \
			or heights.filter(func(h: float) -> bool: return h >= 5.0).any(func(h: float) -> bool: return _beats(definition, 2, fall.call("earth", h))):
		problems.append("stage 3: Jupiter / the Moon / the earth")
	if not heights.all(func(h: float) -> bool: return _beats(definition, 0, fall.call("earth", h))):
		problems.append("stage 1: some earth height does not count")
	# Each stage wants the two different balls (the heavy red one: every stage alike, so it is no picture
	# button, ConditionPicks) and its world (one button fits, the others not).
	for i in 3:
		var want: Dictionary = MissionTracker.missions(definition).stages[i].conditions
		if want.get("mass") != "heavy" or (goals.call("picked", definition, i, "gravity", true) as Array) != [want.gravity] \
				or (goals.call("picked", definition, i, "gravity", false) as Array).size() != 2:
			problems.append("stage %d: the conditions / buttons" % (i + 1))
	expect.call(problems.is_empty(),
		"piece game (drop): the buttons count when the heavy red and the light yellow ball land within one step (the same height: √(2h/g) has no mass); grid heights apart never do (closest %.3f s); the earth any height, the Moon only both at 8 m (3.14 s), Jupiter any height under 1 s (the Moon not from 1 m, the earth not from 5 m); each stage wants the heavy red ball" % closest,
		"; ".join(problems))


# --- the slide: fast enough at its end ---------------------------------------------------------------

func check_incline() -> void:
	var definition := ExperimentRegistry.find("incline-friction")
	var stages: Array = MissionTracker.missions(definition).stages
	var goals := _goals()
	var lab: Experiment = await _lab("incline-friction")
	var problems := []
	var speeds := []
	for i in stages.size():
		var want: Dictionary = stages[i].conditions
		lab.set_control("material", want.material)
		var angles: Array = goals.call("picked", definition, i, "angle", true) if want.has("angle") else [20.0]
		for angle in angles:
			lab.set_control("angle", float(angle))
			var a := PhysicsLaws.incline_acceleration(9.81, deg_to_rad(float(angle)), lab.mu_s, lab.mu_k)
			var v: float = lab.observations().bottom_speed
			if absf(v - sqrt(2.0 * a * lab.run_length())) > 1e-9 or not _beats(definition, i, v):
				problems.append("stage %d at %s°: %.3f m/s" % [i + 1, angle, v])
			speeds.append(snappedf(v, 0.01))
		for angle in goals.call("picked", definition, i, "angle", false) if want.has("angle") else []:
			lab.set_control("angle", float(angle))
			if _beats(definition, i, lab.observations().bottom_speed):
				problems.append("stage %d: the other slope %s° gets there" % [i + 1, angle])
	# A short run (the box put 2 m above the end) is too slow for the rubber stage.
	lab.set_control("material", "rubber")
	lab.set_control("angle", 40.0)
	lab.set_run_length(2.0)
	if _beats(definition, 2, lab.observations().bottom_speed):
		problems.append("a 2 m run on rubber at 40° gets there")
	# The box really gets there at the formula's speed: steel 25°, the formula clock to the end.
	lab.set_run_length(7.5)
	lab.set_control("material", "steel")
	lab.set_control("angle", 25.0)
	lab.release()
	var steps := 0
	while lab.status() != "left" and steps < 400:
		await tree.physics_frame
		steps += 1
	var t := sqrt(2.0 * lab.run_length() / lab.formula_acceleration())
	if absf(steps / 60.0 - t) > 3.0 / 60.0:
		problems.append("steel 25°: left after %.3f s (formula %.3f s)" % [steps / 60.0, t])
	lab.queue_free()
	expect.call(problems.is_empty(),
		"piece game (slide): the dominoes go when the box reaches the end past 5 → 6 → 6.5 m/s (v = √(2ad), a = g(sin θ − μk cos θ)): steel, wood at 30° up, rubber at 40° up (%s); the other slope holds; a short run is too slow; the box reaches the end at the formula's time" % str(speeds),
		"; ".join(problems))


# --- spring: the swing on the beat --------------------------------------------------------------------

func check_spring() -> void:
	var definition := ExperimentRegistry.find("spring")
	var stages: Array = MissionTracker.missions(definition).stages
	var goals := _goals()
	var masses: Array = goals.call("grid", definition, "mass")
	var problems := []
	var period := func(m: float, b: float) -> float:
		var model := SpringModel.new()
		model.mass = m
		model.damping = b
		return model.period()
	for i in stages.size():
		var want: Variant = stages[i].conditions.mass
		for b in [0.0, 0.45]:
			for m in masses:
				var on_beat := _beats(definition, i, period.call(m, b))
				if MissionTracker.condition_holds(want, m) and (m == 1.0 or m == 3.0) and not on_beat:
					problems.append("stage %d: %s kg (b %s) off the beat (%.2f s)" % [i + 1, m, b, period.call(m, b)])
				if not (m == 1.0 or m == 3.0) and on_beat:
					problems.append("stage %d: %s kg (b %s) on the beat (%.2f s)" % [i + 1, m, b, period.call(m, b)])
			for m in goals.call("picked", definition, i, "mass", false):
				if _beats(definition, i, period.call(m, b)):
					problems.append("stage %d: the other ball %s kg on the beat" % [i + 1, m])
	# The real lab: the 1 kg ball let go from 0.3 m and from 2.4 m swings in the same time, the
	# formula's 2π√(m/k), both on the 2.8 s beat (the amplitude does not enter it).
	var lab: Experiment = await _lab("spring")
	var swings := []
	for pull in [0.3, 2.4]:
		lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(lab.ANCHOR_X + lab.REST_LENGTH + pull, lab.ROD_Y, 0.0)))
		await tree.physics_frame
		var k := 0
		while not (lab.observations().swing_period is float) and k < 400:
			await tree.physics_frame
			k += 1
		swings.append(lab.observations().swing_period)
	lab.queue_free()
	if not (swings[0] is float and swings[1] is float and absf(swings[0] - swings[1]) < 1e-12 and absf(swings[0] - TAU * sqrt(1.0 / 5.0)) < 1e-9 and _beats(definition, 2, swings[0])):
		problems.append("pulls 0.3 / 2.4 m: %s" % str(swings))
	expect.call(problems.is_empty(),
		"piece game (spring): the swing matches the clock's beat as shown (2.8 ± 0.2 s: the 1 kg ball 2.81 s; 4.9 ± 0.2 s: the 3 kg ball 4.87 s; with or without damping), no other ball of the grid does; the 1 kg ball pulled 0.3 m and 2.4 m swings in the same 2.81 s",
		"; ".join(problems))


# --- batch B (2026-10-29): the lever, the pulley, the pendulum, the drum, the orbit ------------------------

## The lever: each stage's chest is lifted with its effort point (the force on the beam = the required
## F = m g r₂ / r₁ under the stage's threshold) and not with the stage's other points; the chest is the
## load's look (the same node the mass look scales).
func check_lever() -> void:
	var definition := ExperimentRegistry.find("rotation")
	var stages: Array = MissionTracker.missions(definition).stages
	var lab: Experiment = await _lab("rotation")
	var problems := []
	var forces := []
	for i in stages.size():
		var want: Dictionary = stages[i].conditions
		for point in ["near", "mid", "far"]:
			lab.set_control("mass", float(want.mass))
			lab.set_control("effort", point)
			var f: float = lab.model.required()
			var lifted := _beats(definition, i, f) and MissionTracker.conditions_met(want, lab)
			if point == want.effort:
				forces.append(snappedf(f, 0.1))
			if lifted != (point == want.effort):
				problems.append("stage %d at %s: %.1f N judged %s" % [i + 1, point, f, lifted])
			# Without the condition the force alone: a nearer point never gets under the threshold.
			if ["near", "mid", "far"].find(point) < ["near", "mid", "far"].find(want.effort) and _beats(definition, i, f):
				problems.append("stage %d: the nearer %s point is under the threshold (%.1f N)" % [i + 1, point, f])
	var visual := lab.load_body.get_node("Visual") as MeshInstance3D
	var chest := visual.mesh.get_aabb().size
	if (lab.game as RotationGame) == null or (chest - Vector3.ONE * 0.7).length() > 0.1:
		problems.append("the load does not look like the chest (%s)" % chest)
	lab.queue_free()
	expect.call(problems.is_empty() and str(forces) == "[320.3, 186.9, 124.6]",
		"piece game (lever): the chest lifts with the stage's point under 350 → 200 → 130 N (F = m g r₂ / r₁: near %s N), a nearer point never does; the load looks like a treasure chest" % str(forces),
		"; ".join(problems))


## The pulley: a stage is the chest on the shelf (the state "top", lift = rope / n reaching the
## top) with its strands (F = m g / n under the threshold); halfway counts nothing.
func check_pulley() -> void:
	var definition := ExperimentRegistry.find("pulley")
	var stages: Array = MissionTracker.missions(definition).stages
	var lab: Experiment = await _lab("pulley")
	var problems := []
	var ropes := []
	for i in stages.size():
		var want: Dictionary = stages[i].conditions
		for strands in ["one", "two", "four"]:
			lab.set_control("strands", strands)
			lab.set_control("mass", float(want.mass))
			await tree.physics_frame
			var n: int = lab.model.strands
			var half := roundi(lab.model.cells_per_m * lab.MAX_LIFT * n * 0.5)
			lab.set_stroke(half, false)
			lab.let_go()
			await tree.physics_frame
			var judged_half := MissionTracker.judge(definition, i, lab.status(), lab, lab.observations()) > i
			lab.set_stroke(10000, false)
			lab.let_go()
			await tree.physics_frame
			var judged_top := MissionTracker.judge(definition, i, lab.status(), lab, lab.observations()) > i
			if strands == want.strands:
				ropes.append(snappedf(lab.model.pulled(), 0.01))
			if judged_half or judged_top != (strands == want.strands) or lab.status() != "top" or absf(lab.model.lift() - lab.MAX_LIFT) > 1e-9:
				problems.append("stage %d, %s: halfway %s, on the shelf %s (%s, lift %.2f)" % [i + 1, strands, judged_half, judged_top, lab.status(), lab.model.lift()])
	var game := lab.game as PulleyGame
	if game == null or absf(game.shelf_y - lab.MAX_LIFT) > 1e-9:
		problems.append("the shelf is not at the top")
	lab.queue_free()
	expect.call(problems.is_empty() and ropes == [2.4, 4.8, 9.6],
		"piece game (pulley): the chest counts on the shelf (\"top\": lift = rope / n = 2.4 m, rope %s m) with the stage's strands (F = m g / n under 200 → 100 → 50 N), never halfway or with other strands" % str(ropes),
		"; ".join(problems))


## The half swing x 2 of a rope (the lab's model, RK4) let go from `deg` with damping `b`.
static func half_swing(length: float, g: float, b: float, deg: float) -> float:
	var model := PendulumLabModel.new()
	model.length = length
	model.g = g
	model.damping = b
	model.reset(deg_to_rad(deg))
	while model.half_swing_period <= 0.0 and model.steps < 6000:
		model.step(1.0 / float(Engine.physics_ticks_per_second))
	return model.half_swing_period


## The pendulum's turtle beats: each stage's fitting rope is on the beat from every release angle
## 5–45° (a wider swing is a little slower, the law), with either damping; the stage's other ropes and
## worlds never are up to 60° (the very long stage's 2.5 m rope only past 60°, kept out by the stage's
## rope anyway).
func check_pendulum_beat() -> void:
	var definition := ExperimentRegistry.find("constraints")
	var stages: Array = MissionTracker.missions(definition).stages
	var goals := _goals()
	var problems := []
	var seen := []
	for i in stages.size():
		var want: Dictionary = stages[i].conditions
		var g := float(goals.call("option", definition, "gravity", str(want.gravity)).g)
		var other_g := 1.62 if want.gravity == "earth" else 9.81
		for damping in ["web", "none"]:
			var b := float(goals.call("option", definition, "damping", damping).rope_b)
			for length in goals.call("picked", definition, i, "length", true):
				for deg in [5.0, 25.0, 45.0]:
					var t := half_swing(length, g, b, deg)
					if not _beats(definition, i, t):
						problems.append("stage %d %s: %s m from %s° off the beat (%.2f s)" % [i + 1, damping, length, deg, t])
				if damping == "web":
					seen.append("%s m %.2f s" % [length, half_swing(length, g, b, 35.0)])
			for length in goals.call("picked", definition, i, "length", false):
				for deg in [5.0, 30.0, 60.0]:
					if _beats(definition, i, half_swing(length, g, b, deg)):
						problems.append("stage %d %s: the other rope %s m from %s° on the beat" % [i + 1, damping, length, deg])
			for length in [1.5, 2.5, 3.0]:
				if _beats(definition, i, half_swing(length, other_g, b, 45.0)):
					problems.append("stage %d: the other world with %s m on the beat" % [i + 1, length])
	expect.call(problems.is_empty(),
		"piece game (pendulum): the turtle clock's beats (3.2 ± 0.2, 6.3 ± 0.3, 8.8 ± 0.3 s, the half swing x 2 as shown): the earth's long rope, the Moon's short rope, the Moon's very long rope from 5–45° with or without damping (%s); the other ropes and worlds never (to 60°)" % ", ".join(seen),
		"; ".join(problems))


## The drum: each stage's drum (with the chest, its mass the stage's) floats by the densities
## (ρ = m / V < 1000 kg/m³); the stage's other picture buttons sink or stay; the chest hangs beside
## the drum ROPE under its bottom and lies on the tank floor when the drum is low.
func check_drum() -> void:
	var definition := ExperimentRegistry.find("buoyancy")
	var stages: Array = MissionTracker.missions(definition).stages
	var goals := _goals()
	var lab: Experiment = await _lab("buoyancy")
	var problems := []
	for i in stages.size():
		var want: Dictionary = stages[i].conditions
		lab.set_control("volume", want.volume)
		lab.set_control("mass", float(want.mass))
		if lab.model.judgement() != "floats":
			problems.append("stage %d: %s kg in the %s drum does not float" % [i + 1, want.mass, want.volume])
		# The small drum's lesson: the big drum's weights sink in it.
		for m in (goals.call("picked", definition, i, "mass", false) if want.volume == "small" else []):
			lab.set_control("mass", float(m))
			if lab.model.judgement() != "sinks":
				problems.append("stage %d: %s kg in the small drum does not sink" % [i + 1, m])
	var game := lab.game as BuoyancyGame
	lab.set_control("volume", "big")
	lab.set_control("mass", 80.0)
	await tree.physics_frame
	var bottom: float = lab.drum.global_position.y - lab.drum_height() * 0.5
	var c := game.chest_centre()
	var hung: bool = absf(c.y - (bottom - BuoyancyGame.ROPE - BuoyancyGame.CHEST.y * 0.5)) < 1e-6 and c.x > lab.drum.global_position.x + lab.drum_radius()
	lab.manipulation_placed("drum", Transform3D(Basis(), Vector3(0.0, BuoyancyGame.FLOOR_Y + lab.drum_height() * 0.5, 0.0)))
	lab.reset_run()
	await tree.physics_frame
	var floor_y := game.chest_centre().y
	if not hung or absf(floor_y - (BuoyancyGame.FLOOR_Y + BuoyancyGame.CHEST.y * 0.5)) > 1e-6:
		problems.append("the chest: hung %s, on the floor at %.3f" % [hung, floor_y])
	lab.queue_free()
	expect.call(problems.is_empty(),
		"piece game (drum): each stage's drum with its chest floats (ρ = m / V under the water's 1000 kg/m³: 80 and 95 kg in 100 L, 45 kg in 50 L), 80 and 95 kg sink in the small drum; the chest hangs beside the drum under its bottom and lies on the tank floor when the drum is low",
		"; ".join(problems))


## The orbit: the piece floats on the side a hard tangent shot from 4 m leaves to: the formula planet
## of every escape speed 3.7–6 m/s along the circle (90°) passes within ATTACH of it; a circular lap
## at 4 m pops all the sparkles of stage 1.
func check_orbit_piece() -> void:
	var problems := []
	var closest := []
	var home := Vector3(OrbitGame.HOME_R * cos(deg_to_rad(OrbitGame.HOME_DEG)), 0.0, -OrbitGame.HOME_R * sin(deg_to_rad(OrbitGame.HOME_DEG)))
	for speed in [3.7, 4.0, 4.5, 5.0, 6.0]:
		var model := OrbitModel.new()
		model.plane_y = 0.0
		model.reset(4.0, 0.0, -speed)
		var best := INF
		while model.outcome == "" and model.steps < 60 * 60:
			model.step(1.0 / 60.0)
			best = minf(best, Vector3(model.x, 0.0, model.z).distance_to(home))
		closest.append(snappedf(best, 0.01))
		if best > OrbitGame.ATTACH:
			problems.append("%s m/s passes %.2f m from the piece" % [speed, best])
	# A bound lap at 4 m never comes near it (the piece is only taken by a leaving planet anyway).
	var lap := OrbitModel.new()
	lap.reset(4.0, 0.0, -sqrt(lap.mu / 4.0))
	var near_lap := INF
	for k in 700:
		lap.step(1.0 / 60.0)
		near_lap = minf(near_lap, Vector3(lap.x, 0.0, lap.z).distance_to(home))
	if near_lap <= OrbitGame.ATTACH:
		problems.append("the 4 m circle passes the piece")
	# On the real screen: the circular lap at 4 m pops all the stage-1 sparkles.
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _open(ExperimentRegistry.find("orbit"))
	screen._end_question()
	var lab: Experiment = screen.experiment
	screen._set_control("radius", 4.0)
	screen.experiment_action("circular")
	screen.experiment_action("launch")
	var taken := 0
	for k in 700:   # until the lap's stamp (it lays the next stage's sparkles)
		await tree.physics_frame
		await tree.process_frame
		if screen._missions.stamps >= 1:
			break
		taken = maxi(taken, (lab.game as OrbitGame).sparkles_taken())
	if taken != OrbitGame.SPARKLES or screen._missions.stamps != 1:
		problems.append("one lap at 4 m popped %d sparkles (stamps %d)" % [taken, screen._missions.stamps])
	# Stage 3 (two stamps saved): a 4.5 m/s tangent shot from 4 m takes the piece along and leaves it free.
	await _free(screen)
	ProgressStore.save({"orbit": 2})
	screen = await _open(ExperimentRegistry.find("orbit"))
	screen._end_question()
	lab = screen.experiment
	var game := lab.game as OrbitGame
	screen._set_control("radius", 4.0)
	screen._set_control("direction", 90.0)
	screen._set_control("speed", 4.5)
	screen.experiment_action("launch")
	var rode := false
	for k in 600:
		await tree.physics_frame
		await tree.process_frame
		rode = rode or (game.attached and game.piece.global_position.distance_to(lab.planet.global_position) < OrbitGame.RIDE_UP + 0.01)
		if screen._missions.stamps >= 3:
			break
	await _frames(10)
	if not rode or screen._missions.stamps != 3 or game.piece_state != "out":
		problems.append("stage 3: rode %s, stamps %d, piece %s" % [rode, screen._missions.stamps, game.piece_state])
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(),
		"piece game (orbit): the piece floats where a hard tangent shot from 4 m leaves (3.7–6 m/s pass it within %.1f m: %s), the 4 m circle does not; one lap at 4 m pops every sparkle; the leaving planet takes the piece along and the stamp frees it" % [OrbitGame.ATTACH, str(closest)],
		"; ".join(problems))


# --- the piece: in its object, out only at the last stamp --------------------------------------------------

func check_pieces() -> void:
	var problems := []
	for id in PIECE_LABS:
		DirAccess.remove_absolute(ProgressStore.path)
		var screen := await _open(ExperimentRegistry.find(id))
		screen._end_question()
		var lab: Experiment = screen.experiment
		var game: LabGame = lab.game
		if game == null or game.piece == null:
			problems.append("%s: no piece game" % id)
			await _free(screen)
			continue
		if not (game.piece.visible and game.piece_state == "held" and game.piece.is_inside_tree()):
			problems.append("%s: the piece is not shown in its object at the start" % id)
		for stamps in [1, 2, 3]:
			screen._missions.stamps = stamps   # the demo's way (in memory only)
			screen._mission_progress(id, stamps)
			await _frames(120)
			if stamps < 3 and game.piece_state != "held":
				problems.append("%s: released after stamp %d" % [id, stamps])
		if not (game.piece_state in ["flying", "out"] and game.piece.visible):
			problems.append("%s: the last stamp did not release the piece (%s)" % [id, game.piece_state])
		await _frames(160)
		var floating: bool = id == "orbit"   # in space: freed where it floats, no fall
		if game.piece_state != "out" or (not floating and absf(game.piece.global_position.y - game.piece_size) > 0.06):
			problems.append("%s: the piece is not on the ground after its fall (%s at %s)" % [id, game.piece_state, game.piece.global_position])
		await _free(screen)
		# A finished spot (3 stamps saved): no piece any more; one stamp: still in its object.
		for saved in [3, 1]:
			DirAccess.remove_absolute(ProgressStore.path)
			ProgressStore.save({id: saved})
			var again := await _open(ExperimentRegistry.find(id))
			var g2: LabGame = again.experiment.game
			if saved == 3 and (g2.piece.visible or g2.piece_state != "taken"):
				problems.append("%s: a finished spot still shows its piece" % id)
			if saved == 1 and (not g2.piece.visible or g2.piece_state != "held" or g2.cleared != 1):
				problems.append("%s: one stamp saved: the piece is not in its object (%s)" % [id, g2.piece_state])
			await _free(again)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(),
		"piece game: in all eleven labs the piece is in its object from the start, still there after stamps 1 and 2, out on the last stamp and down on the ground (the orbit's floats free in space); a finished spot has none, a started one keeps it",
		"; ".join(problems))


## With the story on, the round's found piece flies from the lab's piece to the bread cat (it does
## not pop in over the cat), and the lab's piece is handed over (gone from the lab).
func check_found_piece_flies() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var was := Story.enabled
	Story.enabled = true
	ProgressStore.set_mark(ProgressStore.CLUES, "free-fall", true)
	var screen := await _open(ExperimentRegistry.find("free-fall"))
	screen._end_question()
	var game: LabGame = screen.experiment.game
	for stamps in [1, 2, 3]:
		screen._missions.stamps = stamps
		screen._mission_progress("free-fall", stamps)
		await _frames(30)
	var lab_piece_at := Vector3.INF
	var first := Vector3.INF
	for k in 200:
		await tree.process_frame
		if game.piece_state != "taken":
			lab_piece_at = game.piece.global_position
		var found: Node3D = screen.found_piece()
		if found != null:
			first = found.global_position
			break
	var state := game.piece_state
	var ok: bool = first != Vector3.INF and state == "taken" and not game.piece.visible and first.distance_to(lab_piece_at) < 0.5
	await _frames(60)
	var cat: CatActor = screen.lab_cat()
	var over_cat := false
	if screen.found_piece() != null and cat != null:
		var box := cat.bounds()
		var at: Vector3 = screen.found_piece().global_position
		over_cat = Vector2(at.x, at.z).distance_to(Vector2(box.get_center().x, box.get_center().z)) < 0.3 and at.y > box.end.y
	Story.enabled = was
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(ok and over_cat,
		"piece game: the found piece starts where the lab's piece lies (handed over: the lab's is gone) and flies into the bread cat's raised paws",
		"first %s, lab piece %s, state %s, over the cat %s" % [first, lab_piece_at, state, over_cat])


# --- words ---------------------------------------------------------------------------------------------

## The six labs' stage texts point at the game (a crate, the ice, the buttons, the box, the dominoes, the
## beat), Puppy's clue at the object, and the spring's fitting stage says the beat does not change with the pull.
func check_words() -> void:
	var want := {"projectile": "상자", "collision": "얼음", "free-fall": "버튼", "friction": "상자", "incline-friction": "도미노", "spring": "박자",
		"rotation": "보물 상자", "pulley": "선반", "constraints": "거북이 박자", "buoyancy": "상자", "orbit": "조각"}
	var clue := {"projectile": "상자", "collision": "얼음", "free-fall": "버튼", "friction": "상자", "incline-friction": "도미노", "spring": "시계",
		"rotation": "보물 상자", "pulley": "선반", "constraints": "거북이 시계", "buoyancy": "보물 상자", "orbit": "우주"}
	var problems := []
	for id in want:
		var definition := ExperimentRegistry.find(id)
		var stages: Array = MissionTracker.missions(definition).stages
		if not stages.any(func(s: Dictionary) -> bool: return str(s.text).contains(want[id])):
			problems.append("%s: no stage text names %s" % [id, want[id]])
		if not Story.clue(definition).contains(clue[id]):
			problems.append("%s: the clue does not point at %s" % [id, clue[id]])
	var spring_says: Array = MissionTracker.missions(ExperimentRegistry.find("spring")).stages.map(func(s: Dictionary) -> String: return str(s.say))
	if not spring_says.any(func(s: String) -> bool: return s.contains("조금 당겨도 많이 당겨도 같은 박자")):
		problems.append("spring: no say tells the beat does not change with the pull")
	expect.call(problems.is_empty(), "piece game: the stage texts name the game, Puppy's clue points at the object, the spring says the beat stays the same for any pull",
		"; ".join(problems))
