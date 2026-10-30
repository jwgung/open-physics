## The mission round as a module (MissionRound, apps/lab3d/GLOSSARY.md "미션 라운드"): its flow driven
## through its own interface only, with a stand-in lab and a progress kept in memory (no screen, no
## widget, no file, no clock). The screen's drawing of the same round is in game_round_checks.gd,
## celebration_checks.gd, faces_checks.gd and story_checks.gd.
extends RefCounted

var tree: SceneTree
var expect: Callable
var _labs: Array = []   # the stand-ins made (freed at the end: nodes outside the tree)

## A lab whose status, settled state, observations and control values the check sets; it records
## every attempt to change it (the round must never make one).
const STAND_IN := """extends Experiment
var now := "ready"
var done := true
var values := {}
var controls := {}
var changes := []
func status() -> String:
	return now
func settled() -> bool:
	return done
func observations() -> Dictionary:
	return values
func control_value(id: String) -> Variant:
	return controls.get(id, super.control_value(id))
func set_control(id: String, value: Variant) -> void:
	changes.append([id, value])
func run_action(id: String) -> void:
	changes.append([id])
"""


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_clue_question_bridge()
	check_stamps_and_reason()
	check_miss_lines()
	check_finished_place()
	check_no_dugi()
	check_auto_conditions()
	for lab in _labs:
		lab.free()


func _stand_in(definition: Dictionary) -> Experiment:
	var script := GDScript.new()
	script.source_code = STAND_IN
	script.reload()
	var lab: Experiment = script.new()
	lab.definition = definition
	_labs.append(lab)
	return lab


## A round of `id` on a memory store (`saved`: stamps already kept), opened with Dugi; the story as `story`.
func _round(id: String, saved := 0, story := false) -> MissionRound:
	var definition := ExperimentRegistry.find(id)
	var store := MissionRound.MemoryProgress.new()
	if saved > 0:
		store.saved[id] = saved
	var was := Story.enabled
	Story.enabled = story
	var round := MissionRound.create(definition, _stand_in(definition), store)
	round.open(true)
	Story.enabled = was
	return round


## A throw of the projectile that lands with `hits` (the box ids hit) and `range`.
func _land(round: MissionRound, hits: Array, distance := 4.0) -> void:
	var lab = round.lab
	lab.now = "landed"
	lab.values = {"range": distance, "hit_1": 1.0 if 1 in hits else 0.0, "hit_2": 1.0 if 2 in hits else 0.0,
		"hit_3": 1.0 if 3 in hits else 0.0}


## Puppy's clue first (once per spot), then Dugi's question; the answer ends it and leaves the bridge
## line for his box, which comes before anything else he says; the reason waits for a result line.
func check_clue_question_bridge() -> void:
	var round := _round("projectile", 0, true)
	var predict := MissionRound.predict(round.definition)
	var ended := []
	round.question_ended.connect(func() -> void: ended.append(true))
	var clue := round.clue_to_open()
	expect.call(round.phase() == MissionRound.Phase.CLUE and round.asking() and clue.size() == 2
		and clue[0] == Story.clue(round.definition) and round.choices().size() == 2,
		"round module: a first visit opens on Puppy's clue, the question waiting behind it", str(clue))
	round.clue_opened()
	var store: MissionRound.MemoryProgress = round.store
	expect.call(round.clue_open() and round.clue_to_open().is_empty() and store.clue_seen("projectile"),
		"round module: the clue opened is told once (kept in the store)", str(store.clues))
	round.clue_read()
	expect.call(round.phase() == MissionRound.Phase.ASKING and round.question_line()[0] == predict.question
		and ended.is_empty(), "round module: the clue read, Dugi asks", str(round.question_line()))
	var picked := round.answer(str(predict.answer))
	expect.call(picked == "가까이" and round.pick == "near" and round.reason_face == Story.REASON_FACE[true]
		and ended.size() == 1 and round.phase() == MissionRound.Phase.PLAYING,
		"round module: the answer ends the question once, the pick and the reason's happy face kept", picked)
	expect.call(round.answer("far") == "" and round.pick == "near" and ended.size() == 1,
		"round module: a second answer after the question changes nothing", round.pick)
	var bridge := "%s %s" % [predict.bridge, MissionRound.BRIDGE_FIRST]
	expect.call(round.bridge_line() == bridge and round.take_line() == [bridge, Story.face_or_default(predict.bridge_face)]
		and round.take_line().is_empty() and round.reason == str(predict.reason),
		"round module: the bridge comes first and once; the reason waits for the first result line", round.bridge_line())
	var reopened := MissionRound.create(round.definition, _stand_in(round.definition), store)
	Story.enabled = true
	reopened.open(true)
	Story.enabled = false
	expect.call(reopened.phase() == MissionRound.Phase.ASKING and reopened.clue_to_open().is_empty(),
		"round module: the next visit asks without the clue", str(reopened.phase()))


## A landing that beats the stage: Puppy's win line, then the stamp (saved once), then the question
## revealed; the first result line lets Dugi tell the reason (once). Judged only settled, once per attempt.
func check_stamps_and_reason() -> void:
	var round := _round("projectile")
	var order := []
	round.result_told.connect(func(stage: int, won: bool, text: String, _face: String) -> void: order.append(["told", stage, won, text]))
	round.stamp_earned.connect(func(stamps: int) -> void: order.append(["stamp", stamps]))
	round.reason_due.connect(func() -> void: order.append(["reason"]))
	round.revealed.connect(func() -> void: order.append(["revealed"]))
	round.question_ended.connect(func() -> void: order.append(["ended"]))
	var lab = round.lab
	expect.call(round.hidden_observations(lab.values) == MissionRound.missions(round.definition).hidden_until_end,
		"round module: before a result the formula's answers are hidden", str(round.hidden_observations(lab.values)))
	round.threw()
	_land(round, [1])
	lab.done = false
	round.judge_run()
	expect.call(order.is_empty() and round.stamps == 0, "round module: a landing not settled yet decides nothing", str(order))
	lab.done = true
	round.judge_run()
	var win: String = MissionRound.missions(round.definition).stages[0].win
	var want := [["reason"], ["told", 0, true, win], ["stamp", 1], ["ended"], ["revealed"]]
	var store: MissionRound.MemoryProgress = round.store
	expect.call(order == want and round.stamps == 1 and store.stamps("projectile") == 1 and round.judged_run,
		"round module: the reason is due, Puppy's win line, the stamp saved, then the question revealed", str(order))
	order.clear()
	round.judge_run()
	expect.call(order.is_empty() and round.stamps == 1, "round module: the same attempt earns nothing more", str(order))
	expect.call(round.take_line() == [round.definition.predict.reason, round.reason_face] and round.take_line().is_empty(),
		"round module: Dugi tells the reason once, after the first result line", "")
	expect.call(round.say_stage() == 0 and round.stage_say()[0] == MissionRound.missions(round.definition).stages[0].say,
		"round module: Dugi explains the stage just cleared", str(round.say_stage()))
	expect.call(round.hidden_observations(lab.values).is_empty() and round.answer_shown(lab.values),
		"round module: with the result the answers show", "")
	lab.now = "ready"
	round.judge_run()
	expect.call(not round.judged_run and round.say_stage() == 1, "round module: the lab back at ready starts a new attempt", "")
	expect.call((lab.changes as Array).is_empty(), "round module: the round never changes the lab", str(lab.changes))


## Puppy's miss line after an attempt that ends without its stamp: only after a touch, with the finger
## up, seen on MISS_POLLS polls in a row, and once; a condition change drops the attempt's line.
func check_miss_lines() -> void:
	var round := _round("projectile")
	round.end_question()
	var told := []
	round.result_told.connect(func(stage: int, won: bool, text: String, _face: String) -> void: told.append([stage, won, text]))
	_land(round, [])
	round.check_miss(false)
	round.check_miss(false)
	expect.call(told.is_empty(), "round module: no line without an attempt", str(told))
	round.touched()
	round.check_miss(true)
	round.check_miss(true)
	round.check_miss(false)
	expect.call(told.is_empty(), "round module: not while the finger is down, and not on one poll", str(told))
	round.check_miss(false)
	var miss: String = MissionRound.missions(round.definition).stages[0].miss
	expect.call(told == [[0, false, miss]], "round module: the miss line on the second poll in a row", str(told))
	round.check_miss(false)
	round.check_miss(false)
	expect.call(told.size() == 1, "round module: the miss line is told once per attempt", str(told))
	round.placed()
	round.check_miss(false)
	round.check_miss(false)
	expect.call(told.size() == 1, "round module: putting the ball back is not a new touch's line", str(told))
	round.touched()
	round.condition_changed()
	round.check_miss(false)
	round.check_miss(false)
	expect.call(told.size() == 1, "round module: a condition change drops the attempt's line", str(told))


## The last stamp completes the round (the store's round_done once); a reopened finished place asks
## nothing and hands over no stamp again.
func check_finished_place() -> void:
	var round := _round("projectile", 2)
	round.end_question()
	var stamped := []
	round.stamp_earned.connect(func(stamps: int) -> void: stamped.append(stamps))
	round.threw()
	_land(round, [3])
	round.judge_run()
	var store: MissionRound.MemoryProgress = round.store
	expect.call(stamped == [3] and round.phase() == MissionRound.Phase.DONE and store.done == ["projectile"],
		"round module: the third stamp completes the round (kept once)", str(stamped))
	var reopened := MissionRound.create(round.definition, round.lab, store)
	reopened.open(true)
	var again := []
	reopened.stamp_earned.connect(func(stamps: int) -> void: again.append(stamps))
	reopened.threw()
	reopened.judge_run()
	expect.call(reopened.phase() == MissionRound.Phase.DONE and not reopened.asking() and reopened.predict_ended
		and again.is_empty() and store.done.size() == 1,
		"round module: a reopened finished place asks nothing and earns nothing again", str(again))


## Without Dugi there is no question, no bridge and no reason; the stamps still come.
func check_no_dugi() -> void:
	var definition := ExperimentRegistry.find("projectile")
	var round := MissionRound.create(definition, _stand_in(definition), MissionRound.MemoryProgress.new())
	round.open(false)
	var due := []
	round.reason_due.connect(func() -> void: due.append(true))
	round.threw()
	_land(round, [1])
	round.judge_run()
	expect.call(not round.asking() and round.stamps == 1 and due.is_empty() and round.take_line().is_empty(),
		"round module: without Dugi no question or reason, the stamp still comes", str(round.stamps))


## missions.auto_conditions: the stage's conditions the lab does not have, once per stage shown or
## reset, only at rest; the round asks for them and the screen sets them (the round changes nothing).
func check_auto_conditions() -> void:
	var round := _round("collision")
	round.end_question()
	var lab = round.lab
	lab.now = "moving"
	round.stage_shown()
	expect.call(round.take_conditions().is_empty(), "round module: no conditions mid-run", "")
	lab.now = "ready"
	var first := round.take_conditions()
	expect.call(first == {"mass_b": 1.0} and round.take_conditions().is_empty(),
		"round module: at rest the stage's differing conditions, once", str(first))
	lab.controls = {"mass_b": 1.0}
	round.acted(true)
	expect.call(round.take_conditions().is_empty(), "round module: after 처음으로 only what still differs", "")
	lab.controls = {"mass_b": 2.0}
	round.acted(true)
	expect.call(round.take_conditions() == {"mass_b": 1.0} and (lab.changes as Array).is_empty(),
		"round module: 처음으로 asks for the stage's conditions again; the lab is not changed by the round", str(lab.changes))
	# A stamp earned at rest: the screen's stamp_earned handler sets the next stage's conditions at once
	# (a condition change, inside judge_run). The attempt that earned the stamp stays judged, so the
	# same run never earns the next stamp too.
	var again := _round("collision")
	again.end_question()
	var rest = again.lab
	rest.now = "rest"
	rest.controls = {"mass_a": 1.0, "mass_b": 1.0}
	rest.values = {"impulse_b": 30.0}
	var set_now := []
	again.stamp_earned.connect(func(_stamps: int) -> void:
		again.stage_shown()
		var values := again.take_conditions()
		set_now.append(values)
		if not values.is_empty():
			again.condition_changed())
	again.threw()
	again.judge_run()
	var judged_after: bool = again.judged_run
	again.judge_run()
	expect.call(set_now == [{"mass_a": 3.0}] and again.stamps == 1 and judged_after,
		"round module: conditions set inside the stamp's hand-over leave the attempt judged (one stamp per run)",
		"stamps %d, judged %s, set %s" % [again.stamps, str(judged_after), str(set_now)])
	for connection in again.stamp_earned.get_connections():   # the handler holds the round: no cycle left behind
		again.stamp_earned.disconnect(connection.callable)
