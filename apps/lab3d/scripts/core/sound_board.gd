## The app's sound (2026-10-28, autoload "Sound"): short effects and one background music loop.
## Every sound is a CC0 file under res://audio (sources and licenses: audio/CREDITS.md).
##
## Callers only name an event: SoundBoard.play(&"tap"). The board picks the file, its volume and a
## free player from a small pool (POOL players, the oldest is cut when all are busy), and drops the
## same sound asked again within MIN_GAP_S (a burst of the same event is one sound). Sounds only
## listen: nothing here reads or changes a body, a formula value or a displayed number.
##
## Buses: Master <- SFX (effects) and Master <- Music. The settings screen's 효과음 / 배경 음악 switches
## mute one bus each and are kept in user://settings.cfg, section [sound] (sfx, music; both on by
## default). The music is the same loop everywhere, quieter in a lab (MUSIC_DB) so the lab's own
## sounds and a classroom stay calm.
##
## Silent runs: a device measurement (--auto-drag / --auto-release / --demo-celebrate, or
## --sound=0, which tools/bench_device.sh always passes) plays nothing and never writes the
## settings; --sound=1 turns a measurement's sound back on. Headless runs use Godot's dummy audio
## driver (no device needed).
class_name SoundBoard
extends Node

## Event id -> [file under SFX_DIR, volume dB]. The file names are the packs' own (CREDITS.md).
const SFX := {
	&"tap": ["drop_002.ogg", -8.0],                   # a button
	&"pick": ["select_002.ogg", -6.0],                # a picture button: a condition, Dugi's answer
	&"whoosh": ["card-slide-1.ogg", -6.0],            # the screen changes (soft)
	&"spot": ["confirmation_001.ogg", -10.0],         # a spot on the map is tapped
	&"hop": ["impactSoft_medium_000.ogg", -16.0],     # each hop of the bread cat on the map
	&"launch": ["phaseJump1.ogg", -10.0],             # a ball is let go, thrown, shot, pushed off
	&"land": ["impactSoft_heavy_000.ogg", -6.0],      # something lands / hits the ground
	&"bump": ["impactGeneric_light_000.ogg", -4.0],   # the two balls hit each other
	&"stop": ["impactWood_light_002.ogg", -6.0],      # the box stops / reaches the end, the load at the top
	&"splash": ["drop_003.ogg", -4.0],                # the drum drops into the water
	&"spring": ["pepSound1.ogg", -12.0],              # the spring ball is let go (boing)
	&"stamp": ["impactWood_heavy_000.ogg", -2.0],     # 도장 쾅
	&"fanfare": ["jingles_STEEL02.ogg", -4.0],        # the whole round is done (with the confetti; 2026-10-29 user pick)
	&"flag": ["jingles_PIZZI10.ogg", -4.0],           # the map's flag is raised
	&"question": ["question_002.ogg", -14.0],         # Dugi asks
	&"star_break": ["impactGlass_light_000.ogg", -8.0],   # the story: the guiding star cracks (soft glass)
	&"glint": ["glass_002.ogg", -10.0],               # the story: a star piece appears / lands / arrives
	&"piece_fly": ["maximize_004.ogg", -12.0],        # the story: a piece flies to the lookout, the star rises
	&"finale": ["jingles_STEEL00.ogg", -6.0],         # the story: the star is back in the sky
}
const SFX_DIR := "res://audio/sfx/"
const MUSIC_PATH := "res://audio/music/childrens_march.ogg"
## Music volume per place (dB on the music player; the Music bus stays at 0 dB).
const MUSIC_DB := {&"map": -10.0, &"lab": -19.0}
const MUSIC_FADE_S := 0.6
const POOL := 6
const MIN_GAP_S := 0.08
const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const SECTION := "sound"
## The file in use: the app's settings (App.SETTINGS_PATH); tests point it at TEST_PATH.
const PATH := "user://settings.cfg"
const TEST_PATH := "user://settings-test.cfg"
const QualityScript := preload("res://scripts/core/quality.gd")
const LOG_SIZE := 64

static var path := PATH
static var _instance: SoundBoard

var sfx_on := true
var music_on := true
## A measurement or --sound=0: nothing plays and the settings are never written.
var silent := false
## The last LOG_SIZE events asked for (tests), played or not.
var requests: Array[StringName] = []
## Effects actually started (tests: a silent run starts none).
var played := 0
var music_place: StringName = &""
var _streams: Dictionary = {}       # id -> AudioStream
var _last_ms: Dictionary = {}       # id -> Time.get_ticks_msec() of its last start
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_tween: Tween


## The board of the running app (null in a script without the autoload).
static func instance() -> SoundBoard:
	return _instance if _instance != null and is_instance_valid(_instance) else null


## Plays the event `id` (no-op without the board, when effects are off or the run is silent).
static func play(id: StringName) -> void:
	var board := instance()
	if board != null:
		board.play_event(id)


## The music for a place (&"map", &"lab"; anything else keeps the current volume).
static func music_for(place: StringName) -> void:
	var board := instance()
	if board != null:
		board.set_music_place(place)


func _ready() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	silent = is_silent_run(QualityScript.all_args())
	_ensure_bus(SFX_BUS)
	_ensure_bus(MUSIC_BUS)
	for id in SFX:
		_streams[id] = load(SFX_DIR + SFX[id][0])
	for i in POOL:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = MUSIC_BUS
	_music.stream = load(MUSIC_PATH)   # loops: loop=true in its .import file (tests/sound_checks.gd)
	_music.volume_db = MUSIC_DB[&"map"]
	add_child(_music)
	load_settings()


## Stops every sound and the music (the mixer lets their playbacks go on its next pass; a test run
## calls it a few frames before quitting so no stream is still in use at exit).
func stop_all() -> void:
	music_place = &""
	for player in _players:
		player.stop()
	if _music != null:
		_music.stop()


func _exit_tree() -> void:
	stop_all()
	if _instance == self:
		_instance = null


## True for a measurement: --sound=0, or --auto-drag / --auto-release / --demo-celebrate without --sound=1.
static func is_silent_run(args: PackedStringArray) -> bool:
	var sound := ""
	var measuring := false
	for arg in args:
		if arg.begins_with("--sound="):
			sound = arg.trim_prefix("--sound=")
		elif arg.begins_with("--auto-drag=") or arg.begins_with("--auto-release=") or arg.begins_with("--demo-celebrate="):
			measuring = true
	if sound != "":
		return sound == "0"
	return measuring


static func _ensure_bus(bus: StringName) -> int:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")
	return index


## Reads [sound] from the settings file (missing = on) and applies it.
func load_settings() -> void:
	var config := ConfigFile.new()
	config.load(path)
	sfx_on = bool(config.get_value(SECTION, "sfx", true))
	music_on = bool(config.get_value(SECTION, "music", true))
	_apply()


func set_sfx_on(on: bool) -> void:
	sfx_on = on
	_apply()
	_save()


func set_music_on(on: bool) -> void:
	music_on = on
	_apply()
	_save()


func _save() -> void:
	if silent:
		return
	var config := ConfigFile.new()
	config.load(path)   # keeps the file's other sections (ui/show_fps)
	config.set_value(SECTION, "sfx", sfx_on)
	config.set_value(SECTION, "music", music_on)
	config.save(path)


func _apply() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(SFX_BUS), not sfx_on or silent)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MUSIC_BUS), not music_on or silent)
	_update_music()


func play_event(id: StringName) -> void:
	requests.append(id)
	if requests.size() > LOG_SIZE:
		requests.remove_at(0)
	if silent or not sfx_on or not _streams.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(id, -100000)) < int(MIN_GAP_S * 1000.0):
		return
	_last_ms[id] = now
	var player := _free_player()
	player.stream = _streams[id]
	player.volume_db = SFX[id][1]
	player.play()
	played += 1


## A player that is not playing, else the one started longest ago (round robin).
func _free_player() -> AudioStreamPlayer:
	for i in POOL:
		var player := _players[(_next + i) % POOL]
		if not player.playing:
			_next = (_next + i + 1) % POOL
			return player
	var oldest := _players[_next]
	_next = (_next + 1) % POOL
	return oldest


func set_music_place(place: StringName) -> void:
	if MUSIC_DB.has(place):
		music_place = place
	_update_music()


## Plays the loop at the place's volume (fades between places), or stops it.
func _update_music() -> void:
	if _music == null:
		return
	var wanted := music_on and not silent and music_place != &""
	if not wanted:
		if _music.playing:
			_music.stop()
		return
	var target: float = MUSIC_DB[music_place]
	if not _music.playing:
		_music.volume_db = target
		_music.play()
		return
	if is_equal_approx(_music.volume_db, target):
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", target, MUSIC_FADE_S)


func music_playing() -> bool:
	return _music != null and _music.playing


func music_stream() -> AudioStream:
	return _music.stream if _music != null else null


func music_volume_target() -> float:
	return MUSIC_DB.get(music_place, _music.volume_db)
