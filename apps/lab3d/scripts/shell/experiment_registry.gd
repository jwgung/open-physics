## Loads experiment content from content/experiments/index.json and validates each definition
## against the shell's interface. Content is plain JSON so Task 4 can share it with the web app.
## index.json `experiments` are listed on the list screen; `hidden` ones (development scenes) are
## only opened by id (--experiment=<id>).
class_name ExperimentRegistry
extends RefCounted

const INDEX_PATH := "res://content/experiments/index.json"
const CAMERA_MODES := CameraRig.MODES
const REQUIRED_KEYS := ["id", "title", "category", "question", "steps", "observe", "law", "scene",
	"camera", "controls", "actions", "observations", "graph"]
const CONTROL_TYPES := ["slider", "choice"]


static var _cache: Array[Dictionary] = []
static var _hidden: Array[Dictionary] = []
static var _loaded := false


## All valid definitions in index order (read from disk once; treat as read-only). Invalid ones
## are skipped with an error.
static func load_all() -> Array[Dictionary]:
	if _loaded:
		return _cache
	var result: Array[Dictionary] = []
	var hidden: Array[Dictionary] = []
	_cache = result
	_hidden = hidden
	_loaded = true
	var index: Variant = _read_json(INDEX_PATH)
	if not index is Dictionary:
		push_error("ExperimentRegistry: cannot read %s" % INDEX_PATH)
		return result
	_load_files(index.get("experiments", []), result)
	_load_files(index.get("hidden", []), hidden)
	return result


## The loaded definition with this id, listed or hidden ({} if there is none).
static func find(id: String) -> Dictionary:
	load_all()
	for definition in _cache + _hidden:
		if definition.id == id:
			return definition
	return {}


static func _load_files(files: Array, into: Array[Dictionary]) -> void:
	for file_name in files:
		var path := INDEX_PATH.get_base_dir().path_join(str(file_name))
		var definition: Variant = _read_json(path)
		if not definition is Dictionary:
			push_error("ExperimentRegistry: cannot read %s" % path)
			continue
		var problems := validate(definition)
		if not problems.is_empty():
			push_error("ExperimentRegistry: %s is invalid: %s" % [path, "; ".join(problems)])
			continue
		into.append(definition)


## Returns a list of problems (empty = valid).
static func validate(definition: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	for key in REQUIRED_KEYS:
		if not definition.has(key):
			problems.append("missing %s" % key)
	if not problems.is_empty():
		return problems
	if not ResourceLoader.exists(definition.scene):
		problems.append("scene %s not found" % definition.scene)
	else:
		var script: Variant = load(definition.scene)
		if not script is GDScript or not _extends_experiment(script):
			problems.append("scene %s is not an Experiment script" % definition.scene)
	var camera: Dictionary = definition.camera
	for key in ["target", "distance", "distance_range", "yaw_range_deg", "pitch_range_deg", "default_mode", "views"]:
		if not camera.has(key):
			problems.append("camera.%s missing" % key)
	if camera.has("default_mode") and camera.default_mode not in CAMERA_MODES:
		problems.append("camera.default_mode %s unknown" % camera.default_mode)
	if camera.has("views"):
		for mode in _view_modes():
			if not camera.views.has(mode):
				problems.append("camera.views.%s missing" % mode)
	var ids := {}
	for control in definition.controls:
		if not control.has("id") or control.get("type") not in CONTROL_TYPES or not control.has("default"):
			problems.append("control %s needs id, type (slider|choice) and default" % control.get("id", "?"))
			continue
		if ids.has(control.id):
			problems.append("duplicate control id %s" % control.id)
		ids[control.id] = true
		if control.type == "slider":
			for key in ["min", "max", "step"]:
				if not control.has(key):
					problems.append("slider %s.%s missing" % [control.id, key])
		elif control.get("options", []).is_empty():
			problems.append("choice %s has no options" % control.id)
	for action in definition.actions:
		if not action.has("id") or not action.has("label"):
			problems.append("action needs id and label")
	for observation in definition.observations:
		if not observation.has("id") or not observation.has("label"):
			problems.append("observation needs id and label")
	var graph: Dictionary = definition.graph
	if not graph.has("series") or graph.series.is_empty():
		problems.append("graph.series missing")
	problems.append_array(_validate_manipulation(definition.get("manipulation"), definition.actions))
	return problems


## Optional `manipulation` (Task 2b): {"objects": [{"id", "surface", "snap" (m, optional),
## "height": false | {"max" (m, > 0, a multiple of step), "step" (m, optional)}}],
## "demo_action" (optional, an action id: what the --auto-drag demo does after putting an object down)}.
static func _validate_manipulation(manipulation: Variant, actions: Array = []) -> PackedStringArray:
	var problems := PackedStringArray()
	if manipulation == null:
		return problems
	if not manipulation is Dictionary or not manipulation.get("objects") is Array or manipulation.objects.is_empty():
		problems.append("manipulation.objects missing")
		return problems
	var ids := {}
	for object in manipulation.objects:
		if not object is Dictionary or not object.get("id") is String or not object.get("surface") is String:
			problems.append("manipulation object needs id and surface")
			continue
		if ids.has(object.id):
			problems.append("duplicate manipulation object %s" % object.id)
		ids[object.id] = true
		var snap: Variant = object.get("snap", 0.0)
		if not (snap is float or snap is int) or snap < 0.0:
			problems.append("manipulation %s.snap must be a number >= 0" % object.id)
		var height: Variant = object.get("height", false)
		if height is Dictionary:
			var top: Variant = height.get("max")
			var step: Variant = height.get("step", 0.0)
			if not (top is float or top is int) or top <= 0.0 or not (step is float or step is int) or step < 0.0:
				problems.append("manipulation %s.height needs max > 0 and step >= 0" % object.id)
			elif step > 0.0 and absf(float(top) / float(step) - roundf(float(top) / float(step))) > 1e-6:
				problems.append("manipulation %s.height.max must be a multiple of step" % object.id)
		elif height != false:
			problems.append("manipulation %s.height must be false or {max, step}" % object.id)
	var demo: Variant = manipulation.get("demo_action", "")
	if not demo is String or (demo != "" and not actions.any(func(a: Dictionary) -> bool: return a.get("id") == demo)):
		problems.append("manipulation.demo_action must be the id of one of the actions")
	return problems


## Instantiates the experiment scene script with its definition (not yet in the tree).
static func instantiate(definition: Dictionary) -> Experiment:
	var script: Script = load(definition.scene)
	var experiment: Experiment = script.new()
	experiment.definition = definition
	return experiment


## Every preset mode needs a view in the definition; "orbit" is only reached by dragging.
static func _view_modes() -> Array:
	return CAMERA_MODES.filter(func(mode: String) -> bool: return mode != "orbit")


static func _extends_experiment(script: GDScript) -> bool:
	var current: Script = script
	while current != null:
		if current == Experiment:
			return true
		current = current.get_base_script()
	return false


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
