## Easy controls (2026-10-27 user decision "조작이 쉬운게 중요"), every lab on its real screen:
## - the mission's picture buttons (ConditionPicks): per stage the row shows exactly the controls the
##   stage's conditions name (not one every stage asks the same of), each with a button that fits
##   and one that does not, at most four; none for a stage without conditions or a finished round;
##   hidden while Dugi asks.
## - a tap is the sidebar's change: the control, the sidebar widget, the formula values and the run
##   after it are the same as the sidebar chip / slider making that change; a sidebar change lights
##   the matching button.
## - layout, phone and tablet: the row stays in the view and clear of the title bar, the top button,
##   the key card, the mission strip and the action buttons (다시 and the main one); while Dugi talks
##   it hides while his box is open and comes back in its place (2026-10-29); beside the open sidebar it
##   never reaches the actions.
## - one drag per lab: the objects a finger picks up are the lab's one gesture (KEPT: a drag, a
##   slingshot pull or, since 2026-10-28, a press and hold); the others are never picked up (a press
##   on them starts nothing), and no game lab shows a height handle.
## - the grab radius: a press within pick_radius() (at least 72 UI units) of a draggable object starts
##   its drag; a little farther, on empty ground, picks nothing.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)
const GRAB_MIN := 72.0
## Per lab: the objects a finger still picks up (one gesture per lab).
const KEPT := {
	"free-fall": ["drop_red", "drop_yellow"],
	"projectile": ["ball"],
	"collision": ["ball_a"],
	"spring": ["ball"],
	"friction": ["box"],
	"rotation": ["effort"],
	"orbit": ["planet"],
	"buoyancy": ["drum"],
	"constraints": ["rope", "rod"],
	"pulley": ["rope"],
	"incline-friction": ["box"],
}
const FRAMES_AFTER := 30   # physics steps compared after a tap and the same sidebar change


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	for id in KEPT:
		await check_rows(id)
	for id in KEPT:
		await check_tap_is_sidebar(id)
	for id in KEPT:
		for size in [PHONE, TABLET]:
			await check_layout(id, size)
	for id in KEPT:
		await check_drags(id)


func _open(id: String, size := TABLET, sidebar := false) -> Control:
	DirAccess.remove_absolute(ProgressStore.path)   # stage 1, the question asked
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	if sidebar:
		screen.open_sidebar(false)
	for i in 3:
		await tree.process_frame
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProgressStore.path)


## The controls stage `stage` asks the child to set (its conditions, without the ones every stage
## asks the same of).
func _asked(definition: Dictionary, stage: int) -> Array:
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	var fixed := ConditionPicks.fixed_controls(definition)
	var out := []
	for control in definition.controls:
		if stages[stage].get("conditions", {}).has(control.id) and not control.id in fixed:
			out.append(control.id)
	return out


# --- the row per stage ----------------------------------------------------------------------------

func check_rows(id: String) -> void:
	var screen := await _open(id)
	var definition: Dictionary = screen.definition
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	var problems := []
	if screen._asking and screen.picks_shown():
		problems.append("shown while Dugi asks")
	screen._end_question()
	for stage in stages.size() + 1:
		screen._show_stamps(stage)
		for i in 2:
			await tree.process_frame
		var buttons: Array = screen.pick_buttons()
		var want := _asked(definition, stage) if stage < stages.size() else []
		var have := []
		for pick in buttons:
			if not pick.control in have:
				have.append(pick.control)
		if have != want:
			problems.append("stage %d: buttons for %s, the stage asks %s" % [stage + 1, str(have), str(want)])
		if want.is_empty():
			if screen.picks_shown():
				problems.append("stage %d: a row without a condition" % (stage + 1))
			continue
		if not screen.picks_shown() or buttons.size() > ConditionPicks.MAX_BUTTONS:
			problems.append("stage %d: row shown %s with %d buttons" % [stage + 1, screen.picks_shown(), buttons.size()])
		for control in want:
			var holds: Array = buttons.filter(func(p: Dictionary) -> bool: return p.control == control) \
				.map(func(p: Dictionary) -> bool: return MissionTracker.condition_holds(stages[stage].conditions[control], p.preset.value))
			if not (holds.has(true) and holds.has(false)):
				problems.append("stage %d: %s needs a button that fits and one that does not" % [stage + 1, control])
		for pick in buttons:
			var b: Button = pick.button
			var labels := b.find_children("*", "Label", true, false)
			if b.size.x < screen.PICK_SIZE.x - 1.0 or b.size.y < screen.PICK_SIZE.y - 1.0 or labels.size() != 1 or (labels[0] as Label).text == "" \
					or b.button_pressed != ConditionPicks.selected(pick.preset, screen.experiment.control_value(pick.control)):
				problems.append("stage %d: %s is not a big picture button with its words and the current value lit" % [stage + 1, b.name])
	expect.call(problems.is_empty(), "easy controls (%s): per stage the picture buttons are exactly the stage's conditions (one fits, one does not, at most 4); none without conditions, at the end or while Dugi asks" % id,
		"; ".join(problems))
	await _close(screen)


# --- a tap = the sidebar's change ---------------------------------------------------------------

func check_tap_is_sidebar(id: String) -> void:
	var definition := ExperimentRegistry.find(id)
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	var stage := -1
	for i in stages.size():
		if not ConditionPicks.groups(definition, i).is_empty():
			stage = i
			break
	if stage < 0:
		var none := await _open(id)
		none._end_question()
		expect.call(none.pick_buttons().is_empty() and not none.picks_shown(), "easy controls (%s): no stage asks a condition: no picture buttons" % id, "")
		await _close(none)
		return
	# Each button of the stage, on its own screen, against the sidebar making the same change.
	var problems := []
	var count := 0
	for group in ConditionPicks.groups(definition, stage):
		for preset in group.presets:
			var by_tap := await _run_change(id, stage, group.control, preset, true)
			var by_sidebar := await _run_change(id, stage, group.control, preset, false)
			count += 1
			if by_tap != by_sidebar:
				problems.append("%s = %s: tap %s, sidebar %s" % [group.control, str(preset.value), str(by_tap.slice(0, 2)), str(by_sidebar.slice(0, 2))])
	# A sidebar change lights the matching button.
	var screen := await _open(id)
	screen._end_question()
	screen._show_stamps(stage)
	var last: Dictionary = screen.pick_buttons()[-1]
	_sidebar_change(screen, last.control, last.preset.value)
	var lit: bool = (last.button as Button).button_pressed and screen.pick_buttons().all(func(p: Dictionary) -> bool:
		return p.control != last.control or p == last or not (p.button as Button).button_pressed)
	expect.call(problems.is_empty() and count >= 2 and lit,
		"easy controls (%s): a picture button tap sets its control the sidebar's way (control, sidebar widget, formula values and %d steps after it the same); a sidebar change lights its button" % [id, FRAMES_AFTER],
		"; ".join(problems) + ("" if lit else " (sidebar change not lit)"))
	await _close(screen)


## [the control value, the sidebar widget's value, the observations and status after the change and
## for FRAMES_AFTER physics steps] of `control` = `preset` made by a tap (`tap`) or the sidebar.
func _run_change(id: String, stage: int, control: String, preset: Dictionary, tap: bool) -> Array:
	var screen := await _open(id)
	screen._end_question()
	screen._show_stamps(stage)
	if tap:
		for pick in screen.pick_buttons():
			if pick.control == control and pick.preset == preset:
				(pick.button as Button).pressed.emit()
	else:
		_sidebar_change(screen, control, preset.value)
	var lab: Experiment = screen.experiment
	var widgets: Dictionary = screen._control_widgets[control]
	var widget: Variant = widgets.slider.value if widgets.has("slider") else widgets.buttons.keys().filter(func(k: String) -> bool: return widgets.buttons[k].button_pressed)
	var out := [str(lab.control_value(control)), str(widget)]
	for k in FRAMES_AFTER:
		out.append(str(lab.observations()) + lab.status())
		await tree.physics_frame
	await _close(screen)
	return out


## The sidebar's own way: the chip's press, or the slider moved (value_changed).
func _sidebar_change(screen: Control, control: String, value: Variant) -> void:
	var widgets: Dictionary = screen._control_widgets[control]
	if widgets.has("slider"):
		var slider: HSlider = widgets.slider
		if slider.value == float(value):
			screen._set_control(control, value)   # the same value: the slider would not signal
		else:
			slider.value = float(value)
	else:
		(widgets.buttons[value] as Button).pressed.emit()


# --- layout -----------------------------------------------------------------------------------------

func check_layout(id: String, size: Vector2) -> void:
	var screen := await _open(id, size)
	var problems := []
	if screen.pick_buttons().is_empty():
		screen._end_question()
		expect.call(not screen.picks_shown(), "easy controls (%s, %s): no picture buttons to lay out" % [id, size], "")
		await _close(screen)
		return
	var lab: Experiment = screen.experiment
	# The widest stage (most buttons).
	var stages: Array = MissionTracker.missions(screen.definition).get("stages", [])
	var widest := 0
	for i in stages.size():
		if ConditionPicks.groups(screen.definition, i).reduce(func(n: int, g: Dictionary) -> int: return n + g.presets.size(), 0) \
				> ConditionPicks.groups(screen.definition, widest).reduce(func(n: int, g: Dictionary) -> int: return n + g.presets.size(), 0):
			widest = i
	# While Dugi asks: his question and picture buttons, no row.
	if screen._asking and screen.picks_shown():
		problems.append("row shown with Dugi's question")
	if screen._choices != null and screen.picks_shown() and screen._picks_row.get_rect().intersects(screen._choices.get_rect()):
		problems.append("row over Dugi's picture buttons")
	screen._end_question()
	screen._show_stamps(widest)
	for i in 2:
		await tree.process_frame
	var view_rect := Rect2(Vector2.ZERO, screen.view.size)
	var chrome := {"title": screen._title_bar, "top button": screen._top_buttons, "key card": screen._key_row,
		"mission strip": screen._mission_pill, "actions": screen._action_row}
	var row: Rect2 = screen._picks_row.get_rect()
	if not screen.picks_shown():
		problems.append("row hidden on a free view")
	if not view_rect.encloses(row):
		problems.append("row %s outside the view" % row)
	for name in chrome:
		if chrome[name] != null and chrome[name].visible and row.intersects(chrome[name].get_rect()):
			problems.append("row over the %s" % name)
	for button in screen._action_row.get_children():
		if row.intersects(Rect2(screen._action_row.position + button.position, button.size)):
			problems.append("row over %s" % button.text)
	# Dugi talks (2026-10-29 user "좌측 버튼이 딸려 오네"): the row hides while his box is open and comes
	# back where it was when it closes; the box never moves for it.
	if screen.cast != null and screen.cast.dugi != null:
		var before_row: Rect2 = screen._picks_row.get_rect()
		screen.cast.dugi.explain(lab.explain_point)
		for k in int(DugiActor.RAISE_S * 60.0) + 4:
			await tree.process_frame
		var box: DialogueBox = screen.dialogue
		if not (box.active and box.visible):
			problems.append("no dialogue to test")
		if screen.picks_shown():
			problems.append("row shown while Dugi talks")
		var rects_open := str(box.rects())
		await tree.process_frame
		if str(box.rects()) != rects_open:
			problems.append("the box moved while the row hid")
		box.close(true)
		screen.cast.dugi.stop()
		for k in 2:
			await tree.process_frame
		if not screen.picks_shown() or screen._picks_row.get_rect() != before_row:
			problems.append("row not back in its place after the box closed (%s, was %s)" % [screen._picks_row.get_rect(), before_row])
	await _close(screen)
	# Beside the open sidebar: shown only where it does not reach the actions.
	var side := await _open(id, size, true)
	side._end_question()
	side._show_stamps(widest)
	for i in 2:
		await tree.process_frame
	if side.picks_shown() and side._picks_row.get_rect().intersects(side._action_row.get_rect().grow(4.0)):
		problems.append("row over the actions beside the open sidebar")
	await _close(side)
	expect.call(problems.is_empty(), "easy controls (%s, %s): the picture buttons stay in the view, clear of the title, key card, mission strip, 다시 and main buttons, Dugi's question; hidden while his box is open, back in place after (and clear of the actions beside the open sidebar)" % [id, "phone" if size == PHONE else "tablet"],
		"; ".join(problems))


# --- one drag per lab and its grab radius ----------------------------------------------------------

func check_drags(id: String) -> void:
	var screen := await _open(id)
	screen._end_question()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var problems := []
	if m.draggable_ids() != KEPT[id]:
		problems.append("drags %s, want %s" % [str(m.draggable_ids()), str(KEPT[id])])
	for rule_id in m.rules:
		if m.rules[rule_id].height_max > 0.0:
			problems.append("%s has a height handle" % rule_id)
		if rule_id in KEPT[id]:
			continue
		var body := lab.manipulation_body(rule_id)
		if body != null and m._pick(screen.view_point(body.global_position)) == rule_id:
			problems.append("%s is still picked up" % rule_id)
	var r: float = m.pick_radius()
	if r < GRAB_MIN:
		problems.append("pick radius %.0f" % r)
	for kept in KEPT[id]:
		var body := lab.manipulation_body(kept)
		if body == null:
			problems.append("%s has no body" % kept)
			continue
		var at: Vector2 = screen.view_point(lab.manipulation_pick_point(kept))
		# Within the radius (straight up on the screen, off the object itself): the press starts its gesture.
		m.handle_pointer("press", at + Vector2(0.0, -(r - 6.0)))
		if m.active_id != kept or m.mode == "":
			problems.append("%s: a press %.0f units above it started '%s' (%s)" % [kept, r - 6.0, m.active_id, m.mode])
		m.cancel()
		m.select("")
		var far: String = m._pick(at + Vector2(0.0, -(r + 14.0)))
		if far == kept:
			problems.append("%s picked from %.0f units" % [kept, r + 14.0])
	if id == "projectile":
		# The slingshot's own press: unchanged (a tap shows no handle, a press on the ball pulls).
		var ball: Vector2 = screen.view_point(lab.ball_center())
		m.handle_pointer("press", ball)
		var pulls: bool = m.mode == "slingshot"
		m.handle_pointer("release", ball)
		if not pulls or m._knob.visible:
			problems.append("the slingshot press changed")
	expect.call(problems.is_empty(), "easy controls (%s): one drag gesture (%s), the other objects never picked up, no height handle; a press within %.0f units (>= %.0f) starts the drag, farther picks nothing" % [id, ", ".join(KEPT[id]), r, GRAB_MIN],
		"; ".join(problems))
	await _close(screen)
