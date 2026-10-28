## The night map (2026-10-28 user-approved "explore the night map in a fixed order"): the fixed order
## and the next spot, only the next and the found spots open (a locked tap opens nothing, Puppy says
## his line and the landmark shakes), the names hidden until found, Puppy's riddle when the map opens
## (after a flag raise and a flight too) and again on a tap on him or 단서, the hint's glint after the
## delay, the night lifting with the pieces (day after the finale), the found spots lit, old saves,
## a direct --experiment launch never blocked and the measured map (bench) unchanged: day, every name,
## every spot open. Story.enabled is on only inside these checks (and restored).
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const TABLET := Vector2(1340, 800)
const HOME_SCREEN := "res://scripts/app/island_home_screen.gd"
const ORDER := ["free-fall", "projectile", "collision", "friction", "incline-friction", "spring", "constraints",
	"rotation", "pulley", "buoyancy", "orbit"]
const MAP_CLUES := {
	"free-fall": "파란 탑 꼭대기에서 반짝했어!",
	"projectile": "과녁 근처 풀밭에 뭔가 떨어졌어!",
	"collision": "공 두 개가 놓인 길쭉한 레일 쪽이야!",
	"friction": "빨간 손잡이 달린 상자 쪽에서 소리가 났어!",
	"incline-friction": "노란 비탈 아래를 봐!",
	"spring": "울타리 안, 통통 튀는 용수철 쪽이야!",
	"constraints": "줄에 매달린 공이 흔들리는 곳이야!",
	"rotation": "빨간 시소 밑에 뭔가 있어!",
	"pulley": "높은 틀에 줄이 걸린 곳이야!",
	"buoyancy": "연못 물속에서 반짝여!",
	"orbit": "마지막은 섬에서 제일 높은 전망대야!",
}
const WRONG := "음… 여긴 아닌 것 같아."


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	var was := Story.enabled
	Story.enabled = true
	check_order()
	await check_locks()
	await check_labels()
	await check_riddle()
	await check_riddle_after_flight()
	await check_hint()
	await check_brightness()
	await check_old_save()
	Story.enabled = was
	await check_direct_launch()
	await check_bench_map()
	DirAccess.remove_absolute(ProgressStore.path)


## The order and the words are the approved ones; the next spot is the first unfound in the order.
func check_order() -> void:
	var wrong := []
	for id in MAP_CLUES:
		if Story.map_clue(ExperimentRegistry.find(id)) != MAP_CLUES[id]:
			wrong.append(id)
	var spots := Story.spots().duplicate()
	spots.sort()
	var ordered := Story.order().duplicate()
	ordered.sort()
	expect.call(Story.order() == ORDER and ordered == spots and wrong.is_empty() and Story.wrong_line() == WRONG,
		"explore: the fixed order covers the 11 spots once; Puppy's 11 map riddles and his 'not here' line word for word", str(wrong))
	var nexts := []
	var progress := {}
	for id in ORDER:
		nexts.append(Story.next_spot(progress))
		progress[id] = _full(id)
	nexts.append(Story.next_spot(progress))
	expect.call(nexts == ORDER + [""], "explore: next = the first spot in the order whose piece is not found (none at 11)", str(nexts))
	var some := {"free-fall": _full("free-fall"), "projectile": _full("projectile"), "collision": 1}
	var open := ORDER.filter(func(id: String) -> bool: return Story.enterable(some, id))
	expect.call(open == ["free-fall", "projectile", "collision"], "explore: only the found spots and the next one open", str(open))


## A locked spot: no hop, no lab; Puppy's line and the landmark's shake. The next and a found one open.
func check_locks() -> void:
	_store({"free-fall": _full("free-fall")})
	var home := await _home()
	var opened := []
	home.experiment_chosen.connect(func(d: Dictionary) -> void: opened.append(d.id))
	var story: StoryDirector = home.story
	_tap(home, _spot_point(home, "spring"))
	await tree.process_frame
	var locked: bool = not home._walking and story.wrongs_told == 1 and story.riddle != null and story.riddle.active \
		and story.riddle.text == WRONG and story.riddle.speaker == "puppy" and home.shakes == 1 and story.locked("spring")
	var shook := false
	for i in 10:
		await tree.process_frame
		shook = shook or int(MapIsland.material().get_shader_parameter("shake_spot")) == int(_spot(home, "spring").tag)
	for i in 30:
		await tree.process_frame
	expect.call(locked and shook and opened.is_empty() and int(MapIsland.material().get_shader_parameter("shake_spot")) == 0,
		"explore: a locked spot does not open; Puppy says '%s' and the landmark shakes a moment" % WRONG,
		"walking %s wrongs %d shakes %d shook %s" % [str(home._walking), story.wrongs_told, home.shakes, str(shook)])
	_tap(home, _spot_point(home, "projectile"))   # the next one
	var walking: bool = home._walking and not story.riddle.active
	await _arrive(home)
	expect.call(walking and opened == ["projectile"], "explore: the next spot opens (the cat hops there, Puppy's box closes)", str(opened))
	await _free(home)
	home = await _home()
	opened = []
	home.experiment_chosen.connect(func(d: Dictionary) -> void: opened.append(d.id))
	_tap(home, _spot_point(home, "free-fall"))   # found
	await _arrive(home)
	expect.call(opened == ["free-fall"] and home.story.wrongs_told == 0, "explore: a found spot opens again", str(opened))
	await _free(home)


## The names: hidden until the spot's piece is found.
func check_labels() -> void:
	_store(_first(3))
	var home := await _home()
	var shown := ORDER.filter(func(id: String) -> bool: return home._labels.has(id) and (home._labels[id] as Control).visible)
	var tapped_name := home._spot_at(_spot_point(home, "friction"))   # its landmark still taps (a wrong guess)
	expect.call(shown == ORDER.slice(0, 3) and tapped_name == home._spots.find(_spot(home, "friction")),
		"explore: only the found spots show their names; the others' landmarks still take a tap", str(shown))
	await _free(home)


## Puppy's riddle: when the map opens (one page, his portrait at the bottom); again on a tap on him and
## on 단서; nothing while the prologue plays.
func check_riddle() -> void:
	_store(_first(2))
	var home := await _home()
	var story: StoryDirector = home.story
	var box := story.riddle
	var rect := box.rects()[0] if box != null else Rect2()
	expect.call(box != null and box.active and box.visible and box.speaker == "puppy" and box.text == MAP_CLUES.collision
		and box.pages().size() == 1 and story.riddles_told == 1 and rect.end.y > home.view.size.y * 0.8 and home.clue_button.visible,
		"explore: the map opens with Puppy's riddle for the next spot (one page, his box at the bottom, 단서 shown)",
		"%s told %d" % [box.text if box != null else "none", story.riddles_told])
	box.close(true)
	_tap(home, _world_point(home, home.puppy.global_position + Vector3.UP * 0.35))
	var by_puppy: bool = story.riddles_told == 2 and box.active and box.text == MAP_CLUES.collision and not home._walking
	box.close(true)
	home.clue_button.pressed.emit()
	expect.call(by_puppy and story.riddles_told == 3 and box.active and box.text == MAP_CLUES.collision,
		"explore: a tap on Puppy or 단서 says the riddle again (nothing opens)", "told %d" % story.riddles_told)
	await _free(home)
	# The prologue first: no riddle while it plays, the riddle right after it.
	DirAccess.remove_absolute(ProgressStore.path)
	home = await _home(true)
	story = home.story
	var quiet: bool = story.cinematic() and story.riddles_told == 0
	story.skip()
	await tree.process_frame
	await tree.process_frame
	expect.call(quiet and story.riddles_told == 1 and story.riddle.text == MAP_CLUES["free-fall"],
		"explore: no riddle during the prologue; after it Puppy's first riddle (the blue tower)", str(story.riddles_told))
	await _free(home)


## After a flag raise and the piece's flight: then the riddle (for the spot after it).
func check_riddle_after_flight() -> void:
	_store(_first(2))
	ProgressStore.mark_flag_pending("projectile")
	ProgressStore.set_mark(ProgressStore.PIECES, "projectile", false)
	var home := await _home()
	var story: StoryDirector = home.story
	var night_before := story.night
	var during: bool = home.raising() and story.riddles_told == 0
	var t0 := Time.get_ticks_msec()
	while (home.raising() or story.flying() or story.riddles_told == 0) and Time.get_ticks_msec() - t0 < 12000:
		await tree.process_frame
	expect.call(during and story.riddles_told == 1 and story.riddle.text == MAP_CLUES.collision and story.flights_played == 1,
		"explore: the riddle waits for the flag raise and the piece's flight, then comes", str(story.riddles_told))
	for i in 100:   # the night eases to its new step
		await tree.process_frame
	expect.call(story.night < night_before - 0.05 and is_equal_approx(story.night, Story.night_level(2, false)),
		"explore: the piece's arrival at the lookout lifts the night a step", "%.2f -> %.2f" % [night_before, story.night])
	await _free(home)


## The hint: nothing for HINT_DELAY_S after the riddle, then the next spot glints, again and again.
func check_hint() -> void:
	_store(_first(1))
	var home := await _home()
	var story: StoryDirector = home.story
	story.advance(StoryDirector.HINT_DELAY_S - 1.0)
	var early := not story.hinting()
	var shows := 0
	var was := false
	var over_spot := false
	for i in 240:   # 12 s
		story.advance(0.05)
		if story.hinting() and not was:
			shows += 1
			over_spot = story.hint.position.distance_to(_spot(home, "projectile").at) < 4.0
		was = story.hinting()
	story.say_riddle()
	var reset := not story.hinting()
	expect.call(early and shows >= 4 and over_spot and reset,
		"explore: after %.0f s without finding it the next spot glints, again and again; the riddle again starts the wait anew" % StoryDirector.HINT_DELAY_S,
		"early %s shows %d over %s" % [str(early), shows, str(over_spot)])
	await _free(home)


## The night follows the pieces: night at 0, lighter at 3 and 7, day only after the finale; the found
## spots are lit. Nothing new is saved for it.
func check_brightness() -> void:
	var levels := []
	var lit_ok := true
	var tints := []
	for n in [0, 3, 7, 10]:
		_store(_first(n))
		var home := await _home()
		levels.append(home.story.night)
		tints.append(home.story.tint.x)
		lit_ok = lit_ok and home.lit_spots() == Story.spots().filter(func(id: String) -> bool: return id in ORDER.slice(0, n))
		await _free(home)
	var config := ConfigFile.new()
	config.load(ProgressStore.path)
	var sections := Array(config.get_sections())
	sections.sort()
	expect.call(is_equal_approx(levels[0], 1.0) and levels[0] > levels[1] and levels[1] > levels[2] and levels[2] > levels[3] and levels[3] > 0.0
		and tints[0] < tints[1] and tints[2] < tints[3] and lit_ok and sections == ["progress", "story"],
		"explore: the map is night with no piece and lighter with each one (3, 7, 10), still a little dark before the finale; found spots lit; nothing new saved",
		"%s %s" % [str(levels), str(sections)])
	_store(_first(11))
	ProgressStore.set_mark(ProgressStore.STORY, "finale", true)
	var home := await _home()
	var shown := ORDER.filter(func(id: String) -> bool: return (home._labels[id] as Control).visible)
	expect.call(home.story.night == 0.0 and home.story.tint == Vector3.ONE and home.story.next_id == "" and shown == ORDER
		and not home.clue_button.visible and home.story.riddles_told == 0 and Story.night_level(11, true) == 0.0,
		"explore: after the finale the map is day, every name shows, no riddle and nothing locked", str(home.story.night))
	await _free(home)


## An old save (spots complete out of the order): its found spots open, show their names and are lit;
## the next is the first unfound one in the order; the night from its piece count.
func check_old_save() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var old := ConfigFile.new()
	old.set_value("progress", "projectile", 3)
	old.set_value("progress", "orbit", 3)
	old.set_value("progress", "spring", 1)
	old.set_value(ProgressStore.STORY, "prologue", true)
	old.save(ProgressStore.path)
	var home := await _home()
	var story: StoryDirector = home.story
	var shown := ORDER.filter(func(id: String) -> bool: return (home._labels[id] as Control).visible)
	var lit: Array = home.lit_spots()
	lit.sort()
	expect.call(story.next_id == "free-fall" and shown == ["projectile", "orbit"] and lit == ["orbit", "projectile"]
		and not story.locked("orbit") and not story.locked("free-fall") and story.locked("collision") and story.locked("spring")
		and is_equal_approx(story.night, Story.night_level(2, false)) and story.riddle.text == MAP_CLUES["free-fall"],
		"explore: an old save: its found spots open, named and lit; the next is the first unfound in the order; the night from its 2 pieces",
		"%s %s %.2f" % [story.next_id, str(shown), story.night])
	await _free(home)


## A direct --experiment launch opens any lab, even one locked on the map.
func check_direct_launch() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var quality_script: GDScript = load("res://scripts/core/quality.gd")
	var saved_args = quality_script.get("_args_cache")
	quality_script.set("_args_cache", PackedStringArray(["--experiment=orbit"]))
	Story.app_may_enable = true
	var app: Control = load("res://scripts/app/app.gd").new()
	tree.root.add_child(app)
	await tree.process_frame
	var screen: Control = app._screen
	expect.call(Story.enabled and screen is ExperimentScreen and str(screen.definition.id) == "orbit" and Story.next_spot(ProgressStore.load()) == "free-fall",
		"explore: a direct --experiment launch opens the lab even when it is locked on the map", str(screen))
	app.queue_free()
	for i in 3:
		await tree.process_frame
	Story.app_may_enable = false
	Story.enabled = false
	quality_script.set("_args_cache", saved_args)


## The measured map (--progress=bench: no story): day, every name, every spot opens, nothing lit.
func check_bench_map() -> void:
	var path := ProgressStore.path
	var quality_script: GDScript = load("res://scripts/core/quality.gd")
	var saved_args = quality_script.get("_args_cache")
	quality_script.set("_args_cache", PackedStringArray(["--progress=bench"]))
	Story.app_may_enable = true
	var app: Control = load("res://scripts/app/app.gd").new()
	tree.root.add_child(app)
	for i in 4:
		await tree.process_frame
	var home: IslandHomeScreen = app._screen
	var shown := ORDER.filter(func(id: String) -> bool: return home._labels.has(id) and (home._labels[id] as Control).visible)
	var opened := []
	home.experiment_chosen.connect(func(d: Dictionary) -> void: opened.append(d.id))
	home._walk_to_spot(home._spots.find(_spot(home, "orbit")))
	var walking: bool = home._walking
	home._walking = false
	expect.call(not Story.enabled and home.story == null and shown == ORDER and walking and home.lit_spots().is_empty()
		and not home.clue_button.visible and home.find_child("PuppyRiddle", true, false) == null,
		"explore: the measured map (--progress=bench) is the day map as before: every name, every spot opens, no riddle", str(shown))
	app.queue_free()
	for i in 3:
		await tree.process_frame
	Story.app_may_enable = false
	Story.enabled = false
	quality_script.set("_args_cache", saved_args)
	ProgressStore.path = path


# --- helpers ---------------------------------------------------------------------------------------

func _full(id: String) -> int:
	return MissionTracker.missions(ExperimentRegistry.find(id)).get("stages", []).size()


## The first `n` spots of the order complete.
func _first(n: int) -> Dictionary:
	var store := {}
	for id in ORDER.slice(0, n):
		store[id] = _full(id)
	return store


## A fresh test store with these stamps, the prologue seen.
func _store(progress: Dictionary) -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.save(progress)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)


func _spot(home: IslandHomeScreen, id: String) -> Dictionary:
	for spot in home._spots:
		if spot.id == id:
			return spot
	return {}


func _spot_point(home: IslandHomeScreen, id: String) -> Vector2:
	return home._world_to_screen(home.tap_point(_spot(home, id)))


func _world_point(home: IslandHomeScreen, at: Vector3) -> Vector2:
	return home._world_to_screen(at)


func _tap(home: IslandHomeScreen, at: Vector2) -> void:
	home._on_pointer("press", at)
	home._on_pointer("release", at)


## Lets the cat's hop finish (the lab would open).
func _arrive(home: IslandHomeScreen) -> void:
	var t0 := Time.get_ticks_msec()
	while home._walking and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame


func _home(prologue := false) -> IslandHomeScreen:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: IslandHomeScreen = load(HOME_SCREEN).new()
	screen.play_prologue_on_open = prologue
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame
