## UI polish (2026-10-29 user requests):
## 1. 자세히 (the side sheet): the header (the lab's name and 닫기) stays on screen above the scrolled
##    note; scrolled to the end, 닫기 is still there and closes it (phone and tablet).
## 2. 처음부터 다시 하기 (settings): nothing is erased by the first tap or by 아니요; 다시 하기 erases the
##    whole store in use (stamps, cleared runs, flags, prologue / clues / pieces / finale, the map's
##    last spot) and the app starts over at the title.
## 3. Scrolling: a vertical drag that starts on a button, a check box or a slider scrolls the settings
##    page and the sheet (DragScroll) and presses or moves nothing; a tap still presses; a sideways
##    drag on a slider still moves it.
## 4. The settings' on/off rows are big check boxes (no switch), at least 48 units, kept and read back.
## 5. The map walk: calmer (WALK_SPEED, WALK_MIN_S..WALK_MAX_S), along the paths; Puppy and Dugi follow
##    behind, apart, facing where they go; the three at map size (ACTOR_SCALE, the same on phone and
##    tablet); they rest at the last spot (saved), also when the map opens again; spot taps wait for
##    the arrival; the prologue, the flight and the finale with the new places.
## Only the test stores (ProgressStore.TEST_PATH, SoundBoard.TEST_PATH) are written.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const SETTINGS_SCREEN := "res://scripts/app/settings_screen.gd"
const HOME_SCREEN := "res://scripts/app/island_home_screen.gd"
const APP := "res://scripts/app/app.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)
const MIN_APART := 0.5   # m between two of the three (their bodies are about 0.35-0.6 m wide)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	var sound_path := SoundBoard.path
	SoundBoard.path = SoundBoard.TEST_PATH
	DirAccess.remove_absolute(SoundBoard.path)
	for setup in [[PHONE, "phone"], [TABLET, "tablet"]]:
		await check_sheet_header(setup[0], setup[1])
		await check_settings_drag(setup[0], setup[1])
	await check_sheet_drag()
	await check_check_boxes()
	await check_restart()
	await check_restart_in_app()
	check_walk_times()
	await check_walk_group()
	await check_rest_spot()
	await check_scale()
	await check_story_places()
	DirAccess.remove_absolute(SoundBoard.path)
	SoundBoard.path = sound_path
	DirAccess.remove_absolute(ProgressStore.path)


# --- 1. the sheet's header ---------------------------------------------------------------------------

func check_sheet_header(size: Vector2, name: String) -> void:
	var screen := await _lab("projectile", size)
	screen.open_sidebar(false)
	screen.set_more_open(true)   # the longest note
	for i in 3:
		await tree.process_frame
	var scroll: ScrollContainer = screen._scroll
	var close: Button = screen.close_button
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	for i in 2:
		await tree.process_frame
	var problems := []
	if scroll.scroll_vertical < 200:
		problems.append("the note did not scroll (%d)" % scroll.scroll_vertical)
	var r := close.get_global_rect()
	if not close.is_visible_in_tree() or not Rect2(Vector2.ZERO, size).encloses(r) or not screen._sidebar.get_global_rect().encloses(r):
		problems.append("닫기 %s off screen or outside the sheet" % str(r))
	if r.intersects(scroll.get_global_rect()) or r.end.y > scroll.get_global_rect().position.y + 0.5:
		problems.append("닫기 %s is not above the scrolled note %s" % [str(r), str(scroll.get_global_rect())])
	if close.is_ancestor_of(scroll) or scroll.is_ancestor_of(close):
		problems.append("닫기 is inside the scroller")
	await _tap(r.get_center())
	if screen.is_sidebar_open():
		problems.append("a tap on 닫기 after the scroll did not close the sheet")
	expect.call(problems.is_empty(), "자세히 (%s): scrolled to the end, the header with 닫기 stays above the note and closes it" % name, "; ".join(problems))
	await _close(screen)


# --- 3. drag to scroll ------------------------------------------------------------------------------

## Settings: a vertical drag from a quality card (a big button), a check box, 적용, 이야기 다시 보기 and
## 처음부터 다시 하기 scrolls the page by the finger's way and changes nothing; a tap still presses.
func check_settings_drag(size: Vector2, name: String) -> void:
	var host := _host(size)
	var screen: Control = load(SETTINGS_SCREEN).new()
	host.add_child(screen)
	for i in 3:
		await tree.process_frame
	var scroll: ScrollContainer = screen.find_children("*", "ScrollContainer", true, false)[0]
	var problems := []
	var room := scroll.get_v_scroll_bar().max_value - scroll.size.y
	if room < 100.0:
		problems.append("the page fits (%.0f units to scroll)" % room)
	var starts := {"quality card": screen._buttons[Quality.TIER_ORDER[1]], "효과음": screen.sfx_switch,
		"이야기 다시 보기": screen.find_child("StoryReplay", true, false), "처음부터 다시 하기": screen.restart_button}
	var replays := [0]
	screen.story_requested.connect(func() -> void: replays[0] += 1)
	for label in starts:
		var control: Control = starts[label]
		# The control in the middle of the page, then a drag of 90 units (up, or down near the end).
		scroll.scroll_vertical += int(control.global_position.y - scroll.global_position.y - scroll.size.y * 0.4)
		await tree.process_frame
		var selected: String = screen._selected
		var sfx: bool = screen.sfx_switch.button_pressed
		var before := scroll.scroll_vertical
		var at := control.get_global_rect().get_center()
		var way := -90.0 if before + 90 <= int(room) else 90.0
		if not Rect2(scroll.get_global_rect()).has_point(at):
			problems.append("%s not on the page at %s" % [label, str(at)])
			continue
		await _drag(at, at + Vector2(0.0, way))
		var moved := scroll.scroll_vertical - before
		if absi(moved + int(way)) > 2:
			problems.append("%s: a drag of %.0f scrolled %d" % [label, way, moved])
		if screen._selected != selected or screen.sfx_switch.button_pressed != sfx or replays[0] != 0 or screen.restart_confirm.visible:
			problems.append("%s: the drag pressed something (tier %s -> %s, sfx %s -> %s, replays %d, confirm %s)" % [label, selected, screen._selected,
				sfx, screen.sfx_switch.button_pressed, replays[0], screen.restart_confirm.visible])
	# A tap still works: the 효과음 check box.
	scroll.scroll_vertical += int(screen.sfx_switch.global_position.y - scroll.global_position.y - scroll.size.y * 0.4)
	await tree.process_frame
	var was: bool = screen.sfx_switch.button_pressed
	await _tap(screen.sfx_switch.get_global_rect().get_center())
	if screen.sfx_switch.button_pressed == was:
		problems.append("a tap on 효과음 did not toggle it")
	screen.sfx_switch.button_pressed = was
	expect.call(problems.is_empty(), "settings (%s): a vertical drag from a quality card, a check box or a button scrolls the page and presses nothing; a tap still toggles" % name,
		"; ".join(problems))
	host.queue_free()
	await tree.process_frame


## The sheet: a vertical drag from a slider scrolls (the slider keeps its value), a sideways drag
## moves the slider (the note does not scroll), a drag from a condition chip presses nothing.
func check_sheet_drag() -> void:
	var screen := await _lab("free-fall", TABLET)
	screen.open_sidebar(false)
	screen.set_more_open(true)
	for i in 3:
		await tree.process_frame
	var scroll: ScrollContainer = screen._scroll
	var problems := []
	var slider: HSlider = null
	for id in screen._control_widgets:
		if screen._control_widgets[id].has("slider"):
			slider = screen._control_widgets[id].slider
			break
	if slider == null:
		problems.append("no slider")
	else:
		# Bring the slider into the upper part of the view.
		scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + int(slider.global_position.y - scroll.global_position.y) - 150)
		await tree.process_frame
		var value := slider.value
		var before := scroll.scroll_vertical
		var at := slider.get_global_rect().get_center() + Vector2(slider.size.x * 0.3, 0.0)   # off the grabber
		await _drag(at, at + Vector2(0.0, -80.0))
		if absi(scroll.scroll_vertical - before - 80) > 2 or slider.value != value:
			problems.append("slider vertical drag: scrolled %d, value %.2f -> %.2f" % [scroll.scroll_vertical - before, value, slider.value])
		await tree.process_frame
		before = scroll.scroll_vertical
		at = slider.get_global_rect().get_center()
		value = slider.value
		await _drag(at, at + Vector2(-slider.size.x * 0.4, 0.0))
		if scroll.scroll_vertical != before or is_equal_approx(slider.value, value):
			problems.append("slider sideways drag: scrolled %d, value %.2f -> %.2f" % [scroll.scroll_vertical - before, value, slider.value])
	var more: Button = screen._more_button
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + int(more.global_position.y - scroll.global_position.y) - 200)
	await tree.process_frame
	var open: bool = screen.is_more_open()
	var before2 := scroll.scroll_vertical
	if scroll.get_global_rect().has_point(more.get_global_rect().get_center()):
		await _drag(more.get_global_rect().get_center(), more.get_global_rect().get_center() + Vector2(0.0, 70.0))
		if screen.is_more_open() != open or scroll.scroll_vertical == before2:
			problems.append("a drag from 더 보기 toggled it or did not scroll (%d)" % (scroll.scroll_vertical - before2))
	else:
		problems.append("더 보기 not in view")
	expect.call(problems.is_empty(), "자세히: a vertical drag from a slider or a button scrolls the note (no value change, nothing pressed); sideways on a slider moves it",
		"; ".join(problems))
	await _close(screen)


# --- 4. check boxes ----------------------------------------------------------------------------------

func check_check_boxes() -> void:
	var problems := []
	var host := _host(TABLET)
	var screen: Control = load(SETTINGS_SCREEN).new()
	host.add_child(screen)
	for i in 3:
		await tree.process_frame
	var switches := screen.find_children("*", "CheckButton", true, false)
	if not switches.is_empty():
		problems.append("%d switches left" % switches.size())
	var checks: Array = [screen.sfx_switch, screen.music_switch, screen.fps_check]
	for check: CheckBox in checks:
		if check == null or not (check is CheckBox):
			problems.append("not a check box")
			continue
		var icon := check.get_theme_icon("checked")
		if check.size.y < 48.0 or icon == null or icon.get_height() < 40 or check.size.x < 200.0:
			problems.append("%s: row %s, box %d (want a 48+ unit row, a 40+ unit box)" % [check.text, str(check.size), icon.get_height() if icon else 0])
	# A tap on 배경 음악 toggles it, it is kept in the settings file and the next screen shows it.
	var fps_seen := []
	screen.fps_toggled.connect(func(on: bool) -> void: fps_seen.append(on))
	var scroll: ScrollContainer = screen.find_children("*", "ScrollContainer", true, false)[0]
	for check: CheckBox in [screen.music_switch, screen.fps_check]:
		scroll.scroll_vertical += int(check.global_position.y - scroll.global_position.y - scroll.size.y * 0.4)
		await tree.process_frame
		await _tap(check.get_global_rect().get_center())
	var config := ConfigFile.new()
	config.load(SoundBoard.path)
	if config.get_value("sound", "music", true) != false:
		problems.append("배경 음악 off not kept")
	if fps_seen != [true]:
		problems.append("fps check box emitted %s" % str(fps_seen))
	host.queue_free()
	await tree.process_frame
	host = _host(TABLET)
	screen = load(SETTINGS_SCREEN).new()
	host.add_child(screen)
	await tree.process_frame
	if screen.music_switch.button_pressed or not screen.sfx_switch.button_pressed:
		problems.append("not read back (music %s sfx %s)" % [screen.music_switch.button_pressed, screen.sfx_switch.button_pressed])
	screen.music_switch.button_pressed = true
	host.queue_free()
	await tree.process_frame
	expect.call(problems.is_empty(), "settings: 효과음 / 배경 음악 / fps are big check boxes (no switch), a tap toggles, kept and read back", "; ".join(problems))


# --- 2. 처음부터 다시 하기 ------------------------------------------------------------------------------

## A store with everything a child can have.
func _full_store() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.save({"projectile": 3, "spring": 1})
	ProgressStore.save_cleared("projectile", {"speed": 6.0})
	ProgressStore.mark_flag_pending("projectile")
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	ProgressStore.set_mark(ProgressStore.STORY, "finale", true)
	ProgressStore.set_mark(ProgressStore.CLUES, "spring", true)
	ProgressStore.set_mark(ProgressStore.PIECES, "projectile", false)
	ProgressStore.set_last_spot("spring")


func _store_text() -> String:
	return FileAccess.get_file_as_string(ProgressStore.path) if FileAccess.file_exists(ProgressStore.path) else ""


func check_restart() -> void:
	_full_store()
	var full := _store_text()
	var host := _host(TABLET)
	var screen: Control = load(SETTINGS_SCREEN).new()
	host.add_child(screen)
	await tree.process_frame
	var restarts := [0]
	screen.restart_requested.connect(func() -> void: restarts[0] += 1)
	var scroll: ScrollContainer = screen.find_children("*", "ScrollContainer", true, false)[0]
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await tree.process_frame
	var problems := []
	await _tap(screen.restart_button.get_global_rect().get_center())
	await tree.process_frame
	var asking: bool = screen.restart_confirm.visible and not screen.restart_button.visible
	if not asking or _store_text() != full or restarts[0] != 0:
		problems.append("first tap: confirm %s, store kept %s, restarts %d" % [asking, _store_text() == full, restarts[0]])
	var question: Label = screen.restart_confirm.find_children("*", "Label", true, false)[0]
	if question.text != screen.RESTART_QUESTION:
		problems.append("question '%s'" % question.text)
	await _tap(screen.restart_no.get_global_rect().get_center())
	if screen.restart_confirm.visible or not screen.restart_button.visible or _store_text() != full or restarts[0] != 0:
		problems.append("아니요 erased or kept the question")
	screen.restart()   # without the question showing: nothing
	if _store_text() != full or restarts[0] != 0:
		problems.append("restart() without the question erased")
	await _tap(screen.restart_button.get_global_rect().get_center())
	await tree.process_frame
	await _tap(screen.restart_yes.get_global_rect().get_center())
	var empty: bool = ProgressStore.load().is_empty() and not FileAccess.file_exists(ProgressStore.path) \
		and ProgressStore.cleared("projectile").is_empty() and ProgressStore.pending_flags().is_empty() \
		and not Story.prologue_seen() and not Story.finale_seen() and not Story.clue_seen("spring") \
		and ProgressStore.pending(ProgressStore.PIECES).is_empty() and ProgressStore.last_spot() == ""
	if not empty or restarts[0] != 1:
		problems.append("다시 하기: empty %s, restarts %d" % [empty, restarts[0]])
	expect.call(problems.is_empty(), "처음부터 다시 하기: the first tap only asks '정말 처음부터 다시 할까요?'; 아니요 keeps everything; 다시 하기 erases stamps, flags, story, pieces and the last spot",
		"; ".join(problems))
	host.queue_free()
	await tree.process_frame


## In the app: 다시 하기 goes to the title, whose 시작하기 then plays the prologue (never seen now).
func check_restart_in_app() -> void:
	var quality_script: GDScript = load("res://scripts/core/quality.gd")
	var saved_args = quality_script.get("_args_cache")
	quality_script.set("_args_cache", PackedStringArray([]))
	TitleScreen.app_may_show = true
	Story.app_may_enable = true
	_full_store()
	var app: Control = load(APP).new()
	tree.root.add_child(app)
	for i in 2:
		await tree.process_frame
	app.show_settings()
	await tree.process_frame
	var settings: Control = app._screen
	settings.show_restart_confirm(true)
	settings.restart_yes.pressed.emit()
	await tree.process_frame
	var to_title: bool = app._screen is TitleScreen
	var prologue := false
	if to_title:
		(app._screen as TitleScreen).start_button.pressed.emit()
		await tree.process_frame
		prologue = app._screen is IslandHomeScreen and app._screen.play_prologue_on_open
	app.queue_free()
	for i in 3:
		await tree.process_frame
	TitleScreen.app_may_show = false
	Story.app_may_enable = false
	Story.enabled = false
	quality_script.set("_args_cache", saved_args)
	ProgressStore.path = ProgressStore.TEST_PATH
	expect.call(to_title and prologue, "처음부터 다시 하기 in the app: the title, then 시작하기 plays the prologue again", "%s %s" % [to_title, prologue])
	DirAccess.remove_absolute(ProgressStore.path)


# --- 5. the map walk ---------------------------------------------------------------------------------

## The walk's time: at least WALK_MIN_S, at most WALK_MAX_S, else its way at WALK_SPEED (calmer than
## the old 6 m/s hop straight over); in place: a short hop.
func check_walk_times() -> void:
	var script: GDScript = load(HOME_SCREEN)
	var speed: float = script.WALK_SPEED
	var lo: float = script.WALK_MIN_S
	var hi: float = script.WALK_MAX_S
	var ok: bool = speed <= 3.0 and lo >= 1.2 and lo <= 1.8 and is_equal_approx(script.walk_seconds(1.0), lo) \
		and is_equal_approx(script.walk_seconds(6.0), 6.0 / speed) and is_equal_approx(script.walk_seconds(30.0), hi) \
		and script.walk_seconds(0.0) < lo
	expect.call(ok, "map walk: %.1f m/s, %.1f-%.1f s a walk (1 m: %.2f s, 6 m: %.2f s, 30 m: %.2f s)" % [speed, lo, hi,
		script.walk_seconds(1.0), script.walk_seconds(6.0), script.walk_seconds(30.0)], "")


## From the square to every spot, and on from spot to spot: Puppy and Dugi walk with the cat, a
## little behind, never on top of each other (MIN_APART), each facing where it goes, near the paths
## (never in the pond); the walk lasts its walk_seconds; they end in the group's places facing the
## landmark; a second tap during the walk is ignored.
func check_walk_group() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _home(TABLET)
	screen.set_process(false)   # the test steps the walk
	var chosen := []
	screen.experiment_chosen.connect(func(d: Dictionary) -> void: chosen.append(d.id))
	var problems := []
	var order := ["projectile", "pulley", "buoyancy", "orbit", "free-fall", "collision", "incline-friction"]
	var min_apart := INF
	var max_lag := 0.0
	var worst_face := 0.0
	var worst_at := ""
	for id in order:
		var index: int = screen._spot_index(id)
		screen._walk_to_spot(index)
		var total: float = screen._walk_total
		var other: int = screen._spot_index("spring")
		screen._walk_to_spot(other)   # a tap during the walk: ignored
		if screen._walk_spot != index:
			problems.append("%s: a second tap retargeted the walk" % id)
		var t := 0.0
		var last := {}
		while screen._walking and t < 10.0:
			screen._process(1.0 / 60.0)
			t += 1.0 / 60.0
			var actors: Array = [screen.cat, screen.puppy, screen.dugi]
			for i in 3:
				for j in range(i + 1, 3):
					var d := _flat(actors[i].position).distance_to(_flat(actors[j].position))
					min_apart = minf(min_apart, d)
			for actor: Node3D in [screen.puppy, screen.dugi]:
				max_lag = maxf(max_lag, _flat(actor.position).distance_to(_flat(screen.cat.position)))
				if screen.map.water_at(actor.position.x, actor.position.z):
					problems.append("%s in the pond on the way to %s" % [actor.name, id])
			# Facing: against the way it went over the last 0.3 s (18 frames), while it walks on (> 0.6 m/s).
			for actor: Node3D in actors:
				var trail: Array = last.get(actor, [])
				trail.append(_flat(actor.position))
				if trail.size() > 18:
					trail.pop_front()
				last[actor] = trail
				var went: Vector2 = trail.back() - trail.front()
				if t > maxf(0.5, total * 0.25) and t < total * 0.8 and trail.size() == 18 and went.length() > 0.6 * 0.3:   # under way
					var facing := Vector2(sin(actor.rotation.y), cos(actor.rotation.y))
					var off_deg := rad_to_deg(absf(facing.angle_to(went)))
					if off_deg > worst_face:
						worst_face = off_deg
						worst_at = "%s to %s at %.2f/%.2f s" % [actor.name, id, t, total]
		if absf(t - total) > 2.0 / 60.0 or chosen.back() != id:
			problems.append("%s: walked %.2f s (want %.2f), chose %s" % [id, t, total, str(chosen)])
		var group: Dictionary = screen.group_at(screen._spots[index])
		for actor: Node3D in [screen.cat, screen.puppy, screen.dugi]:
			if actor.position.distance_to(group[actor]) > 0.01 or absf(angle_difference(actor.rotation.y, group.facing)) > 0.01:
				problems.append("%s: %s not in its place facing the landmark" % [id, actor.name])
		if ProgressStore.last_spot() != id:
			problems.append("%s: last spot saved as '%s'" % [id, ProgressStore.last_spot()])
	if min_apart < MIN_APART:
		problems.append("two of them came %.2f m close" % min_apart)
	if max_lag > 2.5:
		problems.append("a follower fell %.1f m behind" % max_lag)
	if worst_face > 45.0:
		problems.append("an actor faced %.0f deg off where it went (%s)" % [worst_face, worst_at])
	expect.call(problems.is_empty(), "map walk: Puppy and Dugi walk with the cat (a step behind, %.2f m apart at the closest, at most %.1f m behind), facing their way (worst %.0f deg), to the group's places; taps wait" % [min_apart, max_lag, worst_face],
		"; ".join(problems))
	await _free(screen)


## Every spot's group places: on the grass (no water, inside the beach), clear of every stage, the
## three MIN_APART apart.
func check_rest_spot() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _home(PHONE)
	var problems := []
	for spot in screen._spots:
		var group: Dictionary = screen.group_at(spot)
		var places: Array = [group[screen.cat], group[screen.puppy], group[screen.dugi]]
		for p: Vector3 in places:
			if screen.map.water_at(p.x, p.z) or MapIsland.coast_fraction(p.x, p.z) > MapIsland.grass_edge():
				problems.append("%s: %s off the grass" % [spot.id, str(p)])
			for other in screen._spots:
				if float(other.radius) > 0.0 and _flat(p).distance_to(_flat(other.at)) < float(other.radius) + 0.2:
					problems.append("%s: %s on the %s stage" % [spot.id, str(p), other.id])
		for i in 3:
			for j in range(i + 1, 3):
				if _flat(places[i]).distance_to(_flat(places[j])) < MIN_APART:
					problems.append("%s: two places %.2f m apart" % [spot.id, _flat(places[i]).distance_to(_flat(places[j]))])
	await _free(screen)
	# The map opens again (after the lab): the three stand at the saved spot; the first time on the square.
	ProgressStore.set_last_spot("rotation")
	screen = await _home(TABLET)
	var index: int = screen._spot_index("rotation")
	var group: Dictionary = screen.group_at(screen._spots[index])
	for actor: Node3D in [screen.cat, screen.puppy, screen.dugi]:
		if actor.position.distance_to(group[actor]) > 0.01:
			problems.append("reopened: %s at %s (want %s)" % [actor.name, str(actor.position), str(group[actor])])
	if screen.rest_spot != index:
		problems.append("reopened: rest spot %d" % screen.rest_spot)
	await tree.process_frame
	# A spot name over them fades (they stand under the next spot's name in the yard); the others not.
	ProgressStore.set_last_spot("pulley")
	await _free(screen)
	screen = await _home(TABLET)
	for i in 3:
		await tree.process_frame
	var faded := 0
	for id in screen._labels:
		var label: Control = screen._labels[id]
		var over: bool = label.visible and screen._label_rect(label).intersects(screen.trio_rect())
		if over:
			faded += 1
		if is_equal_approx(label.modulate.a, 1.0) == over:
			problems.append("the %s name: over the three %s, alpha %.2f" % [id, over, label.modulate.a])
	if faded == 0:
		problems.append("at the pulley no name is over the three (the check saw nothing to fade)")
	ProgressStore.set_last_spot("rotation")
	await _free(screen)
	screen = await _home(TABLET)
	index = screen._spot_index("rotation")
	group = screen.group_at(screen._spots[index])
	# From there, a walk starts where they stand.
	screen._walk_to_spot(screen._spot_index("spring"))
	if screen._route.size() < 2 or screen._route[0].distance_to(_flat(group[screen.cat])) > 0.01:
		problems.append("the next walk does not start at the rest spot")
	await _free(screen)
	ProgressStore.set_last_spot("no-such-spot")
	screen = await _home(TABLET)
	if screen.rest_spot != -1 or screen.cat.position.distance_to(screen.trio_spot(screen.cat)) > 0.01 \
			or _flat(screen.cat.position).distance_to(Vector2(MapIsland.HOME[0], MapIsland.HOME[1])) > 0.01:
		problems.append("an unknown saved spot: not on the square")
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(), "map: the group's places at all 11 spots are on the grass, off the stages, apart; the map opens with the three at the last spot (unknown or none: the square)",
		"; ".join(problems))


## The three at map size: the cat about a landmark's height (not over most of them as at lab size)
## and narrower than a path; the same size on screen (UI units) on phone and tablet, big enough to see.
func check_scale() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var problems := []
	var heights := {}
	for setup in [[PHONE, "phone"], [TABLET, "tablet"]]:
		var screen := await _home(setup[0])
		var cat: AABB = screen.cat.bounds()
		var tops: Array = screen._spots.map(func(s: Dictionary) -> float: return float(s.top))
		tops.sort()
		var median: float = tops[tops.size() / 2]
		if cat.size.y > median * 1.1 or cat.size.y < 0.6 or cat.size.x > MapIsland.PATH_WIDTH:
			problems.append("%s: cat %.2f m high, %.2f m wide (landmarks' median %.2f m, path %.1f m)" % [setup[1], cat.size.y, cat.size.x, median, MapIsland.PATH_WIDTH])
		for actor: Node3D in [screen.dugi, screen.puppy]:
			if actor.bounds().size.y > 1.2:
				problems.append("%s: %s %.2f m high" % [setup[1], actor.name, actor.bounds().size.y])
		var foot: Vector2 = screen._world_to_screen(cat.position + Vector3(cat.size.x * 0.5, 0.0, cat.size.z * 0.5))
		var head: Vector2 = screen._world_to_screen(cat.position + Vector3(cat.size.x * 0.5, cat.size.y, cat.size.z * 0.5))
		heights[setup[1]] = foot.distance_to(head)
		await _free(screen)
	if heights.phone < 14.0 or absf(heights.phone - heights.tablet) > 0.05 * heights.tablet:
		problems.append("on screen: phone %.1f, tablet %.1f units" % [heights.phone, heights.tablet])
	expect.call(problems.is_empty(), "map: the three at map size (cat %.0f units high on screen on phone and tablet, about a landmark's height)" % heights.get("tablet", 0.0),
		"; ".join(problems))


## The story with the new places: the prologue (replayed with the three at a spot) starts and ends on
## the square, its last page shows the cat; the finale's cat lifts the star just over its paws and
## comes back to the group at the lookout; a piece's flight with the three at a spot moves nobody.
func check_story_places() -> void:
	var was := Story.enabled
	Story.enabled = true
	var problems := []
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	ProgressStore.set_last_spot("pulley")
	var home := await _home(TABLET, true)
	var story: StoryDirector = home.story
	if home.rest_spot != -1 or ProgressStore.last_spot() != "" or _flat(home.cat.position).distance_to(Vector2(MapIsland.HOME[0], MapIsland.HOME[1])) > 0.01:
		problems.append("prologue: the three are not on the square")
	var cat_seen := false
	for p in Story.pages("prologue").size():
		for i in 70:
			story.advance(0.05)
		if p == Story.pages("prologue").size() - 1:
			var at: Vector2 = home._world_to_screen(home.cat.position + Vector3.UP * 0.4)
			var feet: Vector2 = home._world_to_screen(home.cat.position)
			cat_seen = at != Vector2.INF and Rect2(Vector2(0.0, 0.0), home.view.size).grow(-40.0).has_point(at) and feet.distance_to(at) > 30.0
		var box: DialogueBox = story.dialogue
		var words := box.text
		for k in 6:
			if not box.active or box.text != words:
				break
			box.advance()
	for i in 40:
		story.advance(0.05)
	if not cat_seen:
		problems.append("prologue: the last page does not show the cat big on the square")
	if story.busy() or home.cat.position.distance_to(home.trio_spot(home.cat)) > 0.01 or home.rest_spot != -1:
		problems.append("prologue: afterwards not on the square")
	await _free(home)
	# A flight with the three at a spot: they stay.
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	ProgressStore.save({"projectile": 3})
	ProgressStore.set_mark(ProgressStore.PIECES, "projectile", false)
	ProgressStore.set_last_spot("projectile")
	home = await _home(TABLET, false)
	story = home.story
	var places: Array = [home.cat.position, home.puppy.position, home.dugi.position]
	var t0 := Time.get_ticks_msec()
	while (story.flying() or home.raising() or story.flights_played == 0) and Time.get_ticks_msec() - t0 < 8000:
		await tree.process_frame
	if story.flights_played != 1 or [home.cat.position, home.puppy.position, home.dugi.position] != places:
		problems.append("flight: played %d, the three moved" % story.flights_played)
	await _free(home)
	# The finale with the three at the lookout (the orbit lab just done).
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	var store := {}
	for id in Story.spots():
		store[id] = MissionRound.missions(ExperimentRegistry.find(id)).stages.size()
	ProgressStore.save(store)
	ProgressStore.set_last_spot("orbit")
	home = await _home(TABLET, false)
	story = home.story
	var lift_gap := []
	for i in 600:
		story.advance(0.05)
		if story._lift and story._star != null:
			lift_gap.append(story._star.position.y - home.cat.position.y)   # the last: where it rides
		if story.dialogue != null and story.dialogue.active:
			story.dialogue.advance()
		if not story.busy() and i > 100:
			break
	var group: Dictionary = home.group_at(home._spots[home._spot_index("orbit")])
	if lift_gap.is_empty() or lift_gap.back() > 2.0 or lift_gap.back() < home.cat.bounds().size.y:
		problems.append("finale: the star %s m over the cat at the end of the lift (cat %.2f m)" % [str(lift_gap.back() if not lift_gap.is_empty() else -1.0), home.cat.bounds().size.y])
	if story.busy() or home.cat.position.distance_to(group[home.cat]) > 0.01:
		problems.append("finale: afterwards the cat is not with the group at the lookout")
	await _free(home)
	DirAccess.remove_absolute(ProgressStore.path)
	Story.enabled = was
	expect.call(problems.is_empty(), "story with the map-size three: the prologue on the square (its last page shows the cat), a flight moves nobody, the finale's lift and return at the lookout",
		"; ".join(problems))


# --- helpers ---------------------------------------------------------------------------------------

static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _host(size: Vector2) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	return host


func _lab(id: String, size: Vector2) -> Control:
	DirAccess.remove_absolute(ProgressStore.path)
	var host := _host(size)
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


func _home(size: Vector2, prologue := false) -> Control:
	var host := _host(size)
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


## A finger (the touch and its emulated click, as on Android) at a canvas point.
func _finger(canvas_at: Vector2, kind: String) -> void:
	var at: Vector2 = tree.root.get_final_transform() * canvas_at   # window pixels (canvas_items stretch)
	if kind == "move":
		var drag := InputEventScreenDrag.new()
		drag.position = at
		tree.root.push_input(drag)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.device = InputEvent.DEVICE_ID_EMULATION
		tree.root.push_input(motion)
	else:
		var touch := InputEventScreenTouch.new()
		touch.position = at
		touch.pressed = kind == "down"
		tree.root.push_input(touch)
		var click := InputEventMouseButton.new()
		click.position = at
		click.global_position = at
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = kind == "down"
		click.device = InputEvent.DEVICE_ID_EMULATION
		tree.root.push_input(click)
	await tree.process_frame


func _tap(at: Vector2) -> void:
	await _finger(at, "down")
	await _finger(at, "up")
	await tree.process_frame


## Down at `from`, 10 moves to `to`, held there a moment (no momentum), up there.
func _drag(from: Vector2, to: Vector2) -> void:
	await _finger(from, "down")
	for i in range(1, 11):
		await _finger(from.lerp(to, i / 10.0), "move")
	for i in 8:
		await tree.process_frame
	await _finger(to, "up")
