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
	await check_projectile_one_crate()
	await check_collision()
	await check_free_fall()
	await check_incline()
	await check_incline_dominoes()
	await check_push_path()
	await check_spring()
	await check_lever()
	await check_pulley()
	await check_pendulum_beat()
	await check_drum()
	await check_orbit_piece()
	await check_pieces()
	await check_found_piece_flies()
	await check_clue_glow()
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


func _open(definition: Dictionary, size := TABLET) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
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


## One crate at a time (2026-10-29): only the stage's crate is on the island; it is the one judged;
## a cleared crate falls, and the next pops in only after the stamp (APPEAR_DELAY_S); the round's
## end keeps the fallen last crate. The piece rides the last crate only.
func check_projectile_one_crate() -> void:
	var lab: Experiment = await _lab("projectile")
	var game := lab.game as ProjectileGame
	var problems := []
	var wait_for := func(want: Array) -> float:
		var t0 := game._t
		for k in 600:
			await tree.process_frame
			if game.visible_crates() == want:
				break
		return game._t - t0
	game.show_stage(0, 0, false)
	if game.visible_crates() != [0] or game.piece.visible:
		problems.append("stage 1 shows %s, piece visible %s (want only the near crate, no piece)" % [str(game.visible_crates()), game.piece.visible])
	# Only the visible crate counts: the far crate's hit is not taken while stage 1 is played.
	game.hit(1, 9.81)
	if game._tipped[1] or game._tipped[0]:
		problems.append("a hit on a crate that is not the stage's tipped it")
	game.hit(0, 9.81)
	if not game._tipped[0]:
		problems.append("the stage's own crate did not tip")
	game.show_stage(1, 1, true)   # stamp 1
	if game.visible_crates() != [0]:
		problems.append("right after the stamp %s shows (the fallen crate stays until the next pops in)" % str(game.visible_crates()))
	var waited: float = await wait_for.call([1])
	if waited < ProjectileGame.APPEAR_DELAY_S - 0.05 or game.visible_crates() != [1] or game.piece.visible:
		problems.append("the far crate came after %.2f s, shows %s" % [waited, str(game.visible_crates())])
	game.hit(1, 9.81)
	game.show_stage(2, 2, true)
	waited = await wait_for.call([2])
	if game.visible_crates() != [2] or not game.piece.visible or game.piece_state != "held":
		problems.append("stage 3 shows %s, piece visible %s %s" % [str(game.visible_crates()), game.piece.visible, game.piece_state])
	game.hit(2, 9.81)
	game.show_stage(-1, 3, true)
	await _frames(120)
	if game.visible_crates() != [2] or not game._tipped[2]:
		problems.append("after the round %s shows (want the fallen tree crate)" % str(game.visible_crates()))
	# The clue's glow follows the crate of the stage; a reset shows the stage's crate at once.
	game.show_stage(0, 0, false)
	game.run_reset()
	var spot: Vector2 = ProjectileGame.TARGETS[0]
	var glow_at: Vector3 = game.highlight_spots()[0].at
	if game.visible_crates() != [0] or absf(glow_at.x - spot.x) > 1e-6 or glow_at.y < spot.y or glow_at.y > spot.y + ProjectileGame.CRATE:
		problems.append("after a reset %s shows, the glow is at %s" % [str(game.visible_crates()), glow_at])
	lab.queue_free()
	expect.call(problems.is_empty(),
		"piece game (throw, one crate at a time): stage 1 shows only the near crate, stage 2 only the far one, stage 3 only the tree crate with the piece; only the visible crate is judged; a cleared crate falls and the next pops in after the stamp; the round's end keeps the fallen last one; the clue glows on the stage's crate",
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
	var apart: Variant = await together.call("earth", "heavy", 8.0, 7.0)
	# Two balls only (2026-10-29), and a drag moves its own ball to a whole metre (6.4 m -> 6 m).
	lab.manipulation_placed("drop_red", Transform3D(Basis(), Vector3(lab.starts.red.x, 6.4 + lab.BALL_RADIUS, 0.0)))
	var dragged_one: bool = absf(lab.starts.red.y - 6.0) < 1e-9 and absf(lab.starts.yellow.y - 7.0) < 1e-9 \
		and lab.ORDER == ["yellow", "red"] and lab.balls.size() == 2
	if not (level is float and absf(level - sqrt(2.0 * 5.0 / 9.81)) < 1e-9 and light is float and absf(light - level) < 1e-12 and apart is String and dragged_one):
		problems.append("the lab: level %s, light %s, 8 vs 7 m %s, own whole-metre drag / two balls %s" % [level, light, apart, dragged_one])
	if heights != [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]:
		problems.append("the height grid %s (want 1–8 m by 1 m)" % str(heights))
	lab.queue_free()
	# The formula on the grid: two different heights never land within a step (Jupiter's 7 and 8 m
	# are the closest pair: 0.052 s), the same height always does.
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
		"piece game (drop): the buttons count when the heavy red and the light yellow ball land within one step (the same height: √(2h/g) has no mass); grid heights (1–8 m by 1 m) apart never do (closest %.3f s); the earth any height, the Moon only both at 8 m (3.14 s; 7 m is 2.94 s), Jupiter any height under 1 s (the Moon not from 1 m, the earth not from 5 m); each stage wants the heavy red ball" % closest,
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


# --- push: clear the path -----------------------------------------------------------------------------

## The push's path (2026-10-29 user "상자가 별을 막고 있어서, 이걸 치우면 별에 도달하는 길이 열리는 거로"):
## a stage is the box pushed off the path, the formula distance from the start past 1.5 m (shown).
## With the hold (25 N/s up to 80 N) every stage's box gets there within 3 s on wood (and every
## material's within 4 s), a tap (0.2 s) never moves it, and the shortest hold that passes is well
## over a tap. Returns the shortest holds (s) per stage box on wood.
func push_hold_distance(lab: Experiment, seconds: float) -> float:
	lab.reset_box()
	lab.hold_started("box")
	for k in roundi(seconds * 60.0):
		await tree.physics_frame
	lab.hold_ended("box")
	var k := 0
	while lab.status() == "sliding" and k < 900:
		await tree.physics_frame
		k += 1
	return lab.observations().distance


func check_push_path() -> void:
	var definition := ExperimentRegistry.find("friction")
	var stages: Array = MissionTracker.missions(definition).stages
	var lab: Experiment = await _lab("friction")
	var problems := []
	var shortest := {}
	for material in ["wood", "steel", "rubber", "clay"]:
		lab.set_control("material", material)
		for i in stages.size():
			lab.set_control("mass", stages[i].conditions.mass)
			var tap: float = await push_hold_distance(lab, 0.2)
			if tap != 0.0 or _beats(definition, i, tap):
				problems.append("%s %s: a tap moves it %.3f m" % [material, stages[i].conditions.mass, tap])
			var found := -1.0
			var hold := 0.3
			while hold <= 4.0 + 1e-9:
				var d: float = await push_hold_distance(lab, hold)
				if _beats(definition, i, d):
					found = hold
					break
				hold = snappedf(hold + 0.1, 0.1)
			var limit := 3.0 if material == "wood" else 4.0
			if found < 0.0 or found > limit or found <= 0.4:
				problems.append("%s %s: off the path after a %.1f s hold (want 0.5..%.0f s)" % [material, stages[i].conditions.mass, found, limit])
			if material == "wood":
				shortest[stages[i].conditions.mass] = found
	# The stages judge the distance (not the start of the slide): a box moving 1 m is still on the path.
	if not (_beats(definition, 0, 1.6) and not _beats(definition, 0, 1.5) and not _beats(definition, 2, 1.0)):
		problems.append("the threshold is not 1.5 m as shown")
	# The game: a gate opens per stamp; after the last the cat walks the path once the box rests and the
	# piece waits on its stump until then (the screen waits: piece_ready).
	var game := lab.game as FrictionGame
	lab.reset_box()
	var shut := func(i: int) -> bool:
		return game.gate_open(i) < 1e-3
	game.show_stage(1, 1, true)
	await _frames(45)
	if shut.call(0) or not shut.call(1) or not shut.call(2) or game.piece_state != "held" or not game.piece_ready():
		problems.append("after stamp 1: gate 1 not open alone (%s %s %s), piece %s" % [shut.call(0), shut.call(1), shut.call(2), game.piece_state])
	game.show_stage(2, 2, true)
	await _frames(45)
	if shut.call(1) or not shut.call(2):
		problems.append("after stamp 2: gate 2 not open")
	lab.hold_started("box")   # the child still holds the box: the cat keeps pushing
	game.show_stage(-1, 3, true)
	await _frames(60)
	var waiting: bool = game.walk_state == "pending" and not game.piece_ready() and lab.props.cat.mode == "push"
	lab.hold_ended("box")
	var k := 0
	while not game.piece_ready() and k < 600:
		await tree.process_frame
		k += 1
	var cat: CatActor = lab.props.cat
	var stand := FrictionGame.path_point(FrictionGame.CAT_STOP)
	var there: bool = game.walk_state == "there" and Vector2(cat.position.x, cat.position.z).distance_to(Vector2(stand.x, stand.z)) < 1e-3
	if not (waiting and there and game.piece_state == "out" and shut.call(2) == false):
		problems.append("the last stamp: waits while held %s, the cat at the piece %s (%s, %.1f s), piece %s" % [waiting, there, cat.position, k / 60.0, game.piece_state])
	# The lab keeps the cat's pose to the game until a new run.
	await _frames(10)
	if cat.mode != "free":
		problems.append("the cat at the piece is posed by the push (%s)" % cat.mode)
	lab.run_action("reset")
	await _frames(2)
	if game.cat_busy() or cat.mode != "push":
		problems.append("처음으로 does not give the cat back to the box")
	lab.queue_free()
	expect.call(problems.is_empty(),
		"piece game (push): a stage is the box pushed off the path (formula distance past 1.5 m): on wood the light, normal and heavy box after a %s s hold (all materials within 4 s), never by a tap (0.2 s); each stamp opens a gate; after the last the cat waits for the box to rest, walks the path to the piece and the screen hands it over there" % str(shortest),
		"; ".join(problems))


# --- slide: the dominoes past the slide's end -------------------------------------------------------------

## The slide's dominoes (2026-10-29 user: they did not line up with the slide's bottom and overlapped
## the box): the row starts GAP past the slide's lower end for every angle, beside the box's lane;
## in runs of every stage setup and the fastest ones no domino (standing, falling or fallen) ever
## meets the box; a stamp's chain starts at the formula moment the box reached the end, each domino
## NEXT_S after the one before; at the default camera every domino is in the view and clear of the
## picture buttons on the tablet and the phone.
func check_incline_dominoes() -> void:
	var lab: Experiment = await _lab("incline-friction")
	var game := lab.game as InclineGame
	var problems := []
	for angle in [0.0, 20.0, 30.0, 40.0, 45.0]:
		lab.set_control("angle", angle)
		var end: Vector3 = lab.lower_end()
		var first: Node3D = game._pivots[0][0]
		if absf(first.global_position.x - (end.x - InclineGame.GAP)) > 1e-5 or absf(first.global_position.z - InclineGame.ROW_Z) > 1e-5:
			problems.append("%s°: the row starts at %s (the slide's end %s)" % [angle, first.global_position, end])
	var closest := INF
	var runs := [["steel", 20.0], ["steel", 30.0], ["steel", 45.0], ["wood", 30.0], ["wood", 45.0], ["rubber", 40.0], ["rubber", 45.0]]
	for run: Array in runs:
		lab.set_control("material", run[0])
		lab.set_control("angle", run[1])
		for fallen in [false, true]:
			game.show_stage(0 if not fallen else -1, 0 if not fallen else 3, false)
			lab.release()
			var t_left := -1.0
			for k in 330:
				await tree.physics_frame
				await tree.process_frame
				if t_left < 0.0 and lab.status() == "left":
					t_left = game._t
					if not fallen:
						game.show_stage(1, 1, true)   # the stamp (the screen judges at its next poll)
				var box_aabb: AABB = lab.box.global_transform * AABB(-Vector3.ONE * lab.BOX * 0.5, Vector3.ONE * lab.BOX)
				for d: AABB in game.domino_boxes():
					if d.intersects(box_aabb):
						problems.append("%s %s° (%s): a domino meets the box at step %d" % [run[0], run[1], "fallen" if fallen else "standing", k])
						break
					closest = minf(closest, box_aabb.position.z - d.end.z)
			if not fallen and absf(game.chain_started(0) - t_left) > 1e-6:
				problems.append("%s %s°: the chain started at %.3f, the box got to the end at %.3f" % [run[0], run[1], game.chain_started(0), t_left])
	lab.queue_free()
	# The default camera (tablet and phone): every domino's top and foot in the view, clear of the
	# picture buttons, for every stage's buttons and every angle a button sets.
	for size in [TABLET, Vector2(1560, 720)]:
		DirAccess.remove_absolute(ProgressStore.path)
		var screen := await _open(ExperimentRegistry.find("incline-friction"), size)
		screen._end_question()
		var view: View3D = screen.view
		var g2 := screen.experiment.game as InclineGame
		for stage in 3:
			screen._show_stamps(stage)
			await _frames(3)
			for angle in [20.0, 30.0, 40.0]:
				screen.experiment.set_control("angle", angle)
				await _frames(1)
				var row: Rect2 = screen._picks_row.get_rect() if screen.picks_shown() else Rect2()
				for pivots: Array in g2._pivots:
					for pivot: Node3D in pivots:
						var mi := pivot.get_child(0) as MeshInstance3D
						for local in [Vector3(0.0, 0.0, 0.0), Vector3(0.05, mi.get_aabb().size.y, 0.0)]:
							var p: Vector2 = view.rig.unproject_position(pivot.global_transform * local) / (Vector2(view.viewport.size) / view.size)
							if not Rect2(Vector2.ZERO, view.size).has_point(p) or row.has_point(p):
								problems.append("%s stage %d %s°: %s at %s (row %s)" % [size, stage + 1, angle, pivot.name, p, row])
		await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(),
		"piece game (slide): the dominoes start %.1f m past the slide's lower end at every angle, beside the box's lane (%.2f m clear of it at the closest); no domino ever meets the box (standing, falling, fallen; steel, wood, rubber up to 45°); the chain starts at the formula moment the box reached the end; every domino in the default view and clear of the picture buttons (tablet, phone)" % [InclineGame.GAP, closest],
		"; ".join(problems.slice(0, 8)))


# --- spring: ring the bell --------------------------------------------------------------------------

## The spring's bell (2026-10-29 user "종 치기"): let go from a pull x₀ the ball's first swing turns at
## −x₀ (no damping; x₀ e^(−γT/2) with the web's damping), the same for every mass. Each stage's bell
## (0.5, 1, 1.5 m) is reached from its pull on the 0.1 m grid and not from the pull 0.1 m shorter; the
## last wants the heavy ball and reaches as far; the bell rings at the formula moment the ball's
## extension gets to −d, never when the swing falls short.
func check_spring() -> void:
	var definition := ExperimentRegistry.find("spring")
	var stages: Array = MissionTracker.missions(definition).stages
	var problems := []
	var reach := func(m: float, b: float, x0: float) -> float:
		var model := SpringModel.new()
		model.mass = m
		model.damping = b
		model.reset(x0, 1.0, 0.0)
		return -PhysicsLaws.spring_release_displacement(x0, model.omega0(), model.gamma(), model.period() * 0.5)
	var bells := [0.5, 1.0, 1.5]
	for i in stages.size():
		var d: float = bells[i]
		for m in [1.0, 3.0]:
			var fits := MissionTracker.condition_holds(stages[i].conditions.mass, m)
			# No damping: the swing reaches exactly the pull, whatever the mass.
			if absf(reach.call(m, 0.0, d) - d) > 1e-9:
				problems.append("%s kg from %s m reaches %s" % [m, d, reach.call(m, 0.0, d)])
			if fits and not _beats(definition, i, reach.call(m, 0.0, d)):
				problems.append("stage %d: %s kg pulled %s m misses its bell" % [i + 1, m, d])
			if _beats(definition, i, reach.call(m, 0.0, d - 0.1)):
				problems.append("stage %d: pulled %s m reaches the %s m bell" % [i + 1, d - 0.1, d])
		# With the web's damping the first swing falls short: x₀ e^(−γT/2) (1 kg: 0.728 x₀).
		var damped: float = reach.call(1.0, 0.45, d)
		var model := SpringModel.new()
		model.damping = 0.45
		if absf(damped - d * exp(-model.gamma() * model.period() * 0.5)) > 1e-9 or damped >= d:
			problems.append("damped reach from %s m: %s" % [d, damped])
	# The bell's spots follow the stages; the lab's swing and its ring in a real run.
	var lab: Experiment = await _lab("spring")
	var game := lab.game as SpringGame
	if [0, 1, 2].map(func(i: int) -> float: return game.stage_bell(i)) != bells:
		problems.append("the bells stand at %s" % str([0, 1, 2].map(func(i: int) -> float: return game.stage_bell(i))))
	for run: Array in [[0.4, false], [0.5, true], [2.3, true]]:
		lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(lab.ANCHOR_X + lab.REST_LENGTH + float(run[0]), lab.ROD_Y, 0.0)))
		var rang_at := -1.0
		# The formula time the ball gets to the bell (0.5 m): x(t) = x₀ cos ωt = −d, ω = √(k/m).
		var crossed_at: float = acos(clampf(-0.5 / float(run[0]), -1.0, 1.0)) / sqrt(5.0 / 1.0) if run[1] else -1.0
		for k in 100:
			await tree.physics_frame
			await tree.process_frame
			if rang_at < 0.0 and game.rang():
				rang_at = game.rang_time
		if game.rang() != run[1] or (run[1] and (rang_at < crossed_at - 1e-9 or rang_at - crossed_at > 1.0 / 60.0 + 1e-9)):
			problems.append("pulled %s m: rang %s at %.3f s (the formula ball at the bell %.3f s)" % [run[0], game.rang(), rang_at, crossed_at])
		var shown: Variant = lab.observations().bell_reach
		if not (shown is float and absf(shown - float(run[0])) < 1e-9):
			problems.append("pulled %s m: bell_reach %s" % [run[0], shown])
	# The knob sits where the ball's surface touches it with its centre at −d (the heavy ball's too).
	for m in [1.0, 3.0]:
		lab.set_control("mass", m)
		var r: float = lab.look_radius() + SpringGame.KNOB_R
		var centre := Vector2(game.knob_x(1.5) + sqrt(r * r - SpringGame.KNOB_Z * SpringGame.KNOB_Z), 0.0)
		if absf(centre.x - (lab.ANCHOR_X + lab.REST_LENGTH - 1.5)) > 1e-9:
			problems.append("%s kg: the knob is touched at %s" % [m, centre.x])
	lab.queue_free()
	expect.call(problems.is_empty(),
		"piece game (spring): the first swing turns at −x₀ for every mass (x₀ e^(−γT/2) with damping); the bells at 0.5, 1, 1.5 m are reached from those pulls and not 0.1 m shorter, the last with the heavy ball; the bell rings when the formula ball gets there (not from 0.4 m), the knob is touched at −d",
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
	# The loads are words now (2026-10-29: 가벼운 짐 45, 무거운 짐 80, 아주 무거운 짐 95 kg; no number on
	# the kid screen): each stage floats with every pick that fits it, and the small drum's stage sinks
	# with the picks that do not (the heavy loads), its lesson. The default 70 kg load floats in the
	# big drum (stage 1 takes any load there).
	var picks: Array = definition.kid.picks.mass.map(func(p: Dictionary) -> float: return float(p.value))
	var labels: Array = definition.kid.picks.mass.map(func(p: Dictionary) -> String: return str(p.label))
	if labels != ["가벼운 짐", "무거운 짐", "아주 무거운 짐"]:
		problems.append("the load picks read %s" % str(labels))
	for i in stages.size():
		var want: Dictionary = stages[i].conditions
		lab.set_control("volume", want.volume)
		var fitting := 0
		for m in picks + [70.0]:
			lab.set_control("mass", float(m))
			var fits := MissionTracker.conditions_met(want, lab)
			var floats: bool = lab.model.judgement() == "floats"
			if fits:
				fitting += 1
				if not floats:
					problems.append("stage %d: %s kg in the %s drum fits but does not float" % [i + 1, m, want.volume])
			elif want.volume == "small" and m in picks and floats:
				problems.append("stage %d: %s kg (not a fitting pick) floats in the small drum" % [i + 1, m])
		if fitting == 0:
			problems.append("stage %d: no load fits" % [i + 1])
	# Stage 1 any load in the big drum, stage 2 the heavy picks only, stage 3 the light pick only.
	var fit_of := func(i: int) -> Array:
		return picks.filter(func(m: float) -> bool: return MissionTracker.condition_holds(stages[i].conditions.get("mass", {}), m) if stages[i].conditions.has("mass") else true)
	if fit_of.call(0) != picks or fit_of.call(1) != [80.0, 95.0] or fit_of.call(2) != [45.0]:
		problems.append("fitting picks %s / %s / %s" % [fit_of.call(0), fit_of.call(1), fit_of.call(2)])
	# No number over the drum on the kid screen: the kilograms are in 자세히 only.
	if not lab.find_children("*", "Label3D", true, false).is_empty():
		problems.append("a 3D label over the drum")
	for st: Dictionary in stages:
		if str(st.text).contains("킬로그램") or RegEx.create_from_string("[0-9]").search(str(st.text)) != null:
			problems.append("a number in the stage text %s" % st.text)
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
		"piece game (drum): the loads are words (가벼운·무거운·아주 무거운 짐), no number over the drum or in the stage texts; stage 1 floats the big drum with any load, stage 2 with the heavy loads (80, 95 kg in 100 L), stage 3 the small drum with the light load (45 kg in 50 L) and the heavy ones sink there (ρ = m / V against 1000 kg/m³); the chest hangs beside the drum under its bottom and lies on the tank floor when the drum is low",
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
		# (the throw shows its piece only with the last crate, 2026-10-29: one crate at a time)
		if not ((game.piece.visible or id == "projectile") and game.piece_state == "held" and game.piece.is_inside_tree()):
			problems.append("%s: the piece is not shown in its object at the start" % id)
		for stamps in [1, 2, 3]:
			screen._missions.stamps = stamps   # the demo's way (in memory only)
			screen._mission_progress(id, stamps)
			await _frames(120)
			if stamps < 3 and game.piece_state != "held":
				problems.append("%s: released after stamp %d" % [id, stamps])
		# The push: the cat first walks the opened path to the piece (LabGame.piece_ready).
		for k in 600:
			if game.piece_ready():
				break
			await tree.process_frame
		if not (game.piece_state in ["flying", "out"] and game.piece.visible):
			problems.append("%s: the last stamp did not release the piece (%s)" % [id, game.piece_state])
		await _frames(160)
		var floating: bool = id == "orbit"   # in space: freed where it floats, no fall
		# The push's piece waits on its stump for the cat walking the opened path (2026-10-29).
		var rest_y: float = game.piece_size + (FrictionGame.STUMP_H if id == "friction" else 0.0)
		if game.piece_state != "out" or (not floating and absf(game.piece.global_position.y - rest_y) > 0.06):
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
			if saved == 1 and ((not g2.piece.visible and id != "projectile") or g2.piece_state != "held" or g2.cleared != 1):
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


# --- the clue's glow ----------------------------------------------------------------------------------

## While Puppy tells a lab's clue its game object faintly glows and pulses (2026-10-29 user "해당
## 포인트를 희미하게 강조": LabGame.highlight, ClueGlow halos around the object, the free fall's buttons as
## flat rings); when his box closes (back here; a tap or the read timer alike) it fades out and Dugi
## asks. The glow is around the piece's object (the piece lies within a halo). A run without the
## story (bench, measurements) has no clue and builds no glow.
func check_clue_glow() -> void:
	var was := Story.enabled
	var problems := []
	for id in PIECE_LABS:
		DirAccess.remove_absolute(ProgressStore.path)
		Story.enabled = true
		var screen := await _open(ExperimentRegistry.find(id))
		await _frames(2)
		var game: LabGame = screen.experiment.game
		var telling: bool = screen.clue_telling()
		var on: bool = game.highlighting()
		var glows: Array = game._glows
		var near := false
		var target: Vector3 = game.piece.global_position   # (the throw glows on the stage's crate, the piece is on the last one)
		if id == "projectile":
			target = game.to_global(game.highlight_spots()[0].at)
		for glow: ClueGlow in glows:
			if glow.name == "ClueHalo" and glow.global_position.distance_to(target) <= glow.scale.x:
				near = true
		var faint: bool = glows.all(func(glow: ClueGlow) -> bool: return (glow.material_override as StandardMaterial3D).albedo_color.a <= ClueGlow.PEAK + 1e-6)
		var closed: bool = screen.handle_back() and not screen.clue_telling()
		await _frames(int((ClueGlow.FADE_OUT_S + 0.2) * 60.0))
		var off: bool = not game.highlighting() and glows.all(func(glow: ClueGlow) -> bool: return not glow.visible)
		var asks: bool = screen._asking and screen.dialogue.active and screen.dialogue.speaker == "dugi"
		if not (telling and on and near and faint and closed and off and asks):
			problems.append("%s: telling %s on %s near %s faint %s closed %s off %s asks %s" % [id, telling, on, near, faint, closed, off, asks])
		Story.enabled = was
		await _free(screen)
	# No story (a bench or measured run): no clue, no glow built.
	Story.enabled = false
	DirAccess.remove_absolute(ProgressStore.path)
	var bench := await _open(ExperimentRegistry.find("free-fall"))
	await _frames(10)
	if bench.clue_telling() or not bench.experiment.game._glows.is_empty() or bench.experiment.game.find_children("Clue*", "", true, false).size() > 0:
		problems.append("bench: a clue glow without the story")
	await _free(bench)
	Story.enabled = was
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(),
		"clue glow: in all eleven labs Puppy's clue makes the game object glow faintly (a halo around the piece's object, the free fall's buttons ringed), back closes the clue, the glow fades out and Dugi asks; no glow without the story",
		"; ".join(problems))


# --- words ---------------------------------------------------------------------------------------------

## The six labs' stage texts point at the game (a crate, the ice, the buttons, the box, the dominoes, the
## beat), Puppy's clue at the object, and the spring's fitting stage says the beat does not change with the pull.
func check_words() -> void:
	var want := {"projectile": "상자", "collision": "얼음", "free-fall": "버튼", "friction": "상자", "incline-friction": "도미노", "spring": "종",
		"rotation": "보물 상자", "pulley": "선반", "constraints": "거북이 박자", "buoyancy": "상자", "orbit": "조각"}
	var clue := {"projectile": "상자", "collision": "얼음", "free-fall": "버튼", "friction": "길", "incline-friction": "도미노", "spring": "종",
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
	if not spring_says.any(func(s: String) -> bool: return s.contains("무거운 공도 같은 길이만큼 당기면 종에 닿아요")):
		problems.append("spring: no say tells the heavy ball goes as far")
	var push_texts: Array = MissionTracker.missions(ExperimentRegistry.find("friction")).stages.map(func(s: Dictionary) -> String: return str(s.text))
	if not push_texts.any(func(s: String) -> bool: return s.contains("길")):
		problems.append("friction: no stage text names the path")
	expect.call(problems.is_empty(), "piece game: the stage texts name the game, Puppy's clue points at the object (the push: the path the box blocks; the spring: the bell), the spring says the heavy ball goes as far",
		"; ".join(problems))
