## Plan G4 — the projectile's mission round, start to end on one screen: the stamp strip, Dugi asking
## the prediction in his dialogue box with two picture buttons, three slingshot throws in a row (no
## 처음으로 between them: the next press is the next shot), the reason told once after the first
## throw (later explanations are the lab's observe text again), the stamps filling, the done text and
## the puppy's celebration on the last one only. A reopened finished place keeps its stamps, asks
## nothing and never celebrates again. A landing whose engine report comes after the status flip
## still earns its stamp. The physics is read only (mission_checks: the same flight with or without
## the round).
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const PHONE := Vector2(1560, 720)
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_round()
	await check_late_settle()


func check_round() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var root_size := tree.root.size
	tree.root.size = Vector2i(PHONE)   # the real touch below goes through the window
	var screen := await _lab()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var stages: Array = MissionTracker.missions(lab.definition).get("stages", [])
	var predict: Dictionary = MissionTracker.predict(lab.definition)
	# The strip: one stamp per stage and the first stage's text.
	expect.call(screen._mission_strip != null and screen._mission_strip.visible and screen._stamp_labels.size() == stages.size()
		and screen._mission_text.text == str(stages[0].text),
		"round: the strip shows one stamp per stage and the first stage", screen._mission_text.text)
	# The formula's answer is hidden before the throw (key card and sidebar both read "?": the card
	# in a child's words, the sidebar with its unit).
	screen._update_readouts(false)
	var range_hidden: bool = screen._key_labels["range"].text == "? 미터" and screen._observation_labels["range"].text == "? m" \
		and screen._observation_labels["flight_time"].text == "? s" and not screen._key_labels.has("flight_time")
	expect.call(range_hidden, "round: before the throw the formula range and flight time read ?",
		"%s, %s" % [screen._key_labels["range"].text, screen._observation_labels["flight_time"].text])
	# Dugi asks in his own box (portrait, name tag), the two picture buttons over it.
	var box: DialogueBox = screen.dialogue
	var buttons: Array = screen._choices.get_children() if screen._choices != null else []
	expect.call(screen._asking and box.active and box.visible and box.text == str(predict.question)
		and box.portrait.visible and box.name_label.text == "두기두기" and buttons.size() == 2 and screen._choices.visible,
		"round: Dugi asks the prediction in his dialogue box with two picture buttons",
		"asking %s box %s '%s' buttons %d" % [str(screen._asking), str(box.active), box.text, buttons.size()])
	var strip_ok: bool = screen._stamp_labels.all(func(l: Label) -> bool: return l.size.x > 8.0) \
		and screen._mission_strip.get_rect().end.x <= screen._mission_text.position.x
	expect.call(strip_ok, "round: the stamps sit side by side, clear of the stage text", str(screen._mission_strip.get_rect()))
	# The strip sits on its soft paper pill (readable over trees and sky), drawn under the stamps and the text.
	var pill: PanelContainer = screen._mission_pill
	var pill_ok: bool = pill != null and pill.visible and pill.get_rect().encloses(screen._mission_strip.get_rect()) \
		and pill.get_rect().encloses(screen._mission_text.get_rect()) and pill.get_index() < screen._mission_strip.get_index() \
		and pill.get_rect().end.x <= screen.view.size.x and pill.get_theme_stylebox("panel").bg_color.a >= 0.8
	expect.call(pill_ok, "round: the stamps and the stage text sit on a soft paper pill under them", str(pill.get_rect() if pill else null))
	var row: Rect2 = screen._choices.get_rect()
	var centred: bool = absf(row.get_center().x - screen.view.size.x * 0.5) < 1.0 \
		and absf(row.get_center().y - screen.view.size.y * 0.5) <= screen.CHOICE_HOP + 1.0 \
		and not row.intersects(screen.dialogue.rects()[0])
	expect.call(centred, "round: the picture buttons sit in the middle of the view, above Dugi's box", str(row))
	var pictured := buttons.all(func(b: Button) -> bool:
		return b.size.x >= screen.CHOICE_SIZE.x - 1.0 and b.find_children("*", "Label", true, false).size() == 1 and b.get_child(0).get_child(0) is Control)
	expect.call(pictured, "round: each choice is a big button with a picture and a label", "")
	# Held open: the read timer and a tap on the box do not close it; mouse motion over the view
	# does not either.
	box.step(30.0)
	box.advance()
	var motion := InputEventMouseMotion.new()
	motion.position = screen.view_point(lab.ball_center()) + Vector2(30.0, -30.0)
	screen.view._gui_input(motion)
	await tree.process_frame
	expect.call(screen._asking and box.active, "round: the question stays until it is answered (timer, a tap on the box, mouse motion)", "")
	# Behind the question the view is dimmed; the box and the buttons stand above the dim.
	var shield: ColorRect = screen._question_shield
	var dimmed: bool = shield != null and shield.color.a > 0.2 and shield.get_index() < screen.dialogue.get_index() \
		and shield.get_index() < screen._choices.get_index() and shield.get_index() > screen._action_row.get_index() \
		and shield.get_index() > screen._title_bar.get_index() and shield.get_rect().encloses(Rect2(Vector2.ZERO, screen.view.size))
	expect.call(dimmed, "round: while Dugi asks the view behind is dimmed, his box and the buttons above the dim", "")
	var dialogue_home: int = screen._dialogue_index
	# Nothing behind the question takes a touch (2026-10-28): the ball, 다시, the main button,
	# 자세히 and ← 지도 all lie under the shield; the question stays.
	var behind: Array = [screen.view_point(lab.ball_center())]
	for c: Control in [screen._back_button, screen._sidebar_button] + screen._action_row.get_children():
		behind.append(c.get_global_rect().get_center())
	var shielded := true
	for at: Vector2 in behind:
		var press := InputEventScreenTouch.new()
		press.position = at
		press.pressed = true
		tree.root.push_input(press)
		await tree.process_frame
		shielded = shielded and m.mode != "slingshot"
		var lift := InputEventScreenTouch.new()
		lift.position = at
		tree.root.push_input(lift)
		await tree.process_frame
	expect.call(shielded and screen._asking and box.active and not screen.is_sidebar_open() and screen.is_inside_tree() and screen._question_shield != null,
		"round: while Dugi asks nothing behind takes a touch (ball, 다시, main button, 자세히, 지도)", str(behind))
	# The pick: the question goes at once, the strip shows the pick, the next touch reaches the ball.
	(buttons[0] as Button).pressed.emit()
	expect.call(screen._predict_pick == "farther" and not screen._asking and not box.active and screen._choices == null
		and screen._mission_text.text == ExperimentScreen.PICK_PREFIX + "더 멀리",
		"round: a picked picture is kept and the question goes at once", screen._mission_text.text)
	expect.call(screen.dialogue.get_index() == dialogue_home and screen._question_shield == null,
		"round: after the pick the dim goes and the box is back in its place among the overlays", "%d %d" % [screen.dialogue.get_index(), dialogue_home])
	await tree.process_frame
	var ball: Vector2 = screen.view_point(lab.ball_center())
	var touch := InputEventScreenTouch.new()
	touch.position = ball
	touch.pressed = true
	tree.root.push_input(touch)
	await tree.process_frame
	expect.call(m.mode == "slingshot", "round: the next touch after the pick reaches the ball (nothing of the question catches it)", m.mode)
	touch.pressed = false
	touch.canceled = true
	tree.root.push_input(touch)
	await tree.process_frame
	# First throw (45°, 6 m/s: past 3 m): one stamp, then Dugi tells the reason.
	await _throw(screen, lab, 45.0, 6.0)
	await _run_to_end(lab)
	screen._update_readouts(false)
	var range_value: Variant = lab.observations().get("range")
	var range_text := ExperimentScreen.format_observation(_observation(lab, "range"), range_value)
	var range_card := "%s미터" % Ui.number(float(range_value), 1)
	expect.call(screen._observation_labels["range"].text == range_text and range_text == "%s m" % Ui.number(float(range_value), 2)
		and screen._key_labels["range"].text == range_card,
		"round: once the ball landed the formula range shows (card: one decimal in words; sidebar: full precision)",
		"%s / %s" % [screen._key_labels["range"].text, range_text])
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 1 and screen._mission_text.text == str(stages[1].text),
		"round: the first throw past 3 m earns the first stamp; the next stage shows",
		"stamps %d, '%s'" % [ProgressStore.stamps(ProgressStore.load(), "projectile"), screen._mission_text.text])
	var said := await _next_explanation(screen)
	expect.call(said == str(predict.reason), "round: after the first throw Dugi tells the prediction's reason", said)
	# Second throw straight away (no 처음으로): 7.5 m/s, past 5 m.
	await _throw(screen, lab, 45.0, 7.5)
	await _run_to_end(lab)
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 2, "round: the second throw (no 처음으로 between) earns the second stamp",
		"stamps %d" % ProgressStore.stamps(ProgressStore.load(), "projectile"))
	said = await _next_explanation(screen)
	expect.call(said == str(stages[1].say), "round: later explanations are Dugi's say for the stage (here the one just cleared; the reason was told once)", said)
	expect.call(not screen.cast.puppy.celebrating(), "round: no celebration before the last stamp", "")
	# The third stage wants another angle: 45° again, even thrown harder past 7 m, earns nothing.
	await _throw(screen, lab, 45.0, 9.0)
	await _run_to_end(lab)
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 2 and float(lab.observations().range) > 7.0,
		"round: the second stage's angle again (45°, past 7 m) earns no third stamp",
		"stamps %d, range %s" % [ProgressStore.stamps(ProgressStore.load(), "projectile"), str(lab.observations().range)])
	# Third throw at another angle (40°, 9 m/s: past 7 m) after 처음으로: the last stamp, the done
	# text, the puppy hops and waves.
	screen.experiment_action("reset")
	for i in 4:
		await tree.process_frame
	await _throw(screen, lab, 40.0, 9.0)
	var rest_y: float = screen.cast.puppy.position.y
	var hopped := false
	for i in 900:
		await tree.physics_frame
		await tree.process_frame
		if screen.cast.puppy.position.y > rest_y + 0.1:
			hopped = true
		if hopped and ProgressStore.stamps(ProgressStore.load(), "projectile") == 3:
			break
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 3 and screen._mission_text.text == ExperimentScreen.DONE_TEXT,
		"round: the third throw past 7 m earns the last stamp; the done text shows", screen._mission_text.text)
	expect.call(hopped and screen.cast.puppy.celebrating(), "round: on the last stamp the puppy hops and waves the flag fast", "hopped %s" % str(hopped))
	await _free(screen)
	# A reopened finished place: the stamps, no question, and no celebration on another long throw.
	var again := await _lab()
	var lab2: Experiment = again.experiment
	var awarded := []
	again._missions.progress = func(id: String, stamps: int) -> void: awarded.append(stamps)
	expect.call(again._mission_text.text == ExperimentScreen.DONE_TEXT and not again._asking and again._choices == null,
		"round: a reopened finished place keeps its stamps and asks nothing", again._mission_text.text)
	await _throw(again, lab2, 45.0, 9.0)
	await _run_to_end(lab2)
	expect.call(awarded.is_empty() and not again.cast.puppy.celebrating() and ProgressStore.stamps(ProgressStore.load(), "projectile") == 3,
		"round: a long throw at a finished place celebrates nothing again", str(awarded))
	await _free(again)
	tree.root.size = root_size
	DirAccess.remove_absolute(ProgressStore.path)


## The status can say "landed" (has_landed_by: the clock within the slack of the formula landing)
## before the engine's own report (landed_step) makes the lab settled. The screen's judge on such a
## poll decides nothing and latches nothing; the next poll, settled, gives the stamp. The lab is a
## stand-in here (the two states held as long as needed); the judge is the screen's own.
func check_late_settle() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _lab()
	var real: Experiment = screen.experiment
	var script := GDScript.new()
	script.source_code = "extends Experiment\nvar now := \"landed\"\nvar done := false\n" \
		+ "func status() -> String:\n\treturn now\nfunc settled() -> bool:\n\treturn done\n" \
		+ "func observations() -> Dictionary:\n\treturn {\"range\": 4.2}\n" \
		+ "func control_value(_id: String) -> Variant:\n\treturn 6.0\n"   # any throw past 3 m clears the first stage
	script.reload()
	var stand_in: Experiment = script.new()
	tree.root.add_child(stand_in)
	screen.experiment = stand_in
	screen._missions_judge()   # landed, not settled yet
	var none_yet := ProgressStore.stamps(ProgressStore.load(), "projectile") == 0
	stand_in.done = true
	screen._missions_judge()   # the next poll: settled
	var stamped := ProgressStore.stamps(ProgressStore.load(), "projectile")
	screen._missions_judge()   # and once per throw
	var once := ProgressStore.stamps(ProgressStore.load(), "projectile") == stamped
	screen.experiment = real
	stand_in.queue_free()
	expect.call(none_yet and stamped == 1 and once,
		"round: a landing the engine reports after the status flip still earns its stamp (nothing latched before, judged once)",
		"none on the early poll %s, stamps %d, once %s" % [str(none_yet), stamped, str(once)])
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)


# --- helpers ---------------------------------------------------------------------------------------

## A slingshot throw of (angle, speed): the finger pulls the ball back by the reversed arrow (the
## surface's own plane), through the view's touch input; after a run the press is the next shot.
func _throw(screen: Control, lab: Experiment, angle: float, speed: float) -> void:
	var press: Vector2 = screen.view_point(lab.ball_center())   # the ball, or after a run its launch point
	_touch(screen, press, true)
	await tree.process_frame
	var surface: PolarArrowSurface = screen.manipulator.slingshot_surface
	var at: Vector2 = surface.to_plane(lab.ball_center())
	var launch := PolarArrowSurface.tip_point(angle, speed, 0.0, surface.arrow_scale)
	var finger: Vector2 = screen.view_point(surface.pose(at - launch, 0.0).origin)
	for k in range(1, 5):
		_drag(screen, press.lerp(finger, k / 4.0))
		await tree.process_frame
	_touch(screen, finger, false)
	await tree.process_frame
	expect.call(lab.angle_deg == angle and lab.speed == speed, "round: the pull throws %d° %.1f m/s" % [int(angle), speed],
		"%.1f° %.1f m/s" % [lab.angle_deg, lab.speed])


## Steps until the throw has been released, ended and settled, then the screen's 10 Hz poll.
func _run_to_end(lab: Experiment) -> void:
	for i in 1200:
		await tree.physics_frame
		if lab.released and lab.status() in ["landed", "out", "fence"] and lab.settled():
			break
	for i in 8:
		await tree.process_frame


## The words of Dugi's next explanation (the box opens after his delay), then it is closed.
func _next_explanation(screen: Control) -> String:
	for i in 240:
		await tree.process_frame
		if screen.dialogue.active:
			var words: String = screen.dialogue.text
			screen.dialogue.close()
			return words
	return "(no explanation)"


func _touch(screen: Control, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	screen.view._gui_input(event)


func _drag(screen: Control, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = position
	screen.view._gui_input(event)


## The projectile screen on a phone-sized host, built the app's way (setup before it enters the tree).
func _lab() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = PHONE
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("projectile"))
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame


## The definition's observation entry with this id.
func _observation(lab: Experiment, id: String) -> Dictionary:
	for observation in lab.definition.observations:
		if observation.id == id:
			return observation
	return {}
