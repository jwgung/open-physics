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
const PIECE_LABS := ["projectile", "collision", "free-fall", "friction", "incline-friction", "spring"]


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_tracker_near_also()
	await check_projectile()
	await check_projectile_round()
	check_collision()
	await check_free_fall()
	await check_incline()
	await check_spring()
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
	var counts := [0, 0, 0]
	var weak := 0
	for angle in range(0, 91, 5):
		for k in 17:
			var speed := 1.0 + 0.5 * k
			lab.set_control("angle", float(angle))
			lab.set_control("speed", speed)
			var values: Dictionary = lab.observations()
			for i in 3:
				var hit: bool = _beats(definition, i, float(values["hit_%d" % (i + 1)]))
				if hit != is_finite(lab.hit_times()[i]):
					problems.append("%d° %.1f m/s crate %d: judged %s, hit time %s" % [angle, speed, i + 1, hit, lab.hit_times()[i]])
				if hit:
					counts[i] += 1
					if speed <= 3.0:
						weak += 1
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
	expect.call(problems.is_empty() and counts[0] >= 30 and counts[1] >= 15 and counts[2] >= 5 and counts[0] > counts[1] and counts[1] > counts[2] and weak == 0,
		"piece game (throw): crate n is hit when the formula path (x0 + vx t, y0 + vy t − ½gt²) comes within the ball's radius of its box before the landing; on the slingshot grid the near, far and high crates are hit by fewer and fewer throws (%s), never by a throw of 3 m/s or less" % str(counts),
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
	var throws := [[80.0, 4.0, 0], [40.0, 6.0, 1], [40.0, 6.0, 1], [45.0, 7.5, 2], [45.0, 8.5, 3]]
	for throw in throws:
		screen._set_control("angle", throw[0])
		screen._set_control("speed", throw[1])
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
		"piece game (throw): a miss earns nothing; a hit on the stage's crate tips it at the formula hit time and the landing stamps it (near → far → high); the piece rides the high crate until that hit drops it to the ground",
		"; ".join(problems))


# --- collision: B fast enough to break the ice --------------------------------------------------------

## B's formula speed just after the first hit (CollisionModel, the lab's starts and radii, rubber).
static func after_b(ma: float, mb: float, va: float) -> float:
	var m := CollisionModel.new()
	m.mass_a = ma
	m.mass_b = mb
	m.radius_a = 0.4
	m.radius_b = 0.5
	m.restitution_a = 0.88
	m.restitution_b = 0.88
	m.wall = 7.0
	m.reset(-4.0, 4.0, va, -1.7)
	var n := 0
	while not m.collided and n < 6000:
		m.step(1.0 / 60.0)
		n += 1
	return m.after[1] if m.collided else -INF


func check_collision() -> void:
	var definition := ExperimentRegistry.find("collision")
	var stages: Array = MissionTracker.missions(definition).stages
	var problems := []
	var pulls := []   # the slowest pull (0.5 m/s grid) that clears each stage with its fitting balls
	for i in stages.size():
		var want: Dictionary = stages[i].conditions
		var ma := float(want.mass_a.get("min", 1.0)) if want.mass_a is Dictionary else float(want.mass_a)
		var mb := float(want.mass_b)
		var first := -1.0
		for k in range(1, 19):
			if _beats(definition, i, after_b(ma, mb, 0.5 * k)):
				first = 0.5 * k
				break
		pulls.append(first)
		if first < 0.0:
			problems.append("stage %d: %s kg on %s kg never past %s" % [i + 1, ma, mb, stages[i].threshold])
	# The lesson's other buttons never get there, even at the fastest pull (9 m/s).
	var never := [[0, 1.0, 2.0], [1, 1.0, 1.0], [2, 3.0, 1.0], [2, 3.0, 2.0], [2, 1.0, 0.5]]
	for case in never:
		if _beats(definition, case[0], after_b(case[1], case[2], 9.0)):
			problems.append("stage %d: %s kg on %s kg at 9 m/s gets there (%.2f)" % [case[0] + 1, case[1], case[2], after_b(case[1], case[2], 9.0)])
	# The start (1 kg on 2 kg at 3.4 m/s) clears nothing.
	if _beats(definition, 0, after_b(1.0, 2.0, 3.4)):
		problems.append("the start clears stage 1")
	expect.call(problems.is_empty() and pulls == [6.5, 7.0, 8.5],
		"piece game (bump): the ice cracks when B leaves the hit past 5 → 9 → 13 m/s (the formula's after_b): two 1 kg balls from a 6.5 m/s pull, a 3 kg blue on 1 kg from 7, a 3 kg on the 0.5 kg orange from 8.5; never a heavier orange, a light blue, or a heavier orange in stage 3, even at 9 m/s",
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
	var dragged_one: bool = absf(lab.starts.purple.y - 5.0) < 1e-9   # the drag moved its own ball only
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
		await _frames(120)
		if game.piece_state != "out" or absf(game.piece.global_position.y - game.piece_size) > 0.06:
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
		"piece game: in all six labs the piece is in its object from the start, still there after stamps 1 and 2, out on the last stamp and down on the ground; a finished spot has none, a started one keeps it",
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
	var want := {"projectile": "상자", "collision": "얼음", "free-fall": "버튼", "friction": "상자", "incline-friction": "도미노", "spring": "박자"}
	var clue := {"projectile": "상자", "collision": "얼음", "free-fall": "버튼", "friction": "상자", "incline-friction": "도미노", "spring": "시계"}
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
