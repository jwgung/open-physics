## The title screen (2026-10-29 user decision): it shows on every launch of the child's app (after
## the boot splash) and never in a measurement, a direct --experiment / --screen launch, a
## --demo-story screenshot or the settings' renderer restart (--demo-title forces it); 시작하기 opens
## the prologue the first time and the map afterwards; 이야기 다시 보기 replays the prologue; 설정 opens
## the settings and back returns to the title; back on the map goes to the title, back on the title quits. The island behind turns by
## itself and takes no input; no spot names; the logo and the buttons fit phone and tablet.
extends RefCounted

var tree: SceneTree
var expect: Callable
const APP := "res://scripts/app/app.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	var quality_script: GDScript = load("res://scripts/core/quality.gd")
	var saved_args = quality_script.get("_args_cache")
	var saved_path := ProgressStore.path
	TitleScreen.app_may_show = true
	Story.app_may_enable = true
	check_launch_rule()
	await check_flow(quality_script)
	await check_back_press(quality_script)
	await check_skips(quality_script)
	await check_layout()
	TitleScreen.app_may_show = false
	Story.app_may_enable = false
	Story.enabled = false
	quality_script.set("_args_cache", saved_args)
	ProgressStore.path = saved_path
	DirAccess.remove_absolute(ProgressStore.path)


func check_launch_rule() -> void:
	var skip := [["--progress=bench"], ["--sound=0"], ["--auto-drag=2"], ["--demo-celebrate=1"], ["--demo-flag=orbit"],
		["--experiment=orbit"], ["--screen=settings"], ["--demo-story=map:3"]]
	var skipped := skip.all(func(a: Array) -> bool: return not App.title_on_launch(PackedStringArray(["--quality=low"] + a)))
	var shown := App.title_on_launch(PackedStringArray([])) and App.title_on_launch(PackedStringArray(["--quality=low", "--fps=1"])) \
		and App.title_on_launch(PackedStringArray(["--demo-title", "--sound=0", "--progress=bench"]))
	TitleScreen.app_may_show = false
	var off := not App.title_on_launch(PackedStringArray([]))
	TitleScreen.app_may_show = true
	expect.call(skipped and shown and off,
		"title: a plain launch shows it; measurements, --experiment, --screen and --demo-story skip it; --demo-title forces it", "")


## The launch and every button's way.
func check_flow(quality_script: GDScript) -> void:
	quality_script.set("_args_cache", PackedStringArray([]))
	DirAccess.remove_absolute(ProgressStore.path)
	var app := await _app()
	var title_first: bool = app._screen is TitleScreen and Story.enabled and Bench.scene_name == "title"
	var quits := [0]
	app.quit = func() -> void: quits[0] += 1
	app._go_back()
	var back_quits: bool = quits[0] == 1 and app._screen is TitleScreen
	# 시작하기, the first time: the map with the prologue.
	(app._screen as TitleScreen).start_button.pressed.emit()
	await tree.process_frame
	var first: bool = app._screen is IslandHomeScreen and app._screen.play_prologue_on_open
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	app.show_title()
	await tree.process_frame
	(app._screen as TitleScreen).start_button.pressed.emit()
	await tree.process_frame
	var later: bool = app._screen is IslandHomeScreen and not app._screen.play_prologue_on_open
	# 이야기 다시 보기: the prologue again.
	app.show_title()
	await tree.process_frame
	(app._screen as TitleScreen).story_button.pressed.emit()
	await tree.process_frame
	var replay: bool = app._screen is IslandHomeScreen and app._screen.play_prologue_on_open
	# 설정: the settings; back (Android or its own button) returns to the title.
	app.show_title()
	await tree.process_frame
	(app._screen as TitleScreen).settings_button.pressed.emit()
	await tree.process_frame
	var settings: bool = app._screen is SettingsScreen
	app._go_back()
	await tree.process_frame
	var back_title: bool = app._screen is TitleScreen
	(app._screen as TitleScreen).settings_button.pressed.emit()
	await tree.process_frame
	(app._screen as SettingsScreen).back_requested.emit()
	await tree.process_frame
	var button_title: bool = app._screen is TitleScreen
	# Settings from the map still goes back to the map.
	app.show_list()
	app.show_settings()
	app._go_back()
	await tree.process_frame
	var map_back: bool = app._screen is IslandHomeScreen
	await _free(app)
	expect.call(title_first and back_quits, "title: the app opens on the title (story on, measured as 'title'); back there quits", "%s %s" % [title_first, back_quits])
	expect.call(first and later and replay, "title: 시작하기 = the prologue the first time, the map afterwards; 이야기 다시 보기 = the prologue again",
		"%s %s %s" % [first, later, replay])
	expect.call(settings and back_title and button_title and map_back, "title: 설정 opens the settings and back returns to the title (from the map: to the map)",
		"%s %s %s %s" % [settings, back_title, button_title, map_back])


## Android back as the device sends it (SM-X115, 2026-10-29): one press = two
## NOTIFICATION_WM_GO_BACK_REQUEST in the same frame (onBackPressed + the KEYCODE_BACK key event). Each
## press is one step: an open sidebar closes, the lab -> the map, settings -> where they opened, the
## map -> the title, the title quits once. Before the fix the second of the pair quit from the map.
## Since 2026-10-29 (user: back closes the dialogue first) an open box goes first: in a lab Puppy's
## clue (then Dugi asks) and Dugi's explanation; Dugi's prediction question is not answered by back,
## the lab goes to the map; on the map Puppy's riddle closes before the title.
func check_back_press(quality_script: GDScript) -> void:
	quality_script.set("_args_cache", PackedStringArray([]))
	DirAccess.remove_absolute(ProgressStore.TEST_PATH)
	ProgressStore.path = ProgressStore.TEST_PATH
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)   # the map opens without the prologue
	var app := await _app()
	app.size = TABLET   # room for the dialogue boxes (the headless window is tiny)
	var quits := [0]
	app.quit = func() -> void: quits[0] += 1
	var press := func() -> void:
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		for i in 3:
			await tree.process_frame
	var settle := func(n: int) -> void:
		for i in n:
			await tree.process_frame
	var trail := []
	var where := func() -> String:
		if app._screen is ExperimentScreen:
			var lab := app._screen as ExperimentScreen
			if lab.is_sidebar_open():
				return "lab+sidebar"
			if lab.clue_telling():
				return "lab+clue"
			if lab._asking and lab.dialogue.active:
				return "lab+question"
			if lab.dialogue.active:
				return "lab+dugi"
			return "lab"
		if app._screen is IslandHomeScreen:
			var story: StoryDirector = (app._screen as IslandHomeScreen).story
			return "map+riddle" if story != null and story.riddle != null and story.riddle.active else "map"
		if app._screen is SettingsScreen:
			return "settings"
		if app._screen is TitleScreen:
			return "title"
		return str(app._screen)
	# A first visit: Puppy's clue, then Dugi's question.
	app.show_experiment(ExperimentRegistry.find("projectile"))
	for i in 120:   # the screen slides in, then Puppy speaks
		if app._screen is ExperimentScreen and (app._screen as ExperimentScreen).clue_telling():
			break
		await tree.process_frame
	await settle.call(2)
	trail.append(where.call())   # Puppy's clue
	var glow_on: bool = app._screen is ExperimentScreen and (app._screen as ExperimentScreen).experiment.game.highlighting()
	await press.call()
	trail.append(where.call())   # the clue closed: Dugi asks
	if app._screen is ExperimentScreen:   # (a wrong step left the lab: the trail shows it)
		(app._screen as ExperimentScreen).open_sidebar(false)
	await tree.process_frame
	trail.append(where.call())
	await press.call()
	await settle.call(20)   # the sidebar slides away, the question comes back
	trail.append(where.call())   # the sidebar closed, the question back
	await press.call()
	await settle.call(4)
	trail.append(where.call())   # the question unanswered: the map, Puppy's riddle
	await press.call()
	trail.append(where.call())   # the riddle closed, still the map
	# Dugi's explanation (the question answered first): back closes his box, the lab stays.
	app.show_experiment(ExperimentRegistry.find("projectile"))
	await settle.call(4)
	var lab := app._screen as ExperimentScreen
	lab._end_question()
	lab.cast.dugi.explain(lab.experiment.explain_point)
	for i in 120:
		if lab.dialogue.active:
			break
		await tree.process_frame
	trail.append(where.call())
	await press.call()
	trail.append(where.call())   # his box closed, still the lab
	await press.call()
	trail.append(where.call())   # the map (Puppy says his riddle as it opens)
	app.show_settings()
	await tree.process_frame
	await press.call()
	trail.append(where.call())   # settings from the map -> the map (the riddle again)
	if app._screen is IslandHomeScreen and (app._screen as IslandHomeScreen).story != null:
		(app._screen as IslandHomeScreen).story.hush()
	await press.call()
	trail.append(where.call())   # the map -> the title
	app.show_settings(true)
	await tree.process_frame
	await press.call()
	trail.append(where.call())   # settings from the title -> the title
	var quits_before: int = quits[0]
	await press.call()
	await _free(app)
	DirAccess.remove_absolute(ProgressStore.TEST_PATH)
	var want := ["lab+clue", "lab+question", "lab+sidebar", "lab+question", "map+riddle", "map", "lab+dugi", "lab", "map+riddle", "map+riddle", "title", "title"]
	expect.call(trail == want and glow_on and quits_before == 0 and quits[0] == 1,
		"back: one press (two go-back notifications in a frame) is one step: Puppy's clue -> Dugi's question, sidebar, the unanswered question -> the map, Puppy's riddle, Dugi's explanation, lab -> map, settings -> back, map -> title, title quits once",
		"%s (want %s) glow %s quits %d/%d" % [str(trail), str(want), glow_on, quits_before, quits[0]])


## A measured, direct or resumed launch opens its screen as before (no title).
func check_skips(quality_script: GDScript) -> void:
	var seen := []
	for args in [["--experiment=orbit"], ["--progress=bench"], ["--screen=settings"]]:   # --demo-story: the launch rule (it rewrites the bench store)
		quality_script.set("_args_cache", PackedStringArray(args))
		var app := await _app()
		seen.append(app._screen.get_script().get_global_name())
		await _free(app)
	quality_script.set("_args_cache", PackedStringArray([]))
	var resume := FileAccess.open(App.RESUME_PATH, FileAccess.WRITE)
	resume.store_string("settings")
	resume.close()
	var app := await _app()
	seen.append(app._screen.get_script().get_global_name())
	await _free(app)
	quality_script.set("_args_cache", PackedStringArray(["--demo-title", "--sound=0"]))
	app = await _app()
	seen.append(app._screen.get_script().get_global_name())
	var bench_store := ProgressStore.path == ProgressStore.BENCH_PATH
	await _free(app)
	ProgressStore.path = ProgressStore.TEST_PATH
	expect.call(str(seen.map(func(n: StringName) -> String: return str(n))) == str(["ExperimentScreen", "IslandHomeScreen", "SettingsScreen", "SettingsScreen", "TitleScreen"]) and bench_store,
		"title: --experiment, --progress=bench, --screen=settings and the settings' restart skip it; --demo-title shows it in the bench store", str(seen))


## Phone and tablet: the logo over the buttons, all inside the screen; the island turns by itself, takes
## no input and shows no names; the logo bobs.
func check_layout() -> void:
	for size in [PHONE, TABLET]:
		var host := Control.new()
		host.theme = UiTheme.build()
		host.size = size
		tree.root.add_child(host)
		var title := TitleScreen.new()
		host.add_child(title)
		for i in 3:
			await tree.process_frame
		var screen := Rect2(Vector2.ZERO, size)
		var rects := title.rects()
		var problems := []
		for r in rects:
			if not screen.encloses(r):
				problems.append("%s off screen" % r)
		for k in range(1, rects.size()):
			if rects[0].grow(-TitleScreen.BOB_UNITS).intersects(rects[k]):
				problems.append("logo over button %d" % k)
		if rects[1].intersects(rects[2]) or rects[1].intersects(rects[3]) or rects[2].intersects(rects[3]):
			problems.append("buttons overlap")
		if rects[0].size.x < TitleScreen.LOGO_MIN * 0.9 or rects[1].size.y < 80.0:
			problems.append("too small")
		var yaw: float = title.view.rig.cur_yaw
		var logo_y := title.logo.position.y
		for i in 30:
			await tree.process_frame
		if absf(title.view.rig.cur_yaw - yaw) < 0.01:
			problems.append("the island does not turn")
		if is_equal_approx(title.logo.position.y, logo_y):
			problems.append("the logo does not bob")
		if title.view.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			problems.append("the island takes input")
		if not title.find_children("*", "Label", true, false).is_empty():
			problems.append("labels on the title")
		expect.call(problems.is_empty(), "title (%s): the logo over 시작하기 and the small buttons, all on screen; the island turns by itself, no input, no names; the logo bobs"
			% ("phone" if size == PHONE else "tablet"), "; ".join(problems))
		host.queue_free()
		for i in 3:
			await tree.process_frame


func _app() -> Control:
	ProgressStore.path = ProgressStore.TEST_PATH
	var app: Control = load(APP).new()
	tree.root.add_child(app)
	for i in 2:
		await tree.process_frame
	return app


func _free(app: Control) -> void:
	app.queue_free()
	for i in 3:
		await tree.process_frame
	Story.enabled = false
