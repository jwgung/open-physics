## Celebrations (2026-10-28): the stamp slam (a cleared stage's stamp lands in the middle of the view
## and flies into its strip slot, which fills only then; the bread cat hops), the whole round's
## celebration (confetti, the puppy, Dugi and the cat cheer, then the round-done card with the stamps
## and two buttons, nothing behind it taking a touch), only for a round completed in this visit, and
## the map's flag raise (once per new completion, never for an old save, a tap skips it, the camera
## is the child's again afterwards). ProgressStore keeps old files working. Pictures and motion only:
## no celebration words anywhere.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const HOME_SCREEN := "res://scripts/app/island_home_screen.gd"


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_stamp_slam()
	await check_round_done()
	await check_store_compat()
	await check_flag_raise()


## The stamp: in flight its slot stays empty, a real touch on the ball still works under it, it ends
## in its slot (filled) and frees itself; a second stamp lands the first at once.
func check_stamp_slam() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var root_size := tree.root.size
	tree.root.size = Vector2i(PHONE)
	var screen := await _lab()
	var lab: Experiment = screen.experiment
	(screen._choices.get_child(0) as Button).pressed.emit()   # answer Dugi: the view is free
	await tree.process_frame
	var cat: CatActor = screen.lab_cat()
	var cheers := cat.cheers if cat != null else -1
	var stages: Array = MissionTracker.missions(lab.definition).stages
	screen._missions.stamps = 1
	screen._mission_progress("projectile", 1)
	var slam: StampSlam = screen._slam
	var flying: bool = slam != null and slam.get_parent() == screen.view and slam.mouse_filter == Control.MOUSE_FILTER_IGNORE \
		and slam.get_rect().encloses(Rect2(Vector2.ZERO, screen.view.size))
	expect.call(flying, "stamp: a cleared stage's stamp appears over the whole view and takes no touch", "")
	expect.call((screen._stamp_labels[0] as Label).text == "○" and screen._mission_text.text == str(stages[1].text),
		"stamp: while it flies its slot stays empty (the next stage's text already shows)", (screen._stamp_labels[0] as Label).text)
	expect.call(cat != null and cat.cheers == cheers + 1, "stamp: the bread cat hops", "cheers %d -> %d" % [cheers, cat.cheers if cat else -1])
	# Its course: big in the middle at the landing (squashed), then into the slot.
	slam.t = StampSlam.DROP_S + 0.02
	var landing: Array = slam.pose()
	slam.t = StampSlam.TOTAL_S - 0.001
	var arriving: Array = slam.pose()
	var slot: Vector2 = screen._stamp_slot_center(0)
	slam.t = 0.0
	expect.call((landing[0] as Vector2).distance_to(screen.view.size * Vector2(0.5, 0.46)) < 1.0 and (landing[2] as Vector2).x > 1.05
		and (arriving[0] as Vector2).distance_to(slot) < 3.0 and float(arriving[1]) < StampSlam.RADIUS * 0.3 and StampSlam.TOTAL_S <= 1.1,
		"stamp: lands squashed in the middle, then shrinks into its slot in about a second", "%s %s slot %s" % [str(landing), str(arriving), str(slot)])
	# A real touch on the ball under the flying stamp reaches the slingshot.
	var ball: Vector2 = screen.view_point(lab.ball_center())
	await _real_touch(ball, true)
	var reached: bool = screen.manipulator.mode == "slingshot"
	await _real_touch(ball, false, true)
	expect.call(reached and screen._slam == slam, "stamp: a real touch on the ball under the flying stamp still works", screen.manipulator.mode)
	slam.advance(StampSlam.TOTAL_S)
	await tree.process_frame
	expect.call(not is_instance_valid(slam) and screen._slam == null and (screen._stamp_labels[0] as Label).text == "●",
		"stamp: it ends in its slot, which fills; the stamp node is freed", (screen._stamp_labels[0] as Label).text)
	# Two in a row: the first lands at once, only one flies.
	screen._missions.stamps = 2
	screen._mission_progress("projectile", 2)
	var first: StampSlam = screen._slam
	screen._missions.stamps = 3
	screen._mission_progress("projectile", 3)
	await tree.process_frame
	var slams: int = screen.view.get_children().filter(func(n: Node) -> bool: return n is StampSlam).size()
	expect.call(not is_instance_valid(first) and slams == 1 and (screen._stamp_labels[1] as Label).text == "●"
		and (screen._stamp_labels[2] as Label).text == "○",
		"stamp: a stamp arriving while one flies lands that one at once; one flies", "slams %d" % slams)
	await _free(screen)
	tree.root.size = root_size
	DirAccess.remove_absolute(ProgressStore.path)


## The last stamp of a round earned in this visit: confetti, the three cheer, then the card (stamps
## and two buttons, no words) over a dim that stops every touch; 더 해 보기 closes it (the lab takes
## touches again), 다음으로 goes back to the map. A reopened finished lab shows none of it.
func check_round_done() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var root_size := tree.root.size
	tree.root.size = Vector2i(PHONE)
	var screen := await _lab()
	var lab: Experiment = screen.experiment
	(screen._choices.get_child(0) as Button).pressed.emit()
	await tree.process_frame
	# The round through the real tracker (a stand-in lab's results: 4, 6 and 8 m, other angles).
	var stand_in := _stand_in()
	tree.root.add_child(stand_in)
	for run in [[4.0, 45.0], [6.0, 50.0], [8.0, 40.0]]:
		stand_in.range_m = run[0]
		stand_in.angle = run[1]
		screen._missions.on_run_ended("landed", stand_in, {"range": run[0], "hit_1": 1.0, "hit_2": 1.0, "hit_3": 1.0})
		expect.call(screen._card_left < 0.0 and screen._done_card == null and screen._confetti == null,
			"round done: nothing celebrates while the stamp %d still flies" % screen._missions.stamps, "")
		screen._slam.advance(StampSlam.TOTAL_S)
	stand_in.queue_free()
	await tree.process_frame
	screen.skip_round_wait()
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 3 and ProgressStore.pending_flags() == ["projectile"],
		"round done: the third stamp is saved and the spot's flag waits to be raised on the map", str(ProgressStore.pending_flags()))
	var confetti: Confetti = screen._confetti
	expect.call(confetti != null and confetti.mouse_filter == Control.MOUSE_FILTER_IGNORE and screen.cast.puppy.celebrating()
		and screen.cast.dugi.celebrating() and screen.lab_cat().cheers >= 1 and screen._done_card == null,
		"round done: when the last stamp lands confetti falls and the puppy, Dugi and the cat cheer (the card comes after)", "")
	expect.call(screen._mission_text.text == "" and not screen._mission_text.visible and screen._stamp_labels.all(func(l: Label) -> bool: return l.text == "●"),
		"round done: the strip shows its three stamps and no words", screen._mission_text.text)
	# Dugi's hop: his rig rises while he cheers.
	var dugi: DugiActor = screen.cast.dugi
	var high := 0.0
	for i in 30:
		dugi.advance(1.0 / 30.0)
		high = maxf(high, dugi.rig.position.y)
	expect.call(high > 0.15, "round done: Dugi hops", "rig up %.2f m" % high)
	screen._run_celebration(screen.CARD_DELAY_S + 0.01)
	var card: RoundDoneCard = screen._done_card
	var labels: Array = card.find_children("*", "Label", true, false) if card != null else []
	var buttons: Array = card.find_children("*", "Button", true, false) if card != null else []
	expect.call(card != null and card.get_parent() == screen.view and card.get_index() == screen.view.get_child_count() - 1
		and card.dim.mouse_filter == Control.MOUSE_FILTER_STOP and card.dim.get_rect().encloses(Rect2(Vector2.ZERO, screen.view.size))
		and labels.is_empty() and buttons.size() == 2 and card.map_button.text == "다음으로" and card.map_button.theme_type_variation == "PrimaryButton" and card.stay_button.get_index() < card.map_button.get_index() and card.stay_button.text == "더 해 보기"
		and card.stamps == 3 and not screen.dialogue.active,
		"round done: the card shows the stamps and two buttons only (no words), over a dim that covers the view",
		"labels %d buttons %d" % [labels.size(), buttons.size()])
	await tree.process_frame
	var centred: bool = card.card.get_rect().get_center().distance_to(screen.view.size * 0.5) < 2.0 \
		and card.stay_button.size.y >= 80.0 and card.map_button.size.x >= 180.0
	expect.call(centred, "round done: the card is centred, its buttons big", str(card.card.get_rect()))
	# Nothing behind the card takes a touch (the ball, 다시, the main button, ← 지도).
	var behind: Array = [screen.view_point(lab.ball_center()), screen._back_button.get_global_rect().get_center()]
	for c: Control in screen._action_row.get_children():
		behind.append(c.get_global_rect().get_center())
	var blocked := true
	var backs := [0]
	screen.back_requested.connect(func() -> void: backs[0] += 1)
	for at: Vector2 in behind:
		await _real_touch(at, true)
		blocked = blocked and screen.manipulator.mode != "slingshot"
		await _real_touch(at, false)
	expect.call(blocked and backs[0] == 0 and screen._done_card == card, "round done: while the card is up nothing behind it takes a touch", str(behind))
	# 더 해 보기: the card goes in the same frame, the next touch reaches the ball.
	card.stay_button.pressed.emit()
	expect.call(screen._done_card == null and card.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.dim.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and backs[0] == 0, "round done: 더 해 보기 closes the card (it lets go of touches at once) and stays in the lab", "")
	await tree.process_frame
	var ball: Vector2 = screen.view_point(lab.ball_center())
	await _real_touch(ball, true)
	var free_again: bool = screen.manipulator.mode == "slingshot"
	await _real_touch(ball, false, true)
	expect.call(free_again and not is_instance_valid(card), "round done: after 더 해 보기 the next touch reaches the ball", screen.manipulator.mode)
	# 다음으로: back to the map, like ← 지도.
	screen._show_done_card()
	var card2: RoundDoneCard = screen._done_card
	card2.map_button.pressed.emit()
	expect.call(backs[0] == 1 and screen._done_card == null, "round done: 다음으로 goes back to the map", "back %d" % backs[0])
	# Android back with the card up closes it (the lab stays).
	screen._show_done_card()
	expect.call(screen.handle_back() and screen._done_card == null and backs[0] == 1, "round done: back closes the card first", "")
	await _free(screen)
	# Reopened finished lab: no stamp flies, no confetti, no card.
	var again := await _lab()
	for i in 20:
		await tree.process_frame
	again._run_celebration(5.0)
	expect.call(again._slam == null and again._confetti == null and again._done_card == null and not again.cast.puppy.celebrating()
		and again._stamp_labels.all(func(l: Label) -> bool: return l.text == "●"),
		"round done: reopening a finished lab celebrates nothing (only a round completed in this visit)", "")
	await _free(again)
	tree.root.size = root_size
	DirAccess.remove_absolute(ProgressStore.path)


## ProgressStore: an old file (stamps only) has no pending flag; the flag keys never disturb the
## stamps, and the stamps' save keeps them.
func check_store_compat() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var old := ConfigFile.new()
	old.set_value("progress", "projectile", 3)
	old.set_value("progress", "orbit", 1)
	old.save(ProgressStore.path)
	var none: bool = ProgressStore.pending_flags().is_empty() and ProgressStore.load() == {"projectile": 3, "orbit": 1}
	ProgressStore.mark_flag_pending("orbit")
	var store := ProgressStore.load()
	store["orbit"] = 3
	ProgressStore.save(store)
	var kept: bool = ProgressStore.pending_flags() == ["orbit"] and ProgressStore.load() == {"projectile": 3, "orbit": 3}
	ProgressStore.mark_flag_raised("orbit")
	var raised: bool = ProgressStore.pending_flags().is_empty() and ProgressStore.load() == {"projectile": 3, "orbit": 3}
	var odd := ConfigFile.new()
	odd.load(ProgressStore.path)
	odd.set_value(ProgressStore.FLAGS, "spring", "nope")
	odd.save(ProgressStore.path)
	var corrupt_ok: bool = ProgressStore.pending_flags().is_empty() and ProgressStore.load().size() == 2
	expect.call(none and kept and raised and corrupt_ok,
		"store: an old file has no pending flag; pending / raised keep the stamps and the stamps' save keeps them; an odd value is raised",
		"%s %s %s %s" % [str(none), str(kept), str(raised), str(corrupt_ok)])
	DirAccess.remove_absolute(ProgressStore.path)


## The map: a new completion's flag rises once with the camera framing it and giving the view back;
## not again; not for an old save; a tap skips it and opens nothing.
func check_flag_raise() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.save({"projectile": 3})
	ProgressStore.mark_flag_pending("projectile")
	var screen := await _home(TABLET)
	var flag: Node3D = screen._flags["projectile"]
	var rig: CameraRig = screen.view.rig
	var home_state: Dictionary = rig.get_state()
	var waiting: bool = screen.raising() and not rig.is_framing()   # the map shows first (RAISE_DELAY_S)
	var t0 := Time.get_ticks_msec()
	while screen.raising() and not rig.is_framing() and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
	var start_ok: bool = waiting and screen.raising() and screen.raised_count == 1 and flag.visible and flag.scale.y < 0.5 \
		and rig.is_framing() and ProgressStore.pending_flags().is_empty()
	expect.call(start_ok, "flag raise: a newly completed spot's flag starts low, the camera frames it, the store says raised",
		"raising %s scale %.2f framing %s" % [str(screen.raising()), flag.scale.y, str(rig.is_framing())])
	var near := INF
	var tallest := 0.0
	t0 = Time.get_ticks_msec()
	while screen.raising() and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
		near = minf(near, rig.cur_distance)
		tallest = maxf(tallest, flag.scale.y)
	var back: Dictionary = rig.get_state()
	expect.call(not screen.raising() and flag.scale.is_equal_approx(Vector3.ONE) and tallest > 1.05 and near < rig.goal_distance - 3.0,
		"flag raise: the camera goes near, the flag grows past its height and bounces back", "near %.1f of %.1f, tallest %.2f" % [near, rig.goal_distance, tallest])
	expect.call(not rig.is_framing() and is_equal_approx(rig.cur_distance, rig.goal_distance) and rig.cur_target.is_equal_approx(rig._goal_target())
		and str(back) == str(home_state),
		"flag raise: afterwards the camera is the child's view again, exactly", "%s / %s" % [str(back), str(home_state)])
	await _free(screen)
	# Again: it just stands.
	screen = await _home(TABLET)
	expect.call(screen.raised_count == 0 and not screen.raising() and screen._flags["projectile"].visible and screen._flags["projectile"].scale == Vector3.ONE,
		"flag raise: plays once; the next time the map opens the flag just stands", "")
	await _free(screen)
	# An old save (no flag keys) at full stamps: no raise.
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.save({"orbit": 3})
	screen = await _home(TABLET)
	expect.call(screen.raised_count == 0 and screen._flags["orbit"].visible and not screen.view.rig.is_framing(),
		"flag raise: an old save already at full stamps does not replay (its flag stands)", "")
	await _free(screen)
	# A tap during it skips it: flag up, camera at once the child's, nothing opens.
	ProgressStore.mark_flag_pending("orbit")
	screen = await _home(TABLET)
	await tree.process_frame
	var at: Vector2 = screen.view.size * 0.5
	screen._on_pointer("press", at)
	screen._on_pointer("release", at)
	await tree.process_frame
	expect.call(not screen.raising() and screen._flags["orbit"].scale == Vector3.ONE and not screen.view.rig.is_framing()
		and not screen._walking and ProgressStore.pending_flags().is_empty(),
		"flag raise: a tap skips it (flag up, the camera the child's again) and opens nothing", "walking %s" % str(screen._walking))
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)


# --- helpers ---------------------------------------------------------------------------------------

func _stand_in() -> Experiment:
	var script := GDScript.new()
	script.source_code = "extends Experiment\nvar range_m := 4.0\nvar angle := 45.0\n" \
		+ "func status() -> String:\n\treturn \"landed\"\nfunc settled() -> bool:\n\treturn true\n" \
		+ "func observations() -> Dictionary:\n\treturn {\"range\": range_m}\n" \
		+ "func control_value(id: String) -> Variant:\n\treturn angle if id == \"angle\" else 9.0\n"
	script.reload()
	return script.new()


## A touch through the window (the real input path: every Control on the way decides).
func _real_touch(position: Vector2, pressed: bool, cancel := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	event.canceled = cancel
	tree.root.push_input(event)
	await tree.process_frame


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


func _home(size: Vector2) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(HOME_SCREEN).new()
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame
