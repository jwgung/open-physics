## Plan G1: the mission and progress model — the missions / predict blocks of the content, the
## MissionTracker (a landed run is judged by the formula value; a throw that falls short changes
## nothing), the ProgressStore (user://progress.cfg, 0..3 stamps per spot, a corrupt file starts
## over), and the physics invariant: with and without the tracker on, the projectile's trajectory
## and displayed values are the same at every step.
extends RefCounted

var tree: SceneTree
var expect: Callable
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const TABLET := Vector2(1152, 720)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_content()
	check_kid_words()
	check_key_card_words()
	check_registry_validation()
	await check_mission_tracker()
	check_progress_store()
	await check_physics_unchanged()


## The key cards over the 3D view of every listed lab (2026-10-27, 7~10세): a number reads with one
## decimal and its unit in words ("1.3초", "초속 12.5미터", "? 미터" while hidden), never a unit
## symbol or a formula letter; a lab's status text reads in its kid words. The sidebar's text of the
## same value is format_observation's, unchanged (the formula value at full precision, its unit).
func check_key_card_words() -> void:
	var symbols := RegEx.create_from_string("[A-Za-z√θ₀²³·μ=°]")
	var found := []
	var definitions := ExperimentRegistry.load_all()
	for definition in definitions:
		for observation in definition.observations:
			if observation.id not in definition.key_observations:
				continue
			var cards := []
			if observation.has("unit"):
				for value in [12.345, -0.678, 0.04, -0.04, 3.0]:
					var card := ExperimentScreen.card_text(definition, observation, value)
					cards.append(card)
					var digits := int(observation.get("digits", 2))
					var places := mini(digits, 1)
					var unit: String = observation.unit
					var sidebar := ExperimentScreen.format_observation(observation, value)
					if sidebar != Ui.number(value, digits) + (unit if unit == "°" else " " + unit):
						found.append("%s.%s sidebar %s" % [definition.id, observation.id, sidebar])
					if not card.contains(Ui.number(absf(value), places)) or (card.contains("-0.0")):
						found.append("%s.%s card %s (one decimal of %s)" % [definition.id, observation.id, card, str(value)])
				cards.append(ExperimentScreen.card_text(definition, observation, null, true))
			else:
				for text in definition.get("kid", {}).get("states", {}).keys():
					cards.append(ExperimentScreen.card_text(definition, observation, text))
			for card in cards:
				if symbols.search(card) or card == "":
					found.append("%s.%s: '%s'" % [definition.id, observation.id, card])
	expect.call(definitions.size() == 11 and found.is_empty(),
		"key cards of all %d labs: one decimal, the unit in words, no unit symbol; the sidebar text unchanged" % definitions.size(),
		"; ".join(found))
	var cases := [
		[{"unit": "m", "digits": 2}, 12.345, "12.3미터"], [{"unit": "s", "digits": 2}, 1.26, "1.3초"],
		[{"unit": "m/s", "digits": 2}, 12.46, "초속 12.5미터"], [{"unit": "°", "digits": 1}, 31.0, "31.0도"],
		[{"unit": "줄", "digits": 0}, 4.0, "4줄"], [{"unit": "m", "digits": 2}, -0.04, "0.0미터"]]
	var wrong := []
	for c in cases:
		var observation: Dictionary = c[0].merged({"id": "x"})
		if ExperimentScreen.card_text({}, observation, c[1]) != c[2]:
			wrong.append("%s -> %s" % [c[2], ExperimentScreen.card_text({}, observation, c[1])])
	var spring := ExperimentRegistry.find("spring")
	var stretch: Dictionary = spring.observations.filter(func(o: Dictionary) -> bool: return o.id == "extension")[0]
	var friction := ExperimentRegistry.find("friction")
	var state: Dictionary = friction.observations.filter(func(o: Dictionary) -> bool: return o.id == "state")[0]
	expect.call(wrong.is_empty() and ExperimentScreen.card_text(spring, stretch, -0.31) == "눌려서 0.3미터"
		and ExperimentScreen.card_text({}, {"unit": "m", "id": "x"}, null, true) == "? 미터"
		and ExperimentScreen.card_text({}, {"unit": "m/s", "id": "x"}, null, true) == "초속 ? 미터"
		and ExperimentScreen.card_text(friction, state, "버티는 중 · 마찰이 막고 있어요") == "꼼짝 안 해요"
		and ExperimentScreen.card_text(friction, state, "새 상태") == "새 상태"
		and not spring.key_observations.has("total"),
		"key card words: 12.3미터, 1.3초, 초속 12.5미터, 31.0도, 4줄, 눌려서 0.3미터, ? 미터, a status in kid words; spring's 에너지 합 only in 자세히",
		"; ".join(wrong))


# --- content --------------------------------------------------------------------------------------

## The projectile's mission and predict blocks (Plan: one predict question, two pictures, a reason a
## 7-year-old reads; the three thresholds inside the earth default-height maximum of ~8.7 m; the
## first stage takes any throw, the next ones a changed throw so the same throw never earns the next stamp).
func check_content() -> void:
	var definition := ExperimentRegistry.find("projectile")
	expect.call(definition.has("missions") and definition.has("predict"), "projectile: has the missions and predict blocks", "")
	var missions: Dictionary = definition.missions
	expect.call(missions.observe == "range" and (missions.stages as Array).size() == 3,
		"missions: judged by the formula range, three stages", str(missions.get("observe")))
	var thresholds := (missions.stages as Array).map(func(s: Dictionary) -> Variant: return s.threshold)
	expect.call(thresholds == [3.0, 5.0, 7.0] and thresholds.all(func(t: Variant) -> bool: return t <= 8.7),
		"missions: 3 m -> 5 m -> 7 m, all inside the earth default-height maximum (~8.7 m)", str(thresholds))
	var rules := (missions.stages as Array).map(func(s: Dictionary) -> Variant: return [s.get("conditions", {}), s.get("change", [])])
	expect.call(rules == [[{}, []], [{}, ["speed", "angle"]], [{}, ["angle"]]],
		"missions: any throw -> another speed or angle than the first stamp's -> another angle than the second's", str(rules))
	var texts := (missions.stages as Array).map(func(s: Dictionary) -> Variant: return s.text)
	expect.call(texts == ["3미터 넘게 던지기!", "세기나 각도를 바꿔 5미터 넘기기!", "각도를 바꿔 7미터 넘기기!"],
		"missions: the stage texts say the rule in a child's words", str(texts))
	for stage in missions.stages:
		expect.call(stage.text != "", "missions: every stage has its text", str(stage.get("threshold")))
	var predict: Dictionary = definition.predict
	expect.call(predict.question == "더 세게 던지면 더 멀리 갈까?" and (predict.choices as Array).size() == 2,
		"predict: the one question, two pictures", str(predict.get("question")))
	var ids := (predict.choices as Array).map(func(c: Dictionary) -> Variant: return c.id)
	expect.call(ids == ["farther", "same"], "predict: the two pictures are 멀리 and 똑같이", str(ids))
	expect.call(predict.reason.contains("세게") and predict.reason.contains("멀리") and not predict.reason.contains("v₀"),
		"predict: the reason says a harder throw goes farther, in a child's words (the formula stays in 자세히)", predict.reason)
	expect.call(predict.answer == "farther", "predict: the answer is 멀리", str(predict.get("answer")))
	# Every listed lab has its round now (Plan G2): three stages, a question with two pictures and an
	# answer, a reason, and every threshold / condition inside the lab's controls (the registry).
	for other in ExperimentRegistry.load_all():
		var block := MissionTracker.missions(other)
		var question := MissionTracker.predict(other)
		expect.call((block.get("stages", []) as Array).size() == 3 and question.get("answer") in
			(question.get("choices", []) as Array).map(func(c: Dictionary) -> Variant: return c.id) and str(question.get("reason", "")) != ""
			and ExperimentRegistry.validate(other).is_empty(),
			"%s: three stages, a question with two pictures, its answer and reason" % other.id, ", ".join(ExperimentRegistry.validate(other)))


## Words a 7-year-old does not read (the formula's names and symbols): they stay in "자세히".
const JARGON := ["가속도", "탈출", "반지름", "질량", "구속", "주기", "계수", "임계", "운동량", "마찰력", "부력",
	"토크", "역학", "속력", "탄성", "밀도", "공식", "궤도", "v₀", "μ", "√", "=", "÷", "×", "m/s", " N", "kg"]


## The game layer of every lab speaks a child's words (Plan G2 follow-up, 2026-10-27): the title
## bar, the map's place, Dugi's say, the gesture tip, the key cards' captions, the stage texts, the
## question, its two choices, the reason and the strip's done / pick texts have none of JARGON;
## every key card has its kid caption.
func check_kid_words() -> void:
	var found := []
	for definition in ExperimentRegistry.load_all():
		var texts := [ExperimentScreen.DONE_TEXT, ExperimentScreen.PICK_PREFIX, IslandHomeScreen.BADGE]
		for key in ExperimentRegistry.KID_TEXTS:
			texts.append(ExperimentRegistry.kid_text(definition, key))
		texts.append_array(definition.get("kid", {}).get("states", {}).values())
		texts.append_array(definition.get("kid", {}).get("minus", {}).values())
		for id in definition.key_observations:
			texts.append(ExperimentRegistry.card_label(definition, id))
			if not definition.get("kid", {}).get("cards", {}).has(id):
				found.append("%s: no kid caption for %s" % [definition.id, id])
		for stage in MissionTracker.missions(definition).get("stages", []):
			texts.append(str(stage.text))
		var predict := MissionTracker.predict(definition)
		texts.append(str(predict.get("question", "")))
		texts.append(str(predict.get("reason", "")))
		for choice in predict.get("choices", []):
			texts.append(str(choice.label))
		for action in definition.actions:
			texts.append(str(action.label))
		for text in texts:
			for word in JARGON:
				if word in text:
					found.append("%s: '%s' in %s" % [definition.id, word, text])
	expect.call(found.is_empty(), "kid words: the game layer of every lab has no formula names or symbols, and every key card a kid caption",
		"; ".join(found))


# --- registry validation ---------------------------------------------------------------------------

## Malformed missions / predict are rejected (like the other blocks).
func check_registry_validation() -> void:
	var base := ExperimentRegistry.find("incline-friction").duplicate(true)
	# The base file has no observations list in its raw form: use a defined one.
	var defined := ExperimentRegistry.find("projectile").duplicate(true)
	var problems := ExperimentRegistry.validate(defined)
	expect.call(problems.is_empty(), "projectile (with its missions) is a valid definition", ", ".join(problems))
	var broken := defined.duplicate(true)
	broken.missions.observe = "no-such-observation"
	var found := ExperimentRegistry.validate(broken)
	expect.call(found.size() == 1 and "missions.observe" in found[0],
		"registry rejects a mission judged by an unknown observation id", ", ".join(found))
	var four := defined.duplicate(true)
	four.missions.stages = four.missions.stages.duplicate(true)
	four.missions.stages.append({"threshold": 9.0, "text": "네 번째"})
	found = ExperimentRegistry.validate(four)
	expect.call(found.size() == 1 and "missions.stages" in found[0],
		"registry rejects four stages (the stamp cap is 3)", ", ".join(found))
	var nontext := defined.duplicate(true)
	nontext.missions.stages = defined.missions.stages.duplicate(true)
	nontext.missions.stages[0].text = ""
	found = ExperimentRegistry.validate(nontext)
	expect.call(found.size() == 1 and "text" in found[0], "registry rejects an empty stage text", ", ".join(found))
	var nethreshold := defined.duplicate(true)
	nethreshold.missions.stages = defined.missions.stages.duplicate(true)
	nethreshold.missions.stages[0].threshold = 0.0
	found = ExperimentRegistry.validate(nethreshold)
	expect.call(found.size() == 1 and "threshold" in found[0], "registry rejects a non-positive threshold", ", ".join(found))
	# The G2 fields: compare, judge_on / reveal_on, state goals, conditions on the controls.
	var bad := [
		["compare", func(d: Dictionary) -> void: d.missions.compare = "more", "compare"],
		["judge_on", func(d: Dictionary) -> void: d.missions.judge_on = [], "judge_on"],
		["reveal_on", func(d: Dictionary) -> void: d.missions.reveal_on = ["landed", 3], "reveal_on"],
		["a missing threshold", func(d: Dictionary) -> void: d.missions.stages[1].erase("threshold"), "threshold"],
		["a threshold without observe", func(d: Dictionary) -> void: d.missions.erase("observe"), "needs missions.observe"],
		["an unknown control", func(d: Dictionary) -> void: d.missions.stages[0]["conditions"] = {"wind": 1.0}, "not a control"],
		["an unknown option", func(d: Dictionary) -> void: d.missions.stages[0]["conditions"] = {"gravity": "mars"}, "option id"],
		["a slider value out of range", func(d: Dictionary) -> void: d.missions.stages[0]["conditions"] = {"speed": 12.0}, "inside the slider"],
		["an empty range", func(d: Dictionary) -> void: d.missions.stages[0]["conditions"] = {"speed": {"min": 8.0, "max": 2.0}}, "inside the slider"],
		["a predict picture", func(d: Dictionary) -> void: d.predict.choices[0].picture = "rocket", "picture"],
		["a predict answer", func(d: Dictionary) -> void: d.predict.answer = "maybe", "answer"],
		["one choice", func(d: Dictionary) -> void: d.predict.choices = [d.predict.choices[0]], "two choices"],
		["a kid key", func(d: Dictionary) -> void: d.kid["color"] = "빨강", "kid.color"],
		["an empty kid text", func(d: Dictionary) -> void: d.kid.say = "", "kid.say"],
		["a kid card", func(d: Dictionary) -> void: d.kid.cards = {"nope": "없어요"}, "kid.cards"],
		["a hidden line", func(d: Dictionary) -> void: d.missions.hidden_series_until_end = ["nope"], "hidden_series_until_end"],
	]
	for case in bad:
		var changed := defined.duplicate(true)
		case[1].call(changed)
		found = ExperimentRegistry.validate(changed)
		expect.call(not found.is_empty() and Array(found).all(func(p: String) -> bool: return case[2] in p),
			"registry rejects %s" % case[0], ", ".join(found))
	var fine := defined.duplicate(true)
	fine.missions.compare = "less"
	fine.missions.stages[0]["conditions"] = {"gravity": "moon", "speed": {"min": 2.0}, "angle": 45.0}
	expect.call(ExperimentRegistry.validate(fine).is_empty(), "registry takes compare less and conditions (an option, a range, a value)",
		", ".join(ExperimentRegistry.validate(fine)))
	var goal := ExperimentRegistry.find("friction").duplicate(true)
	expect.call(not goal.missions.has("observe") and ExperimentRegistry.validate(goal).is_empty(),
		"registry takes a state goal (no observe, no thresholds: the friction box moving)", "")
	# A file without `missions` still validates (optional block).
	var none := defined.duplicate(true)
	none.erase("missions")
	expect.call(ExperimentRegistry.validate(none).is_empty(), "missions is an optional block", "")


# --- the tracker -----------------------------------------------------------------------------------

## A landed run judged by the formula value: clears the stage, awards the stamp; a short throw,
## a run without a number and a not-yet-settled landing change nothing; all three stages -> done.
func check_mission_tracker() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var definition := ExperimentRegistry.find("projectile").duplicate(true)
	var awarded := []
	var tracker := MissionTracker.new()
	tracker.definition = definition
	tracker.progress = func(id: String, stamps: int) -> void:
		awarded.append([id, stamps])
		var store := ProgressStore.load()
		store["projectile"] = stamps
		ProgressStore.save(store)
	var stubs := [
		["settled", "extends Experiment\nvar speed := 6.0\nvar angle := 45.0\nfunc status() -> String:\n\treturn \"landed\"\nfunc settled() -> bool:\n\treturn true\nfunc control_value(id: String) -> Variant:\n\treturn angle if id == \"angle\" else speed\n"],
		["not_settled", "extends Experiment\nvar speed := 6.0\nvar angle := 45.0\nfunc status() -> String:\n\treturn \"landed\"\nfunc settled() -> bool:\n\treturn false\nfunc control_value(id: String) -> Variant:\n\treturn angle if id == \"angle\" else speed\n"],
	]
	var labs := {}
	for stub in stubs:
		var script := GDScript.new()
		script.source_code = stub[1]
		script.reload()
		var lab = script.new()
		tree.root.add_child(lab)
		labs[stub[0]] = lab
	var stages: Array = definition.missions.stages
	expect.call(tracker.stage() == 0 and tracker.text() == stages[0].text, "the first stage is 3 m", tracker.text())
	tracker.on_run_ended("flying", labs.settled, {"range": 4.0})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a throw in flight is not judged", str(awarded))
	tracker.on_run_ended("landed", labs.settled, {"range": 2.9})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a throw that falls short (2.9 m < 3 m) changes nothing", str(awarded))
	tracker.on_run_ended("landed", labs.settled, {"range": "닿지 않아요"})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a run with no number is not judged", str(awarded))
	tracker.on_run_ended("out", labs.settled, {"range": 9.0})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a flight out of the island is not a stage clear", str(awarded))
	tracker.on_run_ended("landed", labs.not_settled, {"range": 9.0})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a landing the engine has not finished is not judged yet", str(awarded))
	tracker.on_run_ended("landed", labs.settled, {"range": 3.0})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "exactly at the threshold is not farther", str(awarded))
	labs.settled.speed = 9.0
	tracker.on_run_ended("landed", labs.settled, {"range": 8.26})
	await tree.process_frame
	expect.call(tracker.stage() == 1 and tracker.text() == stages[1].text and awarded == [["projectile", 1]]
		and ProgressStore.cleared("projectile") == {"speed": 9.0, "angle": 45.0},
		"any throw past 3 m (even the strongest, 9 m/s) clears the first stage; its speed and angle are kept",
		"%d stage, %s, kept %s" % [tracker.stage(), str(awarded), str(ProgressStore.cleared("projectile"))])
	tracker.on_run_ended("landed", labs.settled, {"range": 8.26})
	expect.call(tracker.stage() == 1 and awarded == [["projectile", 1]],
		"the same throw again (45°, 9 m/s) earns no second stamp, even past 5 m", str(awarded))
	# A reopened place reads the kept throw: the same throw still earns nothing there.
	var reopened := MissionTracker.new()
	reopened.definition = definition
	ProgressStore.save({"projectile": 1})
	reopened.start()
	reopened.on_run_ended("landed", labs.settled, {"range": 8.26})
	expect.call(reopened.stamps == 1 and reopened.cleared == {"speed": 9.0, "angle": 45.0},
		"a reopened place keeps the first stamp's throw: the same throw again earns nothing", str(reopened.cleared))
	labs.settled.angle = 40.0
	tracker.on_run_ended("landed", labs.settled, {"range": 4.9})
	expect.call(tracker.stage() == 1 and awarded.size() == 1, "a changed throw short of 5 m changes nothing", str(awarded))
	tracker.on_run_ended("landed", labs.settled, {"range": 8.13})
	await tree.process_frame
	expect.call(tracker.stage() == 2 and awarded.size() == 2, "another angle (40°) past 5 m clears the second stage", str(awarded))
	labs.settled.speed = 8.5
	tracker.on_run_ended("landed", labs.settled, {"range": 7.26})
	expect.call(tracker.stage() == 2 and awarded.size() == 2,
		"the third stage wants another angle: the second stamp's 40° (only the speed changed) earns nothing, however far", str(awarded))
	labs.settled.angle = 45.0
	tracker.on_run_ended("landed", labs.settled, {"range": 7.37})
	await tree.process_frame
	expect.call(tracker.stage() == -1 and tracker.text() == "" and awarded == [["projectile", 1], ["projectile", 2], ["projectile", 3]],
		"another angle (45°) past 7 m clears the last stage; all three stamps, done", "stage %d, %s" % [tracker.stage(), str(awarded)])
	# MissionTracker.changed alone: no ids or no kept run counts as changed.
	expect.call(MissionTracker.changed([], labs.settled, {"angle": 45.0}) and MissionTracker.changed(["angle"], labs.settled, {})
		and not MissionTracker.changed(["angle"], labs.settled, {"angle": 45.0}) and MissionTracker.changed(["angle"], labs.settled, {"angle": 40.0}),
		"change: nothing named or nothing kept is a change; the same value is not, another one is", "")
	# A lab without missions: nothing to track.
	var plain := ExperimentRegistry.find("free-fall").duplicate(true)
	plain.erase("missions")
	var bare := MissionTracker.new()
	bare.definition = plain
	expect.call(bare.stage() == -1 and bare.text() == "", "a lab without missions has no stage", "")
	bare.on_run_ended("landed", labs.settled, {"range": 99.0})
	expect.call(bare.stage() == -1, "a lab without missions is never judged", "")
	await _check_judge_kinds()
	for lab in labs.values():
		lab.queue_free()
	await tree.process_frame


## The G2 judgements on the tracker alone: "less" (a smaller force clears), a stage's conditions
## (the lab's control values), a state goal (no observe), judge_on statuses, one stamp per call.
func _check_judge_kinds() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var script := GDScript.new()
	script.source_code = "extends Experiment\nvar mass := 20.0\nvar size := \"big\"\n" \
		+ "func control_value(id: String) -> Variant:\n\treturn mass if id == \"mass\" else size\n"
	script.reload()
	var lab: Experiment = script.new()
	tree.root.add_child(lab)
	var definition := {"id": "kinds", "missions": {"observe": "force", "compare": "less", "judge_on": ["lifted"], "stages": [
		{"threshold": 150.0, "text": "a", "conditions": {"mass": 20.0}},
		{"threshold": 100.0, "text": "b", "conditions": {"mass": {"min": 15.0}, "size": "big"}}]}}
	var tracker := MissionTracker.new()
	tracker.definition = definition
	var seen := []
	seen.append(tracker.on_run_ended("lifted", lab, {"force": 186.9}))   # not less than 150
	seen.append(tracker.on_run_ended("lifted", lab, {"force": 150.0}))   # exactly at it: not less
	seen.append(tracker.on_run_ended("pressing", lab, {"force": 40.0}))  # not a judge_on status
	lab.mass = 19.0
	seen.append(tracker.on_run_ended("lifted", lab, {"force": 40.0}))    # another load (20 kg wanted)
	lab.mass = 20.0
	seen.append(tracker.on_run_ended("lifted", lab, {"force": 124.6}))   # clears stage 1
	seen.append(tracker.on_run_ended("lifted", lab, {"force": 99.0}))    # stage 2 (min 15 kg, big)
	expect.call(seen == [false, false, false, false, true, true] and tracker.stamps == 2,
		"tracker: compare less (strict), judge_on, the stage's control conditions (a value, a range, an option)", str(seen))
	DirAccess.remove_absolute(ProgressStore.path)
	var state := MissionTracker.new()
	state.definition = {"id": "state", "missions": {"judge_on": ["floating"], "stages": [
		{"text": "a", "conditions": {"size": "small"}}, {"text": "b"}]}}
	lab.size = "big"
	var first := state.on_run_ended("floating", lab, {})
	lab.size = "small"
	var second := state.on_run_ended("floating", lab, {})
	var third := state.on_run_ended("moving", lab, {})
	expect.call(not first and second and not third and state.stamps == 1,
		"tracker: a state goal clears on its judge_on status with its conditions (no observe)", "%s %s %s" % [first, second, third])
	expect.call(MissionTracker.result_in(ExperimentRegistry.find("constraints"), "swinging", {"rope_period": "한 번 왕복하면 보여요"}) == false
		and MissionTracker.result_in(ExperimentRegistry.find("constraints"), "swinging", {"rope_period": 2.9})
		and MissionTracker.result_in(ExperimentRegistry.find("projectile"), "fence", {"range": 9.0})
		and not MissionTracker.result_in(ExperimentRegistry.find("projectile"), "flying", {"range": 9.0}),
		"tracker: the result is in on a reveal_on status once the observed value is a number", "")
	lab.queue_free()
	DirAccess.remove_absolute(ProgressStore.path)


# --- the store -------------------------------------------------------------------------------------

## user://progress.cfg: 0..3 stamps per spot, saved and reloaded; a corrupt file starts over.
func check_progress_store() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var path := ProjectSettings.globalize_path(ProgressStore.path)
	var backup := ""
	if FileAccess.file_exists(ProgressStore.path):
		backup = FileAccess.get_file_as_string(ProgressStore.path)
	DirAccess.remove_absolute(ProgressStore.path)
	# A missing file is no progress.
	expect.call(ProgressStore.load().is_empty(), "a missing file is no progress", "")
	# Save, reload.
	var progress := ProgressStore.load()
	progress["projectile"] = 2
	ProgressStore.save(progress)
	var reloaded := ProgressStore.load()
	expect.call(reloaded == {"projectile": 2} and ProgressStore.stamps(reloaded, "projectile") == 2 \
		and ProgressStore.stamps(reloaded, "orbit") == 0, "stamps are saved and reloaded (2 for projectile, 0 for the rest)", str(reloaded))
	# A corrupt file (broken cfg) is no progress, not an error.
	DirAccess.remove_absolute(ProgressStore.path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ProgressStore.path).get_base_dir())
	var file := FileAccess.open(ProgressStore.path, FileAccess.WRITE)
	file.store_string("this is { not a config file ]\n")
	file.close()
	expect.call(ProgressStore.load().is_empty(), "a corrupt file reads back as no progress (start over)", "")
	# A cfg with a section whose stamp is not a number or out of range is dropped. ConfigFile reads
	# a "99" as the string "99" (a hand-written cfg): the numeric-string path of the loader.
	file = FileAccess.open(ProgressStore.path, FileAccess.WRITE)
	file.store_string("[progress]\nprojectile=99\norbit=2\nbuoyancy=1\n")
	file.close()
	var loaded := ProgressStore.load()
	expect.call(loaded == {"orbit": 2, "buoyancy": 1} and ProgressStore.load().get("projectile") == null,
		"a stamp out of range (99) is dropped, a valid one stays", str(loaded))
	# The store is the app's own file: a save after a corrupt read replaces it.
	ProgressStore.save({"projectile": 1})
	expect.call(ProgressStore.load() == {"projectile": 1}, "a save after a corrupt read replaces the file", str(ProgressStore.load()))
	# The kept throw (MissionTracker `change`) lives beside the stamps: a stamp save keeps it, a value
	# that is not an object reads back as none.
	ProgressStore.save({"projectile": 1})
	ProgressStore.save_cleared("projectile", {"speed": 7.5, "angle": 40.0})
	ProgressStore.save({"projectile": 2})
	var kept := ProgressStore.cleared("projectile")
	file = FileAccess.open(ProgressStore.path, FileAccess.WRITE)
	file.store_string("[progress]\nprojectile=2\n[cleared]\nprojectile=\"oops\"\n")
	file.close()
	expect.call(kept == {"speed": 7.5, "angle": 40.0} and ProgressStore.load() == {"projectile": 2} and ProgressStore.cleared("projectile").is_empty()
		and ProgressStore.cleared("orbit").is_empty(),
		"the kept throw survives a stamp save; a broken one or none reads back as {}", str(kept))
	DirAccess.remove_absolute(ProgressStore.path)
	if backup != "":
		file = FileAccess.open(ProgressStore.path, FileAccess.WRITE)
		file.store_string(backup)
		file.close()


# --- physics unchanged -----------------------------------------------------------------------------


## One recorded throw of 40 deg, 8.5 m/s on the projectile screen (earth, 0.5 m): from the frame of
## the throw on, every 5th physics step the status, the panel's values and the engine ball's
## transform. `missions`: the screen with its mission round (the tracker judging, the strip, Dugi's
## question) or a definition without the missions / predict blocks (no tracker at all).
## `slingshot`: the throw is a real pull on the ball through the view's touch input, else the two
## sliders and "공 놓기" (the same frame either way).
func _record(missions: bool, slingshot: bool) -> Array:
	var definition := ExperimentRegistry.find("projectile").duplicate(true)
	if not missions:
		definition.erase("missions")
		definition.erase("predict")
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	var lab: Experiment = screen.experiment
	var tracked: bool = screen._missions != null
	var out := []
	var statuses := []
	var previous := lab.status()
	for k in 600:
		await tree.physics_frame
		if k == 30:
			if slingshot:
				_pull(screen, lab, 40.0, 8.5)
			else:
				screen._set_control("angle", 40.0)
				screen._set_control("speed", 8.5)
				screen.experiment_action("release")
		if lab.status() != previous:
			statuses.append(lab.status())
		previous = lab.status()
		if k >= 30 and k % 5 == 0:
			out.append([lab.status(), str(lab.observations()), lab.ball.global_transform])
	var values: Dictionary = lab.observations()
	host.queue_free()
	await tree.process_frame
	return [out, statuses, values, tracked]


## A slingshot pull to (angle, speed) and the release, all in this frame (press, moves, release).
func _pull(screen: Control, lab: Experiment, angle: float, speed: float) -> void:
	var surface: PolarArrowSurface = screen.manipulator.slingshot_surface
	var press: Vector2 = screen.view_point(lab.ball_center())
	var launch := PolarArrowSurface.tip_point(angle, speed, 0.0, surface.arrow_scale)
	var finger: Vector2 = screen.view_point(surface.pose(surface.to_plane(lab.ball_center()) - launch, 0.0).origin)
	for step in [[press, true], [press.lerp(finger, 0.5), null], [finger, null], [finger, false]]:
		var event: InputEvent
		if step[1] == null:
			event = InputEventScreenDrag.new()
		else:
			event = InputEventScreenTouch.new()
			event.pressed = step[1]
		event.position = step[0]
		screen.view._gui_input(event)


## The first row where two recordings differ (-1: none), and whether they have the same length.
static func _first_difference(a: Array, b: Array) -> int:
	for k in mini(a.size(), b.size()):
		if a[k] != b[k]:
			return k
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


func check_physics_unchanged() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var plain: Array = await _record(false, false)
	var game: Array = await _record(true, false)
	var pulled: Array = await _record(true, true)
	expect.call(not plain[3] and game[3] and pulled[3], "physics check: the plain screen has no tracker, the game screens have one", "")
	var with_round := _first_difference(plain[0], game[0])
	expect.call(with_round == -1 and plain[0].size() > 100,
		"projectile: with or without the mission round, the trajectory and the displayed values are the same at every step",
		"first difference at row %d of %d" % [with_round, plain[0].size()])
	var by_pull := _first_difference(game[0], pulled[0])
	expect.call(by_pull == -1,
		"projectile: a slingshot throw and the sliders + 공 놓기 at the same angle and speed fly the same, step by step",
		"first difference at row %d of %d" % [by_pull, game[0].size()])
	var values: Dictionary = pulled[2]
	expect.call(values.range is float and float(values.range) > 7.0 and pulled[1].has("landed"),
		"the 40° 8.5 m/s throw lands past 7 m (formula range %s)" % str(values.range), str(pulled[1]))
	# The first game screen's throw (past 3 m) earns the first stamp; the same throw again on the
	# slingshot screen earns no second one (stage 2 wants another speed or angle); the plain screen
	# judged nothing (game_round_checks earns them stage by stage).
	expect.call(ProgressStore.load().get("projectile", 0) == 1,
		"the game screens' 40° 8.5 m/s throws: the first earns the first stamp, the same throw again no second; the plain screen judged nothing",
		"stored %s" % str(ProgressStore.load()))
	DirAccess.remove_absolute(ProgressStore.path)
