## Loads experiment content from content/experiments/index.json and validates each definition
## against the shell's interface. Content is plain JSON so Task 4 can share it with the web app.
class_name ExperimentRegistry
extends RefCounted

const INDEX_PATH := "res://content/experiments/index.json"
const CAMERA_MODES := CameraRig.MODES
const REQUIRED_KEYS := ["id", "title", "category", "question", "steps", "observe", "law", "scene",
	"camera", "controls", "actions", "observations", "graph"]
const CONTROL_TYPES := ["slider", "choice"]


static var _cache: Array[Dictionary] = []
static var _loaded := false


## All valid definitions in index order (read from disk once; treat as read-only). Invalid ones
## are skipped with an error. `reload` reads the content again.
static func load_all(reload := false) -> Array[Dictionary]:
	if _loaded and not reload:
		return _cache
	var result: Array[Dictionary] = []
	_cache = result
	_loaded = true
	var index: Variant = _read_json(INDEX_PATH)
	if not index is Dictionary:
		push_error("ExperimentRegistry: cannot read %s" % INDEX_PATH)
		return result
	for file_name in index.get("experiments", []):
		var path := INDEX_PATH.get_base_dir().path_join(str(file_name))
		var definition: Variant = _read_json(path)
		if not definition is Dictionary:
			push_error("ExperimentRegistry: cannot read %s" % path)
			continue
		var problems := validate(definition)
		if not problems.is_empty():
			push_error("ExperimentRegistry: %s is invalid: %s" % [path, "; ".join(problems)])
			continue
		result.append(definition)
	return result


## The loaded definition with this id ({} if there is none).
static func find(id: String) -> Dictionary:
	for definition in load_all():
		if definition.id == id:
			return definition
	return {}


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
	var camera: Dictionary = definition.camera
	for key in ["target", "distance", "distance_range", "yaw_range_deg", "pitch_range_deg", "default_mode", "views"]:
		if not camera.has(key):
			problems.append("camera.%s missing" % key)
	if camera.has("default_mode") and camera.default_mode not in CAMERA_MODES:
		problems.append("camera.default_mode %s unknown" % camera.default_mode)
	if camera.has("views"):
		for mode in ["front", "three_quarter", "top", "side", "follow"]:
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
	return problems


## Instantiates the experiment scene script with its definition (not yet in the tree).
static func instantiate(definition: Dictionary) -> Experiment:
	var script: Script = load(definition.scene)
	var experiment: Experiment = script.new()
	experiment.definition = definition
	return experiment


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
