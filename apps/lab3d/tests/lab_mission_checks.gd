## Plan G2 — the missions of the other 10 labs on their real screens. Per lab a scripted round
## through the screen's own paths (conditions with _set_control, buttons with experiment_action, a
## ball let go where a finger would put it, and the labs' existing test hooks for the hand on a
## press: the push force, the lever's held force, the pulley's stroke): an attempt that misses
## its stage (short, or made under other conditions) earns nothing; each stage is reachable inside
## the lab's control ranges and earns exactly one stamp; the setup that cleared a stage, tried again
## unchanged, never earns the next one (each stage asks for a changed condition: check_conditions
## for every lab). The hidden answers read "?" and the hidden graph lines are not drawn until the
## run has its result; the orbit draws no predicted path before its launch.
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
## ["hand", N] (the lever's held press), ["layout", fulcrum x, load x] (the lever's fulcrum and
## load), ["stroke", cells] (one pulley stroke let go).
const ROUNDS := {
	"free-fall": [
		["the start (the heavy red ball): not the light red ball", [["act", "release"]], 240, 0],
		["the light red ball on the earth: all three land together", [["ctl", "mass", "light"], ["act", "release"]], 240, 1],
		["the light red ball again: the same setup earns nothing", [["act", "release"]], 240, 1],
		["the moon, 7 m: 2.94 s, not past 3", [["ctl", "gravity", "moon"], ["ctl", "height", 7.0], ["act", "release"]], 300, 1],
		["the moon, 7.5 m: 3.04 s, the card reads 3.0초: not past 3 (the number shown is judged)", [["ctl", "height", 7.5], ["act", "release"]], 300, 1],
		["the moon, 8 m: 3.14 s (3.1초)", [["ctl", "height", 8.0], ["act", "release"]], 300, 2],
		["the earth, 4.5 m: 0.96 s, under 1 s but not Jupiter", [["ctl", "gravity", "earth"], ["ctl", "height", 4.5], ["act", "release"]], 150, 2],
		["Jupiter, 8 m: 0.80 s", [["ctl", "gravity", "jupiter"], ["ctl", "height", 8.0], ["act", "release"]], 150, 3],
	],
	"collision": [
		["the start conditions (B is 2 kg): not the two 1 kg balls", [["act", "release"]], 600, 0],
		["two 1 kg balls: B at 2.5 m/s", [["ctl", "mass_b", 1.0], ["act", "release"]], 600, 1],
		["the same two balls again: nothing", [["act", "release"]], 600, 1],
		["a 10 kg A on the 1 kg B: 5.6 m/s", [["ctl", "mass_a", 10.0], ["act", "release"]], 600, 2],
		["again (5.6 m/s, past 5): B is not the lightest, nothing", [["act", "release"]], 600, 2],
		["the 0.5 kg B: 5.9 m/s", [["ctl", "mass_b", 0.5], ["act", "release"]], 600, 3],
	],
	"spring": [
		["놓기 from the start pull 1.2 m: not past 2", [["act", "release"]], 90, 0],
		["a 3 kg ball let go at 2.2 m: not a light ball", [["ctl", "mass", 3.0], ["place", "ball", 2.2]], 90, 0],
		["the 1 kg ball let go at 2 m: the card reads 2.0미터, not past 2", [["ctl", "mass", 1.0], ["place", "ball", 2.0]], 90, 0],
		["the 1 kg ball let go at 2.1 m: past 2", [["place", "ball", 2.1]], 90, 1],
		["the 1 kg ball again (2.81 s a swing): not a heavy ball", [["place", "ball", 2.1]], 220, 1],
		["the 3 kg ball: one swing in 4.87 s", [["ctl", "mass", 3.0], ["place", "ball", 1.6]], 340, 2],
		["the 3 kg ball again (4.87 s): not under 3 s", [["place", "ball", 1.0]], 340, 2],
		["the 1 kg ball: one swing in 2.81 s", [["ctl", "mass", 1.0], ["place", "ball", 1.0]], 220, 3],
	],
	"friction": [
		["the 8 kg start box pushed loose: not the light box", [["force", 40.0]], 90, 0],
		["the light box pushed loose (9 N > 7.8 N)", [["force", 0.0], ["ctl", "mass", "light"], ["force", 9.0]], 90, 1],
		["the light box pushed again: nothing", [["force", 0.0], ["ctl", "mass", "light"], ["force", 9.0]], 90, 1],
		["the normal box held by friction (15 N < 19.6 N)", [["force", 0.0], ["ctl", "mass", "normal"], ["force", 15.0]], 90, 1],
		["the normal box pushed loose (21 N)", [["force", 21.0]], 90, 2],
		["the heavy box held by friction (30 N < 39.2 N)", [["force", 0.0], ["ctl", "mass", "heavy"], ["force", 30.0]], 90, 2],
		["the heavy box pushed loose (41 N)", [["force", 41.0]], 90, 3],
	],
	"rotation": [
		["the middle point lifts with 186.9 N: not the near point", [["hand", 400.0]], 20, 0],
		["the near point: 320.3 N", [["hand", 0.0], ["ctl", "effort", "near"], ["hand", 400.0]], 20, 1],
		["the near point again: nothing", [["hand", 0.0], ["ctl", "effort", "near"], ["hand", 400.0]], 20, 1],
		["the middle point, a 1 kg load: not the 20 kg load", [["hand", 0.0], ["ctl", "effort", "mid"], ["ctl", "mass", 1.0], ["hand", 400.0]], 20, 1],
		["the middle point, 20 kg: 186.9 N", [["hand", 0.0], ["ctl", "mass", 20.0], ["hand", 400.0]], 20, 2],
		["the far point: 124.6 N", [["hand", 0.0], ["ctl", "effort", "far"], ["hand", 400.0]], 20, 3],
	],
	"orbit": [
		["the start (3 m): a circle, not from 4 m", [["act", "launch"]], 300, 0],
		["from 4 m at the circular speed: one lap (9.7 s)", [["ctl", "radius", 4.0], ["act", "circular"], ["act", "launch"]], 700, 1],
		["from 4 m again: nothing", [["act", "launch"]], 700, 1],
		["from 2 m at 3 m/s: it hits the star", [["ctl", "radius", 2.0], ["ctl", "speed", 3.0], ["act", "launch"]], 300, 1],
		["from 2 m at the circular speed: two laps", [["act", "circular"], ["act", "launch"]], 600, 2],
		["from 2 m at 6 m/s: it leaves, but not from 4 m", [["ctl", "speed", 6.0], ["act", "launch"]], 400, 2],
		["from 4 m at 3.6 m/s: far away but still bound (under 3.67)", [["ctl", "radius", 4.0], ["ctl", "speed", 3.6], ["act", "launch"]], 900, 2],
		["from 4 m at 5 m/s: it leaves the star", [["ctl", "speed", 5.0], ["act", "launch"]], 600, 3],
	],
	"buoyancy": [
		["70 kg floats: not the 80 kg drum", [["act", "release"]], 900, 0],
		["80 kg floats", [["ctl", "mass", 80.0], ["act", "release"]], 1200, 1],
		["80 kg again: nothing", [["act", "release"]], 1200, 1],
		["95 kg floats", [["ctl", "mass", 95.0], ["act", "release"]], 1200, 2],
		["50 kg in the small drum stays under (neutral)", [["ctl", "volume", "small"], ["ctl", "mass", 50.0], ["act", "release"]], 900, 2],
		["45 kg in the small drum floats", [["ctl", "mass", 45.0], ["act", "release"]], 1200, 3],
	],
	"constraints": [
		["L = 2 m on the earth: 2.9 s", [["act", "release"]], 330, 0],
		["L = 2.5 m on the earth: 3.24 s", [["ctl", "length", 2.5], ["act", "release"]], 400, 1],
		["L = 2.5 m on the earth again: nothing", [["act", "release"]], 400, 1],
		["the moon, L = 2.5 m: 7.94 s", [["ctl", "gravity", "moon"], ["act", "release"]], 1000, 2],
		["the moon, L = 2.5 m again: 7.94 s, not past 8 (and the same rope)", [["act", "release"]], 1000, 2],
		["the moon, L = 3 m: 8.70 s", [["ctl", "length", 3.0], ["act", "release"]], 1000, 3],
	],
	"pulley": [
		["one strand, a 10 kg load: not the 20 kg load", [["ctl", "mass", 10.0], ["stroke", 20]], 20, 0],
		["one strand, 20 kg: 196.2 N", [["ctl", "mass", 20.0], ["stroke", 20]], 20, 1],
		["one strand, the next stroke: nothing", [["stroke", 20]], 20, 1],
		["two strands: 98.1 N", [["ctl", "strands", "two"], ["stroke", 20]], 20, 2],
		["two strands, the next stroke: nothing", [["stroke", 20]], 20, 2],
		["four strands: 49.05 N", [["ctl", "strands", "four"], ["stroke", 20]], 20, 3],
	],
	"incline-friction": [
		["20° on wood holds", [["act", "release"]], 90, 0],
		["25° on wood: 2.19 m/s², not the steel slope", [["ctl", "angle", 25.0], ["act", "release"]], 90, 0],
		["steel at 25°: 3.43 m/s²", [["ctl", "material", "steel"], ["act", "release"]], 90, 1],
		["steel at 25° again: nothing", [["act", "release"]], 90, 1],
		["wood at 25°: 2.19 m/s²", [["ctl", "material", "wood"], ["act", "release"]], 90, 2],
		["rubber at 35°: 2.25 m/s², not past 3", [["ctl", "material", "rubber"], ["ctl", "angle", 35.0], ["act", "release"]], 90, 2],
		["rubber at 40°: 3.15 m/s²", [["ctl", "angle", 40.0], ["act", "release"]], 90, 3],
	],
}


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_conditions()
	for id in ROUNDS:
		await check_round(id)
	for id in ROUNDS:
		await check_physics_unchanged(id)
	await check_pictures()


# --- conditions -----------------------------------------------------------------------------------

## Every lab with missions: no setup meets the conditions of stage n and of stage n + 1 at once (a
## control both name, with values that cannot both hold), or stage n + 1 names a `change` (another
## value than the run that cleared stage n: the projectile), so repeating the run that cleared a
## stage never clears the next one by itself.
func check_conditions() -> void:
	var shared := []
	for definition in ExperimentRegistry.load_all():
		var stages: Array = MissionTracker.missions(definition).get("stages", [])
		for i in stages.size() - 1:
			# A stage with `change` wants another throw than the one that cleared the stage before.
			if (stages[i + 1].get("change", []) as Array).is_empty() and not _disjoint(stages[i].get("conditions", {}), stages[i + 1].get("conditions", {})):
				shared.append("%s %d-%d" % [definition.id, i + 1, i + 2])
	expect.call(shared.is_empty(), "every lab: the next stage asks for another condition (no setup meets two stages in a row)", ", ".join(shared))


## True when no control values meet both condition sets.
static func _disjoint(a: Dictionary, b: Dictionary) -> bool:
	for id in a:
		if not b.has(id):
			continue
		if a[id] is String or b[id] is String:
			if str(a[id]) != str(b[id]):
				return true
			continue
		var ra := _range(a[id])
		var rb := _range(b[id])
		if ra.y < rb.x - MissionTracker.CONDITION_EPS or rb.y < ra.x - MissionTracker.CONDITION_EPS:
			return true
	return false


static func _range(want: Variant) -> Vector2:
	if want is Dictionary:
		return Vector2(float(want.get("min", -INF)), float(want.get("max", INF)))
	return Vector2(float(want), float(want))


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
	screen._update_readouts(true)
	for series_id in missions.get("hidden_series_until_end", []):
		hidden_ok = hidden_ok and (screen._graph.series.get(series_id, PackedVector2Array()) as PackedVector2Array).is_empty()
	if id == "orbit":
		var props: OrbitProps = lab.props
		hidden_ok = hidden_ok and props.path.multimesh.visible_instance_count == 0 and props.guide.multimesh.visible_instance_count == 0
	expect.call(hidden_ok and screen._missions != null and screen._asking,
		"%s: the round opens with Dugi's question; the hidden answers read ? and no answer line or path is drawn" % id,
		"%s %s" % [str(missions.get("hidden_until_end", [])), str(missions.get("hidden_series_until_end", []))])
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
				var lines: Dictionary = lab.graph_series()
				for series_id in missions.get("hidden_series_until_end", []):
					if screen._graph.series.get(series_id) != lines.get(series_id):
						problems.append("%s: the %s line still hidden after the stamp" % [attempt[0], series_id])
				if id == "orbit" and (lab.props as OrbitProps).path.multimesh.visible_instance_count == 0:
					problems.append("%s: no orbit path after the launch" % attempt[0])
			if stamped_at >= 0 and k >= stamped_at + AFTER_STAMP:
				break
		var stored := ProgressStore.stamps(ProgressStore.load(), id)
		if stored != want or screen._missions.stamps != want:
			problems.append("%s: stamps %d (want %d, status %s, %s)" % [attempt[0], stored, want, lab.status(), _observed(lab)])
	expect.call(problems.is_empty() and ProgressStore.stamps(ProgressStore.load(), id) == 3 and screen._mission_text.text == ExperimentScreen.DONE_TEXT,
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
			"hand":
				lab.set_hand(float(op[1]))   # the held press's force (N; 400 N = its cap)
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
	expect.call(first == -1 and plain[0].size() == game[0].size() and plain[0].size() > 30 and plain[1] == game[1] and game[2] == ROUNDS[id][1][3],
		"%s: with or without the mission round, the formula values, statuses and engine bodies are the same at every step (and the panels after the run)" % id,
		"first difference at step %d of %d; panels equal %s; game stamps %d (want %d)" % [first, plain[0].size(), str(plain[1] == game[1]), game[2], ROUNDS[id][1][3]])
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
