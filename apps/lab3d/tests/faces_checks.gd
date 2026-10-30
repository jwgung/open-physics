## The dialogue's expressions and Dugi's explanation per stage (2026-10-29 user requests "대화시 표정을
## 좀 더 다양하게", "목표마다 두기두기의 설명이 달라지면 좋겠어", and "Puppy never explains science"):
## - every speaker x face picture exists (512 px), every tag in the content is a known face;
## - DialogueBox: a line's face shows its picture, an untagged line the default, the same face again
##   swaps nothing (no re-pop), a new face pops softly and settles, the box and the portrait's rects
##   are the same with every face;
## - the story's pages, Puppy's clue, Dugi's question and his reason (right: happy, wrong: thinking)
##   show their faces in the real screens;
## - Dugi's explanation is the stage's own say (the stage just cleared, else the one being played;
##   kid.say when all are done), it opens in the lab with its face, and every say, question, reason
##   and clue fits in two pages of the box on phone and tablet;
## - Puppy's lines (clues, riddles, the wrong-spot line, his story pages) use no science words.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const HOME_SCREEN := "res://scripts/app/island_home_screen.gd"


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_files()
	check_tags()
	check_puppy_words()
	await check_box()
	await check_story_faces()
	await check_lab_faces()
	await check_stage_says()
	await check_fit()
	DirAccess.remove_absolute(ProgressStore.path)


## Every speaker has every face, the pictures are the portraits' size.
func check_files() -> void:
	var missing := []
	for who in Story.SPEAKERS:
		for face in Story.FACES:
			var path := Story.portrait_path(who, face)
			var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
			if tex == null or tex.get_size() != Vector2(512, 512):
				missing.append(path)
	expect.call(missing.is_empty() and Story.FACES.size() == 5, "faces: every speaker x face portrait exists (5 faces, 512 px)", str(missing))
	expect.call(Story.face_or_default(null) == "explain" and Story.face_or_default("bogus") == "explain" and Story.face_or_default("happy") == "happy",
		"faces: an untagged or unknown face is the default (explain)", "")


## Every line of the content is tagged with a known face; a wrong tag is a validation problem.
func check_tags() -> void:
	var problems := []
	for part in ["prologue", "finale"]:
		for entry in Story.pages(part):
			if not str(entry.get("face", "")) in Story.FACES:
				problems.append("%s: %s" % [part, entry.get("text")])
	if not str(Story._load().get("map_wrong_face", "")) in Story.FACES:
		problems.append("map_wrong_face")
	var labs := 0
	for definition in ExperimentRegistry.load_all():
		var stages: Array = MissionRound.missions(definition).get("stages", [])
		if stages.is_empty():
			continue
		labs += 1
		for i in stages.size():
			if not (str(stages[i].get("say", "")) != "" and str(stages[i].get("say_face", "")) in Story.FACES):
				problems.append("%s stage %d say" % [definition.id, i])
		for key in ["clue_face", "map_clue_face"]:
			if not str(definition.get("story", {}).get(key, "")) in Story.FACES:
				problems.append("%s story.%s" % [definition.id, key])
		if not str(MissionRound.predict(definition).get("question_face", "")) in Story.FACES:
			problems.append("%s predict.question_face" % definition.id)
		if not str(definition.get("kid", {}).get("say_face", "")) in Story.FACES:
			problems.append("%s kid.say_face" % definition.id)
	expect.call(problems.is_empty() and labs == 11, "faces: every story page, clue, riddle, question, kid say and the 33 stage says carry a known face",
		"; ".join(problems))
	var bad := ExperimentRegistry.find("projectile").duplicate(true)
	bad.missions.stages[0].say_face = "angry"
	bad.story.clue_face = "sleepy"
	var found := ExperimentRegistry.validate(bad)
	expect.call(Array(found).any(func(p: String) -> bool: return p.contains("say_face")) and Array(found).any(func(p: String) -> bool: return p.contains("clue_face")),
		"faces: the registry rejects an unknown face tag", str(found))


## Puppy gives clues and story lines only; the science is Dugi's (2026-10-29 user).
func check_puppy_words() -> void:
	var lines := Story.puppy_lines()
	var hits := []
	for line in lines:
		for word in Story.SCIENCE_WORDS:
			if str(line).contains(word):
				hits.append("%s: %s" % [word, line])
	# The list is not vacuous: Dugi's own words use it (and are allowed to).
	var dugi_uses := false
	for definition in ExperimentRegistry.load_all():
		for stage in MissionRound.missions(definition).get("stages", []):
			dugi_uses = dugi_uses or Story.SCIENCE_WORDS.any(func(w: String) -> bool: return str(stage.get("say", "")).contains(w))
	expect.call(hits.is_empty() and lines.size() >= 27 and dugi_uses,
		"faces: Puppy's %d lines (clues, riddles, not-here, story pages) explain no science (Dugi's lines may)" % lines.size(), "; ".join(hits))


## The box: faces, the default, no re-pop for the same face, a soft pop for a new one, stable rects.
func check_box() -> void:
	var box := DialogueBox.new("두기두기의 설명이에요.")
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	host.add_child(box)
	box.layout(Rect2(Vector2.ZERO, TABLET), TABLET.x - 300.0, 16.0)
	await tree.process_frame
	var default_ok := box.face == "explain" and box.portrait.texture == DialogueBox.portrait_texture("dugi", "explain")
	box.open()
	var rects := str(box.rects())
	var tag := box.name_tag.get_rect()
	var problems := []
	var swaps := box.swaps
	box.open("다시 같은 얼굴이에요.", "explain")
	if box.swaps != swaps or box.portrait.scale != Vector2.ONE:
		problems.append("same face re-popped")
	for who in ["dugi", "puppy"]:
		for face in Story.FACES:
			box.set_speaker(who, face)
			box.layout(Rect2(Vector2.ZERO, TABLET), TABLET.x - 300.0, 16.0)
			if box.portrait.texture != DialogueBox.portrait_texture(who, face) or box.face != face or box.speaker != who:
				problems.append("%s %s not shown" % [who, face])
			if str(box.rects()) != rects:
				problems.append("%s %s moved the box or portrait %s" % [who, face, str(box.rects())])
			if box.box.size != box.rects()[0].size or box.portrait.size != Vector2(DialogueBox.PORTRAIT_SIZE, DialogueBox.PORTRAIT_SIZE):
				problems.append("%s %s resized" % [who, face])
	# A new face pops softly (drawing only) and settles; the same face again changes nothing.
	box.set_speaker("dugi", "happy")
	box.set_speaker("dugi", "thinking")
	var popping := box.portrait.scale.x < 1.0 and box.portrait.modulate.a < 1.0
	box.step(DialogueBox.SWAP_S + 0.02)
	var settled := box.portrait.scale == Vector2.ONE and is_equal_approx(box.portrait.modulate.a, 1.0)
	swaps = box.swaps
	box.set_speaker("dugi", "thinking")
	box.open("생각하는 얼굴로 한 번 더.", "thinking")
	var still := box.swaps == swaps and box.portrait.scale == Vector2.ONE
	# Untagged: the default face (and the own words' face on a plain open).
	box.set_words("기본 설명", "")
	box.open()
	var untagged := box.face == "explain"
	box.set_words("기쁜 설명", "happy")
	box.open()
	var words_face := box.face == "happy"
	box.set_speaker("puppy")
	var puppy_default := box.face == "explain" and box.name_label.text == "퍼피"
	expect.call(default_ok and problems.is_empty() and popping and settled and still and untagged and words_face and puppy_default,
		"faces: the box shows each speaker x face; the same face again does not re-pop; a new face pops softly and settles; untagged = explain; the box, portrait and rects never change size or place",
		"%s pop %s settle %s still %s untagged %s words %s puppy %s" % ["; ".join(problems), popping, settled, still, untagged, words_face, puppy_default])
	host.queue_free()
	await tree.process_frame


## The prologue's pages show their tagged faces.
func check_story_faces() -> void:
	var was := Story.enabled
	Story.enabled = true
	DirAccess.remove_absolute(ProgressStore.path)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var home: Control = load(HOME_SCREEN).new()
	home.play_prologue_on_open = true
	host.add_child(home)
	for i in 4:
		await tree.process_frame
	var story: StoryDirector = home.story
	var shown := []
	var want := Story.pages("prologue").map(func(p: Dictionary) -> String: return "%s:%s" % [p.who, p.face])
	for p in want.size():
		shown.append("%s:%s" % [story.dialogue.speaker, story.dialogue.face])
		if story.dialogue.portrait.texture != DialogueBox.portrait_texture(story.dialogue.speaker, story.dialogue.face):
			shown.append("wrong picture")
		for i in 70:
			story.advance(0.05)
		var words := story.dialogue.text
		for k in 6:
			if not story.dialogue.active or story.dialogue.text != words:
				break
			story.dialogue.advance()
	expect.call(str(shown) == str(want), "faces: the prologue's 8 pages show their speakers' tagged faces", str(shown))
	host.queue_free()
	await tree.process_frame
	# Puppy's riddle and his not-here line on the night map.
	home = await _home()
	home.story.say_riddle()
	var riddle: DialogueBox = home.story.riddle
	var next := ExperimentRegistry.find(home.story.next_id)
	var riddle_ok := riddle.speaker == "puppy" and riddle.face == Story.map_clue_face(next)
	home.story.say_wrong()
	var wrong_ok := riddle.face == Story.wrong_face() and riddle.face == "thinking"
	expect.call(riddle_ok and wrong_ok, "faces: Puppy's riddle and his not-here line on the night map show their faces", "%s %s" % [riddle.face, Story.wrong_face()])
	home.get_parent().queue_free()
	await tree.process_frame
	Story.enabled = was
	DirAccess.remove_absolute(ProgressStore.path)


## In a lab: Puppy's clue face, Dugi's question face, then the reason: happy after a right guess,
## thinking after a wrong one; then his explanation is the stage's say with its face.
func check_lab_faces() -> void:
	var was := Story.enabled
	Story.enabled = true
	for pick in ["right", "wrong"]:
		DirAccess.remove_absolute(ProgressStore.path)
		ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
		var screen := await _lab("free-fall", PHONE)
		var box: DialogueBox = screen.dialogue
		var clue_ok: bool = box.speaker == "puppy" and box.face == Story.clue_face(screen.definition.raw) and box.face == "surprised"
		for k in 6:
			if box.speaker != "puppy":
				break
			box.advance()
		await tree.process_frame
		await tree.process_frame
		var predict := MissionRound.predict(screen.definition.raw)
		var question_ok: bool = box.speaker == "dugi" and box.text == str(predict.question) and box.face == "thinking"
		var answer := str(predict.answer)
		var other := ""
		for choice in predict.choices:
			if str(choice.id) != answer:
				other = str(choice.id)
		screen._predict_pick_choice(answer if pick == "right" else other)
		screen.mission_round.reveal()
		# 2026-10-29: Dugi's bridge to the first mission first (its face), the reason only after the first
		# attempt's result line (here a miss), then at once.
		for k in int(DugiActor.RAISE_S * 60.0) + 4:
			await tree.process_frame
		var bridge_ok: bool = box.active and box.text == "%s %s" % [predict.bridge, MissionRound.BRIDGE_FIRST] and box.face == str(predict.bridge_face)
		box.close(true)
		screen.cast.dugi.stop(true)
		await tree.process_frame
		await tree.process_frame
		screen.show_result(0, false)
		for k in int(DugiActor.RAISE_S * 60.0) + 4:
			await tree.process_frame
		var want_face := "happy" if pick == "right" else "thinking"
		var reason_ok: bool = box.active and box.text == str(predict.reason) and box.face == want_face \
			and box.portrait.texture == DialogueBox.portrait_texture("dugi", want_face)
		box.close(true)
		screen.cast.dugi.stop(true)
		for k in 70:   # the arm comes down and the explanation re-arms (REARM_S)
			await tree.process_frame
		screen.cast.dugi.explain(screen.experiment.explain_point)
		for k in int(DugiActor.RAISE_S * 60.0) + 4:
			await tree.process_frame
		var stage: Dictionary = MissionRound.missions(screen.definition.raw).stages[0]
		var say_ok: bool = box.active and box.text == str(stage.say) and box.face == str(stage.say_face)
		expect.call(clue_ok and question_ok and bridge_ok and reason_ok and say_ok,
			"faces (%s guess): Puppy's clue (surprised), Dugi's question (thinking), his bridge (happy), the reason after the first result (%s), then the stage's say with its face" % [pick, want_face],
			"clue %s question %s bridge %s reason %s (%s '%s') say %s (%s '%s')" % [clue_ok, question_ok, bridge_ok, reason_ok, box.face, box.text, say_ok, box.face, box.text])
		await _free(screen)
	Story.enabled = was
	DirAccess.remove_absolute(ProgressStore.path)


## Every lab: the explanation follows the stage (the cleared one right after its stamp, else the one
## being played, kid.say when all are done).
func check_stage_says() -> void:
	var wrong := []
	for definition in ExperimentRegistry.load_all():
		var stages: Array = MissionRound.missions(definition).get("stages", [])
		if stages.is_empty():
			continue
		DirAccess.remove_absolute(ProgressStore.path)
		var screen := await _lab(str(definition.id), TABLET)
		for k in stages.size() + 1:
			screen.mission_round.stamps = k   # in memory only
			screen.mission_round.judged_run = false
			var want: Array = [str(stages[k].say), str(stages[k].say_face)] if k < stages.size() \
				else [ExperimentRegistry.kid_text(definition, "say"), str(definition.kid.say_face)]
			if str(screen.explain_say()) != str(want):
				wrong.append("%s playing %d: %s" % [definition.id, k, str(screen.explain_say())])
			if k > 0:
				screen.mission_round.judged_run = true   # the stamp of stage k-1 just came: its say
				if str(screen.explain_say()) != str([str(stages[k - 1].say), str(stages[k - 1].say_face)]):
					wrong.append("%s cleared %d: %s" % [definition.id, k - 1, str(screen.explain_say())])
		screen.mission_round.stamps = 0
		await _free(screen)
	expect.call(wrong.is_empty(), "stage says: in all 11 labs Dugi explains the stage being played (or just cleared), kid.say once all are done", "; ".join(wrong))


## Every say, question, reason and clue fits in two pages of the box, phone and tablet.
func check_fit() -> void:
	var over := []
	for size in [PHONE, TABLET]:
		for definition in ExperimentRegistry.load_all():
			var stages: Array = MissionRound.missions(definition).get("stages", [])
			if stages.is_empty():
				continue
			var screen := await _lab(str(definition.id), size)
			var box: DialogueBox = screen.dialogue
			var predict := MissionRound.predict(definition)
			var texts := stages.map(func(s: Dictionary) -> String: return str(s.say)) + [str(predict.question), str(predict.reason), Story.clue(definition)]
			for text in texts:
				box.set_words(text)
				box._text_width = 0.0   # lay out again for these words
				if not screen._layout_dialogue() or box.pages().size() > 2 or box.joined() != text:
					over.append("%s %s: %s (%d pages)" % [definition.id, "phone" if size == PHONE else "tablet", text, box.pages().size()])
			await _free(screen)
	expect.call(over.is_empty(), "stage says: every say, question, reason and clue fits in 2 pages of the box (phone, tablet) and reads back whole", "; ".join(over))


func _lab(id: String, size: Vector2) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _home() -> Control:
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(HOME_SCREEN).new()
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame
