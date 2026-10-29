## Game missions (Plan G1, G2): the easy thresholds ("3 m보다 멀리 보내기!"). The tracker is progress
## only — it reads the lab's status(), its control values and the observation values the screen
## already polled, and saves a stamp when the child clears a stage. It never sets a control, runs an
## action or touches a body, so the engine bodies, the formula values and the displayed numbers are
## the same with or without it (tests/mission_checks.gd, tests/lab_mission_checks.gd: step for step).
##
## The definition's `missions` block (validated by ExperimentRegistry):
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
##   `"observe": ""`). A key the stage leaves out is the block's (MissionTracker.rule).
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
## Stamps live in the ProgressStore (user://progress.cfg), read once at start(); the tracker's
## `stamps` is what it last judged, so a judgement reads no file and a stamp is saved once.
class_name MissionTracker
extends RefCounted

## The status that ends a run with a result when the definition names none (the projectile's landing).
const DEFAULT_JUDGE_ON := ["landed"]
const COMPARES := ["greater", "less", "near"]
## A number condition matches a control value within this (slider values sit on their grid).
const CONDITION_EPS := 1e-6
## The decimals a child reads on a key card (ExperimentScreen.kid_value): a stage judges that number.
const CARD_PLACES := 1

var definition: Dictionary
## The cleared stages so far (0..stages.size()); the current stage is stamps (one stamp per stage).
var stamps := 0
var _judged := 0   # the count last saved or handed over (start(): the stored one)
## The control values of the run that cleared the last stage (a stage's `change`; start(): the stored ones).
var cleared: Dictionary = {}
## (id: String, stamps: int) when a stage is cleared; the screen reacts (the stamp animation).
var progress: Callable


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


## The run has its result: the status is a reveal_on one and, with `observe`, its value is a number.
static func result_in(definition: Dictionary, status: String, observations: Dictionary) -> bool:
	if status not in reveal_on(definition):
		return false
	var observe := str(missions(definition).get("observe", ""))
	return observe == "" or _number(observations.get(observe))


## The stored stamp count of `definition`'s spot (0 when it has no missions or none stored).
static func stamps_of(definition: Dictionary) -> int:
	var stages: Array = missions(definition).get("stages", [])
	return mini(ProgressStore.stamps(ProgressStore.load(), str(definition.get("id", ""))),
		stages.size())


## The new stamp count after a run seen in `status` with `stamps` cleared so far: one more when the
## status is one of the stage's judge_on, the lab is settled, the stage's conditions hold (the lab's
## control values) and, with an `observe` (rule: the stage's or the block's), its formula value beats
## the stage's threshold (`compare`). Anything else keeps the count. The caller (the screen) passes the observations() the panels show.
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


## The first not-yet-cleared stage, or -1 when all are cleared or the lab has no missions.
func stage() -> int:
	var stages: Array = missions(definition).get("stages", [])
	return stamps if stamps < stages.size() else -1


## The current stage's text ("" when none is left).
func text() -> String:
	var s := stage()
	if s < 0:
		return ""
	return str((missions(definition).get("stages", []) as Array)[s].get("text", ""))


## Starts from the stamps already saved for this spot (a re-entered, finished place is not
## cleared again: no stamp is handed over and nothing celebrates). The screen calls it once.
func start() -> void:
	stamps = stamps_of(definition)
	_judged = stamps
	cleared = ProgressStore.cleared(str(definition.get("id", ""))) if _changes() else {}


## The run is seen in `status`: the static judge, then the stamp is saved (ProgressStore) and
## handed over through `progress` when it grew past what was already saved. True when this run
## earned a stamp (the screen's attempt is then done).
func on_run_ended(status: String, lab: Experiment, observations: Dictionary) -> bool:
	var id := str(definition.get("id", ""))
	stamps = judge(definition, stamps, status, lab, observations, cleared)
	if stamps <= _judged:
		return false
	_judged = stamps
	var store := ProgressStore.load()
	store[id] = stamps
	ProgressStore.save(store)
	if _changes():
		cleared = change_controls(definition, lab)
		ProgressStore.save_cleared(id, cleared)
	if stamps >= (missions(definition).get("stages", []) as Array).size():
		ProgressStore.mark_flag_pending(id)   # the map raises this spot's flag once (IslandHomeScreen)
		ProgressStore.set_mark(ProgressStore.PIECES, id, false)   # its star piece flies to the lookout once (StoryDirector)
	if progress.is_valid():
		progress.call(id, stamps)
	return true


## A stage names a `change` (only then is the cleared run read and kept).
func _changes() -> bool:
	return (missions(definition).get("stages", []) as Array).any(func(s: Variant) -> bool: return s is Dictionary and not (s.get("change", []) as Array).is_empty())
