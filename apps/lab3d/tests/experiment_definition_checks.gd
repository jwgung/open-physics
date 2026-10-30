## ExperimentDefinition (scripts/shell/experiment_definition.gd): the definition's queries and their
## defaults through the module's own interface, on a small definition written here and on every
## real one (the rules match what the registry loaded).
extends RefCounted

var tree: SceneTree
var expect: Callable

const SAMPLE := {
	"id": "sample", "title": "샘플",
	"controls": [
		{"id": "speed", "type": "slider", "min": 1.0, "max": 9.0, "step": 0.5, "default": 6.0},
		{"id": "angle", "type": "slider", "min": 0.0, "max": 90.0, "step": 5.0, "default": 45.0},
		{"id": "open", "type": "slider", "default": 2.0},
		{"id": "material", "type": "choice", "default": "wood", "options": [{"id": "wood", "label": "나무"}, {"id": "ice", "label": "얼음"}]},
	],
	"observations": [{"id": "range", "label": "거리", "digits": 1}, {"id": "state", "label": "상태"}],
	"graph": {"x": {"max": 5.0}},
	"manipulation": {"objects": [{"id": "ball", "surface": "floor", "snap": 0.25, "height": {"max": 2.0, "step": 0.5}},
		{"id": "box", "drag": false, "hold": true}], "slingshot": {"object": "ball"}},
}


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_controls()
	check_observations_and_rules()
	check_wrapping()
	check_real_definitions()
	check_no_dictionary_calls()


func check_controls() -> void:
	var d := ExperimentDefinition.new(SAMPLE)
	expect.call(d.control("speed").get("max") == 9.0 and d.control("nope").is_empty()
		and d.default_value("material") == "wood" and d.default_value("nope") == null,
		"definition: a control by id, its default; an unknown control is empty / null", "")
	expect.call(d.option("material", "ice").get("label") == "얼음" and d.option("material", "glass").is_empty()
		and d.option("nope", "ice").is_empty(), "definition: a choice's option by id; unknown ones are empty", "")
	expect.call(d.clamp_value("speed", 12.0) == 9.0 and d.clamp_value("speed", 0.0) == 1.0 and d.clamp_value("open", 99.0) == 99.0
		and d.clamp_value("nope", -3.0) == -3.0 and is_nan(d.clamp_value("speed", NAN)) and is_nan(d.clamp_value("speed", INF)),
		"definition: a slider clamps to its declared bounds only; NaN / Inf are refused (NaN)", "")
	expect.call(d.on_grid("speed", 2.3) == 2.3 and d.on_grid("angle", 42.0) == 42.0,
		"definition: a value off the slider's grid stays as it is", str(d.on_grid("speed", 2.3)))
	expect.call(d.on_grid("speed", 6.4999999) == 6.5 and d.on_grid("angle", 44.99999) == 45.0 and d.on_grid("open", 1.2345) == 1.2345,
		"definition: a value on the slider's grid is put on it in 64 bit; a slider without a step keeps it", "")


func check_observations_and_rules() -> void:
	var d := ExperimentDefinition.new(SAMPLE)
	expect.call(d.observation("range").get("label") == "거리" and d.observation("nope").is_empty()
		and d.digits("range") == 1 and d.digits("state") == 2 and d.digits("nope") == 2
		and ExperimentDefinition.control_digits(d.control("speed")) == 1 and ExperimentDefinition.control_digits({"digits": 0}) == 0,
		"definition: an observation by id; digits default to 2 (a control's to 1)", "")
	var rules := d.manipulation_rules()
	expect.call(rules.ball == {"surface": "floor", "snap": 0.25, "height_max": 2.0, "height_step": 0.5, "drag": true, "hold": false}
		and rules.box == {"surface": "", "snap": 0.0, "height_max": 0.0, "height_step": 0.0, "drag": false, "hold": true},
		"definition: the manipulation rules with their defaults", str(rules))
	expect.call(d.grid_step("ball") == 0.25 and d.grid_step("box") == 0.0 and d.grid_step("nope") == 0.0
		and d.slingshot().get("object") == "ball" and d.has_manipulation(),
		"definition: an object's grid step (0 = none) and the slingshot", "")
	var bare := ExperimentDefinition.new({"id": "bare"})
	expect.call(bare.controls().is_empty() and bare.observations().is_empty() and bare.manipulation_rules().is_empty()
		and not bare.has_manipulation() and bare.graph_x_max() == 3.0 and d.graph_x_max() == 5.0 and bare.time_scale() == 1.0
		and bare.bench_id() == "bare" and bare.text("tip") == "" and bare.law().is_empty(),
		"definition: a definition without the optional blocks answers with the defaults", "")


func check_wrapping() -> void:
	var d := ExperimentDefinition.new(SAMPLE)
	expect.call(ExperimentDefinition.of(d) == d and ExperimentDefinition.of(SAMPLE).raw == SAMPLE,
		"definition: of() wraps a Dictionary and passes a definition through", "")
	var before := SAMPLE.duplicate(true)
	d.control("speed")
	d.manipulation_rules()
	d.clamp_value("speed", 99.0)
	expect.call(d.raw == before, "definition: the queries never change raw", "")


## Every loaded definition: each control's default is its own default, each observation is found,
## and every manipulation object has a rule.
func check_real_definitions() -> void:
	var problems := []
	for raw in ExperimentRegistry.load_all():
		var d := ExperimentDefinition.new(raw)
		for control in raw.controls:
			if d.default_value(control.id) != control.default:
				problems.append("%s.%s default" % [raw.id, control.id])
		for observation in raw.observations:
			if d.observation(observation.id) != observation:
				problems.append("%s.%s observation" % [raw.id, observation.id])
		var rules := d.manipulation_rules()
		for object in raw.get("manipulation", {}).get("objects", []):
			if not rules.has(object.id) or rules[object.id].snap != float(object.get("snap", 0.0)):
				problems.append("%s.%s rule" % [raw.id, object.id])
	expect.call(problems.is_empty(), "definition: every real definition's controls, observations and manipulation rules", str(problems))


## No script treats a definition as a Dictionary: `<x>.definition.get(` / `.has(` / `[` on an Experiment's
## or a screen's definition compiles (Object.get) and silently reads null. Block owners take `.raw`.
func check_no_dictionary_calls() -> void:
	var found := []
	var pattern := RegEx.create_from_string("\\bdefinition\\.(get|has)\\(|\\bdefinition\\[")
	for dir in ["res://scripts", "res://experiments"]:
		for path in _scripts(dir):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			if lines.has("var definition: Dictionary"):
				continue   # its own member is a Dictionary (MissionRound)
			for i in lines.size():
				var line := lines[i].strip_edges()
				if line.begins_with("#") or pattern.search(line) == null:
					continue
				if _dictionary_param(lines, i):
					continue
				found.append("%s:%d" % [path, i + 1])
	expect.call(found.is_empty(), "definition: no script calls get / has / [] on an ExperimentDefinition (use a query or raw)", str(found))


## In the enclosing function `definition` is a Dictionary: its parameter (a block owner's raw
## definition) or a local declared before this line.
static func _dictionary_param(lines: PackedStringArray, at: int) -> bool:
	for i in range(at, -1, -1):
		var line := lines[i]
		if line.begins_with("func ") or line.begins_with("static func "):
			return RegEx.create_from_string("[(, ]definition: Dictionary").search(line) != null
		var code := line.strip_edges()
		if (code.begins_with("var definition :=") and not code.contains("ExperimentDefinition")) or code.begins_with("var definition: Dictionary"):
			return true
	return false


static func _scripts(dir: String) -> Array:
	var out := []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	return out
