## Sound (2026-10-28): every event asks SoundBoard for its own sound id (buttons, picture buttons,
## the screen change, the map's spot / hop / flag, a lab's launch / landing / bump / splash / stop /
## spring, Dugi's question, the stamp and the round's fanfare); the 효과음 / 배경 음악 switches mute
## their own bus and are kept in the settings file (another file for the tests: the real
## user://settings.cfg is checked unchanged); the music loops (its import flag); a measurement plays
## nothing and writes nothing; nothing sounds frame after frame while the map or a lab is idle.
## Sounds only listen: the labs' own checks run with the board in place.
extends RefCounted

var tree: SceneTree
var expect: Callable
var board: SoundBoard
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const HOME_SCREEN := "res://scripts/app/island_home_screen.gd"
const SETTINGS_SCREEN := "res://scripts/app/settings_screen.gd"
const APP := "res://scripts/app/app.gd"
const SIZE := Vector2(1152, 720)
const MAX_AUDIO_BYTES := 1_500_000


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	board = SoundBoard.instance()
	expect.call(board != null and board.get_parent() == tree.root, "sound: the board is an autoload (\"Sound\")", "")
	if board == null:
		return
	var real_settings := _file_state(SoundBoard.PATH)
	var saved_path := SoundBoard.path
	SoundBoard.path = SoundBoard.TEST_PATH
	DirAccess.remove_absolute(SoundBoard.path)
	board.load_settings()
	check_assets()
	check_silent_args()
	await check_buttons()
	check_lab_rules()
	await check_lab_stub()
	await check_real_labs()
	await check_question_and_celebration()
	await check_map()
	await check_app_swap()
	await check_switches()
	await check_silent_run()
	await check_idle()
	check_pool()
	DirAccess.remove_absolute(SoundBoard.path)
	SoundBoard.path = saved_path
	board.load_settings()
	expect.call(_file_state(SoundBoard.PATH) == real_settings, "sound: the tests never touch the real settings file (user://settings.cfg)", "")


## Every event's file is there, small; the music loops seamlessly by its import flag (the 64 s Children's March Theme, 2026-10-28).
func check_assets() -> void:
	var missing := []
	var bytes := 0
	for id in SoundBoard.SFX:
		var file := SoundBoard.SFX_DIR + str(SoundBoard.SFX[id][0])
		if not (load(file) is AudioStreamOggVorbis):
			missing.append(id)
		bytes += _bytes(file)
	bytes += _bytes(SoundBoard.MUSIC_PATH)
	expect.call(missing.is_empty() and bytes < MAX_AUDIO_BYTES, "sound: every event has an ogg file; all audio together is small",
		"missing %s, %d bytes" % [str(missing), bytes])
	var music: AudioStream = load(SoundBoard.MUSIC_PATH)
	var loops: bool = music is AudioStreamOggVorbis and (music as AudioStreamOggVorbis).loop
	expect.call(loops and board.music_stream() == music and absf(music.get_length() - 64.0) < 0.05,
		"sound: the music is the 64 s march and loops (loop flag of its import)", "loop %s length %.2f" % [str(loops), music.get_length() if music else -1.0])
	var buses: bool = AudioServer.get_bus_index(SoundBoard.SFX_BUS) > 0 and AudioServer.get_bus_index(SoundBoard.MUSIC_BUS) > 0 \
		and AudioServer.get_bus_send(AudioServer.get_bus_index(SoundBoard.SFX_BUS)) == &"Master" \
		and AudioServer.get_bus_send(AudioServer.get_bus_index(SoundBoard.MUSIC_BUS)) == &"Master"
	expect.call(buses, "sound: SFX and Music buses send to Master", "")


func check_silent_args() -> void:
	var cases := {
		[]: false, ["--experiment=free-fall"]: false, ["--sound=0"]: true, ["--auto-drag=4"]: true,
		["--auto-release=4"]: true, ["--demo-celebrate=1"]: true, ["--auto-drag=4", "--sound=1"]: false,
	}
	var wrong := []
	for args in cases:
		if SoundBoard.is_silent_run(PackedStringArray(args)) != cases[args]:
			wrong.append(args)
	expect.call(wrong.is_empty(), "sound: a measurement (--auto-drag / --auto-release / --demo-celebrate, --sound=0) is silent; --sound=1 wins", str(wrong))


## A button "tap", a condition picture button and Dugi's answer button "pick".
func check_buttons() -> void:
	var host := _host()
	var ids := []
	for variation in ["", "PrimaryButton", "PickButton", "ChoiceButton"]:
		var button := Ui.button("x", variation)
		host.add_child(button)
		board.requests.clear()
		button.pressed.emit()
		ids.append(_last())
	host.queue_free()
	await tree.process_frame
	expect.call(ids == [&"tap", &"tap", &"pick", &"pick"], "sound: a button taps, a picture button (condition, answer) picks", str(ids))


## The status changes that sound, per lab (and the ones that must not).
func check_lab_rules() -> void:
	var cases := [
		["free-fall", "ready", "falling", &"launch"], ["projectile", "ready", "flying", &"launch"],
		["collision", "ready", "moving", &"launch"], ["spring", "held", "moving", &"spring"],
		["spring", "ready", "moving", &"spring"], ["buoyancy", "held", "moving", &"launch"],
		["orbit", "ready", "orbiting", &"launch"], ["constraints", "held", "swinging", &"launch"],
		["incline-friction", "ready", "sliding", &"launch"], ["friction", "holding", "sliding", &"launch"],
		["friction", "sliding", "holding", &"stop"], ["pulley", "pulling", "top", &"stop"],
		["rotation", "pressing", "lifted", &"launch"],
		# silent: a drum bobbing about its depth, the ball landing (the impact sounds it), a reset
		["buoyancy", "floating", "moving", &""], ["buoyancy", "moving", "floating", &""],
		["free-fall", "falling", "landed", &""], ["projectile", "landed", "ready", &""],
		["rotation", "holding", "moving", &""], ["orbit", "orbiting", "crash", &""],
	]
	var wrong := []
	for c in cases:
		if LabSounds.sound_for(c[0], c[1], c[2]) != c[3]:
			wrong.append(c)
	expect.call(wrong.is_empty(), "sound: a lab's status changes map to launch / spring / stop; bobbing, landing (status) and reset are silent", str(wrong))


## A stand-in lab: a status change sounds once (not again while it stays), an impact lands, a raised
## splash / hit counter makes the impact a splash / bump, the friction's end a stop.
func check_lab_stub() -> void:
	var lab = _stand_in("free-fall")   # untyped: its own s / splashes / hit_reactions
	tree.root.add_child(lab)
	var sounds := LabSounds.create(lab)
	tree.root.add_child(sounds)
	board.requests.clear()
	for i in 3:
		sounds.watch()
	var idle := board.requests.size()
	lab.s = "falling"
	for i in 5:
		sounds.watch()
	var launched := board.requests.duplicate()
	board.requests.clear()
	lab.impact.emit(0.5)
	var landed := _last()
	lab.splashes = 1
	lab.impact.emit(0.5)
	var splash := _last()
	lab.impact.emit(0.5)   # the floor after the splash: a landing
	var floor_hit := _last()
	lab.hit_reactions = 1
	lab.impact.emit(0.5)
	var bump := _last()
	sounds.lab_id = "friction"
	lab.s = "end"
	sounds._status = "end"
	lab.impact.emit(0.35)
	var stop := _last()
	sounds.queue_free()
	lab.queue_free()
	await tree.process_frame
	expect.call(idle == 0 and launched == [&"launch"], "sound: a status change sounds once (not every frame it stays)", "%d %s" % [idle, str(launched)])
	expect.call(landed == &"land" and splash == &"splash" and floor_hit == &"land" and bump == &"bump" and stop == &"stop",
		"sound: an impact lands; with the splash / hit counter up a splash / bump; the friction box's end a stop",
		"%s %s %s %s %s" % [landed, splash, floor_hit, bump, stop])


## Real labs through the screen: free fall (launch, then a landing), collision (launch, the bump), and
## the lab's sounds sit beside the lab (its tree has none).
func check_real_labs() -> void:
	for spec in [["free-fall", [&"launch", &"land"]], ["collision", [&"launch", &"bump"]]]:
		var screen := await _lab(spec[0])
		var lab: Experiment = screen.experiment
		var beside: bool = screen.sounds != null and screen.sounds.get_parent() == screen \
			and lab.find_children("*", "LabSounds", true, false).is_empty()
		board.requests.clear()
		screen.experiment_action("release")
		var heard := []
		for i in 600:
			await tree.physics_frame
			await tree.process_frame
			for id in board.requests:
				if not heard.has(id):
					heard.append(id)
			if heard.size() >= 2:
				break
		expect.call(beside and heard.slice(0, 2) == spec[1], "sound: %s release -> %s (heard %s)" % [spec[0], str(spec[1]), str(heard)],
			"status %s" % lab.status())
		await _free(screen)


## Dugi asks (question), the answer picks; the stamp lands once with a 쾅 (stamp); the round's
## celebration plays the fanfare.
func check_question_and_celebration() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	board.requests.clear()
	var screen := await _lab("projectile")
	var asked := board.requests.has(&"question")
	board.requests.clear()
	(screen._choices.get_child(0) as Button).pressed.emit()
	var answered := _last()
	screen.mission_round.stamps = 1
	screen.mission_round.demo_stamp(1)
	var slam: StampSlam = screen._slam
	board.requests.clear()
	slam.advance(StampSlam.DROP_S * 0.5)
	var before_landing := board.requests.size()
	slam.advance(StampSlam.DROP_S)
	slam.advance(0.1)
	var stamps := board.requests.count(&"stamp")
	board.requests.clear()
	screen._celebrate_round()
	var fanfare := _last()
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(asked and answered == &"pick", "sound: Dugi's question sounds when he asks, the answer picks", str(answered))
	expect.call(before_landing == 0 and stamps == 1, "sound: the stamp sounds once, when it lands (쾅)", "%d %d" % [before_landing, stamps])
	expect.call(fanfare == &"fanfare", "sound: the whole round's celebration plays the fanfare", str(fanfare))


## The map: a spot tap (spot), the cat's hops (hop, about HOP_HZ a second), the flag raise (flag, once).
func check_map() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _home()
	board.requests.clear()
	screen._walk_to_spot(0)
	var tapped := _last()
	var total: float = screen._walk_total
	var t0 := Time.get_ticks_msec()
	while screen._walking and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
	var hops := board.requests.count(&"hop")
	var expected := floori(total * float(load(HOME_SCREEN).HOP_HZ))
	await _free(screen)
	expect.call(tapped == &"spot" and absi(hops - expected) <= 1 and hops >= 1,
		"sound: a spot tap sounds, the cat's hops patter (one per hop)", "%s, %d hops for %.2f s" % [tapped, hops, total])
	ProgressStore.save({"projectile": 3})
	ProgressStore.mark_flag_pending("projectile")
	board.requests.clear()
	screen = await _home()
	t0 = Time.get_ticks_msec()
	while screen.raising() and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	var flags := board.requests.count(&"flag")
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(flags == 1, "sound: the map's flag raise sounds once", str(flags))


## The app: the first screen has no whoosh, a change of screen does; the music is the map's, quieter in a lab.
func check_app_swap() -> void:
	board.requests.clear()
	var app: Control = load(APP).new()
	tree.root.add_child(app)
	await tree.process_frame
	var first := board.requests.has(&"whoosh")
	var map_place := board.music_place
	board.requests.clear()
	app.show_experiment(ExperimentRegistry.find("free-fall"))
	await tree.process_frame
	var swapped := board.requests.has(&"whoosh")
	var lab_place := board.music_place
	app.show_list()
	await tree.process_frame
	var back_place := board.music_place
	app.queue_free()
	for i in 3:
		await tree.process_frame
	expect.call(not first and swapped, "sound: a change of screen whooshes (not the first screen)", "%s %s" % [str(first), str(swapped)])
	expect.call(map_place == &"map" and lab_place == &"lab" and back_place == &"map" and board.music_playing()
		and SoundBoard.MUSIC_DB[&"lab"] < SoundBoard.MUSIC_DB[&"map"],
		"sound: the music plays on the map and, quieter, in a lab", "%s %s %s" % [map_place, lab_place, back_place])


## 효과음 / 배경 음악: each switch mutes only its own bus, is kept in [sound] of the settings file
## (its other keys kept), reads back; both on by default.
func check_switches() -> void:
	DirAccess.remove_absolute(SoundBoard.path)
	board.load_settings()
	var defaults := board.sfx_on and board.music_on
	var keep := ConfigFile.new()
	keep.set_value("ui", "show_fps", true)
	keep.save(SoundBoard.path)
	var host := _host()
	var screen: Control = load(SETTINGS_SCREEN).new()
	host.add_child(screen)
	await tree.process_frame
	var shown_on: bool = screen.sfx_switch.button_pressed and screen.music_switch.button_pressed
	var sfx_bus := AudioServer.get_bus_index(SoundBoard.SFX_BUS)
	var music_bus := AudioServer.get_bus_index(SoundBoard.MUSIC_BUS)
	screen.sfx_switch.button_pressed = false   # as a tap: emits toggled
	var played := board.played
	SoundBoard.play(&"land")
	var sfx_off: bool = AudioServer.is_bus_mute(sfx_bus) and not AudioServer.is_bus_mute(music_bus) \
		and not AudioServer.is_bus_mute(0) and board.played == played
	screen.music_switch.button_pressed = false
	var music_off: bool = AudioServer.is_bus_mute(music_bus) and not board.music_playing() and not AudioServer.is_bus_mute(0)
	var config := ConfigFile.new()
	config.load(SoundBoard.path)
	var stored: bool = config.get_value("sound", "sfx", true) == false and config.get_value("sound", "music", true) == false \
		and config.get_value("ui", "show_fps", false) == true
	board.sfx_on = true
	board.music_on = true
	board.load_settings()
	var read_back := not board.sfx_on and not board.music_on
	host.queue_free()
	await tree.process_frame
	host = _host()
	screen = load(SETTINGS_SCREEN).new()
	host.add_child(screen)
	await tree.process_frame
	var shown_off: bool = not screen.sfx_switch.button_pressed and not screen.music_switch.button_pressed
	screen.sfx_switch.button_pressed = true
	screen.music_switch.button_pressed = true
	var back_on: bool = not AudioServer.is_bus_mute(sfx_bus) and not AudioServer.is_bus_mute(music_bus) and board.music_playing()
	host.queue_free()
	await tree.process_frame
	expect.call(defaults and shown_on, "sound: 효과음 and 배경 음악 are on by default (settings screen shows it)", "")
	expect.call(sfx_off, "sound: 효과음 off mutes the SFX bus only and plays nothing", "")
	expect.call(music_off, "sound: 배경 음악 off mutes the Music bus only and stops the loop", "")
	expect.call(stored and read_back and shown_off, "sound: both switches are kept in [sound] of the settings file (other keys kept) and read back", "")
	expect.call(back_on, "sound: switched on again, both buses play", "")


## A measurement: nothing plays (effects or music), the switches write nothing.
func check_silent_run() -> void:
	DirAccess.remove_absolute(SoundBoard.path)
	board.load_settings()
	var before := _file_state(SoundBoard.path)
	board.silent = true
	board.load_settings()
	var played := board.played
	var screen := await _lab("free-fall")
	screen.experiment_action("release")
	for i in 180:
		await tree.process_frame
	SoundBoard.play(&"tap")
	board.set_sfx_on(false)
	board.set_music_on(true)
	var music := board.music_playing()
	await _free(screen)
	var after := _file_state(SoundBoard.path)
	board.silent = false
	board.load_settings()
	expect.call(board.played == played and not music and before == after,
		"sound: a measurement run plays nothing (no effect, no music) and writes no setting", "played %d -> %d, music %s" % [played, board.played, str(music)])


## Idle (the map, a lab before anything happens): nothing sounds frame after frame.
func check_idle() -> void:
	var screen := await _home()
	board.requests.clear()
	for i in 120:
		await tree.process_frame
	var map_idle := board.requests.size()
	await _free(screen)
	screen = await _lab("spring")
	for i in 10:
		await tree.process_frame
	board.requests.clear()
	for i in 120:
		await tree.physics_frame
		await tree.process_frame
	var lab_idle := board.requests.size()
	await _free(screen)
	expect.call(map_idle == 0 and lab_idle == 0, "sound: nothing sounds while the map or a lab is idle (2 s)", "%d %d" % [map_idle, lab_idle])


## A small pool: many sounds at once use at most POOL players; the same sound twice at once is one.
func check_pool() -> void:
	var played := board.played
	SoundBoard.play(&"tap")
	SoundBoard.play(&"tap")
	var once := board.played - played
	for id in SoundBoard.SFX:
		SoundBoard.play(id)
	var players := board.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer and n.bus == SoundBoard.SFX_BUS)
	expect.call(once == 1 and players.size() == SoundBoard.POOL, "sound: the same sound asked twice at once plays once; %d effect players" % SoundBoard.POOL,
		"%d, %d players" % [once, players.size()])


# --- helpers ---------------------------------------------------------------------------------------

func _last() -> StringName:
	return board.requests[-1] if not board.requests.is_empty() else &""


func _bytes(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else 0


func _file_state(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return [false]
	return [true, FileAccess.get_modified_time(path), FileAccess.get_file_as_string(path)]


func _stand_in(id: String) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Experiment\nvar s := \"ready\"\nvar splashes := 0\nvar hit_reactions := 0\n" \
		+ "func status() -> String:\n\treturn s\n"
	script.reload()
	var lab: Experiment = script.new()
	lab.definition = {"id": id}
	return lab


func _host() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = SIZE
	tree.root.add_child(host)
	return host


func _lab(id: String) -> Control:
	var host := _host()
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _home() -> Control:
	var host := _host()
	var screen: Control = load(HOME_SCREEN).new()
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame
