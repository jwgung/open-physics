## App root: theme, screen navigation (list -> experiment, settings) and the fps overlay.
## Launch args (command line or Android `opargs`, see Quality.all_args):
##   --experiment=<id>   open that experiment directly (measurements, screenshots)
##   --screen=settings   open the settings screen
##   --fps=1             show the fps overlay
##   --orientation=landscape|portrait   lock the screen orientation (screenshots; default: sensor)
## plus the experiment screen's --camera / --ctl-<id> / --auto-release.
class_name App
extends Control

const RESUME_PATH := "user://resume.txt"   # written before a renderer restart from settings
const SETTINGS_PATH := "user://settings.cfg"

var _definitions: Array[Dictionary] = []
var _screen: Control
var _return_to: Dictionary = {}           # experiment to return to from settings ({} = list)
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
	match Quality.cmdline_value("orientation"):
		"landscape":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
		"portrait":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)

	var resume := ""
	if FileAccess.file_exists(RESUME_PATH):
		resume = FileAccess.get_file_as_string(RESUME_PATH).strip_edges()
		DirAccess.remove_absolute(RESUME_PATH)
	var requested := Quality.cmdline_value("experiment")
	if resume == "settings" or Quality.cmdline_value("screen") == "settings":
		show_settings()
	elif requested != "" and not _find(requested).is_empty():
		show_experiment(_find(requested))
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
	var screen := ListScreen.new()
	screen.definitions = _definitions
	screen.experiment_chosen.connect(show_experiment)
	screen.settings_requested.connect(func() -> void:
		_return_to = {}
		show_settings())
	_swap(screen, "list")


func show_experiment(definition: Dictionary) -> void:
	var screen := ExperimentScreen.new()
	screen.setup(definition)
	screen.back_requested.connect(show_list)
	screen.settings_requested.connect(func() -> void:
		_return_to = definition
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
	else:
		show_experiment(_return_to)


func _swap(screen: Control, bench_scene: String) -> void:
	if _screen:
		remove_child(_screen)
		_screen.queue_free()
	_screen = screen
	add_child(screen)
	if bench_scene != "":
		Bench.reset(bench_scene)


func _find(id: String) -> Dictionary:
	for definition in _definitions:
		if definition.id == id:
			return definition
	return {}


func _on_quality_changed() -> void:
	# Same-renderer tier change: rebuild the current screen so lights and the 3D view re-read it.
	if _screen is ExperimentScreen:
		show_experiment((_screen as ExperimentScreen).definition)


func _set_fps(on: bool) -> void:
	_show_fps = on
	_fps_label.visible = on


func _on_bench_report(line: String, fps: float) -> void:
	if not _show_fps:
		return
	var data: Dictionary = JSON.parse_string(line)
	_fps_label.text = "%s %s  %.1f fps  p95 %.1f ms" % [data.scene, Quality.label(), fps, data.p95ms]
