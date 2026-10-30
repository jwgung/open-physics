## A lab's sounds (2026-10-28): listens to what the shell already reads from the lab and asks
## SoundBoard for an effect. Like IslandCast it only reads: the lab's status() once a frame (a change
## of it, by RULES) and its `impact` signal (the same visual hint the camera dip uses). It never
## touches a body, a formula value or a displayed number, and the lab's tree is the same with or
## without it (the shell adds it beside the lab).
##
## An impact is a splash when the lab's `splashes` count just went up (buoyancy), the two balls'
## bump when `hit_reactions` did (collision), the box's stop when the run just ended at the bumper
## (friction, status "end"), and otherwise a landing.
class_name LabSounds
extends Node

## Per lab id: [from statuses ("*" = any), to statuses, sound]. A status change that matches no rule
## is silent (a drum bobbing about its floating depth, a lever held and moved, ...).
const RULES := {
	"free-fall": [[["ready"], ["falling", "floating"], &"launch"]],
	"projectile": [[["ready"], ["flying", "floating"], &"launch"]],
	"collision": [[["ready"], ["moving"], &"launch"]],
	"spring": [[["ready", "held"], ["moving"], &"spring"]],
	"buoyancy": [[["ready", "held"], ["moving"], &"launch"]],
	"orbit": [[["ready", "held"], ["orbiting", "leaving"], &"launch"]],
	"constraints": [[["ready", "held"], ["swinging", "weightless"], &"launch"]],
	"incline-friction": [[["ready", "holding"], ["sliding"], &"launch"], [["sliding"], ["holding"], &"stop"]],
	"friction": [[["holding"], ["sliding"], &"launch"], [["sliding"], ["holding"], &"stop"]],
	"pulley": [[["*"], ["top"], &"stop"]],
	"rotation": [[["*"], ["lifted"], &"launch"]],
}
## Counters a lab raises right before its impact: the impact is that sound.
const COUNTERS := {"splashes": &"splash", "hit_reactions": &"bump"}

var experiment: Experiment
var lab_id := ""
var _status := ""
var _counts: Dictionary = {}


static func create(lab: Experiment) -> LabSounds:
	var sounds := LabSounds.new()
	sounds.name = "LabSounds"
	sounds.experiment = lab
	sounds.lab_id = lab.definition.id()
	return sounds


func _ready() -> void:
	if experiment == null:
		return
	experiment.impact.connect(_on_impact)
	_status = experiment.status()
	for property in COUNTERS:
		if property in experiment:
			_counts[property] = int(experiment.get(property))


func _process(_delta: float) -> void:
	watch()


## Follows the lab's status (tests call it after exact steps).
func watch() -> void:
	if experiment == null or not is_instance_valid(experiment):
		return
	var now := experiment.status()
	if now == _status:
		return
	var id := sound_for(lab_id, _status, now)
	_status = now
	if id != &"":
		SoundBoard.play(id)


## The sound of a status change of lab `id` (&"" = none).
static func sound_for(id: String, from: String, to: String) -> StringName:
	for rule in RULES.get(id, []):
		if (rule[0].has("*") or rule[0].has(from)) and rule[1].has(to):
			return rule[2]
	return &""


func _on_impact(_strength: float) -> void:
	SoundBoard.play(impact_sound())


## What the impact just emitted is (reads the lab's counters and status).
func impact_sound() -> StringName:
	var id: StringName = &"land"
	for property in _counts:
		var count := int(experiment.get(property))
		if count > int(_counts[property]):
			id = COUNTERS[property]
		_counts[property] = count
	if id == &"land" and lab_id == "friction" and experiment.status() == "end":
		id = &"stop"
	return id
