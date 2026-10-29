## The kid screen's words and the science note (2026-10-28 user decisions "어려운 말들은 세부 쪽으로
## 빼자", "세부쪽도 좀 정리가 필요해"):
## - the number judged is the number shown (MissionTracker.shown: the card's one decimal),
## - the free fall's card and stamps are the red ball's own time (not the slowest ball's),
## - the spring's first stage shows how far the ball was pulled, the later stages the swing,
## - the push's card is a bar (no "뉴턴" on the kid screen), its number in "자세히",
## - a content lint over every kid text: no "뉴턴", no "초속", no decimals in the stage texts and the
##   picture buttons, 강철 (not 금속), the approved wordings,
## - the science note of every lab: 법칙 (one sentence, one formula), 이번 실험 숫자 (3-4 numbers),
##   조건 바꾸기, 그래프 only where the note keeps it, and a collapsed 더 보기 with everything else.
## Read only: nothing here changes a lab's physics.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const TABLET := Vector2(1152, 720)
## Words the kid screen never shows (they live in "자세히").
const BANNED := ["뉴턴", "초속", "금속"]


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_shown_number()
	check_content_lint()
	await check_free_fall_card()
	await check_spring_card()
	await check_push_bar()
	for definition in ExperimentRegistry.load_all():
		await check_note(definition)


func _open(id: String) -> Control:
	DirAccess.remove_absolute(ProgressStore.path)   # stage 1
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	for i in 3:
		await tree.process_frame
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProgressStore.path)


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


# --- the number shown is the number judged -------------------------------------------------------

## A stage compares the card's rounding with its threshold: 3.04 s reads "3.0초" and is not past 3 s,
## 3.06 s reads "3.1초" and is; 0.96 s reads "1.0초" and is not under 1 s, 0.94 s is.
func check_shown_number() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var definition := {"id": "shown", "observations": [{"id": "t", "unit": "s", "digits": 2}],
		"missions": {"observe": "t", "judge_on": ["landed"], "stages": [
			{"threshold": 3.0, "text": "a"}, {"compare": "less", "threshold": 1.0, "text": "b"}]}}
	var lab := Experiment.new()
	tree.root.add_child(lab)
	var seen := []
	for value in [3.04, 3.06, 0.96, 0.94]:
		seen.append(MissionTracker.judge(definition, 0 if value > 2.0 else 1, "landed", lab, {"t": value}))
	var cards := [3.04, 3.06, 0.96, 0.94].map(func(v: float) -> String: return ExperimentScreen.card_text(definition, definition.observations[0], v))
	lab.free()
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(seen == [0, 1, 1, 2] and cards == ["3.0초", "3.1초", "1.0초", "0.9초"],
		"kid words: a stage judges the number its card shows (3.04 s = 3.0초 is not past 3 s, 3.06 s = 3.1초 is; 0.96 s = 1.0초 is not under 1 s, 0.94 s is)",
		"stamps %s, cards %s" % [str(seen), str(cards)])


# --- the content lint -----------------------------------------------------------------------------

## Every text a child reads on the lab screen: the title, Dugi's say, the tip, the card captions and
## state words, the stage texts, the picture buttons, the question and its choices and reason, the
## story's clues, and the cards and the slingshot readout for a few values.
static func kid_texts(definition: Dictionary) -> Array:
	var texts := []
	for key in ["title", "place", "say", "tip"]:
		texts.append(ExperimentRegistry.kid_text(definition, key))
	var kid: Dictionary = definition.get("kid", {}) if definition.get("kid") is Dictionary else {}
	for key in ["cards", "states", "minus"]:
		texts.append_array((kid.get(key, {}) as Dictionary).values())
	var predict := MissionTracker.predict(definition)
	texts.append(str(predict.get("question", "")))
	texts.append(str(predict.get("reason", "")))
	for choice in predict.get("choices", []):
		texts.append(str(choice.get("label", "")))
	var story: Dictionary = definition.get("story", {}) if definition.get("story") is Dictionary else {}
	texts.append_array(story.values())
	texts.append_array(stage_and_pick_texts(definition))
	return texts


## The stage texts and the picture buttons' labels (no decimals there: "2미터", "가벼운 공").
static func stage_and_pick_texts(definition: Dictionary) -> Array:
	var texts := []
	for stage in MissionTracker.missions(definition).get("stages", []):
		texts.append(str(stage.get("text", "")))
	for presets in ConditionPicks.picks(definition).values():
		for preset in presets:
			texts.append(str(preset.get("label", "")))
	return texts


func check_content_lint() -> void:
	var decimal := RegEx.create_from_string("\\d[.,]\\d")
	var found := []
	for definition in ExperimentRegistry.load_all():
		var texts := kid_texts(definition)
		for observation in definition.observations:
			if observation.id in definition.key_observations:
				for value in [12.345, -3.21, 0.5]:
					texts.append(ExperimentScreen.card_text(definition, observation, value))
				texts.append(ExperimentScreen.card_text(definition, observation, null, true))
		for text in texts:
			for word in BANNED:
				if str(text).contains(word):
					found.append("%s: '%s' (%s)" % [definition.id, text, word])
		for text in stage_and_pick_texts(definition):
			if decimal.search(str(text)):
				found.append("%s: '%s' (a decimal)" % [definition.id, text])
		for control in definition.controls:
			for option in control.get("options", []):
				if str(option.get("label", "")) == "금속":
					found.append("%s.%s: 금속 (강철)" % [definition.id, control.id])
	# The slingshot's readout reads its speed "1초에 … 미터".
	var readout := ExperimentScreen.kid_value("m/s", 8.5, 1)
	if readout != "1초에 8.5미터":
		found.append("slingshot speed '%s'" % readout)
	# The approved wordings (2026-10-28).
	var want := {
		"pulley": [ExperimentRegistry.kid_text(ExperimentRegistry.find("pulley"), "title"), "줄이 많으면 힘이 덜 들까?"],
		"buoyancy": [MissionTracker.missions(ExperimentRegistry.find("buoyancy")).stages[0].text, "보물 상자를 매단 큰 통을 물에 띄우기!"],
		"constraints": [ExperimentRegistry.find("constraints").story.clue, "거북이 시계 속에 조각이 있어! 공을 시계 추랑 똑같이 흔들어 보자!"],
		# The piece game's stages (2026-10-29).
		"spring": [MissionTracker.missions(ExperimentRegistry.find("spring")).stages.map(func(s: Dictionary) -> String: return s.text),
			["가벼운 공을 당겨 가까운 종 치기!", "더 멀리 당겨서 먼 종 치기!", "무거운 공으로 제일 먼 종 치기!"]],
		"free-fall": [MissionTracker.missions(ExperimentRegistry.find("free-fall")).stages.map(func(s: Dictionary) -> String: return s.text),
			["빨간 공과 노란 공을 같이 떨어뜨려 버튼 누르기!", "달에서 두 공을 맨 위에서 같이 떨어뜨리기!", "목성에서 두 공을 같이 1초 안에 떨어뜨리기!"]],
		"collision": [MissionTracker.missions(ExperimentRegistry.find("collision")).stages.map(func(s: Dictionary) -> String: return s.text),
			["같은 무게 공을 세게 부딪혀 얼음에 금 내기!", "무거운 파란 공으로 더 세게 부딪히기!", "무거운 주황 공을 세게 쳐서 얼음 깨기!"]],
		# Batch B (2026-10-29) and the throw's angle game.
		"projectile": [MissionTracker.missions(ExperimentRegistry.find("projectile")).stages.map(func(s: Dictionary) -> String: return s.text),
			["낮게 던져서 가까운 상자 맞히기!", "얼마나 기울여 던질까? 먼 상자 맞히기!", "높이 던져서 나무 위 상자 맞히기!"]],
		"constraints_stages": [MissionTracker.missions(ExperimentRegistry.find("constraints")).stages.map(func(s: Dictionary) -> String: return s.text),
			["지구에서 긴 줄로 거북이 박자 맞추기!", "달에서 짧은 줄로 느린 거북이 박자 맞추기!", "달에서 아주 긴 줄로 아주 느린 박자 맞추기!"]],
		"pulley_stages": [MissionTracker.missions(ExperimentRegistry.find("pulley")).stages.map(func(s: Dictionary) -> String: return s.text),
			["1줄로 보물 상자를 선반까지 올리기!", "2줄로 보물 상자를 선반까지 올리기!", "4줄로 가볍게 선반까지 올리기!"]],
		"incline-friction": [MissionTracker.missions(ExperimentRegistry.find("incline-friction")).stages.map(func(s: Dictionary) -> String: return s.text),
			["강철 미끄럼틀로 작은 도미노 넘어뜨리기!", "나무 미끄럼틀을 더 기울여 큰 도미노 넘어뜨리기!", "고무 미끄럼틀을 많이 기울여 빨간 기둥 넘어뜨리기!"]],
	}
	for id in want:
		if want[id][0] != want[id][1]:
			found.append("%s: '%s' (want '%s')" % [id, str(want[id][0]), str(want[id][1])])
	var fall := ExperimentRegistry.find("free-fall")
	if not (ExperimentRegistry.kid_text(fall, "say").contains("같은 높이에서 놓으면 같이 닿아요") and fall.predict.reason.contains("같은 높이에서 놓으면 같이 닿아요")
			and fall.predict.choices[0].label == "같이 닿아요"):
		found.append("free-fall: the law 같은 높이에서 놓으면 같이 닿아요 (choice kept short)")
	# The collision's balls by weight in words: one word per weight, the same word = the same weight.
	var words := {}
	for presets in ConditionPicks.picks(ExperimentRegistry.find("collision")).values():
		for preset in presets:
			if words.has(preset.label) and words[preset.label] != float(preset.value):
				found.append("collision: '%s' is %s kg and %s kg" % [preset.label, words[preset.label], preset.value])
			words[preset.label] = float(preset.value)
	expect.call(found.is_empty(),
		"kid words: no 뉴턴 / 초속 / 금속 on the kid screen (cards, stages, buttons, question, clues), no decimals in stage texts and picture buttons, the speed reads 1초에 … 미터, the approved wordings, collision weights in words",
		"; ".join(found))


# --- the cards ------------------------------------------------------------------------------------

## The free fall's card is the red ball's time: with the red ball low and the yellow one high, the
## red ball has landed while the yellow one still falls; the card stays at the red ball's landing
## while the slowest ball's time (`time`) runs on.
func check_free_fall_card() -> void:
	var screen := await _open("free-fall")
	screen._end_question()
	var lab: Experiment = screen.experiment
	screen._set_control("height", 2.0)
	lab.manipulation_placed("yellow", Transform3D(Basis(), Vector3(lab.starts.yellow.x, 8.0 + 0.25, 0.0)))
	screen.experiment_action("release")
	await _frames(54)   # 0.9 s: the red ball (2 m, 0.64 s) is down, the yellow one (8 m, 1.28 s) not
	screen._poll()
	var values: Dictionary = lab.observations()
	var red := PhysicsLaws.landing_time(0.0, -9.81, 2.0)
	var card: String = screen._key_labels.red_time.text if screen._key_labels.has("red_time") else ""
	var ok: bool = lab.status() == "falling" and screen.key_card_ids() == ["red_time"] and absf(float(values.red_time) - red) < 1e-9 \
		and float(values.time) > red + 0.2 and card == ExperimentScreen.kid_value("s", red, 2) and card != ExperimentScreen.kid_value("s", float(values.time), 2)
	expect.call(ok, "kid words: the free fall's card is the red ball's own time (landed at 0.6초 while the high yellow ball still falls), not the slowest ball's",
		"status %s, card '%s', red_time %s, time %s" % [lab.status(), card, str(values.red_time), str(values.time)])
	await _close(screen)


## The spring's card (2026-10-29, the bell game): every stage shows how far the first swing went
## past the rest ("반대쪽으로 간 길이"), "흔들면 보여요" until the ball got there, then the length in words.
func check_spring_card() -> void:
	var screen := await _open("spring")
	screen._end_question()
	screen._poll()
	var first: Array = screen.key_card_ids()
	var caption := ExperimentRegistry.card_label(screen.definition, "bell_reach")
	var waiting: String = screen._key_labels.bell_reach.text if screen._key_labels.has("bell_reach") else ""
	var lab: Experiment = screen.experiment
	lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(lab.ANCHOR_X + lab.REST_LENGTH + 1.5, lab.ROD_Y, 0.0)))
	for k in 100:
		await tree.physics_frame
	screen._poll()
	var reached: String = screen._key_labels.bell_reach.text if screen._key_labels.has("bell_reach") else ""
	screen._show_stamps(1)
	await tree.process_frame
	var second: Array = screen.key_card_ids()
	expect.call(first == ["bell_reach"] and caption == "반대쪽으로 간 길이" and waiting == "흔들면 보여요" and reached == "1.5미터" and second == ["bell_reach"]
		and screen._key_row.get_child_count() == 1,
		"kid words: the spring's card is how far the first swing went past the rest (반대쪽으로 간 길이: 흔들면 보여요, then 1.5미터 from a 1.5 m pull), every stage",
		"%s '%s' '%s' '%s' -> %s" % [str(first), caption, waiting, reached, str(second)])
	await _close(screen)


## The push's card: the waiting words before the box moved, then a bar (no text) that is longer for
## a heavier box, the number only in "자세히".
func check_push_bar() -> void:
	var screen := await _open("friction")
	screen._end_question()
	var lab: Experiment = screen.experiment
	var lengths := []
	var problems := []
	for mass in ["light", "heavy"]:
		screen._set_control("mass", mass)
		screen._poll()
		var bar: Control = screen._key_bars.get("start_force")
		var label: Label = screen._key_labels.get("start_force")
		if bar == null or bar.visible or not label.visible or label.text == "":
			problems.append("%s before: bar %s, text '%s'" % [mass, str(bar != null and bar.visible), label.text if label != null else ""])
			continue
		lab.set_applied_force(ceilf(lab.model.max_static()) + 1.0)
		await _frames(10)
		lab.set_applied_force(0.0)
		screen._poll()
		if not bar.visible or label.visible or str(screen._observation_labels.start_force.text).is_empty() \
				or not str(screen._observation_labels.start_force.text).ends_with(" N"):
			problems.append("%s moved: bar %s, text shown %s, sidebar '%s'" % [mass, bar.visible, label.visible, screen._observation_labels.start_force.text])
		lengths.append(bar.fraction)
	expect.call(problems.is_empty() and lengths.size() == 2 and lengths[0] > 0.0 and lengths[0] < lengths[1] and lengths[1] < 1.0,
		"kid words: the push's card is a bar once the box moved (longer for the heavy box, no 뉴턴), the number in 자세히",
		"lengths %s; %s" % [str(lengths), "; ".join(problems)])
	await _close(screen)


# --- the science note -----------------------------------------------------------------------------

## 법칙 (one sentence, one formula), 이번 실험 숫자 (3-4 rows with every number in its unit), 조건
## 바꾸기, 그래프 where the note keeps it, then 더 보기 (closed): every other observation, the graph
## otherwise, the explanation. Every observation has its one label with the panel's text.
func check_note(definition: Dictionary) -> void:
	var screen := await _open(definition.id)
	screen.open_sidebar(false)
	await tree.process_frame
	screen._poll()
	var note := ExperimentRegistry.note(definition)
	var problems := []
	if not definition.has("note"):
		problems.append("no note")
	var column: Control = screen._sections.law.get_parent()
	var order := []
	for child in column.get_children():
		for id in screen._sections:
			if screen._sections[id] == child:
				order.append(id)
	var want := ["law", "numbers", "conditions"] + (["graph"] if note.graph else []) + ["more", "ask"]
	if order != want:
		problems.append("order %s (want %s)" % [str(order), str(want)])
	var law_texts: Array = screen._sections.law.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	if not (law_texts.has("법칙") and law_texts.has(note.law) and law_texts.has(note.formula) and str(note.law).length() < 90):
		problems.append("law %s" % str(law_texts))
	var rows: Array = note.numbers
	if rows.size() < 3 or rows.size() > 4:
		problems.append("%d number rows" % rows.size())
	var values: Dictionary = screen.experiment.observations()
	var hidden: Array = screen._hidden_answers(values)
	var in_numbers := {}
	for row in rows:
		for id in row.ids:
			in_numbers[id] = true
	for observation in definition.observations:
		var label: Label = screen._observation_labels.get(observation.id)
		var text := ExperimentScreen.hidden_observation(observation) if hidden.has(observation.id) else ExperimentScreen.format_observation(observation, values.get(observation.id))
		if label == null or label.text != text:
			problems.append("%s reads '%s' (want '%s')" % [observation.id, label.text if label != null else "-", text])
			continue
		var under_more: bool = screen._more.is_ancestor_of(label)
		var under_numbers: bool = screen._sections.numbers.is_ancestor_of(label)
		if under_more == in_numbers.has(observation.id) or under_numbers != in_numbers.has(observation.id):
			problems.append("%s: in the numbers %s, under 더 보기 %s" % [observation.id, under_numbers, under_more])
	if screen.is_more_open() or screen._more.visible:
		problems.append("더 보기 open at start")
	if screen._more.is_ancestor_of(screen._graph) == note.graph:
		problems.append("the graph under 더 보기: %s (note.graph %s)" % [screen._more.is_ancestor_of(screen._graph), note.graph])
	if not screen._more.is_ancestor_of(screen._sections.more_explanation):
		problems.append("the explanation is not under 더 보기")
	screen.set_more_open(true)
	if not screen._more.visible or screen._more_button.text != "접기":
		problems.append("더 보기 does not open")
	expect.call(problems.is_empty(),
		"science note (%s): 법칙 + %s, %d numbers in their units, 조건 바꾸기, graph %s, 더 보기 closed with the other %d observations and the explanation" % [
			definition.id, note.formula, rows.size(), "kept" if note.graph else "in 더 보기", definition.observations.size() - in_numbers.size()],
		"; ".join(problems))
	await _close(screen)
