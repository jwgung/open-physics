## One experiment's definition (content/experiments/<id>.json, resolved and validated by
## ExperimentRegistry) read through named queries: the core schema an experiment and its screen
## share — the controls and their options, ranges and grids, the observations, the manipulation
## rules, the camera, the graph, the actions and the texts. Each query owns its defaults (a control
## without a step is off the grid, a slider bound the control does not declare stays open, an
## observation without digits has 2), so a caller never walks the JSON for them.
##
## A block with its own owner is read by that owner from `raw`: `missions` and `predict`
## (MissionRound), `kid` (ExperimentRegistry's kid texts, ConditionPicks), `story` (Story), `note`
## (ExperimentRegistry.note), `cast` (IslandCast). Read-only: the queries never change `raw`.
##
## Not a Dictionary: `definition.get("key")` compiles (Object.get reads a property) and returns null.
## Use a query, or `raw` for a block (tests/experiment_definition_checks.gd looks for such calls).
class_name ExperimentDefinition
extends RefCounted

## The definition as loaded (read-only; tests build their own and wrap it).
var raw: Dictionary


func _init(content: Dictionary = {}) -> void:
	raw = content


## `content` as a definition: a Dictionary is wrapped, a definition is returned as it is. Anything
## else is a caller's mistake: reported here (not later, where the empty definition is first read).
static func of(content: Variant) -> ExperimentDefinition:
	if content is ExperimentDefinition:
		return content
	if not content is Dictionary:
		push_error("ExperimentDefinition.of: a definition or a Dictionary, not %s" % type_string(typeof(content)))
		return ExperimentDefinition.new()
	return ExperimentDefinition.new(content)


## The experiment's id.
func id() -> String:
	return str(raw.get("id", ""))


## The id the measurements report (Bench): `bench_id`, else the id.
func bench_id() -> String:
	return str(raw.get("bench_id", id()))


## A text of the definition: "title", "category", "question", "observe", "tip", "tip_short", "icon"
## ("" when it has none).
func text(key: String) -> String:
	return str(raw.get(key, ""))


## The three steps of the experiment's explanation.
func steps() -> Array:
	return raw.get("steps", [])


## {"title", "description", "equation"} ({} when there is none).
func law() -> Dictionary:
	return raw.get("law", {}) if raw.get("law") is Dictionary else {}


## [{"name", "description"}, ...].
func terms() -> Array:
	return raw.get("terms", [])


## The camera block (CameraRig.configure).
func camera() -> Dictionary:
	return raw.get("camera", {})


## The graph block (GraphView.spec).
func graph() -> Dictionary:
	return raw.get("graph", {})


## The graph's time window (s): its x axis max, `fallback` when it names none.
func graph_x_max(fallback := 3.0) -> float:
	return float(graph().get("x", {}).get("max", fallback))


## The action buttons [{"id", "label", ...}].
func actions() -> Array:
	return raw.get("actions", [])


## The pace a run is shown at (Experiment.time_scale; 1 when the definition names none).
func time_scale() -> float:
	return float(raw.get("time_scale", 1.0))


# --- controls -----------------------------------------------------------------------------------

## The controls in their order [{"id", "type": "slider" | "choice", "default", ...}].
func controls() -> Array:
	return raw.get("controls", [])


## The control `id` ({} when there is none).
func control(control_id: String) -> Dictionary:
	for entry in controls():
		if entry.get("id") == control_id:
			return entry
	return {}


## The option `option_id` of the choice control `control_id` ({} when the control or the option
## does not exist).
func option(control_id: String, option_id: String) -> Dictionary:
	for entry in control(control_id).get("options", []):
		if entry.get("id") == option_id:
			return entry
	return {}


## The control's default value (null when there is no such control).
func default_value(control_id: String) -> Variant:
	var entry := control(control_id)
	return entry.get("default") if not entry.is_empty() else null


## `value` limited to the slider `control_id`'s min / max (a bound the control does not declare stays
## open; no such control: `value` as it is). A NaN or infinite `value` is refused: NaN comes back and
## the caller changes nothing, so a bad input leaves the run and the graph alone.
func clamp_value(control_id: String, value: float) -> float:
	if not is_finite(value):
		return NAN
	var entry := control(control_id)
	if entry.is_empty():
		return value
	return clampf(value, float(entry.get("min", -INF)), float(entry.get("max", INF)))


## `value` (a pull's value, a 32-bit Vector2 component) on the slider `control_id`'s grid in 64 bit:
## whole steps counted from 0 (0.1 m/s: 23 / 10.0 = 2.3, not 2.29999995). A value off the grid (a
## pull's finer grid than the slider's) or a control without a step stays as it is.
func on_grid(control_id: String, value: float) -> float:
	var step := float(control(control_id).get("step", 0.0))
	if step <= 0.0:
		return value
	if step >= 1.0:
		var whole := roundf(value / step) * step
		return whole if absf(whole - value) < 1e-4 else value
	var cells := roundf(1.0 / step)
	var snapped := roundi(value * cells) / cells
	return snapped if absf(snapped - value) < 1e-4 else value


# --- observations -------------------------------------------------------------------------------

## The observations in their order [{"id", "label", "unit"?, "digits"?}].
func observations() -> Array:
	return raw.get("observations", [])


## The observation `observation_id` ({} when there is none).
func observation(observation_id: String) -> Dictionary:
	for entry in observations():
		if entry.get("id") == observation_id:
			return entry
	return {}


## The decimals observation `observation_id` is shown with (2 when it names none).
func digits(observation_id: String) -> int:
	return observation_digits(observation(observation_id))


## The decimals an observation entry is shown with (2 when it names none).
static func observation_digits(entry: Dictionary) -> int:
	return int(entry.get("digits", 2))


## The decimals a slider control's value is shown with (1 when it names none).
static func control_digits(entry: Dictionary) -> int:
	return int(entry.get("digits", 1))


# --- manipulation -------------------------------------------------------------------------------

## The definition declares objects a finger may pick up (the screen makes a Manipulator).
func has_manipulation() -> bool:
	return raw.has("manipulation")


## The manipulation block as declared ({} when there is none).
func manipulation() -> Dictionary:
	return raw.get("manipulation", {})


## The manipulation rules: object id -> {"surface", "snap", "height_max", "height_step", "drag",
## "hold"} (the one reading of manipulation.objects: the Manipulator and the lab's grid both use it).
func manipulation_rules() -> Dictionary:
	var result := {}
	for object in manipulation().get("objects", []):
		var h: Variant = object.get("height", false)
		var height_rule: Dictionary = h if h is Dictionary else {}
		result[object.id] = {
			"surface": str(object.get("surface", "")),
			"snap": float(object.get("snap", 0.0)),
			"height_max": float(height_rule.get("max", 0.0)),
			"height_step": float(height_rule.get("step", 0.0)),
			"drag": object.get("drag", true) != false,
			"hold": object.get("hold", false) == true,
		}
	return result


## Grid step of the manipulation object `object_id` (m, or the lab's own unit; 0 = no grid): the one
## value its rule's `snap`, the lab's surface and its snapping all use.
func grid_step(object_id: String) -> float:
	return float(manipulation_rules().get(object_id, {}).get("snap", 0.0))


## The slingshot's declared pull (manipulation.slingshot; {} when there is none).
func slingshot() -> Dictionary:
	return manipulation().get("slingshot", {})
