## Render quality tiers (autoload "Quality"). One place decides renderer, resolution, AA, shadows
## and environment cost for every scene; scenes ask it when they build lights / environments.
## Tier comes from `--quality=<tier>` (command line, or on Android the launch intent extra
## `opargs`, see _all_args), else user://quality.txt, else DEFAULT_TIER. Single fields can be
## overridden for measurements with `--q-<field>=<value>` (not persisted), e.g. `--q-msaa=0`.
## Rationale and SM-P200 numbers: spikes/bench/results/phase1-task1/README.md.
extends Node

signal changed

const TIER_ORDER := ["low", "medium", "high"]
const DEFAULT_TIER := "high"
const SAVE_PATH := "user://quality.txt"
## Loaded at startup through application/config/project_settings_override (project.godot).
const RENDERER_OVERRIDE_PATH := "user://renderer_override.cfg"
const RESTART_MARKER_PATH := "user://renderer_restart.txt"
const RESTART_MARKER_TTL_S := 60  # an older marker is left over from a killed restart
const RENDERERS := ["mobile", "gl_compatibility"]
const BASE_SIZE := Vector2i(720, 1280)  # project.godot window/size/viewport_*

## renderer: "mobile" (Vulkan) or "gl_compatibility" (OpenGL ES 3); applied by restarting the app.
## render_width: width of the whole root viewport (2D + 3D) in px, upscaled to the screen;
## 0 = native resolution with canvas_items stretch (Phase 0). msaa: 0 or 2 (x).
## shadow_splits: 0 = shadows off, 1 = orthogonal, 2/4 = parallel splits (a scene never goes above
## its Phase 0 mode). shadow_size: directional shadow atlas (px). sky: S2 procedural sky + sky
## ambient/reflections, otherwise flat color. glow: S1 bloom.
const TIERS := {
	"low": {"renderer": "gl_compatibility", "render_width": 540, "msaa": 0, "shadow_splits": 0, "shadow_size": 1024, "sky": false, "glow": false},
	"medium": {"renderer": "mobile", "render_width": 720, "msaa": 2, "shadow_splits": 1, "shadow_size": 1024, "sky": false, "glow": true},
	"high": {"renderer": "mobile", "render_width": 0, "msaa": 2, "shadow_splits": 4, "shadow_size": 2048, "sky": true, "glow": true},
}

var tier := DEFAULT_TIER
var _overrides: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var requested := cmdline_value("quality")
	# After a renderer restart the launch args are still there; the saved tier (picked in the app) wins.
	if TIERS.has(requested) and not _restart_pending():
		tier = requested
		_save_tier()
	elif FileAccess.file_exists(SAVE_PATH):
		var saved := FileAccess.get_file_as_string(SAVE_PATH).strip_edges()
		if TIERS.has(saved):
			tier = saved
	for arg in _all_args():
		if arg.begins_with("--q-") and "=" in arg:
			var key := arg.trim_prefix("--q-").get_slice("=", 0)
			if TIERS[DEFAULT_TIER].has(key):
				var text := arg.get_slice("=", 1)
				if typeof(TIERS[DEFAULT_TIER][key]) == TYPE_INT and not text.is_valid_int():
					push_warning("Quality: ignoring %s (not an integer)" % arg)
					continue
				if key == "renderer" and text not in RENDERERS:
					push_warning("Quality: ignoring %s (unknown renderer)" % arg)
					continue
				_overrides[key] = _parse_like(TIERS[DEFAULT_TIER][key], text)
	_apply_viewport()
	_ensure_renderer.call_deferred()


## Value of `--<key>=<value>` from the command line or Android intent ("" when absent).
static func cmdline_value(key: String) -> String:
	var prefix := "--%s=" % key
	for arg in _all_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


## Engine + user command-line args, plus on Android the launch intent's string extra "opargs"
## (comma-separated; the release template ignores Godot's own command_line_params extra):
## adb shell am start -n <pkg>/com.godot.game.GodotAppLauncher --es opargs "--scene=S2,--quality=low"
static func _all_args() -> PackedStringArray:
	if _args_cache != null:
		return _args_cache
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if Engine.has_singleton("AndroidRuntime"):
		var activity: Object = Engine.get_singleton("AndroidRuntime").getActivity()
		var intent: Object = activity.getIntent() if activity else null
		var extra = intent.getStringExtra("opargs") if intent else null
		if extra is String:
			args.append_array(extra.split(",", false))
	_args_cache = args
	return args


static var _args_cache = null


static func _restart_pending() -> bool:
	return FileAccess.file_exists(RESTART_MARKER_PATH) \
		and Time.get_unix_time_from_system() - FileAccess.get_modified_time(RESTART_MARKER_PATH) < RESTART_MARKER_TTL_S


static func _parse_like(default_value: Variant, text: String) -> Variant:
	match typeof(default_value):
		TYPE_BOOL:
			return text in ["1", "true", "on", "yes"]
		TYPE_INT:
			return int(text)
	return text


func get_value(key: String) -> Variant:
	return _overrides.get(key, TIERS[tier][key])


## Tier name plus any measurement overrides, e.g. "low" or "high+msaa=0".
func label() -> String:
	var text: String = tier
	for key in _overrides:
		text += "+%s=%s" % [key, _overrides[key]]
	return text


func set_tier(new_tier: String) -> void:
	if not TIERS.has(new_tier) or new_tier == tier:
		return
	tier = new_tier
	_save_tier()
	if _ensure_renderer():
		return
	_apply_viewport()
	changed.emit()


func next_tier() -> String:
	return TIER_ORDER[(TIER_ORDER.find(tier) + 1) % TIER_ORDER.size()]


func _save_tier() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(tier)


func _apply_viewport() -> void:
	var root := get_tree().root
	var width: int = get_value("render_width")
	if width > 0:
		# Whole root viewport at a lower size: post-processing and 2D also run at this size.
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(width, width * BASE_SIZE.y / BASE_SIZE.x)
	else:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_size = BASE_SIZE
	root.msaa_3d = Viewport.MSAA_2X if get_value("msaa") >= 2 else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(get_value("shadow_size"), true)


## The renderer is fixed at startup, so a tier with another renderer writes the override file
## and restarts the app once. Returns true when a restart was requested.
func _ensure_renderer() -> bool:
	var current := RenderingServer.get_current_rendering_method()
	var wanted: String = get_value("renderer")
	if OS.has_feature("web") or current not in ["mobile", "forward_plus", "gl_compatibility"]:
		return false  # Web is always Compatibility; headless runs use the dummy renderer.
	if wanted not in RENDERERS:
		return false  # `--q-renderer` comes from an intent; never write an unknown value to the override file.
	var file := FileAccess.open(RENDERER_OVERRIDE_PATH, FileAccess.WRITE)
	if file:
		file.store_string('[rendering]\n\nrenderer/rendering_method="%s"\nrenderer/rendering_method.mobile="%s"\n' % [wanted, wanted])
		file.close()
	if current == wanted:
		DirAccess.remove_absolute(RESTART_MARKER_PATH)
		return false
	if _restart_pending():
		push_warning("Quality: renderer %s requested but %s is running; not restarting again" % [wanted, current])
		DirAccess.remove_absolute(RESTART_MARKER_PATH)
		return false
	var marker := FileAccess.open(RESTART_MARKER_PATH, FileAccess.WRITE)
	if marker:
		marker.store_string(wanted)
	var restart_args := OS.get_cmdline_args()
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		restart_args.append("--")
		restart_args.append_array(user_args)
	OS.set_restart_on_exit(true, restart_args)
	get_tree().quit()
	return true


## Applies the tier's shadow setting; `phase0_mode` is the scene's Phase 0 (high tier) mode.
func configure_sun(sun: DirectionalLight3D, phase0_mode: DirectionalLight3D.ShadowMode) -> void:
	var splits: int = get_value("shadow_splits")
	sun.shadow_enabled = splits > 0
	var phase0_splits: int = {DirectionalLight3D.SHADOW_ORTHOGONAL: 1, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS: 2}.get(phase0_mode, 4)
	match mini(splits, phase0_splits):
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
