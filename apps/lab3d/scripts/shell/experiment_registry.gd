## Loads experiment content from content/experiments/index.json and validates each definition
## against the shell's interface. index.json `experiments` are listed on the list screen; `hidden`
## ones (development scenes) are only opened by id (--experiment=<id>).
## Task 4a: the texts of the guided labs (title, question, steps, observe, terms, law, tip) live in
## one file shared with the web 2D app, content/mechanics-labs.json. An experiment file names its
## lab with `"content": "<lab id>"` and keeps only the 3D fields (scene, camera, controls, actions,
## observations, graph, manipulation); resolve() merges the two. A file without `content` (the
## development scene) writes its texts itself.
class_name ExperimentRegistry
extends RefCounted

const INDEX_PATH := "res://content/experiments/index.json"
const SHARED_CONTENT_PATH := "res://content/mechanics-labs.json"
## Text fields an experiment takes from its shared lab (content/mechanics-labs.json); `tip` comes
## from the lab's `app.tip` (the web has its own interaction tip). `app.steps` / `app.observe` replace
## the shared `steps` / `observe` for the 3D app when its motion differs from the web's (Task 4e).
const SHARED_KEYS := ["title", "category", "icon", "question", "steps", "observe", "terms", "law"]
const APP_OVERRIDES := ["steps", "observe"]
const CAMERA_MODES := CameraRig.MODES
const REQUIRED_KEYS := ["id", "title", "category", "question", "steps", "observe", "law", "scene",
	"camera", "controls", "actions", "observations", "key_observations", "graph"]
const CONTROL_TYPES := ["slider", "choice"]
## Key observations (Task 2d): the observation ids shown as small cards over the 3D view.
const KEY_OBSERVATIONS_MIN := 2
const KEY_OBSERVATIONS_MAX := 3


static var _cache: Array[Dictionary] = []
static var _hidden: Array[Dictionary] = []
static var _loaded := false
static var _shared: Dictionary = {}   # lab id -> shared lab content (labs + app_labs)
static var _shared_loaded := false    # read once, also when the file is missing (one error, then {})


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
		var raw: Variant = _read_json(path)
		if not raw is Dictionary:
			push_error("ExperimentRegistry: cannot read %s" % path)
			continue
		var resolved := resolve(raw)
		var definition: Dictionary = resolved[0]
		var problems: PackedStringArray = resolved[1]
		problems.append_array(validate(definition))
		if not problems.is_empty():
			push_error("ExperimentRegistry: %s is invalid: %s" % [path, "; ".join(problems)])
			continue
		into.append(definition)


## The shared lab content by lab id (content/mechanics-labs.json `labs` + `app_labs`; read once:
## an unreadable file is reported once and then stays {}).
static func shared_labs() -> Dictionary:
	if _shared_loaded:
		return _shared
	_shared_loaded = true
	var file: Variant = _read_json(SHARED_CONTENT_PATH)
	if not file is Dictionary:
		push_error("ExperimentRegistry: cannot read %s" % SHARED_CONTENT_PATH)
		return _shared
	for lab in file.get("labs", []) + file.get("app_labs", []):
		_shared[lab.id] = lab
	return _shared


## [definition, problems]: an experiment file with `content` gets the texts of that shared lab
## (SHARED_KEYS, and `tip` / `tip_short` from the lab's app.tip / app.tip_short); it must not write them itself. Files without
## `content` are returned as they are. A lab's `app.steps` (three texts) or `app.observe` replaces
## the shared text in the 3D app only; the web never reads `app`.
static func resolve(raw: Dictionary) -> Array:
	var problems := PackedStringArray()
	if not raw.has("content"):
		return [raw, problems]
	var lab: Dictionary = shared_labs().get(str(raw.content), {})
	if lab.is_empty():
		problems.append("content %s not in %s" % [raw.content, SHARED_CONTENT_PATH])
		return [raw, problems]
	var definition := raw.duplicate(true)
	for key in SHARED_KEYS + ["tip", "tip_short"]:
		if raw.has(key):
			problems.append("%s duplicates the shared content (%s)" % [key, raw.content])
	for key in SHARED_KEYS:
		if lab.has(key):
			definition[key] = lab[key].duplicate(true) if lab[key] is Dictionary or lab[key] is Array else lab[key]
	var app: Dictionary = lab.get("app", {})
	var tip: String = app.get("tip", "")
	if tip != "":
		definition["tip"] = tip
	var tip_short: String = app.get("tip_short", "")
	if tip_short != "":
		definition["tip_short"] = tip_short
	for key in APP_OVERRIDES:
		if not app.has(key):
			continue
		var text: Variant = app[key]
		if (key == "steps" and not (text is Array and text.size() == 3)) or (key == "observe" and not (text is String and text != "")):
			problems.append("app.%s of %s is not valid (steps: three texts, observe: a text)" % [key, raw.content])
		else:
			definition[key] = text.duplicate(true) if text is Array else text
	return [definition, problems]


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
			elif camera.views[mode].has("target") and not _is_vector3(camera.views[mode].target):
				problems.append("camera.views.%s.target must be [x, y, z]" % mode)
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
	problems.append_array(_validate_key_observations(definition.key_observations, definition.observations))
	var graph: Dictionary = definition.graph
	if not graph.has("series") or graph.series.is_empty():
		problems.append("graph.series missing")
	problems.append_array(_validate_manipulation(definition.get("manipulation"), definition.actions))
	return problems


## `key_observations`: 2-3 distinct ids of the definition's observations.
static func _validate_key_observations(keys: Variant, observations: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	if not keys is Array or keys.size() < KEY_OBSERVATIONS_MIN or keys.size() > KEY_OBSERVATIONS_MAX:
		problems.append("key_observations must list %d-%d observation ids" % [KEY_OBSERVATIONS_MIN, KEY_OBSERVATIONS_MAX])
		return problems
	var ids := observations.map(func(o: Dictionary) -> Variant: return o.get("id"))
	var seen := {}
	for key in keys:
		if not key is String or key not in ids:
			problems.append("key_observations: %s is not an observation id" % str(key))
		elif seen.has(key):
			problems.append("key_observations: duplicate %s" % key)
		seen[key] = true
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


static func _is_vector3(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(func(v: Variant) -> bool: return v is float or v is int)


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
