## App root: theme, screen navigation (list -> experiment, settings) and the fps overlay.
## Landscape only (Task 2d): project.godot locks the screen to sensor landscape on Android and iOS.
## Launch args (command line or Android `opargs`, see Quality.all_args):
##   --experiment=<id>   open that experiment directly (measurements, screenshots)
##   --screen=settings   open the settings screen
##   --fps=1             show the fps overlay
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
var _return_to: Dictionary = {}           # experiment to return to from settings ({} = list)
## The experiment screen is kept (out of the tree) while settings is open, so angle, material,
## release state and camera survive. A same-renderer quality change rebuilds its 3D view
## (Quality.changed): then only the conditions and camera are kept (_saved_state). A renderer
## restart ends the process and returns to the list.
var _held: ExperimentScreen
var _saved_state: Dictionary = {}
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
	Quality.changed.connect(_on_quality_changed)

	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	_set_fps(Quality.cmdline_value("fps") == "1" or bool(config.get_value("ui", "show_fps", false)))
	_definitions = ExperimentRegistry.load_all()

	var resume := ""
	if FileAccess.file_exists(RESUME_PATH):
		resume = FileAccess.get_file_as_string(RESUME_PATH).strip_edges()
		DirAccess.remove_absolute(RESUME_PATH)
	var requested := ExperimentRegistry.find(Quality.cmdline_value("experiment"))
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
		show_list()
	elif _screen is SettingsScreen:
		_leave_settings()
	else:
		get_tree().quit()


func show_list() -> void:
	_drop_held()
	var screen := ListScreen.new()
	screen.definitions = _definitions
	screen.experiment_chosen.connect(show_experiment)
	screen.settings_requested.connect(func() -> void:
		_return_to = {}
		show_settings())
	_swap(screen, "list")


func show_experiment(definition: Dictionary, state := {}, launch_args := false) -> void:
	_drop_held()
	var screen := ExperimentScreen.new()
	screen.setup(definition, state, launch_args)
	screen.back_requested.connect(show_list)
	screen.settings_requested.connect(func() -> void:
		_return_to = definition
		_held = screen
		show_settings())
	_swap(screen, "")  # the screen resets Bench with the experiment's bench id


func show_settings() -> void:
	var screen := SettingsScreen.new()
	screen.show_fps = _show_fps
	screen.back_requested.connect(_leave_settings)
	screen.fps_toggled.connect(func(on: bool) -> void:
		_set_fps(on)
		var config := ConfigFile.new()
		config.load(SETTINGS_PATH)
		config.set_value("ui", "show_fps", on)
		config.save(SETTINGS_PATH))
	_swap(screen, "settings")


func _leave_settings() -> void:
	if _return_to.is_empty():
		show_list()
	elif _held != null:
		var screen := _held
		_held = null
		_swap(screen, "")
		Bench.reset(screen.definition.get("bench_id", screen.definition.id))
	else:
		var state := _saved_state
		_saved_state = {}
		show_experiment(_return_to, state)


func _drop_held() -> void:
	if _held != null:
		_held.queue_free()
		_held = null
	_saved_state = {}


func _swap(screen: Control, bench_scene: String) -> void:
	if _screen:
		remove_child(_screen)
		if _screen != _held:
			_screen.queue_free()
	_screen = screen
	add_child(screen)
	_slide_in(screen)
	if bench_scene != "":
		Bench.reset(bench_scene)


func _slide_in(screen: Control) -> void:
	# A held screen comes back more than once: stop its previous slide so two tweens never fight.
	var old: Tween = screen.get_meta("slide_tween") if screen.has_meta("slide_tween") else null
	if old and old.is_valid():
		old.kill()
	screen.position.x = SLIDE_UNITS
	screen.modulate.a = 0.0
	var tween := screen.create_tween().set_parallel()
	screen.set_meta("slide_tween", tween)
	tween.tween_property(screen, "position:x", 0.0, SLIDE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(screen, "modulate:a", 1.0, SLIDE_S * 0.7)


func _on_quality_changed() -> void:
	# Same-renderer tier change: the held experiment screen is rebuilt on return so lights and the
	# 3D view re-read the tier; its conditions and camera carry over.
	if _held != null:
		_saved_state = _held.capture_state()
		_held.queue_free()
		_held = null


func _set_fps(on: bool) -> void:
	_show_fps = on
	_fps_label.visible = on


func _on_bench_report(_line: String, fps: float, scene: String, p95_ms: float) -> void:
	if not _show_fps:
		return
	_fps_label.text = "%s %s  %.1f fps  p95 %.1f ms" % [scene, Quality.label(), fps, p95_ms]
