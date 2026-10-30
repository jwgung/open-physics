## The learning goals of the missions (2026-10-28 user decision): each lab's stages make the child
## see the goal of a high-school law (the README's "목표 · 공식"), judged on the formula's own value.
## For the five labs whose stages were rewritten for it (free fall, spring, pendulum, orbit, push):
## (a) every stage's threshold is reachable under its fitting conditions through the real formula /
##     model the lab shows (PhysicsLaws, SpringModel, PendulumLabModel, OrbitModel, the push lab),
## (b) not under the non-fitting picture button where the rule is the lesson (Earth never falls for
##     3 s, a light ball never swings for 4 s, a short rope on the Moon never takes 8 s, a bound
##     shot never counts as leaving),
## (c) a stage's own observe / compare / judge_on override the block's (MissionRound.rule) and the
##     registry checks them,
## (d) the round's invariants still hold: the definitions validate, consecutive stages ask for other
##     conditions (or a `change`), every stage's buttons hold one that fits and one that does not,
##     and the defaults never clear stage 1 by themselves.
## Read only: no lab script or model is changed here.
extends RefCounted

var tree: SceneTree
var expect: Callable
const GOAL_LABS := ["free-fall", "spring", "constraints", "orbit", "friction"]
const LAB_MISSIONS := "res://tests/lab_mission_checks.gd"


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_rule_overrides()
	check_registry_stage_keys()
	await check_free_fall()
	await check_spring()
	check_pendulum()
	check_pendulum_half()
	await check_pendulum_card()
	check_orbit()
	await check_push()
	check_invariants()


# --- helpers ---------------------------------------------------------------------------------------

## The stage's threshold is beaten by `value` under its rule (strictly, like MissionRound.judge),
## on the number the child reads (MissionRound.shown: the card's one decimal, 2026-10-28).
static func beats(definition: Dictionary, stage: int, value: float) -> bool:
	var threshold := float(MissionRound.missions(definition).stages[stage].threshold)
	var how := MissionRound.rule(definition, stage)
	var number := MissionRound.shown(definition, how.observe, value)
	return number < threshold if how.compare == "less" else number > threshold


## The grid values of a slider control (min..max on its step).
static func grid(definition: Dictionary, id: String) -> Array:
	for control in definition.controls:
		if control.id == id:
			var out := []
			var v := float(control.min)
			while v <= float(control.max) + 1e-9:
				out.append(snappedf(v, 1e-6))
				v += float(control.step)
			return out
	return []


## The option `option` of choice control `id` (its dictionary: "g", "kg", "b", ...).
static func option(definition: Dictionary, id: String, option_id: String) -> Dictionary:
	for control in definition.controls:
		if control.id == id:
			for o in control.options:
				if o.id == option_id:
					return o
	return {}


## The picture buttons of stage `stage` for control `id` that fit (`fits`) or do not fit its condition.
static func picked(definition: Dictionary, stage: int, id: String, fits: bool) -> Array:
	for group in ConditionPicks.groups(definition, stage):
		if group.control == id:
			return group.presets.filter(func(p: Dictionary) -> bool: return MissionRound.condition_holds(group.want, p.value) == fits).map(func(p: Dictionary) -> Variant: return p.value)
	return []


func _lab(id: String) -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find(id))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


# --- (c) the stage's own rule ---------------------------------------------------------------------

## MissionRound.rule: a stage's keys over the block's; judge() uses the stage's rule.
func check_rule_overrides() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var definition := {"id": "rules", "missions": {"observe": "t", "judge_on": ["landed"], "stages": [
		{"threshold": 2.0, "text": "a"},
		{"compare": "less", "threshold": 1.0, "text": "b"},
		{"observe": "", "judge_on": ["far"], "text": "c"}]}}
	var rules := [0, 1, 2, -1].map(func(i: int) -> Dictionary: return MissionRound.rule(definition, i))
	expect.call(rules == [
		{"observe": "t", "compare": "greater", "judge_on": ["landed"]},
		{"observe": "t", "compare": "less", "judge_on": ["landed"]},
		{"observe": "", "compare": "greater", "judge_on": ["far"]},
		{"observe": "t", "compare": "greater", "judge_on": ["landed"]}]
		and MissionRound.judge_on(definition, 2) == ["far"] and MissionRound.judge_on(definition) == ["landed"],
		"goal rules: a stage's observe / compare / judge_on replace the block's, the rest is the block's", str(rules))
	var lab := Experiment.new()
	tree.root.add_child(lab)
	var tracker := MissionRound.new()
	tracker.definition = definition
	var seen := []
	seen.append(tracker.on_run_ended("landed", lab, {"t": 1.5}))   # stage 1: greater 2 -> no
	seen.append(tracker.on_run_ended("landed", lab, {"t": 2.5}))   # stage 1 cleared
	seen.append(tracker.on_run_ended("landed", lab, {"t": 2.5}))   # stage 2 is less 1 -> no
	seen.append(tracker.on_run_ended("landed", lab, {"t": 0.8}))   # stage 2 cleared (less)
	seen.append(tracker.on_run_ended("landed", lab, {"t": 0.8}))   # stage 3 judges "far" only
	seen.append(tracker.on_run_ended("far", lab, {}))              # a state goal: no number needed
	expect.call(seen == [false, true, false, true, false, true] and tracker.stamps == 3,
		"goal rules: the tracker judges each stage by its own rule (greater, then less, then the state far without a number)", str(seen))
	lab.free()
	DirAccess.remove_absolute(ProgressStore.path)


## The registry checks a stage's own keys: observe "" or an id, compare, judge_on, and a threshold
## exactly where the stage's rule has a number.
func check_registry_stage_keys() -> void:
	var base := ExperimentRegistry.find("free-fall").duplicate(true)
	expect.call(ExperimentRegistry.validate(base).is_empty(), "goal registry: the free fall's stage rules validate", ", ".join(ExperimentRegistry.validate(base)))
	var bad := [
		["an unknown stage observe", func(d: Dictionary) -> void: d.missions.stages[1].observe = "nope", "observe"],
		["a stage compare", func(d: Dictionary) -> void: d.missions.stages[2].compare = "more", "compare"],
		["an empty stage judge_on", func(d: Dictionary) -> void: d.missions.stages[0]["judge_on"] = [], "judge_on"],
		["a stage observe without its threshold", func(d: Dictionary) -> void: d.missions.stages[1].erase("threshold"), "threshold"],
		["a threshold on a state goal stage", func(d: Dictionary) -> void: d.missions.stages[0].erase("observe"), "needs missions.observe"],
	]
	for case in bad:
		var changed := base.duplicate(true)
		case[1].call(changed)
		var found := ExperimentRegistry.validate(changed)
		expect.call(not found.is_empty() and Array(found).all(func(p: String) -> bool: return case[2] in p),
			"goal registry rejects %s" % case[0], ", ".join(found))


# --- free fall: heavy and light land together; slower on the Moon (h = ½gt², t = √(2h/g)) ----------
## Since the piece game (2026-10-29) every stage judges "together_time": the heavy red and the light
## yellow ball land within one step (the same height), with the stage's world; the reachability per
## world and height is tests/game_piece_checks.gd. Here: the rule of each stage and the lab's values.

func check_free_fall() -> void:
	var definition := ExperimentRegistry.find("free-fall")
	var problems := []
	var rules := [0, 1, 2].map(func(i: int) -> Dictionary: return MissionRound.rule(definition, i))
	if rules.any(func(r: Dictionary) -> bool: return r.observe != "together_time") or rules[2].compare != "less":
		problems.append("the stages do not judge the two balls together (%s)" % str(rules))
	var worlds := [0, 1, 2].map(func(i: int) -> String: return str(MissionRound.missions(definition).stages[i].conditions.gravity))
	if worlds != ["earth", "moon", "jupiter"]:
		problems.append("the worlds %s" % str(worlds))
	# The start (the earth, the heavy red ball; red 5 m, yellow 3 m) is stage 1's setup (the world and
	# the ball); the child lifts the two level. The decision of 2026-10-29 (README).
	var start: Experiment = await _lab("free-fall")
	if not MissionRound.conditions_met(MissionRound.missions(definition).stages[0].conditions, start):
		problems.append("the start is not stage 1's setup")
	start.queue_free()
	var lab: Experiment = await _lab("free-fall")
	lab.set_control("gravity", "moon")
	lab.set_control("height", 7.0)
	var shown: Variant = lab.observations().fall_time
	if not (shown is float and absf(shown - sqrt(2.0 * 7.0 / 1.62)) < 1e-9):
		problems.append("the lab's fall_time %s is not √(2h/g)" % str(shown))
	if ExperimentRegistry.shown_cards(definition) != ["red_time"]:
		problems.append("the card is not the red ball's time")
	lab.queue_free()
	expect.call(problems.is_empty(),
		"goal (free fall): every stage judges the heavy red and the light yellow ball landing together (the earth, the Moon past 3 s, Jupiter under 1 s); the start is stage 1's setup; fall_time = √(2h/g); the card is the red ball's time",
		"; ".join(problems))


# --- spring: the swing on the clock's beat; the heavier ball swings slower (T = 2π√(m/k)) -----------

func check_spring() -> void:
	var definition := ExperimentRegistry.find("spring")
	var problems := []
	var stages: Array = MissionRound.missions(definition).stages
	var spring_script: GDScript = load("res://experiments/spring/spring.gd")
	var constants := spring_script.get_script_constant_map()
	# The bell game (2026-10-29 user "종 치기"): every stage judges how far the first swing goes past the
	# rest (bell_reach, as shown) beyond the bell's spot − 0.05 m: 0.5, 1, 1.5 m, all within the rod's
	# squeezed side (EXT_MIN) and reached from pulls on the rod (up to EXT_MAX); the card is that reach.
	var bells := [0.5, 1.0, 1.5]
	for i in stages.size():
		var how := MissionRound.rule(definition, i)
		var d: float = bells[i]
		var hit := MissionRound.beats(definition, "bell_reach", how.compare, stages[i], {"bell_reach": d})
		var short := MissionRound.beats(definition, "bell_reach", how.compare, stages[i], {"bell_reach": d - 0.1})
		if how.observe != "bell_reach" or how.compare != "greater" or not hit or short or d > -float(constants.EXT_MIN) + 1e-9 or d > float(constants.EXT_MAX):
			problems.append("stage %d: the bell at %s m (%s, hit %s, 0.1 m short %s)" % [i + 1, d, str(how), hit, short])
		if ExperimentRegistry.shown_cards(definition, i) != ["bell_reach"]:
			problems.append("stage %d card %s" % [i + 1, ExperimentRegistry.shown_cards(definition, i)])
	if not MissionRound.condition_holds(stages[2].conditions.mass, 3.0) or MissionRound.condition_holds(stages[2].conditions.mass, 1.0):
		problems.append("the last bell does not want the heavy ball")
	# The period law stays in 자세히 (the note's formula and its numbers).
	var note: Dictionary = ExperimentRegistry.note(definition)
	if note.formula != "T = 2π√(m/k)" or not note.numbers.any(func(r: Dictionary) -> bool: return "swing_period" in r.ids):
		problems.append("the period law left 자세히")
	# The lab's swing reads the formula period once the ball has been back once, not before.
	var lab: Experiment = await _lab("spring")
	lab.set_control("mass", 3.0)
	lab.run_action("release")
	await _frames(240)
	var early: Variant = lab.observations().swing_period
	await _frames(70)
	var late: Variant = lab.observations().swing_period
	if not (early is String and late is float and absf(late - TAU * sqrt(3.0 / 5.0)) < 1e-9):
		problems.append("the swing reads %s after 4 s, %s after 5.2 s (want text, then 2π√(3/5))" % [str(early), str(late)])
	lab.queue_free()
	expect.call(problems.is_empty(),
		"goal (spring): the bells at 0.5, 1, 1.5 m on the squeezed side (within EXT_MIN), each reached by the first swing as shown and not 0.1 m short, the last with the heavy ball, the card is that reach; the period law T = 2π√(m/k) stays in 자세히 and the swing reads it after one return",
		"; ".join(problems))


# --- pendulum: a longer rope and the Moon swing slower (T = 2π√(L/g)) -------------------------------

## A rope of `length` in `g` let go from the lab's start angle with its rope damping `b`, stepped
## until both periods are known: [the half swing x 2 (the mission's value), the seconds it was known
## after, the measured period (two same-way zero crossings), the seconds that was known after].
static func swing(length: float, g: float, b: float) -> Array:
	var start: float = load("res://experiments/constraints/constraints.gd").get_script_constant_map().WEB_ANGLES[0]
	var model := PendulumLabModel.new()
	model.length = length
	model.g = g
	model.damping = b
	model.reset(start)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var half_at := -1.0
	var period_at := -1.0
	while (model.period <= 0.0 or model.half_swing_period <= 0.0) and model.steps < 6000:
		model.step(dt)
		if half_at < 0.0 and model.half_swing_period > 0.0:
			half_at = model.time()
		if period_at < 0.0 and model.period > 0.0:
			period_at = model.time()
	return [model.half_swing_period, half_at, model.period, period_at]


## The period the mission judges (the half swing x 2, 2026-10-28) of a rope of `length` in `g`.
static func measured_period(length: float, g: float, b: float) -> float:
	return swing(length, g, b)[0]


func check_pendulum() -> void:
	# Since 2026-10-29 the stages are the turtle clock's beats (MissionRound "near", the piece game:
	# tests/game_piece_checks.gd check_pendulum_beat sweeps the release angles). Here: from the lab's
	# start angle, each stage's fitting rope is on the beat with either damping, the default 2 m rope
	# on the earth clears nothing, and the stages ask for different ropes and worlds.
	var definition := ExperimentRegistry.find("constraints")
	var stages: Array = MissionRound.missions(definition).stages
	var problems := []
	var seen := []
	for damping in ["web", "none"]:
		var b := float(option(definition, "damping", damping).rope_b)
		for stage in stages.size():
			var want: Dictionary = stages[stage].conditions
			var g := float(option(definition, "gravity", str(want.gravity)).g)
			for length in picked(definition, stage, "length", true):
				var t := measured_period(length, g, b)
				if damping == "web":
					seen.append("%s %s m %.2f s" % [want.gravity, length, t])
				if not _near(definition, stage, t):
					problems.append("stage %d (%s): %s m off the beat at %.2f s" % [stage + 1, damping, length, t])
	if _near(definition, 0, measured_period(2.0, 9.81, float(option(definition, "damping", "web").rope_b))) and MissionRound.condition_holds(stages[0].conditions.get("length", {}), 2.0):
		problems.append("the default 2 m rope clears stage 1")
	for stage in range(1, stages.size()):
		if stages[stage].conditions == stages[stage - 1].conditions:
			problems.append("stages %d and %d ask the same" % [stage, stage + 1])
	expect.call(problems.is_empty() and stages.all(func(s: Dictionary) -> bool: return s.get("compare") == "near"),
		"goal (pendulum): the turtle clock's beats (half swing x 2 as shown, near): from the lab's start angle the earth's long rope on 3.2 s, the Moon's short rope on 6.3 s, the Moon's very long rope on 8.8 s; the default 2 m rope clears nothing",
		"%s; %s" % [", ".join(seen), "; ".join(problems)])


## The stage's "near" rule holds for `value` (the shown number within the stage's tolerance).
static func _near(definition: Dictionary, stage: int, value: float) -> bool:
	var entry: Dictionary = MissionRound.missions(definition).stages[stage]
	var how := MissionRound.rule(definition, stage)
	return MissionRound.beats(definition, how.observe, how.compare, entry, {how.observe: value})


## The half swing x 2 against the measured period (2026-10-28): every rope of the grid, the Moon and
## the earth, with and without damping. Undamped they are the same period (a symmetric swing; 1e-5:
## the two in-step interpolations); with
## the web's damping the half swing is the first, widest one, so it is longer but by under 0.6 %.
## It is known at the turning point, half a period after the release (the measured one 1.25 later).
func check_pendulum_half() -> void:
	var definition := ExperimentRegistry.find("constraints")
	var problems := []
	var worst := {"web": 0.0, "none": 0.0}
	for damping in ["web", "none"]:
		var b := float(option(definition, "damping", damping).rope_b)
		for world in ["earth", "moon"]:
			var g := float(option(definition, "gravity", world).g)
			for length in grid(definition, "length"):
				var r := swing(length, g, b)
				var rel: float = (r[0] - r[2]) / r[2]
				worst[damping] = maxf(worst[damping], absf(rel))
				var agrees: bool = absf(rel) <= 1e-5 if damping == "none" else (rel >= 0.0 and rel <= 0.006)
				# Known within one step of half its own value after the release.
				var early: bool = absf(r[1] - 0.5 * r[0]) <= 1.0 / float(Engine.physics_ticks_per_second) + 1e-9
				if not agrees or not early or r[1] >= r[3]:
					problems.append("%s %s %s m: half x 2 %.4f s at %.2f s, period %.4f s at %.2f s" % [damping, world, length, r[0], r[1], r[2], r[3]])
	var moon := swing(2.75, 1.62, float(option(definition, "damping", "web").rope_b))
	expect.call(problems.is_empty(),
		"goal (pendulum): the half swing x 2 = the measured period (undamped to 1e-5, the web's damping 0-0.6 %% longer), known half a period after the release (the Moon's 2.75 m rope: %.2f s, not %.2f s)" % [moon[1], moon[3]],
		"worst rel %s (web), %s (none); %s" % [String.num_scientific(worst.web), String.num_scientific(worst.none), "; ".join(problems)])


## The key card and the judged value in the lab: waiting text until the first turning point on the
## other side, then the half swing x 2; the measured rope_period still waits then.
func check_pendulum_card() -> void:
	var lab: Experiment = await _lab("constraints")
	lab.set_control("gravity", "moon")
	lab.set_control("length", 2.75)
	lab.release()
	var problems := []
	var shown_at := -1.0
	var period_then: Variant = null
	var before: Variant = null
	for i in 12 * Engine.physics_ticks_per_second:
		await tree.physics_frame
		var values: Dictionary = lab.observations()
		if values.rope_half_swing is float:
			shown_at = lab.models[0].time()
			period_then = values.rope_period
			break
		before = values.rope_half_swing
	var want: float = lab.models[0].half_swing_period
	if before != "한 번 왕복하면 보여요" or shown_at < 4.0 or shown_at > 4.4 or not (period_then is String) or absf(want - measured_period(2.75, 1.62, lab.models[0].damping)) > 1e-9:
		problems.append("before %s, shown at %.2f s (%.4f s), rope_period then %s" % [before, shown_at, want, period_then])
	lab.queue_free()
	expect.call(problems.is_empty(), "goal (pendulum): the card waits (\"한 번 왕복하면 보여요\") until the turning point, then shows the half swing x 2 at about T/2 (Moon 2.75 m: about 4.2 s) while the measured period still waits",
		"; ".join(problems))


# --- orbit: the star pulls the planet round; too fast and it leaves (√(GM/r), √(2GM/r)) -----------

func check_orbit() -> void:
	var definition := ExperimentRegistry.find("orbit")
	var stages: Array = MissionRound.missions(definition).stages
	var speeds := grid(definition, "speed")
	var problems := []
	var model := OrbitModel.new()
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	# Stages 1 and 2: the laps at the circular speed of the stage's radius are reachable, and the
	# closer orbit goes round faster.
	var laps := func(radius: float, steps: int) -> float:
		model.reset(radius, 0.0, -sqrt(model.mu / radius))
		for k in steps:
			model.step(dt)
		return absf(model.swept) / TAU
	var periods := [4.0, 2.0].map(func(r: float) -> float: return TAU * sqrt(pow(r, 3.0) / model.mu))
	if not (beats(definition, 0, laps.call(float(stages[0].conditions.radius), ceili(periods[0] * 1.05 / dt)))
			and beats(definition, 1, laps.call(float(stages[1].conditions.radius), ceili(periods[1] * 2.05 / dt)))
			and periods[1] < periods[0]):
		problems.append("the laps are not reachable at the circular speed (periods %s)" % str(periods))
	# Stage 3: judged when the planet is far away (the lab's "far") on a launch past the escape speed
	# of 4 m: on the speed grid the threshold splits exactly the unbound shots from the bound ones.
	var rule := MissionRound.rule(definition, 2)
	var radius := float(stages[2].conditions.radius)
	var escape := sqrt(2.0 * model.mu / radius)
	for s in speeds:
		var unbound: bool = 0.5 * s * s - model.mu / radius >= 0.0
		if beats(definition, 2, s) != unbound:
			problems.append("%s m/s: past the threshold %s, unbound %s" % [s, beats(definition, 2, s), unbound])
	# A shot just under it (3.6 m/s) still flies past 12 m (bound, far apoapsis): "far" alone would
	# not be the law, the speed past √(2GM/r) is.
	var reach := func(speed: float) -> String:
		model.reset(radius, 0.0, -speed)
		while model.outcome == "" and model.steps < 60 * 120:
			model.step(dt)
		return model.outcome
	if rule.observe != "launch_speed" or rule.judge_on != ["far"] or reach.call(3.7) != "far" or reach.call(3.6) != "far" or absf(escape - 3.674) > 1e-3:
		problems.append("stage 3: rule %s, 3.7 m/s %s, 3.6 m/s %s, escape %.3f" % [str(rule), reach.call(3.7), reach.call(3.6), escape])
	expect.call(problems.is_empty(),
		"goal (orbit): one lap at 4 m (9.7 s) and two at 2 m (2 x 3.4 s, closer is faster); leaving from 4 m counts past 3.67 m/s (√(2GM/r) = 3.674: 3.7 leaves, 3.6 is bound though it flies past 12 m)",
		"; ".join(problems))


# --- push: the floor holds the box; heavier holds tighter (f_max = μs·m·g) --------------------------

func check_push() -> void:
	var definition := ExperimentRegistry.find("friction")
	var observation: Dictionary = definition.observations.filter(func(o: Dictionary) -> bool: return o.id == "start_force")[0]
	var lab: Experiment = await _lab("friction")
	var problems := []
	var shown := []
	var cards := []
	for mass in ["light", "normal", "heavy"]:
		lab.set_control("mass", mass)
		var want := float(option(definition, "material", "wood").mu_s) * float(option(definition, "mass", mass).kg) * float(lab.model.g)
		var before: Variant = lab.observations().start_force
		lab.set_applied_force(0.5)    # under every limit: the box holds, nothing to show yet
		await _frames(10)
		var held: Variant = lab.observations().start_force
		lab.set_applied_force(ceilf(want) + 1.0)   # a newton past the limit: it breaks loose
		await _frames(10)
		var moved: Variant = lab.observations().start_force
		lab.set_applied_force(0.0)
		await _frames(240)
		var after: Variant = lab.observations().start_force
		if not (before is String and held is String and moved is float and absf(moved - want) < 1e-9 and after == moved and lab.status() == "holding"):
			problems.append("%s: before %s, held %s, moved %s (μs m g %.3f), stopped %s (%s)" % [mass, before, held, moved, want, after, lab.status()])
		shown.append(moved)
		cards.append(ExperimentScreen.card_text(definition, observation, moved))
	# The card is a bar (kid.bars, 2026-10-28: no "뉴턴" on the kid screen): no text, heavier is longer,
	# full at the heaviest kid box on clay (its μs·m·g on the real lab).
	var bars := shown.map(func(v: float) -> float: return ExperimentScreen.bar_fraction(definition, "start_force", v))
	lab.set_control("material", "clay")
	lab.set_control("mass", "heavy")
	await _frames(2)
	var full: float = lab.model.max_static()
	lab.set_control("material", "wood")
	if not (cards == ["", "", ""] and bars[0] < bars[1] and bars[1] < bars[2] and bars[2] < 1.0
			and absf(ExperimentRegistry.card_bar(definition, "start_force") - full) < 1e-3):
		problems.append("the bar: cards %s, lengths %s, full %.3f N vs clay 10 kg %.3f N" % [str(cards), str(bars), ExperimentRegistry.card_bar(definition, "start_force"), full])
	expect.call(problems.is_empty() and shown[0] < shown[1] and shown[1] < shown[2]
		and ExperimentRegistry.shown_cards(definition) == ["start_force"],
		"goal (push): the key card shows the push that started the box as a bar (μs·m·g: 7.8 -> 19.6 -> 39.2 N light -> normal -> heavy, longer each, full at clay 10 kg 74.6 N; no text), from the moment it moves, kept after it stops, cleared by a new box",
		"%s %s; %s" % [str(shown), str(bars), "; ".join(problems)])
	# Heavier kid boxes (2026-10-28 "너무 쉽게 밀려"); since the press and hold (2026-10-28) wood takes
	# 0.31 / 0.78 / 1.57 s of holding, and every material moves every box within the hold's cap (the
	# heaviest, clay 10 kg, within 3 s); pushed for 1 s and let go, the box slides and friction stops
	# it on the track.
	problems = []
	var travel := []
	var reach: float = lab.PUSH_MAX
	var slowest := 0.0
	for material in ["rubber", "wood", "steel", "clay"]:
		for mass in ["light", "normal", "heavy"]:
			lab.set_control("material", material)
			lab.set_control("mass", mass)
			await _frames(2)
			var limit: float = lab.model.max_static()
			var push := ceilf(limit + 1e-9)
			slowest = maxf(slowest, limit / lab.PUSH_RATE)
			if material == "wood":
				travel.append(snappedf(limit / lab.PUSH_RATE, 0.01))
			if push > reach:
				problems.append("%s %s: %.2f N past the reach %.0f N" % [material, mass, limit, reach])
				continue
			lab.set_applied_force(push)
			await _frames(60)
			var moving: bool = lab.status() == "sliding"
			lab.set_applied_force(0.0)
			var k := 0
			while lab.status() == "sliding" and k < 900:
				await _frames(1)
				k += 1
			if not moving or lab.status() != "holding" or lab.model.displacement <= 0.0:
				problems.append("%s %s: %.0f N moving %s, then %s at %.2f m" % [material, mass, push, moving, lab.status(), lab.model.displacement])
	lab.queue_free()
	expect.call(problems.is_empty() and travel == [0.31, 0.78, 1.57] and slowest <= 3.0,
		"goal (push): the kid boxes 2 / 5 / 10 kg start after 0.31 / 0.78 / 1.57 s of holding on wood; every material moves every box within the cap (clay 10 kg 74.6 < 80 N, after %.2f s), slides and stops on the track" % slowest,
		"wood %s s; %s" % [str(travel), "; ".join(problems)])


# --- (d) the round's invariants ---------------------------------------------------------------------

func check_invariants() -> void:
	var disjoint: GDScript = load(LAB_MISSIONS)
	var problems := []
	for id in GOAL_LABS:
		var definition := ExperimentRegistry.find(id)
		problems.append_array(Array(ExperimentRegistry.validate(definition)).map(func(p: String) -> String: return "%s: %s" % [id, p]))
		var stages: Array = MissionRound.missions(definition).stages
		for i in stages.size():
			var on_purpose: bool = "%s %d-%d" % [id, i, i + 1] in disjoint.get_script_constant_map().SHARED_ON_PURPOSE
			if i > 0 and not on_purpose and (stages[i].get("change", []) as Array).is_empty() and not disjoint.call("_disjoint", stages[i - 1].get("conditions", {}), stages[i].get("conditions", {})):
				problems.append("%s: stages %d and %d share a setup" % [id, i, i + 1])
			for group in ConditionPicks.groups(definition, i):
				var holds: Array = group.presets.map(func(p: Dictionary) -> bool: return MissionRound.condition_holds(group.want, p.value))
				if not (holds.has(true) and holds.has(false)):
					problems.append("%s stage %d: %s needs one fitting and one other button" % [id, i + 1, group.control])
	expect.call(problems.is_empty(),
		"goal labs: the definitions validate, consecutive stages want another setup (or a change), each stage's buttons hold one that fits and one that does not",
		"; ".join(problems))
