## Game missions (Plan G1): the easy thresholds ("3 m보다 멀리 보내기!"). The tracker is progress
## only — it reads the lab's status() and the observation value the screen already polled, and
## saves a stamp when the child clears a stage. It never sets a control, runs an action or touches
## a body, so the engine bodies, the formula values and the displayed numbers are the same with
## or without it (tests/mission_checks.gd: the trajectory is step for step).
##
## The definition's `missions` block (validated by ExperimentRegistry):
##   "missions": { "observe": "range",
##                 "stages": [ {"threshold": 3.0, "text": "3 m보다 멀리 보내기!"}, ... ] }
## `observe` is an observation id of the definition; the run's value is judged against the current
## stage's threshold when the lab's status is the success status (the lab's landed state,
## "landed") and the lab is settled (`settled()`: the engine has finished the landing, not merely
## reached the formula landing within the slack). One throw clears at most the current stage (one
## stamp): a throw that falls short (or a run with no number, e.g. "닿지 않아요") changes
## nothing, and the next throw is judged against the next stage. The stamps are the child's
## collection — 3 m past, then 5 m past, then 7 m past (stamps: 0..MAX_STAMPS, one per stage).
##
## Stamps live in the ProgressStore (user://progress.cfg); the tracker's `stamps` is what it last
## judged, so a run's result is recorded once (the settled status is reported at the end of the
## run, not flickered through on every status change).
class_name MissionTracker
extends RefCounted

## The status that ends a run with a result (the lab's landed state).
const SUCCESS_STATUS := "landed"

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


## The definition's prediction (the question, the two choices, the reason) or {} when it has
## none. (Plan G4: Dugi asks before the run and explains the reason after it.)
static func predict(definition: Dictionary) -> Dictionary:
	var predict: Variant = definition.get("predict")
	return predict if predict is Dictionary else {}


## The stored stamp count of `definition`'s spot (0 when it has no missions or none stored).
static func stamps_of(definition: Dictionary) -> int:
	var stages: Array = missions(definition).get("stages", [])
	return mini(ProgressStore.stamps(ProgressStore.load(), str(definition.get("id", ""))),
		stages.size())


## The run ended (the lab's status is its final state): the new stamp count — one more when it is
## the success status, the lab is settled (`settled()`: the engine finished the landing, not
## merely reached the formula landing within the slack) and the formula value of `observe` beats
## the current threshold; a throw that falls short (or a run with no number, e.g. "닿지 않아요")
## keeps the count. A throw clears at most the current stage. The caller (the screen) passes the
## observations() the panels show.
static func judge(definition: Dictionary, status: String, lab: Experiment,
		observations: Dictionary) -> int:
	var stages: Array = missions(definition).get("stages", [])
	var stamps := stamps_of(definition)
	if stamps >= stages.size() or status != SUCCESS_STATUS or not lab.settled():
		return stamps
	var value: Variant = observations.get(str(missions(definition).get("observe", "")))
	if not (value is int or value is float) or not is_finite(float(value)):
		return stamps
	if float(value) > float(stages[stamps].get("threshold", -INF)):
		return mini(stamps + 1, ProgressStore.MAX_STAMPS)
	return stamps


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


## A run ended (the lab's status is its final state): the static judge, then the stamp is saved
## (ProgressStore) and handed over through `progress` when it grew past what was already saved.
func on_run_ended(status: String, lab: Experiment, observations: Dictionary) -> void:
	stamps = judge(definition, status, lab, observations)
	if stamps > _judged:
		_judged = stamps
		var store := ProgressStore.load()
		store[str(definition.get("id", ""))] = stamps
		ProgressStore.save(store)
		if progress.is_valid():
			progress.call(str(definition.get("id", "")), stamps)

