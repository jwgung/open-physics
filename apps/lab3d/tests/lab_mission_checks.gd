## Plan G2 — the missions of the other 10 labs on their real screens. Per lab a scripted round
## through the screen's own paths (conditions with _set_control, buttons with experiment_action, a
## ball let go where a finger would put it, and the labs' existing test hooks for the hand on a
## handle: the push force, the lever's pressed cells, the pulley's stroke): an attempt that misses
## its stage (short, or made under other conditions) earns nothing; each stage is reachable inside
## the lab's control ranges and earns exactly one stamp (the same attempt never earns a second one,
## even when it also beats the next stage). The hidden answers read "?" until the run has its result.
## Physics invariance: the same script on a screen without the missions / predict blocks gives the
## same formula values, statuses and engine bodies at every physics step. The prediction pictures
## of every kind draw.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const TABLET := Vector2(1152, 720)
const AFTER_STAMP := 40          # frames an attempt runs on after its stamp (no second stamp)

## Per lab: the attempts in order, [what, ops, frames, stamps after]. Ops: ["ctl", id, value],
## ["act", id], ["place", object, pull m] (the spring ball let go there), ["force", N] (the push),
## ["cells", n] (the lever's press), ["layout", fulcrum x, load x] (the lever's dragged fulcrum and
## load), ["stroke", cells] (one pulley stroke let go).
const ROUNDS := {
	"free-fall": [
		["5 m on the earth: 9.9 m/s, not past 10", [["act", "release"]], 240, 0],
		["8 m: 12.5 m/s (past 10 and 12: one stamp)", [["ctl", "height", 8.0], ["act", "release"]], 300, 1],
		["8 m again: past 12", [["act", "release"]], 300, 2],
		["8 m: 12.5 m/s, not past 15", [["act", "release"]], 300, 2],
		["Jupiter, 5 m: 15.7 m/s", [["ctl", "gravity", "jupiter"], ["ctl", "height", 5.0], ["act", "release"]], 240, 3],
	],
	"collision": [
		["the start conditions: B leaves at 1.5 m/s", [["act", "release"]], 600, 0],
		["A at 9 m/s: B at 5.0 m/s (past 2 and 4: one stamp)", [["ctl", "velocity_a", 9.0], ["act", "release"]], 600, 1],
		["again: past 4", [["act", "release"]], 600, 2],
		["again: 5.0 m/s, not past 6", [["act", "release"]], 600, 2],
		["a 10 kg A: B at 15 m/s", [["ctl", "mass_a", 10.0], ["act", "release"]], 600, 3],
	],
	"spring": [
		["놓기 from the start pull 1.2 m", [["act", "release"]], 90, 0],
		["let go at 2.5 m (past 1.5, 2 and 2.4: one stamp)", [["place", "ball", 2.5]], 90, 1],
		["let go at 2.1 m: past 2", [["place", "ball", 2.1]], 90, 2],
		["let go at 2.4 m: not past 2.4", [["place", "ball", 2.4]], 90, 2],
		["let go at 2.5 m", [["place", "ball", 2.5]], 90, 3],
	],
	"friction": [
		["the 8 kg start box pushed loose: not the light box", [["force", 40.0]], 90, 0],
		["the light box pushed loose", [["force", 0.0], ["ctl", "mass", "light"], ["force", 5.0]], 90, 1],
		["the normal box pushed loose", [["force", 0.0], ["ctl", "mass", "normal"], ["force", 10.0]], 90, 2],
		["the heavy box held by friction (10 N < 11.8 N)", [["force", 0.0], ["ctl", "mass", "heavy"], ["force", 10.0]], 90, 2],
		["the heavy box pushed loose (20 N)", [["force", 20.0]], 90, 3],
	],
	"rotation": [
		["the middle point lifts with 186.9 N", [["cells", 50]], 20, 0],
		["the far point: 124.6 N", [["cells", 0], ["ctl", "effort", "far"], ["cells", 50]], 20, 1],
		["the load 1.5 m from the fulcrum: 93.4 N", [["cells", 0], ["layout", -0.5, -2.0], ["cells", 50]], 20, 2],
		["a 1 kg load close in: not the 20 kg load", [["cells", 0], ["layout", -0.5, -1.25], ["ctl", "mass", 1.0], ["cells", 50]], 20, 2],
		["the 20 kg load 0.75 m from the fulcrum: 46.7 N", [["cells", 0], ["ctl", "mass", 20.0], ["cells", 50]], 20, 3],
	],
	"orbit": [
		["the start (3 m): a circle, not from 4 m", [["act", "launch"]], 300, 0],
		["from 4 m at 3 m/s: half a lap", [["ctl", "radius", 4.0], ["act", "launch"]], 700, 1],
		["from 5 m at the circular speed: one lap", [["ctl", "radius", 5.0], ["act", "circular"], ["act", "launch"]], 1000, 2],
		["from 2 m at 3 m/s: it hits the star", [["ctl", "radius", 2.0], ["ctl", "speed", 3.0], ["act", "launch"]], 300, 2],
		["from 2 m at the circular speed: two laps", [["act", "circular"], ["act", "launch"]], 600, 3],
	],
	"buoyancy": [
		["70 kg floats: not heavier than 70", [["act", "release"]], 900, 0],
		["95 kg floats (past 70 and 90: one stamp)", [["ctl", "mass", 95.0], ["act", "release"]], 1200, 1],
		["95 kg again: past 90", [["act", "release"]], 1200, 2],
		["50 kg in the small drum stays under (neutral)", [["ctl", "volume", "small"], ["ctl", "mass", 50.0], ["act", "release"]], 900, 2],
		["45 kg in the small drum floats", [["ctl", "mass", 45.0], ["act", "release"]], 1200, 3],
	],
	"constraints": [
		["L = 2 m on the earth: 2.9 s", [["act", "release"]], 330, 0],
		["L = 3.5 m: 3.9 s (past 3 and 3.5: one stamp)", [["ctl", "length", 3.5], ["act", "release"]], 400, 1],
		["L = 3.5 m again: past 3.5", [["act", "release"]], 400, 2],
		["L = 3.5 m: 3.9 s, not past 4", [["act", "release"]], 400, 2],
		["the moon, L = 1 m: 5 s", [["ctl", "gravity", "moon"], ["ctl", "length", 1.0], ["act", "release"]], 600, 3],
	],
	"pulley": [
		["one strand: 196.2 N", [["stroke", 20]], 20, 0],
		["two strands: 98.1 N (past 150 only)", [["ctl", "strands", "two"], ["stroke", 20]], 20, 1],
		["two strands, the next stroke: past 100", [["stroke", 20]], 20, 2],
		["four strands, a 10 kg load: not the 20 kg load", [["ctl", "strands", "four"], ["ctl", "mass", 10.0], ["stroke", 20]], 20, 2],
		["four strands, 20 kg: 49.05 N", [["ctl", "mass", 20.0], ["stroke", 20]], 20, 3],
	],
	"incline-friction": [
		["20° on wood holds", [["act", "release"]], 90, 0],
		["25°: 2.19 m/s² (past 1 and 2: one stamp)", [["ctl", "angle", 25.0], ["act", "release"]], 90, 1],
		["25° again: past 2", [["act", "release"]], 90, 2],
		["25°: 2.19 m/s², not past 3", [["act", "release"]], 90, 2],
		["30°: 3.04 m/s²", [["ctl", "angle", 30.0], ["act", "release"]], 90, 3],
	],
}


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	for id in ROUNDS:
		await check_round(id)
	for id in ROUNDS:
		await check_physics_unchanged(id)
	await check_pictures()


# --- the round ------------------------------------------------------------------------------------

func check_round(id: String) -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _open(ExperimentRegistry.find(id))
	var lab: Experiment = screen.experiment
	var missions := MissionTracker.missions(lab.definition)
	# Before any run the formula answers read "?" (key cards and the sidebar).
	screen._update_readouts(false)
	var hidden_ok := true
	for observation in lab.definition.observations:
		if observation.id in missions.get("hidden_until_end", []):
			hidden_ok = hidden_ok and screen._observation_labels[observation.id].text == ExperimentScreen.hidden_observation(observation)
	expect.call(hidden_ok and screen._missions != null and screen._asking,
		"%s: the round opens with Dugi's question; the hidden answers read ?" % id, str(missions.get("hidden_until_end", [])))
	var problems := []
	for attempt in ROUNDS[id]:
		var before := ProgressStore.stamps(ProgressStore.load(), id)
		await _ops(screen, attempt[1])
		var frames: int = attempt[2]
		var want: int = attempt[3]
		var stamped_at := -1
		for k in frames:
			await tree.physics_frame
			await tree.process_frame
			if stamped_at < 0 and screen._missions.stamps != before:
				stamped_at = k
				# The run has its result: the hidden answers show (the panel's own text).
				screen._update_readouts(false)
				for observation in lab.definition.observations:
					if observation.id in missions.get("hidden_until_end", []) \
							and screen._observation_labels[observation.id].text == ExperimentScreen.hidden_observation(observation):
						problems.append("%s: %s still hidden after the stamp" % [attempt[0], observation.id])
			if stamped_at >= 0 and k >= stamped_at + AFTER_STAMP:
				break
		var stored := ProgressStore.stamps(ProgressStore.load(), id)
		if stored != want or screen._missions.stamps != want:
			problems.append("%s: stamps %d (want %d, status %s, %s)" % [attempt[0], stored, want, lab.status(), _observed(lab)])
	expect.call(problems.is_empty() and ProgressStore.stamps(ProgressStore.load(), id) == 3 and screen._mission_text.text.contains("모두 완료"),
		"%s: a missed stage earns nothing, each of the 3 stages is reachable in the control ranges and earns one stamp per attempt" % id,
		"; ".join(problems))
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)


## The mission's value now (for a failure message).
func _observed(lab: Experiment) -> String:
	var observe := str(MissionTracker.missions(lab.definition).get("observe", ""))
	return "%s = %s" % [observe, str(lab.observations().get(observe))] if observe != "" else "state goal"


## Runs one attempt's ops through the screen's paths (or the labs' hand hooks).
func _ops(screen: Control, ops: Array) -> void:
	var lab: Experiment = screen.experiment
	for op in ops:
		match op[0]:
			"ctl":
				screen._set_control(op[1], op[2])
			"act":
				screen.experiment_action(op[1])
			"place":
				# What Manipulator does with a finger: pick up, put down (= let go) inside its
				# callback guard (`notifying`: the lab's own state_changed there is not the screen's),
				# then `changed`.
				var xf := Transform3D(Basis.IDENTITY, Vector3(lab.ANCHOR_X + lab.REST_LENGTH + float(op[2]), lab.ROD_Y, 0.0))
				var body: PhysicsBody3D = lab.manipulation_body(op[1])
				var m: Manipulator = screen.manipulator
				m.notifying = true
				lab.change_from_input(lab.manipulation_started.bind(op[1]))
				lab.change_from_input(func() -> void:
					body.global_transform = xf
					lab.manipulation_placed(op[1], xf))
				m.notifying = false
				m.changed.emit()
			"force":
				lab.set_applied_force(float(op[1]))
			"cells":
				lab.set_cells(int(op[1]))
			"layout":
				lab.set_layout(float(op[1]), float(op[2]))
			"stroke":
				lab.set_stroke(int(op[1]), false)
				lab.let_go()
				screen.manipulator.changed.emit()   # the grip let go (the hand's attempt ends there)
		await tree.physics_frame


# --- physics unchanged ----------------------------------------------------------------------------

## The first two attempts of the round on a screen with the round and on one without the missions /
## predict blocks (no tracker): the formula values, the status and every engine body at each step.
func check_physics_unchanged(id: String) -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var plain: Array = await _record(id, false)
	var game: Array = await _record(id, true)
	var first := -1
	for k in mini(plain[0].size(), game[0].size()):
		if plain[0][k] != game[0][k]:
			first = k
			break
	expect.call(first == -1 and plain[0].size() == game[0].size() and plain[0].size() > 30 and plain[1] == game[1] and game[2] == 1,
		"%s: with or without the mission round, the formula values, statuses and engine bodies are the same at every step (and the panels after the run)" % id,
		"first difference at step %d of %d; panels equal %s; game stamps %d" % [first, plain[0].size(), str(plain[1] == game[1]), game[2]])
	DirAccess.remove_absolute(ProgressStore.path)


func _record(id: String, missions: bool) -> Array:
	var definition := ExperimentRegistry.find(id).duplicate(true)
	if not missions:
		definition.erase("missions")
		definition.erase("predict")
	var screen := await _open(definition)
	var lab: Experiment = screen.experiment
	var rows := []
	var bodies := lab.find_children("*", "RigidBody3D", true, false)
	for attempt in ROUNDS[id].slice(0, 2):
		await _ops(screen, attempt[1])
		for k in int(attempt[2]):
			await tree.physics_frame
			await tree.process_frame
			var row := [lab.status(), str(lab.observations())]
			for b: RigidBody3D in bodies:
				row.append(b.global_transform)
			rows.append(row)
	# The panels once the run has its result (the "?" of a hidden answer is gone by then).
	screen._update_readouts(true)
	var panels := []
	for observation in lab.definition.observations:
		panels.append(screen._observation_labels[observation.id].text)
	var stamps := ProgressStore.stamps(ProgressStore.load(), id)
	await _free(screen)
	return [rows, panels, stamps]


# --- pictures -------------------------------------------------------------------------------------

## Every picture kind draws on a choice-sized canvas, and every lab's two choices name two of them.
func check_pictures() -> void:
	var canvas := Control.new()
	canvas.size = Vector2(190.0, 100.0)
	tree.root.add_child(canvas)
	var drawn := []
	for kind in PredictPictures.KINDS:
		var draw := func() -> void:
			PredictPictures.draw(canvas, kind)
			drawn.append(kind)
		canvas.draw.connect(draw)
		canvas.queue_redraw()
		await tree.process_frame
		canvas.draw.disconnect(draw)
	canvas.queue_free()
	var pictured := true
	for definition in ExperimentRegistry.load_all():
		var choices: Array = MissionTracker.predict(definition).get("choices", [])
		pictured = pictured and choices.size() == 2 and choices[0].picture != choices[1].picture
	expect.call(drawn == PredictPictures.KINDS and pictured,
		"pictures: every kind draws; every lab's two choices are two different pictures", str(drawn.size()))


# --- helpers ---------------------------------------------------------------------------------------

func _open(definition: Dictionary) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame
