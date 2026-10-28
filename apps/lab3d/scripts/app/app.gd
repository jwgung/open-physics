## App root: theme, screen navigation (island map -> experiment, settings from the map; back always
## returns to the map, back on the map quits) and the fps overlay.
## Landscape only (Task 2d): project.godot locks the screen to sensor landscape on Android and iOS.
## Launch args (command line or Android `opargs`, see Quality.all_args):
##   --experiment=<id>   open that experiment directly (measurements, screenshots)
##   --screen=settings   open the settings screen
##   --fps=1             show the fps overlay
##   --sound=0|1         0 = no sound and no sound setting written (SoundBoard; measurements default to 0)
##   --demo-story=<part> screenshots of the story in the bench store only (never the child's progress):
##                       prologue | clue:<id> | found:<id> | flight:<id> | finale | map (Story, _demo_story)
## plus the experiment screen's --camera / --ctl-<id> / --sidebar / --scroll-to / --auto-release / --auto-drag.
class_name App
extends Control

const RESUME_PATH := "user://resume.txt"   # written by settings right after Quality.set_tier() requested a renderer restart
const SETTINGS_PATH := "user://settings.cfg"
## Screen change (art direction): the new screen slides in from SLIDE_UNITS to the right and fades
## in over SLIDE_S. Only the screen's own position/modulate are tweened (no overlay layer).
const SLIDE_UNITS := 48.0
const SLIDE_S := 0.22

var _definitions: Array[Dictionary] = []
var _screen: Control
var _fps_label: Label
var _show_fps := false


func _ready() -> void:
	theme = UiTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The background is the clear color, not a full-screen rect: at native resolution one extra
	# full-screen layer costs SM-P200 the 60 fps budget (docs/ui-resolution.md).
	RenderingServer.set_default_clear_color(UiTheme.BACKGROUND)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	_fps_label = Ui.label("", "FpsLabel")
	_fps_label.theme = theme
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_fps_label)
	Bench.report.connect(_on_bench_report)

	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	_set_fps(Quality.cmdline_value("fps") == "1" or bool(config.get_value("ui", "show_fps", false)))
	_definitions = ExperimentRegistry.load_all()
	if Quality.cmdline_value("progress") == "bench":
		ProgressStore.path = ProgressStore.BENCH_PATH   # a measured map never raises the child's flags
	# The story plays in the child's app only: never in a measurement (bench store, auto runs, silent).
	Story.enabled = Story.app_may_enable and not Story.measurement_run(Quality.all_args())
	var demo := _demo_story(Quality.cmdline_value("demo-story"))

	var resume := ""
	if FileAccess.file_exists(RESUME_PATH):
		resume = FileAccess.get_file_as_string(RESUME_PATH).strip_edges()
		DirAccess.remove_absolute(RESUME_PATH)
	var requested := ExperimentRegistry.find(Quality.cmdline_value("experiment"))
	if demo.has("experiment"):
		requested = demo.experiment
	if resume == "settings" or Quality.cmdline_value("screen") == "settings":
		show_settings()
	elif not requested.is_empty():
		show_experiment(requested, {}, true)  # the launch args (--ctl-*, --camera) apply to this screen
	else:
		show_list()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _go_back() -> void:
	if _screen is ExperimentScreen:
		if not (_screen as ExperimentScreen).handle_back():   # an open sidebar closes first
			show_list()
	elif _screen is SettingsScreen:
		show_list()
	else:
		get_tree().quit()   # the map is the home


## The home is the 3D island (Plan G2): tap a spot, the cat hops over, the experiment opens. The
## story's prologue plays over it the first time (or again from the settings: `replay`).
func show_list(replay := false) -> void:
	var screen := IslandHomeScreen.new()
	screen.definitions = _definitions
	screen.play_prologue_on_open = Story.should_play_prologue(replay)
	screen.experiment_chosen.connect(show_experiment)
	screen.settings_requested.connect(show_settings)
	_swap(screen, "home")


func show_experiment(definition: Dictionary, state := {}, launch_args := false) -> void:
	var screen := ExperimentScreen.new()
	screen.setup(definition, state, launch_args)
	screen.back_requested.connect(show_list)
	_swap(screen, "")  # the screen resets Bench with the experiment's bench id


func show_settings() -> void:
	var screen := SettingsScreen.new()
	screen.show_fps = _show_fps
	screen.back_requested.connect(show_list)   # settings opens from the map (Plan G2) and goes back to it
	screen.story_requested.connect(func() -> void: show_list(true))   # 이야기 다시 보기
	screen.fps_toggled.connect(func(on: bool) -> void:
		_set_fps(on)
		var config := ConfigFile.new()
		config.load(SETTINGS_PATH)
		config.set_value("ui", "show_fps", on)
		config.save(SETTINGS_PATH))
	_swap(screen, "settings")


func _swap(screen: Control, bench_scene: String) -> void:
	if _screen:
		remove_child(_screen)
		_screen.queue_free()
		SoundBoard.play(&"whoosh")   # a change of screen (not the first one)
	# The music: the map's loop, quieter in a lab (SoundBoard.MUSIC_DB).
	SoundBoard.music_for(&"lab" if screen is ExperimentScreen else &"map")
	_screen = screen
	add_child(screen)
	_slide_in(screen)
	if bench_scene != "":
		Bench.reset(bench_scene)


func _slide_in(screen: Control) -> void:
	# A screen that comes back (re-added) stops its previous slide so two tweens never fight.
	var old: Tween = screen.get_meta("slide_tween") if screen.has_meta("slide_tween") else null
	if old and old.is_valid():
		old.kill()
	screen.position.x = SLIDE_UNITS
	screen.modulate.a = 0.0
	var tween := screen.create_tween().set_parallel()
	screen.set_meta("slide_tween", tween)
	tween.tween_property(screen, "position:x", 0.0, SLIDE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(screen, "modulate:a", 1.0, SLIDE_S * 0.7)


## --demo-story=<part> (screenshots): the story on, in the bench store set up for that part. Returns
## {"experiment": definition} when the part is a lab's ({} otherwise: the map).
##   prologue      the map plays the prologue (nothing found yet)
##   clue:<id>     the lab opens with Puppy's clue (its round not started)
##   found:<id>    the lab opens and its three stamps play (--demo-celebrate's way), then its piece
##   flight:<id>   the map: that spot just completed (its flag, then its piece's flight); 4 others found
##   finale        the map: the orbit spot just completed with the 10 others found: flag, flight, finale
##   map           the map with the story (5 pieces at the lookout), nothing playing: fps measurements
func _demo_story(value: String) -> Dictionary:
	if value == "":
		return {}
	ProgressStore.path = ProgressStore.BENCH_PATH
	Story.enabled = true
	var kind := value.get_slice(":", 0)
	var id := value.get_slice(":", 1) if ":" in value else ""
	var config := ConfigFile.new()   # a fresh bench store
	config.save(ProgressStore.path)
	if kind != "prologue":
		ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	var store := {}
	var full := func(spot: String) -> int:
		return MissionTracker.missions(ExperimentRegistry.find(spot)).get("stages", []).size()
	match kind:
		"clue", "found":
			if kind == "found":
				ProgressStore.set_mark(ProgressStore.CLUES, id, true)
			ProgressStore.save(store)
			var definition := ExperimentRegistry.find(id)
			return {"experiment": definition} if not definition.is_empty() else {}
		"flight", "map":
			for spot in Story.spots().slice(0, 5 if kind == "map" else 4):
				if spot != id:
					store[spot] = full.call(spot)
		"finale":
			id = "orbit"
			for spot in Story.spots():
				store[spot] = full.call(spot)
	if kind in ["flight", "finale"] and ExperimentRegistry.find(id).size() > 0:
		store[id] = full.call(id)
		ProgressStore.save(store)
		ProgressStore.mark_flag_pending(id)
		ProgressStore.set_mark(ProgressStore.PIECES, id, false)
	else:
		ProgressStore.save(store)
	return {}


func _set_fps(on: bool) -> void:
	_show_fps = on
	_fps_label.visible = on


func _on_bench_report(_line: String, fps: float, scene: String, p95_ms: float) -> void:
	if not _show_fps:
		return
	_fps_label.text = "%s %s  %.1f fps  p95 %.1f ms" % [scene, Quality.label(), fps, p95_ms]
