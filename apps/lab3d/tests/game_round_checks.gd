## Plan G4 — the projectile's mission round: the stamp strip, Dugi's prediction question (two
## choices), the reason after the run, the stamps filling, and the done text on the last one.
## The physics is read only: a throw is the same formula flight with or without the round (the
## mission's stamp is the same as in slingshot_checks).
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


## One screen, three slingshot throws (3 m, 5 m, 7 m): the strip fills, the prediction's reason
## speaks after the first run, the done text appears on the last stamp, a reopened screen keeps
## the round, and a corrupt progress file starts over.
func check_round() -> void:
	DirAccess.remove_absolute(ProgressStore.PATH)
	var screen := await _lab()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var stages: Array = MissionTracker.missions(lab.definition).get("stages", [])
	# The strip: one stamp per stage and the first stage's text.
	expect.call(screen._mission_strip != null and screen._mission_strip.visible,
		"the round shows the mission strip")
	expect.call(screen._stamp_labels.size() == stages.size(),
		"the strip has one stamp per stage",
		"stamps %d stages %d" % [screen._stamp_labels.size(), stages.size()])
	expect.call(screen._mission_text != null and screen._mission_text.text == str(stages[0].get("text", "")),
		"the first stage's text shows",
		screen._mission_text.text if screen._mission_text else "")
	await tree.process_frame
	expect.call(screen._predict_overlay != null, "the prediction's question shows before the run")
	# Pick the first choice: the strip remembers it.
	var buttons: Array = []
	if screen._predict_overlay != null:
		for c: Node in screen._predict_overlay.get_children():
			for b: Node in c.find_children("*", "Button", true, false):
				buttons.append(b)
	expect.call(buttons.size() == 2, "the question offers two choices", "%d" % buttons.size())
	if buttons.size() == 2:
		(buttons[0] as Button).pressed.emit()
	await tree.process_frame
	expect.call(screen._predict_pick == "farther", "a picked choice is remembered", screen._predict_pick)
	expect.call(screen._mission_text != null and screen._mission_text.text == "예측: 더 멀리",
		"the strip shows the pick",
		screen._mission_text.text if screen._mission_text else "")
	# Throw past 3 m (the slingshot's pull commits angle / speed and throws).
	await _throw(screen, lab, m, [Vector2(0.0, -20.0), Vector2(80.0, -80.0), Vector2(140.0, -140.0)])
	var thrown_range: float = lab.flight_range()
	expect.call(is_finite(thrown_range) and thrown_range > 3.0,
		"the thrown ball's formula range passes 3 m", "range %s" % str(thrown_range))
	await _run_to_end(lab)
	expect.call(screen._predict_ended, "the prediction ended after the run")
	expect.call(screen._predict_overlay == null, "the question is gone after the run")
	var reason: String = MissionTracker.predict(lab.definition).get("reason", "")
	expect.call(screen.dialogue != null and screen.dialogue.text == reason,
		"Dugi explains the reason after the run",
		screen.dialogue.text if screen.dialogue else "")
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 1,
		"the first stage clears with one stamp",
		"stamps %d" % ProgressStore.stamps(ProgressStore.load(), "projectile"))
	expect.call(screen._mission_text != null and screen._mission_text.text == str(stages[1].get("text", "")),
		"the next stage's text appears",
		screen._mission_text.text if screen._mission_text else "")
	# The second throw (past 5 m): the second stamp.
	await _throw(screen, lab, m, [Vector2(0.0, -12.0), Vector2(55.0, -55.0), Vector2(98.0, -98.0)])
	await _run_to_end(lab)
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 2, "the second stage clears", "")
	# The third throw (past 7 m): the last stamp and the done text.
	await _throw(screen, lab, m, [Vector2(0.0, -8.0), Vector2(40.0, -40.0), Vector2(72.0, -72.0)])
	await _run_to_end(lab)
	await tree.process_frame
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 3, "the third stage clears", "")
	expect.call(screen._mission_text != null and screen._mission_text.text.contains("모두 완료"),
		"the done text shows", screen._mission_text.text if screen._mission_text else "")
	# A reopened screen keeps the stamps and asks no more question (the round is done).
	var screen2 := await _lab()
	expect.call(screen2._mission_text != null and screen2._mission_text.text.contains("모두 완료"),
		"a reopened screen keeps the stamps",
		screen2._mission_text.text if screen2._mission_text else "")
	expect.call(screen2._predict_overlay == null, "a done round asks no more question", "")
	await tree.process_frame
	# A corrupt progress file starts over.
	var config := ConfigFile.new()
	config.set_value("progress", "projectile", 99)
	config.save(ProgressStore.PATH)
	var bad := ProgressStore.load()
	expect.call(ProgressStore.stamps(bad, "projectile") == 0, "a corrupt progress file starts over",
		"stamps %d" % ProgressStore.stamps(bad, "projectile"))
	await _free(screen)
	await _free(screen2)


## Frees a built screen (its host with it), a few frames for the queue to run.
func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame


## Builds the projectile screen on a host of PHONE (the other lab tests' way).
func _lab() -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = PHONE
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	host.add_child(screen)
	screen.setup(ExperimentRegistry.find("projectile"))
	await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame
	return screen


## A slingshot throw: press the ball, pull through the given deltas, release (the pull's angle and
## speed commit to the controls and the lab throws).
func _throw(screen: Control, lab: Experiment, m: Manipulator, deltas: Array) -> void:
	var ball_point: Vector2 = screen.view_point(lab.ball_center())
	m.handle_pointer("press", ball_point)
	await tree.process_frame
	for delta in deltas:
		m.handle_pointer("move", ball_point + (delta as Vector2))
		await tree.process_frame
	m.handle_pointer("release", ball_point + (deltas[deltas.size() - 1] as Vector2))
	await tree.process_frame


## Steps the physics until the lab settles (a bounded number of frames: the screen's 10 Hz poll
## judges the stamp on its own cadence).
func _run_to_end(exp: Experiment) -> void:
	for i in 3600:
		await tree.process_frame
		if exp.status() in ["landed", "out", "fence"] and exp.settled():
			await tree.process_frame
			return
