## When the hand guide (HandGuide) shows the gesture: once the first time a child is at a lab (the
## first quiet moment after the clue and the question), and again after IDLE_S quiet seconds without a
## touch while a stage is being played. A touch at any time stops the wait (and a first touch before
## the guide means the child already knows: no first guide). No clock or node: the screen steps it.
class_name GuideCoach
extends RefCounted

## The first guide comes this long after the screen is quiet (the question just closed).
const FIRST_DELAY_S := 0.6
## A stage being played and nothing touched for this long: the guide again.
const IDLE_S := 8.0

## The first guide was shown (or the child touched first): kept in the progress store by the screen.
var seen := false
var _first_wait := 0.0
var _idle := 0.0


func _init(already_seen := false) -> void:
	seen = already_seen


## One step of `delta` s. `quiet`: nothing else wants the child's eyes (no question, dialogue, sidebar,
## celebration or card, the guide itself not playing). `touched`: a finger was on the lab, the view or
## a control in this step. `stage_open`: a mission stage is being played (only then does the guide
## repeat). Returns "first", "idle" or "" (nothing to show now).
func step(delta: float, quiet: bool, touched: bool, stage_open: bool) -> String:
	if touched:
		seen = true
		_first_wait = 0.0
		_idle = 0.0
		return ""
	if not quiet:
		_first_wait = 0.0
		_idle = 0.0
		return ""
	if not seen:
		_first_wait += delta
		if _first_wait >= FIRST_DELAY_S:
			seen = true
			_idle = 0.0
			return "first"
		return ""
	if not stage_open:
		_idle = 0.0
		return ""
	_idle += delta
	if _idle >= IDLE_S:
		_idle = 0.0
		return "idle"
	return ""
