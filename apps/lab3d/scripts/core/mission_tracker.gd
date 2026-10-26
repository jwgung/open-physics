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
##   Without `observe` a stage is a state goal: reaching a `judge_on` status is the clear.
## - a stage's `conditions` (optional): {control id: option id | number | {"min"?, "max"?}} — the
##   lab's current control values the run must have been made with ("가벼운 상자", "20 kg 짐",
##   "출발 반지름 2 m"). Read through Experiment.control_value; a number matches within 1e-6, a range
##   is inclusive.
## - `reveal_on` (default `judge_on`): the statuses where the run has its result: the
##   hidden_until_end values (the formula's answer) read "?" until then, and the prediction's question
##   is over. With `observe`, the result is in once that value is a number too (the pendulum's period
##   after its first full swing).
##
## An attempt (what one stamp at most comes from): the run since the child last acted on the lab —
## an action ("공 놓기", "발사", "처음으로"), a condition change, an object put down or put back (a
## let-go handle, a placed ball), a slingshot throw — or since the lab was back at "ready". The
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
const COMPARES := ["greater", "less"]
## A number condition matches a control value within this (slider values sit on their grid).
const CONDITION_EPS := 1e-6

var definition: Dictionary
## The cleared stages so far (0..stages.size()); the current stage is stamps (one stamp per stage).
var stamps := 0
var _judged := 0   # the count last saved or handed over (start(): the stored one)
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


## The statuses a stage is judged on (the run's result states).
static func judge_on(definition: Dictionary) -> Array:
	return missions(definition).get("judge_on", DEFAULT_JUDGE_ON)


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
## status is a judge_on one, the lab is settled, the stage's conditions hold (the lab's control
## values) and, with `observe`, its formula value beats the stage's threshold (`compare`). Anything
## else keeps the count. The caller (the screen) passes the observations() the panels show.
static func judge(definition: Dictionary, stamps: int, status: String, lab: Experiment,
		observations: Dictionary) -> int:
	var block := missions(definition)
	var stages: Array = block.get("stages", [])
	if stamps >= stages.size() or status not in judge_on(definition) or not lab.settled():
		return stamps
	var stage: Dictionary = stages[stamps]
	if not conditions_met(stage.get("conditions", {}), lab):
		return stamps
	var observe := str(block.get("observe", ""))
	if observe != "":
		var value: Variant = observations.get(observe)
		if not _number(value):
			return stamps
		var threshold := float(stage.get("threshold", INF if block.get("compare") == "less" else -INF))
		var beaten := float(value) < threshold if block.get("compare", "greater") == "less" else float(value) > threshold
		if not beaten:
			return stamps
	return mini(stamps + 1, ProgressStore.MAX_STAMPS)


## The lab's control values match every condition (an option id, a number within CONDITION_EPS, or
## an inclusive {"min", "max"} range).
static func conditions_met(conditions: Dictionary, lab: Experiment) -> bool:
	for id in conditions:
		var want: Variant = conditions[id]
		var have: Variant = lab.control_value(id)
		if want is String:
			if str(have) != want:
				return false
		elif not _number(have):
			return false
		elif want is Dictionary:
			if float(have) < float(want.get("min", -INF)) - CONDITION_EPS or float(have) > float(want.get("max", INF)) + CONDITION_EPS:
				return false
		elif absf(float(have) - float(want)) > CONDITION_EPS:
			return false
	return true


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


## The run is seen in `status`: the static judge, then the stamp is saved (ProgressStore) and
## handed over through `progress` when it grew past what was already saved. True when this run
## earned a stamp (the screen's attempt is then done).
func on_run_ended(status: String, lab: Experiment, observations: Dictionary) -> bool:
	stamps = judge(definition, stamps, status, lab, observations)
	if stamps <= _judged:
		return false
	_judged = stamps
	var store := ProgressStore.load()
	store[str(definition.get("id", ""))] = stamps
	ProgressStore.save(store)
	if progress.is_valid():
		progress.call(str(definition.get("id", "")), stamps)
	return true
