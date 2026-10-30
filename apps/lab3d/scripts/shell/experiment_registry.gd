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
const APP_OVERRIDES := ["steps", "observe", "question"]
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
## `content` are returned as they are. A lab's `app.steps` (three texts), `app.observe` or `app.question` replaces
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
		if (key == "steps" and not (text is Array and text.size() == 3)) or (key != "steps" and not (text is String and text != "")):
			problems.append("app.%s of %s is not valid (steps: three texts, observe / question: a text)" % [key, raw.content])
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
	# The playback pace (optional, 2026-10-29: the orbit shown 2.5x faster, Experiment.time_scale).
	var pace: Variant = definition.get("time_scale", 1.0)
	if not ((pace is float or pace is int) and float(pace) > 0.0 and float(pace) <= 4.0):
		problems.append("time_scale must be a number in (0, 4]")
	for observation in definition.observations:
		if not observation.has("id") or not observation.has("label"):
			problems.append("observation needs id and label")
	problems.append_array(_validate_key_observations(definition.key_observations, definition.observations))
	var graph: Dictionary = definition.graph
	if not graph.has("series") or graph.series.is_empty():
		problems.append("graph.series missing")
	problems.append_array(_validate_manipulation(definition.get("manipulation"), definition.actions))
	problems.append_array(_validate_cast(definition.get("cast")))
	problems.append_array(MissionRound.validate(definition))   # missions and predict
	problems.append_array(_validate_kid(definition.get("kid"), definition.observations.map(func(o: Dictionary) -> Variant: return o.get("id"))))
	problems.append_array(_validate_story(definition.get("story")))
	problems.append_array(_validate_note(definition.get("note"), definition.observations))
	if definition.get("kid") is Dictionary:
		problems.append_array(_validate_kid_cards(definition))
		problems.append_array(ConditionPicks.validate(definition))
	return problems


## The game layer's words for a 7-year-old (`kid`, optional): short everyday sentences without the
## formula's names. Content shared with the web (content/mechanics-labs.json) keeps its own texts;
## the 3D experiment file puts the child-facing ones here and the screen shows them in place of the
## shared ones (the "자세히" sidebar keeps the shared texts and the formula labels):
##   "kid": {"title": <the title bar>, "place": <the map's spot name>, "say": <Dugi's dialogue>, "say_face": <its face>,
##           "tip": <the short gesture hint>, "card": <the one key observation shown as a card>,
##           "cards": {<observation id>: <its key card's caption>},
##           "states": {<a status text of the lab>: <its key card words>},
##           "minus": {<observation id>: <the word a negative value reads with: "눌려서", "왼쪽으로">},
##           "bars": {<observation id>: <the value of a full bar>},
##           "picks": {<control id>: [the mission's picture buttons, ConditionPicks]}}
## Every key is optional; a missing one falls back to the shared text (kid_text, card_label).
## The key cards over the 3D view show a number with one decimal and its unit in words (KID_UNITS:
## "1.3초", "1초에 12.5미터"); a game lab's key observations have such a unit (an energy, an
## acceleration, a force stays in "자세히"). A force that is the lab's goal (the push that started the
## box) is a bar instead (`bars`, 2026-10-28 "어려운 말들은 세부 쪽으로": no "뉴턴" on the kid screen):
## the bar grows with the value up to its full length at the given value; the number is in "자세히".
## States and minus words change the card's words only: the lab's text and the value (the sidebar's,
## full precision) stay the formula's (ExperimentScreen.card_text).
const KID_TEXTS := {"title": "title", "place": "title", "say": "observe", "tip": "tip_short"}
const KID_MAPS := ["cards", "states", "minus"]
## Observation unit -> [the words before the number, the words after it] on a key card.
const KID_UNITS := {"": ["", ""], "m": ["", "미터"], "s": ["", "초"], "m/s": ["1초에 ", "미터"],
	"°": ["", "도"], "kg": ["", "킬로그램"], "바퀴": ["", "바퀴"], "줄": ["", "줄"], "배": ["", "배"]}


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
		elif key == "say_face":
			if not kid.say_face in Story.FACES:
				problems.append("kid.say_face must be one of Story.FACES")
		elif key == "picks":
			pass   # ConditionPicks.validate (it needs the controls and the missions)
		elif key == "bars":
			var bars: Variant = kid.bars
			if not (bars is Dictionary and bars.keys().all(func(id: Variant) -> bool: return id in ids)
					and bars.values().all(func(v: Variant) -> bool: return (v is float or v is int) and v > 0.0)):
				problems.append("kid.bars must name observations with a full-bar value > 0 each")
		elif not KID_TEXTS.has(key):
			problems.append("kid.%s unknown (title, place, say, tip, card, cards, states, minus, bars, picks)" % key)
		elif not (kid[key] is String and kid[key] != ""):
			problems.append("kid.%s must be a text" % key)
	return problems


## The story's words for this lab (`story`, optional, 2026-10-28 "별 조각 찾기"): {"clue": <Puppy's
## clue, told once on the first visit before Dugi's question>, "map_clue": <Puppy's riddle on the
## night map while this spot is the next to find>, "clue_face"?, "map_clue_face"?: <Story.FACES>}
## (Story.clue, Story.map_clue, their portraits' faces).
static func _validate_story(story: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if story == null:
		return problems
	if not story is Dictionary:
		problems.append("story must be an object")
		return problems
	for key in story:
		if key in ["clue_face", "map_clue_face"]:
			if not story[key] in Story.FACES:
				problems.append("story.%s must be one of Story.FACES" % key)
		elif not key in ["clue", "map_clue"]:
			problems.append("story.%s unknown (clue, map_clue, clue_face, map_clue_face)" % key)
		elif not (story[key] is String and story[key] != ""):
			problems.append("story.%s must be a text" % key)
	return problems


## A game lab's key cards (it has `kid`): every key observation's unit has its words (KID_UNITS) or
## the observation is a bar (kid.bars); kid.card and every stage's `card` are key observations.
static func _validate_kid_cards(definition: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var kid: Dictionary = definition.kid if definition.get("kid") is Dictionary else {}
	var bars: Dictionary = kid.get("bars") if kid.get("bars") is Dictionary else {}
	for observation in definition.observations:
		if observation.get("id") in definition.key_observations and not KID_UNITS.has(str(observation.get("unit", ""))) \
				and not bars.has(observation.get("id")):
			problems.append("key_observations: %s (%s) has no kid unit words; keep it in the sidebar" % [observation.id, observation.unit])
	if kid.has("card") and not kid.card in definition.key_observations:
		problems.append("kid.card %s is not one of key_observations" % str(kid.card))
	var stages: Array = MissionRound.missions(definition).get("stages", [])
	for i in stages.size():
		if stages[i] is Dictionary and stages[i].has("card") and not _cards(stages[i].card).all(func(id: Variant) -> bool: return id in definition.key_observations):
			problems.append("missions.stages[%d].card %s is not one of key_observations" % [i, str(stages[i].card)])
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
## Stage `stage`'s own `card` (optional, 2026-10-28: the spring's first stage shows how far the ball
## was pulled) replaces kid.card while that stage is the current one.
static func shown_cards(definition: Dictionary, stage := -1) -> Array:
	var stages: Array = MissionRound.missions(definition).get("stages", [])
	if stage >= 0 and stage < stages.size() and stages[stage] is Dictionary and stages[stage].has("card"):
		return _cards(stages[stage].card)
	var kid: Variant = definition.get("kid")
	if kid is Dictionary and kid.get("card") is String:
		return [kid.card]
	return definition.get("key_observations", [])


## A stage's `card`: one key observation id or a list of them (2026-10-29: the spring's pull and swing).
static func _cards(card: Variant) -> Array:
	if card is String:
		return [card]
	return card if card is Array and not card.is_empty() and card.all(func(id: Variant) -> bool: return id is String) else [null]


## The full-bar value of a key card shown as a bar (kid.bars), or 0 when the card is a number.
static func card_bar(definition: Dictionary, id: String) -> float:
	var kid: Variant = definition.get("kid")
	if kid is Dictionary and kid.get("bars") is Dictionary and kid.bars.has(id):
		return float(kid.bars[id])
	return 0.0


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


## The science note of "자세히" (`note`, optional, 2026-10-28 "세부쪽도 좀 정리가 필요해"): for older
## children and adults, the lab's law in one plain sentence and one formula, the run's key numbers
## (with units), and whether the graph stays in the note or goes under "더 보기" —
##   {"law": <one sentence>, "formula": <one formula, unicode sub/superscripts and primes>,
##    "numbers": [{"label": <what it is>, "ids": [<observation id>, <optional second id: "before → after">]}],
##    "graph": true | false}
## NOTE_NUMBERS_MIN..NOTE_NUMBERS_MAX rows, each observation at most once. Every other observation
## (and the graph when "graph" is false, the steps, the observe card, the shared law and its terms)
## sits under the collapsed "더 보기" (ExperimentScreen._build_sidebar). Without `note` the sidebar
## takes the shared law and the key observations (note()).
const NOTE_NUMBERS_MIN := 3
const NOTE_NUMBERS_MAX := 4


static func _validate_note(note: Variant, observations: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	if note == null:
		return problems
	if not note is Dictionary:
		problems.append("note must be an object")
		return problems
	for key in note:
		if not key in ["law", "formula", "numbers", "graph"]:
			problems.append("note.%s unknown (law, formula, numbers, graph)" % key)
	for key in ["law", "formula"]:
		if not (note.get(key) is String and note.get(key) != ""):
			problems.append("note.%s must be a text" % key)
	if not note.get("graph", true) is bool:
		problems.append("note.graph must be true or false")
	var ids := observations.map(func(o: Dictionary) -> Variant: return o.get("id"))
	var rows: Variant = note.get("numbers")
	if not (rows is Array and rows.size() >= NOTE_NUMBERS_MIN and rows.size() <= NOTE_NUMBERS_MAX):
		problems.append("note.numbers must list %d-%d rows" % [NOTE_NUMBERS_MIN, NOTE_NUMBERS_MAX])
		return problems
	var seen := {}
	for row in rows:
		var row_ids: Variant = row.get("ids") if row is Dictionary else null
		if not (row is Dictionary and row.get("label") is String and row.label != "" and row_ids is Array
				and row_ids.size() >= 1 and row_ids.size() <= 2 and row_ids.all(func(id: Variant) -> bool: return id in ids and not seen.has(id))):
			problems.append("note.numbers: each row needs a label and 1-2 observation ids not used before")
			continue
		for id in row_ids:
			seen[id] = true
	return problems


## The definition's science note (`note`), or one made from the shared law (its description and
## equation), the key observations as the numbers and the graph kept.
static func note(definition: Dictionary) -> Dictionary:
	var own: Variant = definition.get("note")
	if own is Dictionary:
		return own
	var law: Dictionary = definition.get("law", {}) if definition.get("law") is Dictionary else {}
	var labels := {}
	for observation in definition.get("observations", []):
		labels[observation.get("id")] = str(observation.get("label", ""))
	var numbers := []
	for id in definition.get("key_observations", []):
		numbers.append({"label": labels.get(id, str(id)), "ids": [id]})
	return {"law": str(law.get("description", "")), "formula": str(law.get("equation", "")), "numbers": numbers, "graph": true}


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
## "height": false | {"max" (m, > 0, a multiple of step), "step" (m, optional)}} or a hold object
## {"id", "hold": true} (2026-10-28: press and hold, no surface)],
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
		if not object is Dictionary or not object.get("id") is String:
			problems.append("manipulation object needs an id")
			continue
		var hold: Variant = object.get("hold", false)
		if not hold is bool:
			problems.append("manipulation %s.hold must be true or false" % object.id)
		if hold != true and not object.get("surface") is String:
			problems.append("manipulation object %s needs a surface (or \"hold\": true)" % object.id)
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
