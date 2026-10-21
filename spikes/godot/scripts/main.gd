## Scene switcher + FPS overlay. Persists the last scene so app restarts (spec 5.2) resume it.
extends Node

const SCENES := {
	"S1": "res://scenes/s1_orbit.tscn",
	"S2": "res://scenes/s2_lab.tscn",
	"S3": "res://scenes/s3_incline.tscn",
}
const LAST_SCENE_PATH := "user://last_scene.txt"

@onready var _scene_root: Node = $SceneRoot
@onready var _fps_label: Label = $Hud/FpsLabel
@onready var _fps_toggle: Button = $Hud/TopBar/FpsToggle
var _current := ""


func _ready() -> void:
	for scene_id in SCENES:
		var button: Button = get_node("Hud/TopBar/%s" % scene_id)
		button.pressed.connect(switch_to.bind(scene_id))
	_fps_toggle.toggled.connect(func(on: bool) -> void: _fps_label.visible = on)
	Bench.report.connect(_on_bench_report)
	switch_to(_initial_scene())


func _initial_scene() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			return arg.trim_prefix("--scene=")
	if OS.has_feature("web"):
		var hash := str(JavaScriptBridge.eval("window.location.hash", true)).trim_prefix("#")
		if SCENES.has(hash):
			return hash  # index.html#S2 opens S2 directly
	if FileAccess.file_exists(LAST_SCENE_PATH):
		var saved := FileAccess.get_file_as_string(LAST_SCENE_PATH).strip_edges()
		if SCENES.has(saved):
			return saved
	return "S1"


func switch_to(scene_id: String) -> void:
	if not SCENES.has(scene_id):
		scene_id = "S1"
	for child in _scene_root.get_children():
		child.queue_free()
	_scene_root.add_child(load(SCENES[scene_id]).instantiate())
	_current = scene_id
	for id in SCENES:
		(get_node("Hud/TopBar/%s" % id) as Button).set_pressed_no_signal(id == scene_id)
	var file := FileAccess.open(LAST_SCENE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(scene_id)
	Bench.reset(scene_id)


func _on_bench_report(line: String, fps: float) -> void:
	var data: Dictionary = JSON.parse_string(line)
	_fps_label.text = "%s  %.1f fps  p95 %.1f ms  long %d" % [_current, fps, data.p95ms, data.long]
