## The story "별 조각 찾기" (2026-10-28): the prologue (once; skip; replay from the settings; the camera
## moves and comes back to the child's view and control; the night comes and goes; the map is clean
## afterwards), Puppy's clue (once per spot, before Dugi's question, never again), the found piece
## (only on the round's completion: the cat lifts it, the card shows it), its flight to the lookout
## on the map (once; the emblem counts the pieces), old progress files (a finished spot is a found
## piece, no flight), the finale (once, at 11; the star stays in the sky) and measurements (no story).
## Story.enabled is on only inside these checks (and restored).
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const HOME_SCREEN := "res://scripts/app/island_home_screen.gd"
const SETTINGS_SCREEN := "res://scripts/app/settings_screen.gd"
const CLUES := {
	"projectile": "상자를 하나씩 맞히다 보면 조각이 나올 것 같아!",
	"collision": "얼음 속에 조각이 갇혔어! 공을 부딪혀서 저 얼음을 깨 보자!",
	"free-fall": "조각이 파란 집에 갇혔어! 버튼 두 개를 같이 누르면 문이 열릴 것 같아!",
	"incline-friction": "조각이 빨간 기둥 꼭대기에 있어! 상자로 도미노를 쓰러뜨려 보자!",
	"friction": "상자가 길을 막고 있어! 상자를 치우면 조각까지 갈 수 있겠어!",
	"spring": "종 안에 조각이 매달려 있어! 공으로 종을 땡 쳐 보자!",
	"rotation": "무거운 보물 상자 밑에 조각이 끼어 있어! 막대를 눌러서 상자를 들어 보자.",
	"pulley": "보물 상자 창살 안에 조각이 있어! 줄을 당겨서 상자를 높은 선반까지 올려 보자!",
	"constraints": "거북이 시계 속에 조각이 있어! 공을 시계 추랑 똑같이 흔들어 보자!",
	"buoyancy": "물속 보물 상자에 조각이 있어! 통을 띄워서 상자를 건져 보자.",
	"orbit": "조각 하나가 저 멀리 우주에 떠 있어! 행성을 쏴서 데려오자!",
}
const PROLOGUE := [
	["dugi", "여기는 바다 위 나라, 퍼피랜드예요."],
	["dugi", "퍼피랜드에는 섬이 많아요. 그중 하나가 우리 과학섬이에요."],
	["puppy", "밤마다 길잡이 별이 바다를 비춰 줘. 배들이 길을 잃지 않게!"],
	["puppy", "어? 길잡이 별이 깨졌어!"],
	["dugi", "별빛이 없으면 밤바다에서는 아무것도 안 보여요. 배가 길을 찾을 수 없어요."],
	["puppy", "조각이 떨어지는 걸 봤어. 들판, 언덕, 놀이터, 연못… 섬 곳곳이야!"],
	["dugi", "조각마다 숨은 곳이 달라요. 공을 던지고, 상자를 밀고, 통을 띄워 봐야 꺼낼 수 있어요."],
	["puppy", "빵고양이, 같이 가자!"],
]
const FINALE := [["puppy", "조각을 모두 찾았어!"], ["dugi", "조각을 다시 맞추면 별이 빛을 낼 수 있어요. 하늘로 돌려보내요."]]


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	var was := Story.enabled
	Story.enabled = true
	check_content()
	check_old_files()
	await check_prologue()
	await check_prologue_once_and_replay()
	await check_skip()
	await check_clue()
	await check_piece_found()
	await check_flight()
	await check_finale()
	await check_one_tap()
	Story.enabled = was
	await check_measurements()
	DirAccess.remove_absolute(ProgressStore.path)


## The words are the approved ones, exactly: the 11 clues in the labs' content (five pointing at the
## piece game's object since 2026-10-29), the prologue and finale.
func check_content() -> void:
	var wrong := []
	for id in CLUES:
		if Story.clue(ExperimentRegistry.find(id)) != CLUES[id]:
			wrong.append(id)
	var pages := Story.pages("prologue").map(func(p: Dictionary) -> Array: return [p.who, p.text])
	var finale := Story.pages("finale").map(func(p: Dictionary) -> Array: return [p.who, p.text])
	expect.call(wrong.is_empty() and Story.spots().size() == 11 and CLUES.keys().all(func(id: String) -> bool: return id in Story.spots()),
		"story: every one of the 11 spots has Puppy's clue, word for word", str(wrong))
	expect.call(str(pages) == str(PROLOGUE) and str(finale) == str(FINALE), "story: the prologue (8 pages) and the finale words, speakers and order",
		str(pages.size()))


## A save from before the story: a finished spot is a found piece at the lookout, no flight to play,
## no clue told, the prologue not seen yet (it plays once); the stamps are untouched.
func check_old_files() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var old := ConfigFile.new()
	old.set_value("progress", "projectile", 3)
	old.set_value("progress", "orbit", 3)
	old.set_value("progress", "spring", 1)
	old.set_value("flags", "projectile", true)
	old.save(ProgressStore.path)
	var progress := ProgressStore.load()
	expect.call(Story.found(progress) == ["projectile", "orbit"] and Story.placed(progress).size() == 2 and Story.to_fly(progress).is_empty()
		and not Story.prologue_seen() and not Story.clue_seen("spring") and not Story.finale_seen()
		and progress == {"projectile": 3, "orbit": 3, "spring": 1} and Story.should_play_prologue(),
		"story: an old save counts its finished spots as pieces at the lookout (no flight), nothing told yet, stamps unchanged",
		str(Story.found(progress)))
	var odd := ConfigFile.new()
	odd.load(ProgressStore.path)
	odd.set_value(ProgressStore.STORY, "prologue", "yes")
	odd.set_value(ProgressStore.PIECES, "orbit", 7)
	odd.save(ProgressStore.path)
	expect.call(not Story.prologue_seen() and Story.to_fly(ProgressStore.load()).is_empty() and ProgressStore.load().size() == 3,
		"story: odd story values read as not played / flown; the stamps never read a story section", "")
	DirAccess.remove_absolute(ProgressStore.path)


## The prologue: 8 pages with their speakers, the camera from the far sea in to the island, up to the
## star, the night and the darker night, the 11 pieces at the spots, the cat on the square, then the
## day, a clean map and the child's camera exactly, which the child can turn again.
func check_prologue() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var home := await _home(TABLET, true)
	var story: StoryDirector = home.story
	var rig: CameraRig = home.view.rig
	var bar: Control = home.find_child("TopBar", true, false)
	var start_ok: bool = story != null and story.cinematic() and story.page == 0 and story.dialogue.active \
		and story.dialogue.speaker == "dugi" and story.dialogue.text == PROLOGUE[0][1] and not rig.is_processing() \
		and not bar.visible and story.skip_button.visible and rig.cur_distance > 100.0
	expect.call(start_ok, "prologue: the first launch opens on the far sea (wide shot), Dugi's first page, 건너뛰기, no top bar",
		"distance %.0f" % rig.cur_distance)
	var speakers := []
	var max_pitch := -90.0
	var min_dist := INF
	var max_night := 0.0
	var pieces_seen := 0
	var pieces_at_spots := true
	var eye_moves := 0
	var last_eye: Vector3 = rig.global_position
	for p in PROLOGUE.size():
		speakers.append([story.dialogue.speaker, story.dialogue.text])
		for i in 70:   # 3.5 s of the page
			story.advance(0.05)
			max_pitch = maxf(max_pitch, rad_to_deg(rig.cur_pitch))
			min_dist = minf(min_dist, rig.cur_distance)
			max_night = maxf(max_night, story.night)
			if rig.global_position.distance_to(last_eye) > 0.001:
				eye_moves += 1
			last_eye = rig.global_position
		if p == 4:
			pieces_seen = story._pieces.size()
			for i in story._pieces.size():
				var piece: Dictionary = story._pieces[i]
				var spot: Dictionary = home._spots[i]
				pieces_at_spots = pieces_at_spots and (piece.node as Node3D).position.distance_to(spot.at + Vector3.UP * (float(spot.top) + 0.6)) < 0.01
		if p == 2:
			expect.call(story.night > 0.95 and story.tint.x < 0.5 and home.env.environment.background_color.v < MapIsland.sea_color().v
				and story._star != null and story.sea.lanterns.all(func(l: Node3D) -> bool: return l.visible),
				"prologue: page 3 brings the night (tint, a darker sea) and the guiding star; the boats' lanterns show", "night %.2f" % story.night)
		_tap_through(story.dialogue)
	expect.call(str(speakers) == str(PROLOGUE), "prologue: the 8 pages in order with their speakers' portraits (Dugi / Puppy)", str(speakers))
	expect.call(max_pitch > 15.0 and min_dist < 10.0 and eye_moves > 400 and max_night > 1.9,
		"prologue: the camera moves on every page (tilts up to the star, comes close to the square) and the night darkens after the break",
		"pitch %.0f dist %.1f moves %d night %.2f" % [max_pitch, min_dist, eye_moves, max_night])
	expect.call(pieces_seen == 11 and pieces_at_spots, "prologue: the star breaks into 11 pieces that land at the 11 spots", "%d" % pieces_seen)
	# The camera eases back (RETURN_S), then everything is the map's again.
	for i in 40:
		story.advance(0.05)
	var state: Dictionary = rig.get_state()
	var pieces_left: Array = home.world.find_children("Star*", "Node3D", true, false).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	expect.call(not story.busy() and Story.prologue_seen() and is_equal_approx(story.night, Story.night_level(0, false)) and story.tint.is_equal_approx(StoryDirector.DARK_TINT)
		and home.env.environment.background_color.is_equal_approx(StoryDirector.DARK_SEA),
		"prologue: at the end the map is the night map (no piece found yet: the story's night, tint and sea) and it is marked played",
		"night %.2f" % story.night)
	expect.call(rig.is_processing() and rig.cur_distance == rig.goal_distance and rig.cur_target.is_equal_approx(rig._goal_target())
		and str(state) == str(_default_state(rig)) and bar.visible and not story.skip_button.visible and pieces_left.is_empty()
		and home.cat.position.is_equal_approx(home.trio_spot(home.cat)),
		"prologue: the camera is exactly the child's view again, the map is clean (no piece), the cat on the square", str(state))
	var yaw: float = rig.goal_yaw
	home._on_pointer("press", home.view.size * 0.5)
	home._on_pointer("move", home.view.size * 0.5 + Vector2(80.0, 0.0))
	home._on_pointer("release", home.view.size * 0.5 + Vector2(80.0, 0.0))
	expect.call(not is_equal_approx(rig.goal_yaw, yaw), "prologue: afterwards the child turns the map again", "")
	await _free(home)


## Once: the next map opens without it; 이야기 다시 보기 in the settings plays it again.
func check_prologue_once_and_replay() -> void:
	var home := await _home(TABLET, Story.should_play_prologue())
	expect.call(not home.story.busy() and home.find_child("TopBar", true, false).visible, "prologue: plays once (the next map opens without it)", "")
	await _free(home)
	var settings: Control = load(SETTINGS_SCREEN).new()
	settings.set_tier = func(_t: String) -> bool: return false
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	host.add_child(settings)
	await tree.process_frame
	var asked := [0]
	settings.story_requested.connect(func() -> void: asked[0] += 1)
	var button: Button = settings.find_child("StoryReplay", true, false)
	if button != null:
		button.pressed.emit()
	expect.call(button != null and button.text == "이야기 다시 보기" and asked[0] == 1 and Story.should_play_prologue(true),
		"prologue: the settings' 이야기 다시 보기 asks for it again", "")
	host.queue_free()
	await tree.process_frame
	home = await _home(TABLET, Story.should_play_prologue(true))
	expect.call(home.story.cinematic() and home.story.page == 0, "prologue: the replay plays it from the first page", "")
	await _free(home)


## 건너뛰기 in the middle of the night: at once the day, no pieces, the child's camera, played.
func check_skip() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var home := await _home(PHONE, true)
	var story: StoryDirector = home.story
	var rig: CameraRig = home.view.rig
	for p in 4:
		for i in 60:
			story.advance(0.05)
		_tap_through(story.dialogue)
	var mid: bool = story.cinematic() and story.night > 0.5 and not story._pieces.is_empty()
	story.skip_button.pressed.emit()
	await tree.process_frame
	var left: Array = home.world.find_children("Star*", "Node3D", true, false).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	expect.call(mid and not story.busy() and Story.prologue_seen() and is_equal_approx(story.night, Story.night_level(0, false)) and left.is_empty() and rig.is_processing()
		and str(rig.get_state()) == str(_default_state(rig)) and rig.cur_distance == rig.goal_distance and not story.dialogue.visible
		and story.sea.lanterns.all(func(l: Node3D) -> bool: return not l.visible),
		"prologue: 건너뛰기 ends it at once (the map's night, no pieces, lanterns off, the child's camera exactly, played)", str(mid))
	await _free(home)


## Puppy's clue: the first visit tells it before Dugi's question (puppy portrait, the question's shield,
## no answer buttons yet); then Dugi asks; never again in that lab. Off without the story.
func check_clue() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	var screen := await _lab("projectile")
	var box: DialogueBox = screen.dialogue
	var first: bool = box.active and box.speaker == "puppy" and box.text == CLUES.projectile and box.name_label.text == "퍼피" \
		and screen._question_shield != null and screen._choices != null and not screen._choices.visible and Story.clue_seen("projectile")
	expect.call(first, "clue: the first visit opens with Puppy's clue (his portrait and name) over the question's shield, before the question",
		"%s %s" % [box.speaker, box.text])
	_tap_through(box)
	await tree.process_frame
	await tree.process_frame
	var asked: bool = box.active and box.speaker == "dugi" and box.name_label.text == "두기두기" and box.hold \
		and box.text == str(MissionRound.predict(screen.definition.raw).question) and screen._choices.visible
	expect.call(asked, "clue: then Dugi asks his question with the picture buttons", box.text)
	await _free(screen)
	screen = await _lab("projectile")
	expect.call(screen.dialogue.speaker == "dugi" and screen.dialogue.text == str(MissionRound.predict(screen.definition.raw).question),
		"clue: never again in the same lab (Dugi's question at once)", screen.dialogue.text)
	await _free(screen)
	Story.enabled = false
	screen = await _lab("spring")
	expect.call(screen.dialogue.speaker == "dugi" and not Story.clue_seen("spring"), "clue: without the story no clue is told", "")
	await _free(screen)
	Story.enabled = true
	DirAccess.remove_absolute(ProgressStore.path)


## The piece: no piece for a stage, one when the last stamp lands (over the bread cat), then the card
## with the stamps and the piece; the store keeps it to fly on the map.
func check_piece_found() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.CLUES, "projectile", true)
	var screen := await _lab("projectile")
	(screen._choices.get_child(0) as Button).pressed.emit()
	await tree.process_frame
	var stand_in := _stand_in()
	tree.root.add_child(stand_in)
	var early := true
	for run in [[4.0, 45.0], [6.0, 50.0], [8.0, 40.0]]:
		stand_in.range_m = run[0]
		stand_in.angle = run[1]
		screen.mission_round.on_run_ended("landed", stand_in, {"range": run[0], "hit_1": 1.0, "hit_2": 1.0, "hit_3": 1.0})
		if screen.mission_round.stamps < 3:
			screen._slam.advance(StampSlam.TOTAL_S)
			early = early and screen.found_piece() == null and ProgressStore.pending(ProgressStore.PIECES).is_empty()
	expect.call(early, "piece: a cleared stage finds no piece", "")
	expect.call(screen.found_piece() == null, "piece: none while the last stamp still flies", "")
	screen._slam.advance(StampSlam.TOTAL_S)
	screen.skip_round_wait()
	stand_in.queue_free()
	var piece: Node3D = screen.found_piece()
	var cat: CatActor = screen.lab_cat()
	screen._run_celebration(screen.PIECE_FLY_S + 0.1)   # the lab's piece flies into the paws (the piece game, 2026-10-29)
	var above: bool = piece != null and cat != null and piece.global_position.y > cat.bounds().end.y and cat.cheers >= 1
	expect.call(above and ProgressStore.pending(ProgressStore.PIECES) == ["projectile"],
		"piece: the round's last stamp finds the star piece; the bread cat lifts it (it shines over the cat); the map will fly it", "")
	screen._run_celebration(screen.CARD_DELAY_S - 0.4)
	var waited: bool = screen._done_card == null
	screen._run_celebration(screen.PIECE_HOLD_S)
	var card: RoundDoneCard = screen._done_card
	expect.call(waited and card != null and card.piece and card.find_children("*", "Label", true, false).is_empty()
		and screen.found_piece() == null and card.map_button != null and card.stay_button != null,
		"piece: the card comes after the piece, with the stamps and the piece, its two buttons, no words", "")
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)


## The map: a found piece flies once to the lookout after its flag rises (the emblem fills a wedge);
## not again; a tap skips it; an old finished spot shows on the emblem without a flight.
func check_flight() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	ProgressStore.save({"projectile": 3, "orbit": 3})   # orbit: an old finished spot
	ProgressStore.mark_flag_pending("projectile")
	ProgressStore.set_mark(ProgressStore.PIECES, "projectile", false)
	var home := await _home(TABLET, false)
	var story: StoryDirector = home.story
	var during_raise: bool = home.raising() and not story.flying() and story.emblem.filled == 1
	home.skip_raise()
	await tree.process_frame
	await tree.process_frame
	var started: bool = story.flying() and story.flights_played == 1 and Story.to_fly(ProgressStore.load()).is_empty()
	var t0 := Time.get_ticks_msec()
	while story.flying() and Time.get_ticks_msec() - t0 < 8000:
		await tree.process_frame
	expect.call(during_raise and started and not story.flying() and story.emblem.filled == 2 and not home.view.rig.is_framing()
		and str(home.view.rig.get_state()) == str(_default_state(home.view.rig)),
		"flight: after the flag, the piece flies to the lookout; the emblem fills (2 of 11); the camera is the child's again",
		"%s %s filled %d" % [str(during_raise), str(started), story.emblem.filled])
	await _free(home)
	home = await _home(TABLET, false)
	for i in 5:
		await tree.process_frame
	expect.call(home.story.flights_played == 0 and home.story.emblem.filled == 2 and home.story.emblem.total == 11,
		"flight: once (the next map shows the emblem only)", "")
	await _free(home)
	# A tap during the flag skips the flag and the flight: the emblem at once.
	var store := ProgressStore.load()
	store["spring"] = 3
	ProgressStore.save(store)
	ProgressStore.mark_flag_pending("spring")
	ProgressStore.set_mark(ProgressStore.PIECES, "spring", false)
	home = await _home(TABLET, false)
	home._on_pointer("press", home.view.size * 0.5)
	home._on_pointer("release", home.view.size * 0.5)
	for i in 3:
		await tree.process_frame
	expect.call(not home.raising() and not home.story.flying() and home.story.flights_played == 0 and home.story.emblem.filled == 3
		and Story.to_fly(ProgressStore.load()).is_empty() and not home._walking,
		"flight: a tap skips the flag and the flight (the emblem fills at once, nothing opens)", "%d" % home.story.emblem.filled)
	await _free(home)
	DirAccess.remove_absolute(ProgressStore.path)


## The finale: when the 11th piece is at the lookout, once: the pieces gather into the star, Puppy then
## Dugi speak, the cat lifts it and it rises; the sea sparkles, the lanterns light; then the child's
## camera, and the star stays in the map's sky (in the default view).
func check_finale() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	var store := {}
	for id in Story.spots():
		store[id] = MissionRound.missions(ExperimentRegistry.find(id)).stages.size()
	ProgressStore.save(store)
	var almost := store.duplicate()
	var home := await _home(TABLET, false)
	await tree.process_frame
	var story: StoryDirector = home.story
	var rig: CameraRig = home.view.rig
	expect.call(story.cinematic() and story.part == "finale" and Story.finale_seen(), "finale: 11 pieces at the lookout start it (marked once)", story.part)
	var gathered := false
	for i in 70:
		story.advance(0.05)
		gathered = gathered or (story._star != null and story._pieces.is_empty())
	var words := []
	for p in FINALE.size():
		words.append([story.dialogue.speaker, story.dialogue.text])
		for i in 20:
			story.advance(0.05)
		_tap_through(story.dialogue)
	var lifted := false
	var rose := 0.0
	var sparkled := false
	for i in 200:
		story.advance(0.05)
		lifted = lifted or story._lift
		if story._star != null:
			rose = maxf(rose, story._star.position.y)
		sparkled = sparkled or story._sparkles.size() > 10
	expect.call(gathered and str(words) == str(FINALE), "finale: the pieces gather into the star, then Puppy and Dugi speak", str(words))
	expect.call(lifted and rose > 15.0 and sparkled, "finale: the cat lifts the star, it rises to the sky, the sea sparkles", "rose %.1f" % rose)
	for i in 40:
		story.advance(0.05)
	await tree.process_frame
	var sky: Node3D = story.sky_star
	var on_view: Vector2 = home.view.rig.unproject_position(sky.global_position) / (Vector2(home.view.viewport.size) / home.view.size) if sky != null else Vector2.INF
	var bar: Control = home.find_child("TopBar", true, false)
	expect.call(not story.busy() and sky != null and Rect2(Vector2(0.0, bar.size.y), home.view.size - Vector2(0.0, bar.size.y)).has_point(on_view)
		and story.sea.lanterns.all(func(l: Node3D) -> bool: return l.visible) and story.night == 0.0
		and str(rig.get_state()) == str(_default_state(rig)) and rig.is_processing(),
		"finale: afterwards the star stays in the map's sky (in the child's default view), the lanterns lit, the child's camera", str(on_view))
	await _free(home)
	home = await _home(TABLET, false)
	await tree.process_frame
	expect.call(not home.story.busy() and home.story.sky_star != null and almost == ProgressStore.load(), "finale: once (the next map has the star in the sky)", "")
	await _free(home)
	DirAccess.remove_absolute(ProgressStore.path)


## Measurements never play the story: their launch args turn it off; with it off the map has no
## director (no prologue, no emblem) and a lab tells no clue.
func check_measurements() -> void:
	var off := ["--progress=bench", "--auto-drag=2", "--auto-release=3", "--demo-celebrate=1", "--demo-flag=orbit", "--sound=0"]
	var all_off := off.all(func(a: String) -> bool: return Story.measurement_run(PackedStringArray(["--quality=low", a])))
	expect.call(all_off and not Story.measurement_run(PackedStringArray(["--quality=low", "--fps=1"])),
		"story: every measurement flag turns it off; a plain launch does not", "")
	DirAccess.remove_absolute(ProgressStore.path)
	var home := await _home(TABLET, Story.should_play_prologue())
	expect.call(home.story == null and home.find_children("*", "StarEmblem", true, false).is_empty() and home.find_child("TopBar", true, false).visible,
		"story: off (a measurement) the map plays nothing and shows no emblem", "")
	await _free(home)
	var screen := await _lab("buoyancy")
	expect.call(screen.dialogue.speaker == "dugi" and screen.mission_round.phase() != MissionRound.Phase.CLUE, "story: off, a lab tells no clue", "")
	await _free(screen)


# --- helpers ---------------------------------------------------------------------------------------

## Taps until this page is gone (the next page may open at once: it is not tapped).
func _tap_through(box: DialogueBox) -> void:
	var words := box.text
	for i in 6:
		if not box.active or box.text != words:
			return
		box.advance()


## The map camera's own default (the child's view when nothing turned it).
func _default_state(rig: CameraRig) -> Dictionary:
	var probe := CameraRig.new()
	var home := IslandHomeScreen.new()
	probe.configure(home._map_camera())
	home.free()
	var state := probe.get_state()
	probe.free()
	return state


func _stand_in() -> Experiment:
	var script := GDScript.new()
	script.source_code = "extends Experiment\nvar range_m := 4.0\nvar angle := 45.0\n" \
		+ "func status() -> String:\n\treturn \"landed\"\nfunc settled() -> bool:\n\treturn true\n" \
		+ "func observations() -> Dictionary:\n\treturn {\"range\": range_m}\n" \
		+ "func control_value(id: String) -> Variant:\n\treturn angle if id == \"angle\" else 9.0\n"
	script.reload()
	return script.new()


func _lab(id: String) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = PHONE
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _home(size: Vector2, prologue: bool) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(HOME_SCREEN).new()
	screen.play_prologue_on_open = prologue
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame


## One finger tap on Android arrives twice: the touch and its emulated click
## (emulate_mouse_from_touch). The dialogue box takes one step for it: the next page, not the next
## page already typed out (2026-10-28, SM-X115 prologue check).
func check_one_tap() -> void:
	var words := "퍼피랜드에는 섬이 많아요. 그중 하나가 우리 과학섬이에요."
	for i in 16:
		words += " 밤마다 길잡이 별이 바다를 비춰 줘. 배들이 길을 잃지 않게!"
	var box := DialogueBox.new(words)
	box.size = Vector2(900, 200)
	tree.root.add_child(box)
	box.layout(Rect2(0, 0, 1340, 800), 1340.0, 16.0)
	box.open()
	await tree.process_frame
	box.advance()   # the first page all typed
	var before := box.page
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.device = InputEvent.DEVICE_ID_EMULATION
	box._gui_input(touch)
	box._gui_input(click)
	var one := box.page == before + 1 and not box.typed()   # the next page, still typing (the click did not also finish it)
	expect.call(box.pages().size() >= 3 and one, "dialogue: one tap (a touch and its emulated click) is one step: the next page starts typing",
		"pages %d, page %d -> %d" % [box.pages().size(), before, box.page])
	box.queue_free()
	await tree.process_frame
