## The mission's picture buttons (2026-10-27 user decision "조작이 쉬운게 중요"): which conditions the
## current stage needs, as a few big buttons at the bottom of the lab screen. Before them, every
## stage's condition (the moon, 2 ropes, the small drum, the steel slide) was a chip or a slider
## inside "자세히". A button sets its control through the screen's own condition path (the same
## _set_control as the sidebar's chips and sliders), so the run is the one the sidebar would make.
##
## The definition names the buttons per control in kid.picks:
##   "kid": {"picks": {"gravity": [{"value": "earth", "label": "지구", "picture": "earth"}, ...],
##                     "mass": [{"value": 80.0, "label": "80킬로그램", "picture": "weight", "size": 0.6}, ...]}}
## - `value`: an option id (choice) or a slider value inside its range on its step.
## - `label`: a few words a 7-year-old reads; `picture`: a PickPictures kind (optional `size` 0..1 and
##   `count`, what the drawing shows: a bigger box, 4 ropes).
## A stage shows the controls its `conditions` name, except a control every stage asks the same of
## (the lever's and the pulley's 20 kg load: nothing to choose there). Each shown control has at
## least one button that satisfies the stage and one that does not (the child still chooses);
## with two controls each shows two buttons (the satisfying one and its neighbour), so a row never
## has more than MAX_BUTTONS. No stage conditions (the projectile's throws, a finished round): no row.
## Read only: nothing here sets a control or moves a body.
class_name ConditionPicks
extends RefCounted

const MAX_BUTTONS := 4
const MAX_GROUPS := 2


## The definition's kid.picks ({} when it has none).
static func picks(definition: Dictionary) -> Dictionary:
	var kid: Variant = definition.get("kid")
	var p: Variant = kid.get("picks") if kid is Dictionary else null
	return p if p is Dictionary else {}


## The controls every stage asks the same value of (no choice for the child: no buttons).
static func fixed_controls(definition: Dictionary) -> Array:
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	var out := []
	for control in definition.get("controls", []):
		var id: String = control.id
		var wants := stages.map(func(s: Variant) -> Variant: return (s as Dictionary).get("conditions", {}).get(id))
		if not stages.is_empty() and wants.all(func(w: Variant) -> bool: return w != null and str(w) == str(wants[0])):
			out.append(id)
	return out


## The button groups of stage `stage` (-1 or past the last: none), in the definition's control order:
## [{"control": id, "want": the stage's condition, "presets": [the kid.picks entries shown]}].
static func groups(definition: Dictionary, stage: int) -> Array:
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	if stage < 0 or stage >= stages.size():
		return []
	var conditions: Dictionary = stages[stage].get("conditions", {})
	var fixed := fixed_controls(definition)
	var all := picks(definition)
	var out := []
	for control in definition.get("controls", []):
		var id: String = control.id
		if conditions.has(id) and not id in fixed and all.has(id) and not out.any(func(g: Dictionary) -> bool: return g.control == id):
			out.append({"control": id, "want": conditions[id], "presets": all[id]})
	var per := MAX_BUTTONS if out.size() <= 1 else floori(float(MAX_BUTTONS) / out.size())
	for group in out:
		group.presets = _shown(group.presets, group.want, per)
	return out


## At most `per` of `presets`, keeping their order: all of them when they fit, else the first one
## that satisfies `want` and the nearest ones that do not (the next first, then the one before).
static func _shown(presets: Array, want: Variant, per: int) -> Array:
	if presets.size() <= per:
		return presets
	var hit := -1
	for i in presets.size():
		if MissionTracker.condition_holds(want, presets[i].value):
			hit = i
			break
	if hit < 0:
		return presets.slice(0, per)
	var keep := [hit]
	var step := 1
	while keep.size() < per and step < presets.size():
		for j in [hit + step, hit - step]:
			if keep.size() < per and j >= 0 and j < presets.size() and not MissionTracker.condition_holds(want, presets[j].value):
				keep.append(j)
		step += 1
	keep.sort()
	return keep.map(func(i: int) -> Dictionary: return presets[i])


## The button of `preset` is the control's current value `have` (highlighted).
static func selected(preset: Dictionary, have: Variant) -> bool:
	return MissionTracker.condition_holds(preset.value, have)


## kid.picks: every stage condition a child must change has buttons, each value is a real setting of
## its control, each picture is known, and every stage's buttons hold one value that satisfies it
## and one that does not.
static func validate(definition: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var kid: Variant = definition.get("kid")
	if not kid is Dictionary or not kid.has("picks"):
		return problems
	if not kid.picks is Dictionary:
		problems.append("kid.picks must be an object")
		return problems
	var controls := {}
	for control in definition.get("controls", []):
		controls[control.id] = control
	for id in kid.picks:
		var list: Variant = kid.picks[id]
		if not controls.has(id):
			problems.append("kid.picks.%s is not a control" % id)
			continue
		if not (list is Array and list.size() >= 2 and list.size() <= MAX_BUTTONS):
			problems.append("kid.picks.%s must list 2..%d buttons" % [id, MAX_BUTTONS])
			continue
		for preset in list:
			if not (preset is Dictionary and preset.get("label") is String and preset.label != ""
					and preset.get("picture") in PickPictures.KINDS and _real_value(controls[id], preset.get("value"))):
				problems.append("kid.picks.%s: each button needs a value of the control, a label and a picture (PickPictures.KINDS)" % id)
				break
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	var fixed := fixed_controls(definition)
	for i in stages.size():
		var conditions: Dictionary = stages[i].get("conditions", {})
		var asked := conditions.keys().filter(func(id: Variant) -> bool: return not id in fixed)
		if asked.size() > MAX_GROUPS:
			problems.append("missions.stages[%d]: more than %d conditions to pick" % [i, MAX_GROUPS])
		for id in asked:
			if not kid.picks.has(id):
				problems.append("missions.stages[%d]: no kid.picks for %s" % [i, id])
		for group in groups(definition, i):
			var holds: Array = group.presets.map(func(p: Dictionary) -> bool: return MissionTracker.condition_holds(group.want, p.value))
			if not (holds.has(true) and holds.has(false)):
				problems.append("missions.stages[%d]: the %s buttons need one that fits and one that does not" % [i, group.control])
	return problems


## `value` is a setting of `control`: one of its options, or a slider value in its range on its step.
static func _real_value(control: Dictionary, value: Variant) -> bool:
	if control.get("type") == "choice":
		return value is String and control.get("options", []).any(func(o: Dictionary) -> bool: return o.get("id") == value)
	if not (value is float or value is int):
		return false
	var lo := float(control.get("min", -INF))
	var step := float(control.get("step", 0.0))
	var cells := (float(value) - lo) / step if step > 0.0 else 0.0
	return float(value) >= lo - 1e-9 and float(value) <= float(control.get("max", INF)) + 1e-9 and absf(cells - roundf(cells)) < 1e-6
