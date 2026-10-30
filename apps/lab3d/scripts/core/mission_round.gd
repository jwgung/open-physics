## The mission round of one lab (apps/lab3d/GLOSSARY.md "미션 라운드"): Puppy's clue, Dugi's prediction
## question, the stages' attempts and stamps, Puppy's result lines, the prediction's reason, the bridge
## to the mission, and the end of the round. One module owns the rules of the definition's `missions`
## and `predict` blocks (validate(), the static queries below) and the round's flow on a screen (the
## instance below). It reads the lab (status(), settled(), observations(), control_value()) and never
## sets a control, runs an action or touches a body, so the engine bodies, the formula values and the
## displayed numbers are the same with or without it (tests/mission_checks.gd, lab_mission_checks.gd).
##
## The flow has no nodes and no clock (tests/mission_round_checks.gd drives it with events only). The
## screen (ExperimentScreen) is its adapter: it tells the round what happened (a touch, an action, a
## condition change, a placed object, a throw, a poll, a picked answer, the clue opened or read) and
## draws what the round says (its signals and queries). The pace of the pictures (the stamp's flight,
## the confetti, the piece, the round-done card) stays the screen's.
##
## The definition's `missions` block (validate()):
##   "missions": { "observe": "range", "compare": "greater",
##                 "judge_on": ["landed"], "reveal_on": ["landed", "out", "fence"],
##                 "hidden_until_end": ["range", ...],
##                 "stages": [ {"threshold": 3.0, "text": "3 m보다 멀리 보내기!"}, ... ] }
## - `judge_on` (default ["landed"]): the lab statuses that are a run's result. A stage is judged only
##   while the status is one of them and the lab is settled (`settled()`: the engine has finished
##   what the status reports, e.g. the projectile's landing, not merely the formula landing within
##   the slack). A lab without a release (the push, the lever, the pulley) names the state that shows
##   the goal ("sliding", "lifted", "held").
## - `observe` (optional): a numeric observation id; the stage's `threshold` must be beaten —
##   `compare` "greater" (default: farther, faster) or "less" (a smaller force) — strictly (exactly
##   at the threshold is not past it). A run with no number there (e.g. "닿지 않아요") is not judged.
##   The number judged is the number shown (2026-10-28): the value rounded as the key card rounds it
##   (shown(): one decimal at most), so a card reading "3.0초" never earns "3초 넘게" and "3.1초" does.
##   Without `observe` a stage is a state goal: reaching a `judge_on` status is the clear.
## - a stage's `conditions` (optional): {control id: option id | number | {"min"?, "max"?}} — the
##   lab's current control values the run must have been made with ("가벼운 상자", "20 kg 짐",
##   "출발 반지름 2 m"). Read through Experiment.control_value; a number matches within 1e-6, a range
##   is inclusive.
## - a stage's `change` (optional): [control id, ...] — the run must differ in at least one of these
##   controls from the run that cleared the stage before ("세기나 각도를 바꿔"): throwing the same
##   throw again never earns the next stamp. The cleared run's control values are kept with the
##   stamps (ProgressStore.cleared); with none kept (a first stage, an older save) any run counts.
## - a stage's `observe`, `compare`, `judge_on` (optional, 2026-10-28): that stage's own rule in
##   place of the block's ("빨리 떨어지게" is "less", "별을 떠나기" is the state "far" with no number:
##   `"observe": ""`). A key the stage leaves out is the block's (MissionRound.rule).
## - a stage's `compare` "near" (2026-10-29, the spring's beat): the shown number is within the
##   stage's `tolerance` (> 0) of its `threshold` ("박자 맞추기": the swing matches the clock's beat).
## - a stage's `also` (optional, 2026-10-29): [{"observe", "compare", "threshold", "tolerance"?}, ...]
##   more numbers the same run must beat, each its own rule on its shown number ("2미터 넘게 당겨
##   박자 맞추기": the pull and the swing). Every one must hold for the stamp.
## - `reveal_on` (default `judge_on`): the statuses where the run has its result: the
##   hidden_until_end values (the formula's answer) read "?" until then, and the prediction's question
##   is over. With `observe`, the result is in once that value is a number too (the pendulum's period
##   after its first full swing).
##
## An attempt (what one stamp at most comes from): the run since the child last acted on the lab —
## an action ("공 놓기", "발사", "처음으로"), a condition change, an object put down or put back (a
## let-go hold, a placed ball), a slingshot throw — or since the lab was back at "ready". The
## screen judges every poll while the status is a judge_on one and keeps judging until the attempt
## earns its stamp (a growing value — orbit laps, a measured period — is judged when it gets there);
## then the attempt is done. A run that falls short changes nothing, and the next attempt is judged
## against the same stage. One attempt clears at most the current stage. The stamps are the child's
## collection — 3 m past, then 5 m past, then 7 m past (stamps: 0..MAX_STAMPS, one per stage).
##
## Stamps live in the progress store (`store`: FileProgress = ProgressStore, user://progress.cfg;
## MemoryProgress in tests), read once at start(); `stamps` is what the round last judged, so a
## judgement reads no file and a stamp is saved once.
class_name MissionRound
extends RefCounted

## The status that ends a run with a result when the definition names none (the projectile's landing).
const DEFAULT_JUDGE_ON := ["landed"]
const COMPARES := ["greater", "less", "near"]
## A number condition matches a control value within this (slider values sit on their grid).
const CONDITION_EPS := 1e-6
## The decimals a child reads on a key card (ExperimentScreen.kid_value): a stage judges that number.
const CARD_PLACES := 1
## Puppy's miss line needs the miss seen on this many polls in a row (a status of one step is not a result).
const MISS_POLLS := 2
## Dugi's bridge from the answer to the mission (predict.bridge) ends with one of these.
const BRIDGE_FIRST := "첫 번째 미션이에요."
const BRIDGE_NEXT := "다음 미션이에요."
## The statuses where a lab is not mid-run: the stage's automatic conditions are set only then.
const AT_REST := ["ready", "rest"]

## The round's place in its flow (phase()).
enum Phase {
	CLUE,     ## Puppy's clue is told (or waits for its box) before Dugi's question.
	ASKING,   ## Dugi's prediction question is open (held until an answer).
	PLAYING,  ## a stage is being played.
	DONE,     ## every stage is cleared (or the lab has no missions).
}

## The clue or the question is over (answered, skipped by a pull, the run's result, the demo): the
## screen takes down its shield and picture buttons.
signal question_ended
## A stamp was earned and saved now (`stamps`: the count with it). Puppy's win line came just before
## (result_told). Not emitted for a stamp that was already saved (a reopened place).
signal stamp_earned(stamps: int)
## Puppy's result line of `stage` after an attempt (`won`: its stamp came; else a miss). `text` ""
## when the stage has none (nothing to show).
signal result_told(stage: int, won: bool, text: String, face: String)
## Dugi tells the prediction's reason now: the first result line of the visit came (take_line()).
signal reason_due
## The first run has its result (reveal_on): the question is over and the strip shows the stage again.
signal revealed

var definition: Dictionary
## The cleared stages so far (0..stages.size()); the current stage is stamps (one stamp per stage).
var stamps := 0
var _judged := 0   # the count last saved or handed over (start(): the stored one)
## The control values of the run that cleared the last stage (a stage's `change`; start(): the stored ones).
var cleared: Dictionary = {}
## Where the stamps, the cleared runs, the round's end and the told clues are kept.
var store: Object
## The lab the round reads (the screen's experiment).
var lab: Experiment = null
## The picked choice id ("" before an answer).
var pick := ""
## The reason's face: happy after a right guess, thinking after a wrong one (Story.REASON_FACE).
var reason_face := Story.DEFAULT_FACE
## This attempt earned its stamp (cleared by the next attempt or the lab back at "ready").
var judged_run := false
## The first run has its result, or there is no question to wait for.
var predict_ended := false

var _asking := false
var _clue := ""
var _clue_open := false
var _question := ""
var _question_face := Story.DEFAULT_FACE
## The prediction's reason still to tell ("" once told or when there is none).
var reason := ""
var _bridge := ""
var _bridge_face := Story.DEFAULT_FACE
var _first_result := false
var _armed := false
var _resolved := false
var _miss_polls := 0
var _auto_pending := false


## `progress_store` null = the app's ProgressStore (FileProgress).
func _init(round_definition: Dictionary = {}, progress_store: Object = null) -> void:
	definition = round_definition
	store = progress_store if progress_store != null else FileProgress.new()


## The round of `round_definition` for a screen, started from its saved stamps; null when it has no missions.
static func create(round_definition: Dictionary, experiment: Experiment, progress_store: Object = null) -> MissionRound:
	if missions(round_definition).is_empty():
		return null
	var made := MissionRound.new(round_definition, progress_store)
	made.lab = experiment
	made.start()
	return made


# --- the rules (static queries of the definition) ------------------------------------------------

## The definition's missions, or {} when it has none.
static func missions(definition: Dictionary) -> Dictionary:
	var missions: Variant = definition.get("missions")
	return missions if missions is Dictionary else {}


## The definition's prediction (the question, the two choices, the answer, the reason) or {} when
## it has none. (Plan G4: Dugi asks before the run and explains the reason after it.)
static func predict(definition: Dictionary) -> Dictionary:
	var predict: Variant = definition.get("predict")
	return predict if predict is Dictionary else {}


## The statuses a stage is judged on (the run's result states): stage `stage`'s own judge_on, else
## the block's (stage -1 or past the last: the block's).
static func judge_on(definition: Dictionary, stage := -1) -> Array:
	return rule(definition, stage).judge_on


## Stage `stage`'s judging rule {"observe": id or "", "compare": "greater" | "less", "judge_on": [...]}:
## the stage's own keys over the block's (stage -1 or past the last: the block's alone).
static func rule(definition: Dictionary, stage := -1) -> Dictionary:
	var block := missions(definition)
	var out := {"observe": str(block.get("observe", "")), "compare": str(block.get("compare", "greater")),
		"judge_on": block.get("judge_on", DEFAULT_JUDGE_ON)}
	var stages: Array = block.get("stages", [])
	if stage >= 0 and stage < stages.size() and stages[stage] is Dictionary:
		for key in out:
			if (stages[stage] as Dictionary).has(key):
				out[key] = stages[stage][key] if key == "judge_on" else str(stages[stage][key])
	return out


## The statuses where the run has its result (the hidden answers show, the question is over).
static func reveal_on(definition: Dictionary) -> Array:
	return missions(definition).get("reveal_on", judge_on(definition))


## The statuses where an attempt of stage `stage` that earned no stamp is a miss (2026-10-29, Puppy's
## hint): the stage's own `miss_on`, else the block's; [] when the definition names none (no hints).
static func miss_on(definition: Dictionary, stage: int) -> Array:
	var stages: Array = missions(definition).get("stages", [])
	if stage >= 0 and stage < stages.size() and stages[stage] is Dictionary and (stages[stage] as Dictionary).has("miss_on"):
		return stages[stage].miss_on
	return missions(definition).get("miss_on", [])


## A miss of stage `stage` is told once the run, seen in `status` (settled), has its result: the status
## is one of miss_on and the block's `miss_needs` observation (a swing's result) is a number.
static func missed(definition: Dictionary, stage: int, status: String, observations: Dictionary) -> bool:
	if status not in miss_on(definition, stage):
		return false
	var needs := str(missions(definition).get("miss_needs", ""))
	return needs == "" or _number(observations.get(needs))


## Puppy's result line of stage `stage` [text, face]: `win` (face win_face, else happy) after its stamp,
## `miss` (miss_face, else thinking) after a miss; ["", ""] when the stage has none.
static func result_line(definition: Dictionary, stage: int, won: bool) -> Array:
	var stages: Array = missions(definition).get("stages", [])
	if stage < 0 or stage >= stages.size() or not stages[stage] is Dictionary:
		return ["", ""]
	var key := "win" if won else "miss"
	var text := str(stages[stage].get(key, ""))
	var face: Variant = stages[stage].get(key + "_face")
	return [text, str(face) if face is String and face in Story.FACES else ("happy" if won else "thinking")]


## The run has its result: the status is a reveal_on one and, with `observe`, its value is a number.
static func result_in(definition: Dictionary, status: String, observations: Dictionary) -> bool:
	if status not in reveal_on(definition):
		return false
	var observe := str(missions(definition).get("observe", ""))
	return observe == "" or _number(observations.get(observe))


## The new stamp count after a run seen in `status` with `stamps` cleared so far: one more when the
## status is one of the stage's judge_on, the lab is settled, the stage's conditions hold (the lab's
## control values) and, with an `observe` (rule: the stage's or the block's), its formula value beats
## the stage's threshold (`compare`). Anything else keeps the count. The caller passes the observations() the panels show.
## `cleared`: the control values of the run that cleared the stage before (a stage's `change`).
static func judge(definition: Dictionary, stamps: int, status: String, lab: Experiment,
		observations: Dictionary, cleared := {}) -> int:
	var stages: Array = missions(definition).get("stages", [])
	if stamps >= stages.size():
		return stamps
	var how := rule(definition, stamps)
	if status not in how.judge_on or not lab.settled():
		return stamps
	var stage: Dictionary = stages[stamps]
	if not conditions_met(stage.get("conditions", {}), lab) or not changed(stage.get("change", []), lab, cleared):
		return stamps
	if how.observe != "" and not beats(definition, how.observe, how.compare, stage, observations):
		return stamps
	for extra in stage.get("also", []):
		if not beats(definition, str(extra.get("observe", "")), str(extra.get("compare", "greater")), extra, observations):
			return stamps
	return mini(stamps + 1, ProgressStore.MAX_STAMPS)


## The shown number of observation `observe` beats `rule`'s threshold (a stage or one of its `also`
## entries: "threshold", "tolerance") by `compare`: strictly past it ("greater", "less") or within
## the tolerance of it ("near", inclusive). A value that is not a number never beats it.
static func beats(definition: Dictionary, observe: String, compare: String, rule: Dictionary, observations: Dictionary) -> bool:
	var value: Variant = observations.get(observe)
	if not _number(value):
		return false
	var number := shown(definition, observe, float(value))
	match compare:
		"less":
			return number < float(rule.get("threshold", INF))
		"near":
			# The shown number and the threshold both have one decimal: compare in tenths (no float slop).
			return absf(number - float(rule.get("threshold", INF))) <= float(rule.get("tolerance", 0.0)) + 1e-9
	return number > float(rule.get("threshold", -INF))


## The lab's control values match every condition (an option id, a number within CONDITION_EPS, or
## an inclusive {"min", "max"} range).
static func conditions_met(conditions: Dictionary, lab: Experiment) -> bool:
	for id in conditions:
		if not condition_holds(conditions[id], lab.control_value(id)):
			return false
	return true


## One condition `want` (an option id, a number, or an inclusive {"min", "max"} range) holds for the
## control value `have` (the same rule for the stamp and the picture buttons, ConditionPicks).
static func condition_holds(want: Variant, have: Variant) -> bool:
	if want is String:
		return str(have) == want
	if not _number(have):
		return false
	if want is Dictionary:
		return float(have) >= float(want.get("min", -INF)) - CONDITION_EPS and float(have) <= float(want.get("max", INF)) + CONDITION_EPS
	return absf(float(have) - float(want)) <= CONDITION_EPS


## The run differs from the `cleared` one in at least one of the `ids` controls (a number by more
## than CONDITION_EPS). No ids, or no cleared run kept: true.
static func changed(ids: Array, lab: Experiment, cleared: Dictionary) -> bool:
	if ids.is_empty() or cleared.is_empty():
		return true
	for id in ids:
		var have: Variant = lab.control_value(id)
		var had: Variant = cleared.get(id)
		if _number(have) and _number(had):
			if absf(float(have) - float(had)) > CONDITION_EPS:
				return true
		elif str(have) != str(had):
			return true
	return false


## The control values a later stage's `change` compares with (every control any stage names).
static func change_controls(definition: Dictionary, lab: Experiment) -> Dictionary:
	var out := {}
	for stage in missions(definition).get("stages", []):
		for id in stage.get("change", []):
			out[id] = lab.control_value(id)
	return out


## The number a child reads for observation `id` (the key card's rounding, ExperimentScreen.kid_value:
## the observation's digits, one decimal at most): what a stage compares with its threshold.
static func shown(definition: Dictionary, id: String, value: float) -> float:
	var digits := 2
	for observation in definition.get("observations", []):
		if observation.get("id") == id:
			digits = int(observation.get("digits", 2))
	return float(Ui.number(value, mini(digits, CARD_PLACES)))


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


# --- validation (ExperimentRegistry.validate calls it) --------------------------------------------

## The problems of the definition's `missions` and `predict` blocks (empty = valid; both optional).
static func validate(definition: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	problems.append_array(_validate_missions(definition.get("missions"), definition.get("observations", []), definition.get("controls", [])))
	problems.append_array(_validate_series(definition.get("missions"), definition.get("graph", {}).get("series", [])))
	problems.append_array(_validate_predict(definition.get("predict")))
	return problems


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


## `missions` (Plan G1, G2, optional): the stages and how a run is judged (this file's header) —
## {"stages": [{"text": <non-empty>, "say"?: <Dugi's explanation of the stage>, "say_face"?: <Story.FACES>, "threshold"?: <number > 0>, "conditions"?: {...},
##              "win"?, "miss"?: <Puppy's result lines>, "win_face"?, "miss_face"?: <Story.FACES>, "miss_on"?: [...],
##              "change"?: [<control id>, ...], "observe"?: <an observation id> | "",
##              "compare"?: ..., "judge_on"?: [...]}, ...],
##  "observe"?: <an observation id>, "compare"?: "greater" | "less",
##  "judge_on"?: [<status>, ...], "reveal_on"?: [<status>, ...],
##  "auto_conditions"?: <bool: the screen sets each stage's `conditions` itself, ConditionPicks>,
##  "miss_on"?: [<status>, ...] (an attempt without a stamp that comes to one of these, settled and the
##  finger up, is a miss: Puppy's stage `miss` line; with it every stage has `win` and `miss`; a stage's
##  own `miss_on` replaces it), "miss_needs"?: <an observation id that must be a number first>,
##  "hidden_until_end"?: [<observation id>, ...], "hidden_series_until_end"?: [<graph series id>, ...]}.
## With `observe` every stage has its threshold; without it a stage is a state goal (no threshold).
## A stage's own observe / compare / judge_on replace the block's for that stage ("": no observe).
## A stage's `conditions` name the definition's controls: a choice wants one of its option ids, a
## slider a number or a {"min"?, "max"?} range inside its min..max. The round only reads (it never
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
	if missions.get("compare", "greater") not in ["greater", "less"]:
		problems.append("missions.compare must be greater or less")
	for key in ["judge_on", "reveal_on"]:
		if not _statuses(missions.get(key, DEFAULT_JUDGE_ON)):
			problems.append("missions.%s must list statuses" % key)
	if missions.has("auto_conditions") and not missions.auto_conditions is bool:
		problems.append("missions.auto_conditions must be true or false")
	# The result lines (2026-10-29): the statuses where an attempt without a stamp is a miss (Puppy's
	# hint), and the observation that must have a number first (a swing's result).
	if missions.has("miss_on") and not _statuses(missions.miss_on):
		problems.append("missions.miss_on must list statuses")
	if missions.has("miss_needs") and not (missions.miss_needs is String and ids.has(missions.miss_needs)):
		problems.append("missions.miss_needs must be one of the observation ids")
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
		# Dugi's explanation of this stage (2026-10-29, optional): a text and its face.
		if stage is Dictionary and stage.has("say") and not (stage.say is String and stage.say != ""):
			problems.append("missions.stages[%d].say must be a text" % i)
		if stage is Dictionary and stage.has("say_face") and not stage.say_face in Story.FACES:
			problems.append("missions.stages[%d].say_face must be one of Story.FACES" % i)
		# Puppy's short result lines (2026-10-29): what the win did, what to try after a miss; their faces.
		if stage is Dictionary and missions.has("miss_on"):
			for key in ["win", "miss"]:
				if not (stage.get(key) is String and stage.get(key) != ""):
					problems.append("missions.stages[%d].%s must be a text" % [i, key])
		if stage is Dictionary:
			for key in ["win_face", "miss_face"]:
				if stage.has(key) and not stage[key] in Story.FACES:
					problems.append("missions.stages[%d].%s must be one of Story.FACES" % [i, key])
			if stage.has("miss_on") and not _statuses(stage.miss_on):
				problems.append("missions.stages[%d].miss_on must list statuses" % i)
		# A stage's own rule (rule()): observe "" (a state goal) or an id, compare, judge_on.
		var own: Variant = stage.get("observe") if stage is Dictionary else null
		var observed: bool = (own != "") if stage is Dictionary and stage.has("observe") else missions.has("observe")
		if not stage is Dictionary:
			problems.append("missions.stages[%d] must be an object" % i)
		elif stage.has("observe") and not (own is String and (own == "" or ids.has(own))):
			problems.append("missions.stages[%d].observe must be \"\" or one of the observation ids" % i)
		elif stage.has("compare") and stage.compare not in COMPARES:
			problems.append("missions.stages[%d].compare must be greater, less or near" % i)
		elif rule({"missions": missions}, i).compare == "near" and not ((stage.get("tolerance") is float or stage.get("tolerance") is int) and stage.tolerance > 0.0):
			problems.append("missions.stages[%d].tolerance must be a number > 0 (compare near)" % i)
		elif not _valid_also(stage.get("also", []), ids):
			problems.append("missions.stages[%d].also must list {observe: an observation id, compare, threshold > 0, tolerance > 0 when near}" % i)
		elif stage.has("judge_on") and not _statuses(stage.judge_on):
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


## A non-empty list of status names.
static func _statuses(statuses: Variant) -> bool:
	return statuses is Array and not statuses.is_empty() and statuses.all(func(v: Variant) -> bool: return v is String and v != "")


## A stage's `also` (judge()): more rules of the same run, each on an observation.
static func _valid_also(also: Variant, ids: Dictionary) -> bool:
	if not also is Array:
		return false
	for extra in also:
		if not (extra is Dictionary and extra.get("observe") is String and ids.has(extra.observe)
				and str(extra.get("compare", "greater")) in COMPARES
				and (extra.get("threshold") is float or extra.get("threshold") is int) and extra.threshold > 0.0):
			return false
		if str(extra.get("compare", "greater")) == "near" and not ((extra.get("tolerance") is float or extra.get("tolerance") is int) and extra.tolerance > 0.0):
			return false
	return true


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
##  "answer": <a choice id>, "reason": <text>, "bridge"?: <Dugi's line from the answer to the mission>,
##  "bridge_face"?: <Story.FACES>}.
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
	if predict.has("question_face") and not predict.question_face in Story.FACES:
		problems.append("predict.question_face must be one of Story.FACES")
	# Dugi's bridge from the answer to the first mission (2026-10-29, optional): a text and its face.
	if predict.has("bridge") and not (predict.bridge is String and predict.bridge != ""):
		problems.append("predict.bridge must be a text")
	if predict.has("bridge_face") and not predict.bridge_face in Story.FACES:
		problems.append("predict.bridge_face must be one of Story.FACES")
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


# --- the stamps -----------------------------------------------------------------------------------

## The first not-yet-cleared stage, or -1 when all are cleared or the lab has no missions.
func stage() -> int:
	var stages: Array = missions(definition).get("stages", [])
	return stamps if stamps < stages.size() else -1


## The number of stages (one stamp each).
func stage_count() -> int:
	return (missions(definition).get("stages", []) as Array).size()


## The current stage's text ("" when none is left).
func text() -> String:
	return stage_text(stage())


## Stage `index`'s text ("" past the stages).
func stage_text(index: int) -> String:
	var stages: Array = missions(definition).get("stages", [])
	return str(stages[index].get("text", "")) if index >= 0 and index < stages.size() else ""


## Starts from the stamps already saved for this spot (a re-entered, finished place is not
## cleared again: no stamp is handed over and nothing celebrates). Called once (create()).
func start() -> void:
	var id := str(definition.get("id", ""))
	stamps = mini(int(store.stamps(id)), stage_count())
	_judged = stamps
	cleared = store.cleared(id) if _changes() else {}


## The run is seen in `status`: the static judge, then the stamp is saved and handed over (Puppy's
## win line, then stamp_earned) when it grew past what was already saved. True when this run earned a
## stamp (the attempt is then done).
func on_run_ended(status: String, run_lab: Experiment, observations: Dictionary) -> bool:
	var id := str(definition.get("id", ""))
	stamps = judge(definition, stamps, status, run_lab, observations, cleared)
	if stamps <= _judged:
		return false
	_judged = stamps
	store.save_stamps(id, stamps)
	if _changes():
		cleared = change_controls(definition, run_lab)
		store.save_cleared(id, cleared)
	if stamps >= stage_count():
		store.round_done(id)
	_hand_over(stamps)
	return true


## The screenshot demo (--demo-celebrate): the question goes unanswered and nothing waits for a result.
func demo_begin() -> void:
	predict_ended = true
	end_question()


## The demo's stamp `count` shown as earned, in memory only (nothing judged or saved).
func demo_stamp(count: int) -> void:
	stamps = count
	_hand_over(count)


func _hand_over(count: int) -> void:
	tell(count - 1, true)   # Puppy's win line of the stage just cleared (2026-10-29)
	stamp_earned.emit(count)


## A stage names a `change` (only then is the cleared run read and kept).
func _changes() -> bool:
	return (missions(definition).get("stages", []) as Array).any(func(s: Variant) -> bool: return s is Dictionary and not (s.get("change", []) as Array).is_empty())


# --- the flow on the screen ---------------------------------------------------------------------

## The round opens on the screen (once, after a restored state): Puppy's clue on the spot's first
## visit (Story), then Dugi's question, while stages are left and there is Dugi to ask. `dugi`: the
## screen has him (his box).
func open(dugi: bool) -> void:
	if stage() < 0 or not dugi:
		predict_ended = true   # the round is done (or no Dugi to ask): no question, no clue
		return
	var id := str(definition.get("id", ""))
	if Story.enabled and not store.clue_seen(id):
		_clue = Story.clue(definition)
	var question := predict(definition)
	if question.is_empty():
		predict_ended = true   # no question: the clue alone, if any
		_asking = _clue != ""
		return
	reason = str(question.get("reason", ""))
	_question = str(question.get("question", ""))
	_question_face = Story.face_or_default(question.get("question_face"))
	_asking = true


## Where the round is now.
func phase() -> Phase:
	if _asking:
		return Phase.CLUE if _clue != "" else Phase.ASKING
	return Phase.DONE if stage() < 0 else Phase.PLAYING


## The clue or the question is open (the screen's shield: nothing behind it takes a touch).
func asking() -> bool:
	return _asking


## Puppy's clue waits for its box [text, face] ([] when there is none to open).
func clue_to_open() -> Array:
	if not _asking or _clue == "" or _clue_open:
		return []
	return [_clue, Story.clue_face(definition)]


## The clue is in the box now (not yet read).
func clue_open() -> bool:
	return _asking and _clue != "" and _clue_open


## The screen opened the clue in Puppy's box: it is told once (kept in the store).
func clue_opened() -> void:
	_clue_open = true
	store.mark_clue(str(definition.get("id", "")))


## The clue was read (its box closed): Dugi asks next, or the round plays when there is no question.
func clue_read() -> void:
	_clue = ""
	_clue_open = false
	if _question == "":
		end_question()


## Dugi's question [text, face] (the text "" when the clue came alone).
func question_line() -> Array:
	return [_question, _question_face]


## The question's two picture choices ([] while only the clue is told).
func choices() -> Array:
	return predict(definition).get("choices", []) if _question != "" else []


## The child picked choice `choice_id`: the question ends, Dugi's bridge to the mission waits for his
## box (bridge_line()). Returns the picked choice's label ("" when the round was not asking).
func answer(choice_id: String) -> String:
	if not _asking:
		return ""
	var question := predict(definition)
	pick = choice_id
	reason_face = Story.REASON_FACE[choice_id == str(question.get("answer", ""))]
	var picked := ""
	for choice in question.get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			picked = str(choice.get("label", ""))
	end_question()
	var line := str(question.get("bridge", ""))
	if line != "" and stage() >= 0:
		_bridge = "%s %s" % [line, BRIDGE_FIRST if stage() == 0 else BRIDGE_NEXT]
		_bridge_face = Story.face_or_default(question.get("bridge_face"))
	return picked


## The clue or the question goes now, unanswered (a pull on the ball, a test): question_ended.
func end_question() -> void:
	if not _asking:
		return
	_asking = false
	_clue = ""
	_clue_open = false
	question_ended.emit()


## Dugi's bridge line still waiting for his box ("" once it opened or when there is none).
func bridge_line() -> String:
	return _bridge


## What Dugi says when his box opens now [text, face], taken once: the bridge first, else the
## prediction's reason after the first result line, else [] (his explanation of the stage, stage_say()).
func take_line() -> Array:
	if _bridge != "":
		var bridge := [_bridge, _bridge_face]
		_bridge = ""
		return bridge
	if reason != "" and _first_result:
		var told := [reason, reason_face]
		reason = ""
		return told
	return []


## The stage Dugi's explanation is about: the one this attempt cleared (its stamp just came), else the
## one being played; -1 when every stage is done.
func say_stage() -> int:
	if judged_run and stamps > 0:
		return stamps - 1
	return stage()


## The say of say_stage() [text, face] (missions.stages[i].say), or [] when it has none (the lab's kid.say).
func stage_say() -> Array:
	var s := say_stage()
	if s < 0:
		return []
	var entry: Dictionary = missions(definition).get("stages", [])[s]
	if str(entry.get("say", "")) == "":
		return []
	return [str(entry.say), Story.face_or_default(entry.get("say_face"))]


# --- attempts -----------------------------------------------------------------------------------

## A finger came down on one of the lab's objects (a drag, a pull, a press): an attempt that waits for its line.
func touched() -> void:
	_resolved = false
	_armed = true
	_miss_polls = 0


## A run action (`reset`: 다시 / 처음으로, its attempt gets no line; the stage's conditions are set again).
func acted(reset: bool) -> void:
	judged_run = false
	if reset:
		_disarm()
		_auto_pending = ConditionPicks.auto(definition)
	else:
		touched()


## A condition was changed: a new attempt, and the attempt in progress gets no line.
func condition_changed() -> void:
	judged_run = false
	_disarm()


## An object was put down or put back (a let-go hold, a placed ball): a new attempt, whose line waits
## unless this touch already had it.
func placed() -> void:
	judged_run = false
	if not _resolved:
		_armed = true
	_miss_polls = 0


## A slingshot throw or the rearm before it: a new attempt.
func threw() -> void:
	judged_run = false


func _disarm() -> void:
	_armed = false
	_resolved = false
	_miss_polls = 0


## Judges the current attempt while the lab's status is one of the stage's judge_on states and the
## lab is settled: the stamp from the formula values the panel shows and the lab's control values.
## Nothing is latched before a stamp; an attempt that earned one is done until the next attempt (or
## the lab back at "ready"). Once the run has its result (reveal_on) the prediction's question is over.
func judge_run() -> void:
	var status := lab.status()
	if status == "ready":
		judged_run = false
		return
	var judging := not judged_run and stage() >= 0 and status in judge_on(definition, stage())
	if not (judging or (not predict_ended and status in reveal_on(definition))) or not lab.settled():
		return
	var values := lab.observations()
	if judging and on_run_ended(status, lab, values):
		judged_run = true
	if result_in(definition, status, values):
		reveal()


## The first run has its result: the question is over (question_ended) and the strip shows the stage again (revealed).
func reveal() -> void:
	if predict_ended:
		return
	predict_ended = true
	end_question()
	revealed.emit()


## The attempt has no stamp and its run has come to one of the stage's miss_on results (settled, the
## finger up: `touching` false, the result number there) on MISS_POLLS polls in a row: Puppy's miss line, once.
func check_miss(touching: bool) -> void:
	if not _armed or judged_run:
		_miss_polls = 0
		return
	var s := stage()
	if s < 0 or touching or not lab.settled() or not missed(definition, s, lab.status(), lab.observations()):
		_miss_polls = 0
		return
	_miss_polls += 1
	if _miss_polls >= MISS_POLLS:
		tell(s, false)


## Puppy says stage `stage`'s `win` or `miss` line (result_told). The first line of a visit lets Dugi
## tell the prediction's reason right after it (reason_due).
func tell(stage_index: int, won: bool) -> void:
	_armed = false
	_resolved = true
	_miss_polls = 0
	var line := result_line(definition, stage_index, won)
	if not _first_result:
		_first_result = true
		if reason != "":   # (never without Dugi: open() asks nothing then)
			reason_due.emit()
	result_told.emit(stage_index, won, str(line[0]), str(line[1]))


## A stage became current (the screen shows it): its automatic conditions (missions.auto_conditions)
## are to be set once the lab is not mid-run.
func stage_shown() -> void:
	if ConditionPicks.auto(definition):
		_auto_pending = true


## The current stage's automatic conditions the lab does not have yet {control id: value}, taken once
## per stage or reset, and only while the lab is at rest (a stamp earned in the middle of a run does
## not snatch the balls back). The screen sets them the way a tap does; the round sets nothing.
func take_conditions() -> Dictionary:
	if not _auto_pending or lab.status() not in AT_REST:
		return {}
	_auto_pending = false
	var out := {}
	var values := ConditionPicks.auto_values(definition, stage())
	for id in values:
		if not condition_holds(values[id], lab.control_value(id)):
			out[id] = values[id]
	return out


## The run has its result (the formula's answers may show): `values` are the observations shown now.
func answer_shown(values: Dictionary) -> bool:
	return result_in(definition, lab.status(), values)


## The observation ids whose value reads "?" now (missions.hidden_until_end, until the result).
func hidden_observations(values: Dictionary) -> Array:
	return [] if answer_shown(values) else missions(definition).get("hidden_until_end", [])


## The graph series drawn empty now (missions.hidden_series_until_end, until the result).
func hidden_series(values: Dictionary) -> Array:
	return [] if answer_shown(values) else missions(definition).get("hidden_series_until_end", [])


# --- the progress store ---------------------------------------------------------------------------

## The app's progress (ProgressStore, user://progress.cfg; tests redirect its path).
class FileProgress:
	extends RefCounted

	func stamps(id: String) -> int:
		return ProgressStore.stamps(ProgressStore.load(), id)

	func cleared(id: String) -> Dictionary:
		return ProgressStore.cleared(id)

	func save_stamps(id: String, count: int) -> void:
		var progress := ProgressStore.load()
		progress[id] = count
		ProgressStore.save(progress)

	func save_cleared(id: String, controls: Dictionary) -> void:
		ProgressStore.save_cleared(id, controls)

	## Every stage is cleared: the map raises this spot's flag once (IslandHomeScreen) and its star
	## piece flies to the lookout once (StoryDirector).
	func round_done(id: String) -> void:
		ProgressStore.mark_flag_pending(id)
		ProgressStore.set_mark(ProgressStore.PIECES, id, false)

	func clue_seen(id: String) -> bool:
		return Story.clue_seen(id)

	func mark_clue(id: String) -> void:
		ProgressStore.set_mark(ProgressStore.CLUES, id, true)


## A progress kept in memory (tests): the same calls, no file.
class MemoryProgress:
	extends RefCounted

	var saved: Dictionary = {}       # id -> stamps
	var kept: Dictionary = {}        # id -> cleared control values
	var done: Array = []             # ids whose round was completed
	var clues: Dictionary = {}       # id -> true once its clue was told

	func stamps(id: String) -> int:
		return int(saved.get(id, 0))

	func cleared(id: String) -> Dictionary:
		return kept.get(id, {}).duplicate()

	func save_stamps(id: String, count: int) -> void:
		saved[id] = count

	func save_cleared(id: String, controls: Dictionary) -> void:
		kept[id] = controls.duplicate()

	func round_done(id: String) -> void:
		done.append(id)

	func clue_seen(id: String) -> bool:
		return clues.has(id)

	func mark_clue(id: String) -> void:
		clues[id] = true
