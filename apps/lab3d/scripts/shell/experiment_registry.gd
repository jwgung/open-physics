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
	problems.append_array(_validate_cast(definition.get("cast")))
	problems.append_array(_validate_missions(definition.get("missions"), definition.observations, definition.controls))
	problems.append_array(_validate_series(definition.get("missions"), graph.get("series", [])))
	problems.append_array(_validate_predict(definition.get("predict")))
	problems.append_array(_validate_kid(definition.get("kid"), definition.observations.map(func(o: Dictionary) -> Variant: return o.get("id"))))
	problems.append_array(_validate_story(definition.get("story")))
	if definition.get("kid") is Dictionary:
		problems.append_array(_validate_kid_cards(definition))
		problems.append_array(ConditionPicks.validate(definition))
	return problems


## The game layer's words for a 7-year-old (`kid`, optional): short everyday sentences without the
## formula's names. Content shared with the web (content/mechanics-labs.json) keeps its own texts;
## the 3D experiment file puts the child-facing ones here and the screen shows them in place of the
## shared ones (the "자세히" sidebar keeps the shared texts and the formula labels):
##   "kid": {"title": <the title bar>, "place": <the map's spot name>, "say": <Dugi's dialogue>,
##           "tip": <the short gesture hint>, "card": <the one key observation shown as a card>,
##           "cards": {<observation id>: <its key card's caption>},
##           "states": {<a status text of the lab>: <its key card words>},
##           "minus": {<observation id>: <the word a negative value reads with: "눌려서", "왼쪽으로">},
##           "picks": {<control id>: [the mission's picture buttons, ConditionPicks]}}
## Every key is optional; a missing one falls back to the shared text (kid_text, card_label).
## The key cards over the 3D view show a number with one decimal and its unit in words (KID_UNITS:
## "1.3초", "초속 12.5미터"); a game lab's key observations have such a unit (an energy, an
## acceleration stays in "자세히"; a force reads "11.8뉴턴" only where it is the lab's goal: the push
## that started the box, 2026-10-28). States and minus words change the card's words only: the lab's
## text and the value (the sidebar's, full precision) stay the formula's (ExperimentScreen.card_text).
const KID_TEXTS := {"title": "title", "place": "title", "say": "observe", "tip": "tip_short"}
const KID_MAPS := ["cards", "states", "minus"]
## Observation unit -> [the words before the number, the words after it] on a key card.
const KID_UNITS := {"": ["", ""], "m": ["", "미터"], "s": ["", "초"], "m/s": ["초속 ", "미터"],
	"°": ["", "도"], "kg": ["", "킬로그램"], "바퀴": ["", "바퀴"], "줄": ["", "줄"], "배": ["", "배"],
	"N": ["", "뉴턴"]}


static func _validate_kid(kid: Variant, ids: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	if kid == null:
		return problems
	if not kid is Dictionary:
		problems.append("kid must be an object")
		return problems
	for key in kid:
		if key in KID_MAPS:
			var map: Variant = kid[key]
			var named: bool = key == "states" or (map is Dictionary and map.keys().all(func(id: Variant) -> bool: return id in ids))
			if not (map is Dictionary and named and map.values().all(func(t: Variant) -> bool: return t is String and t != "")):
				problems.append("kid.%s must name %s with a text each" % [key, "status texts" if key == "states" else "observations"])
		elif key == "card":
			if not kid.card in ids:
				problems.append("kid.card must name an observation")
		elif key == "picks":
			pass   # ConditionPicks.validate (it needs the controls and the missions)
		elif not KID_TEXTS.has(key):
			problems.append("kid.%s unknown (title, place, say, tip, card, cards, states, minus, picks)" % key)
		elif not (kid[key] is String and kid[key] != ""):
			problems.append("kid.%s must be a text" % key)
	return problems


## The story's words for this lab (`story`, optional, 2026-10-28 "별 조각 찾기"): {"clue": <Puppy's
## clue, told once on the first visit before Dugi's question>, "map_clue": <Puppy's riddle on the
## night map while this spot is the next to find>} (Story.clue, Story.map_clue).
static func _validate_story(story: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if story == null:
		return problems
	if not story is Dictionary:
		problems.append("story must be an object")
		return problems
	for key in story:
		if not key in ["clue", "map_clue"]:
			problems.append("story.%s unknown (clue, map_clue)" % key)
		elif not (story[key] is String and story[key] != ""):
			problems.append("story.%s must be a text" % key)
	return problems


## A game lab's key cards (it has `kid`): every key observation's unit has its words (KID_UNITS).
static func _validate_kid_cards(definition: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	for observation in definition.observations:
		if observation.get("id") in definition.key_observations and not KID_UNITS.has(str(observation.get("unit", ""))):
			problems.append("key_observations: %s (%s) has no kid unit words; keep it in the sidebar" % [observation.id, observation.unit])
	var kid: Dictionary = definition.kid if definition.get("kid") is Dictionary else {}
	if kid.has("card") and not kid.card in definition.key_observations:
		problems.append("kid.card %s is not one of key_observations" % str(kid.card))
	return problems


## The child-facing text `key` of the game layer (KID_TEXTS): the definition's kid text, or the
## shared one it replaces (the tip falls back to the long tip, the place to the title).
static func kid_text(definition: Dictionary, key: String) -> String:
	var kid: Variant = definition.get("kid")
	if kid is Dictionary and kid.get(key) is String and kid[key] != "":
		return kid[key]
	var shared := str(definition.get(KID_TEXTS.get(key, key), ""))
	if key == "tip" and shared == "":
		shared = str(definition.get("tip", ""))
	return shared


## The key observations shown as cards over the 3D view: the game lab's one card (`kid.card`, one
## number for a child; the rest stay in "자세히", 2026-10-27), else all of key_observations.
static func shown_cards(definition: Dictionary) -> Array:
	var kid: Variant = definition.get("kid")
	if kid is Dictionary and kid.get("card") is String:
		return [kid.card]
	return definition.get("key_observations", [])


## The caption of a key observation's card over the 3D view: the kid wording, or the observation's
## label (the sidebar always shows the label).
static func card_label(definition: Dictionary, id: String) -> String:
	var kid: Variant = definition.get("kid")
	if kid is Dictionary and kid.get("cards") is Dictionary and kid.cards.get(id) is String:
		return kid.cards[id]
	for observation in definition.get("observations", []):
		if observation.get("id") == id:
			return str(observation.get("label", ""))
	return ""


## `missions.hidden_series_until_end` (optional): graph series ids drawn only once the run has its
## result (the formula's answer as a line: the projectile's y(t), the friction limit).
static func _validate_series(missions: Variant, series: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	if not missions is Dictionary or not missions.has("hidden_series_until_end"):
		return problems
	var ids := series.map(func(s: Dictionary) -> Variant: return s.get("id"))
	var hidden: Variant = missions.hidden_series_until_end
	if not (hidden is Array and hidden.all(func(id: Variant) -> bool: return id is String and id in ids)):
		problems.append("missions.hidden_series_until_end must list graph series ids")
	return problems


## `missions` (Plan G1, G2, optional): the stages and how a run is judged (MissionTracker's header) —
## {"stages": [{"text": <non-empty>, "threshold"?: <number > 0>, "conditions"?: {...},
##              "change"?: [<control id>, ...], "observe"?: <an observation id> | "",
##              "compare"?: ..., "judge_on"?: [...]}, ...],
##  "observe"?: <an observation id>, "compare"?: "greater" | "less",
##  "judge_on"?: [<status>, ...], "reveal_on"?: [<status>, ...],
##  "hidden_until_end"?: [<observation id>, ...], "hidden_series_until_end"?: [<graph series id>, ...]}.
## With `observe` every stage has its threshold; without it a stage is a state goal (no threshold).
## A stage's own observe / compare / judge_on replace the block's for that stage ("": no observe).
## A stage's `conditions` name the definition's controls: a choice wants one of its option ids, a
## slider a number or a {"min"?, "max"?} range inside its min..max. The tracker only reads (it never
## changes the run). The hidden_until_end values (the formula's answer) read "?" and the
## hidden_series_until_end lines are not drawn until the run has its result, so the round is not
## given away.
static func _validate_missions(missions: Variant, observations: Array, controls: Array = []) -> PackedStringArray:
	var problems := PackedStringArray()
	if missions == null:
		return problems
	if not missions is Dictionary:
		problems.append("missions must be an object")
		return problems
	var ids := {}
	for observation in observations:
		if observation.get("id") is String:
			ids[observation.id] = true
	var observe: Variant = missions.get("observe")
	if missions.has("observe") and not (observe is String and ids.has(observe)):
		problems.append("missions.observe must be one of the observation ids")
	if missions.get("compare", "greater") not in MissionTracker.COMPARES:
		problems.append("missions.compare must be greater or less")
	for key in ["judge_on", "reveal_on"]:
		var statuses: Variant = missions.get(key, MissionTracker.DEFAULT_JUDGE_ON)
		if not (statuses is Array and not statuses.is_empty() and statuses.all(func(v: Variant) -> bool: return v is String and v != "")):
			problems.append("missions.%s must list statuses" % key)
	var hidden: Variant = missions.get("hidden_until_end", [])
	if not (hidden is Array and hidden.all(func(id: Variant) -> bool: return id is String and ids.has(id))):
		problems.append("missions.hidden_until_end must list observation ids")
	var stages: Variant = missions.get("stages")
	if not (stages is Array and stages.size() > 0 and stages.size() <= ProgressStore.MAX_STAMPS):
		problems.append("missions.stages must list %d or fewer non-empty stages" % ProgressStore.MAX_STAMPS)
		return problems
	for i in stages.size():
		var stage: Variant = stages[i]
		var threshold: Variant = stage.get("threshold") if stage is Dictionary else null
		var text: Variant = stage.get("text") if stage is Dictionary else null
		# A stage's own rule (MissionTracker.rule): observe "" (a state goal) or an id, compare, judge_on.
		var own: Variant = stage.get("observe") if stage is Dictionary else null
		var observed: bool = (own != "") if stage is Dictionary and stage.has("observe") else missions.has("observe")
		if not stage is Dictionary:
			problems.append("missions.stages[%d] must be an object" % i)
		elif stage.has("observe") and not (own is String and (own == "" or ids.has(own))):
			problems.append("missions.stages[%d].observe must be \"\" or one of the observation ids" % i)
		elif stage.has("compare") and stage.compare not in MissionTracker.COMPARES:
			problems.append("missions.stages[%d].compare must be greater or less" % i)
		elif stage.has("judge_on") and not (stage.judge_on is Array and not stage.judge_on.is_empty() and stage.judge_on.all(func(v: Variant) -> bool: return v is String and v != "")):
			problems.append("missions.stages[%d].judge_on must list statuses" % i)
		elif observed and not ((threshold is int or threshold is float) and threshold > 0.0):
			problems.append("missions.stages[%d].threshold must be a number > 0" % i)
		elif not observed and stage.has("threshold"):
			problems.append("missions.stages[%d].threshold needs missions.observe (or the stage's observe)" % i)
		elif not (text is String and text != ""):
			problems.append("missions.stages[%d].text must be a text" % i)
		else:
			problems.append_array(_validate_conditions(stage.get("conditions", {}), controls, i))
			var change: Variant = stage.get("change", [])
			var control_ids := controls.map(func(c: Dictionary) -> Variant: return c.get("id"))
			if not (change is Array and change.all(func(id: Variant) -> bool: return id in control_ids)):
				problems.append("missions.stages[%d].change must list control ids" % i)
	return problems


## A stage's `conditions`: {control id: option id (choice) | number or {"min"?, "max"?} (slider)}.
static func _validate_conditions(conditions: Variant, controls: Array, i: int) -> PackedStringArray:
	var problems := PackedStringArray()
	if not conditions is Dictionary:
		problems.append("missions.stages[%d].conditions must be an object" % i)
		return problems
	for id in conditions:
		var control: Dictionary = {}
		for c in controls:
			if c.get("id") == id:
				control = c
		var want: Variant = conditions[id]
		if control.is_empty():
			problems.append("missions.stages[%d].conditions: %s is not a control" % [i, str(id)])
		elif control.get("type") == "choice":
			if not (want is String and control.get("options", []).any(func(o: Dictionary) -> bool: return o.get("id") == want)):
				problems.append("missions.stages[%d].conditions.%s must be an option id" % [i, id])
		else:
			var lo := float(control.get("min", -INF))
			var hi := float(control.get("max", INF))
			var bounds: Array = [want.get("min", lo), want.get("max", hi)] if want is Dictionary else [want, want]
			if not (bounds.all(func(v: Variant) -> bool: return (v is int or v is float) and v >= lo and v <= hi) and bounds[0] <= bounds[1]):
				problems.append("missions.stages[%d].conditions.%s must be a number or {min, max} inside the slider" % [i, id])
	return problems


## `predict` (Plan G4, optional): Dugi's question before the run —
## {"question": <text>, "choices": [{"id", "label", "picture": <PredictPictures kind>} x 2],
##  "answer": <a choice id>, "reason": <text>}.
static func _validate_predict(predict: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if predict == null:
		return problems
	if not predict is Dictionary:
		problems.append("predict must be an object")
		return problems
	for key in ["question", "reason"]:
		if not (predict.get(key) is String and predict.get(key) != ""):
			problems.append("predict.%s must be a text" % key)
	var choices: Variant = predict.get("choices")
	var ids := []
	if not (choices is Array and choices.size() == 2):
		problems.append("predict.choices must list two choices")
		return problems
	for choice in choices:
		if not (choice is Dictionary and choice.get("id") is String and choice.get("label") is String and choice.label != ""):
			problems.append("predict choice needs id and label")
			continue
		if choice.get("picture") not in PredictPictures.KINDS:
			problems.append("predict choice %s: picture must be one of PredictPictures.KINDS" % choice.id)
		ids.append(choice.id)
	if ids.size() == 2 and ids[0] == ids[1]:
		problems.append("predict choices need distinct ids")
	if predict.get("answer") not in ids:
		problems.append("predict.answer must be one of the choice ids")
	return problems


## `cast` (Task 4h, optional): {"dugi": {"at": [x, z], "explain_on": [status...], "delay_s"?},
## "puppy": {"at": [x, z]}} (IslandCast).
static func _validate_cast(cast: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if cast == null:
		return problems
	if not cast is Dictionary:
		problems.append("cast must be an object")
		return problems
	for who in cast:
		var spec: Variant = cast[who]
		if who not in ["dugi", "puppy"] or not spec is Dictionary:
			problems.append("cast.%s unknown" % who)
			continue
		var at: Variant = spec.get("at")
		if not (at is Array and at.size() == 2 and at.all(func(v: Variant) -> bool: return v is float or v is int)):
			problems.append("cast.%s.at must be [x, z]" % who)
		if who == "dugi":
			var on: Variant = spec.get("explain_on", [])
			if not (on is Array and not on.is_empty() and on.all(func(v: Variant) -> bool: return v is String)):
				problems.append("cast.dugi.explain_on must list statuses")
			var delay: Variant = spec.get("delay_s", 0.0)
			if not ((delay is float or delay is int) and delay >= 0.0):
				problems.append("cast.dugi.delay_s must be a number >= 0")
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
		if not object.get("drag", true) is bool:
			problems.append("manipulation %s.drag must be true or false" % object.id)
	var grab: Variant = manipulation.get("grab_radius", 1.0)   # (Manipulator.PICK_RADIUS when absent)
	if not (grab is float or grab is int) or grab <= 0.0:
		problems.append("manipulation.grab_radius must be a number > 0 (UI units)")
	var demo: Variant = manipulation.get("demo_action", "")
	if not demo is String or (demo != "" and not actions.any(func(a: Dictionary) -> bool: return a.get("id") == demo)):
		problems.append("manipulation.demo_action must be the id of one of the actions")
	# The slingshot (Plan G3): the pull's object (one of the manipulable ids) and its angle step.
	var slingshot: Variant = manipulation.get("slingshot")
	if slingshot is Dictionary:
		if not slingshot.get("object") is String or not ids.has(slingshot.object):
			problems.append("manipulation.slingshot.object must be one of the manipulation objects")
		var angle_step: Variant = slingshot.get("angle_step", 15.0)
		if not (angle_step is float or angle_step is int) or angle_step <= 0.0:
			problems.append("manipulation.slingshot.angle_step must be a number > 0")
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
