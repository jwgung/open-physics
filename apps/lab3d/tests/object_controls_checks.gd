## Act on the object itself (2026-10-28 user decision: no handles), on the real screens of the five
## labs that had one (collision, orbit, friction, rotation, pulley):
## 1. no handles: no handle / knob / grip / rod node in the lab and no handle or arrow rule; the one
##    gesture is a slingshot pull (ball A, the planet) or a press and hold (the box, the lever's effort
##    end, the rope end).
## 2. hold rates per stage: through the lab's own hold the force reaches the stage's formula force F
##    on step ceil(F / rate x 60); the heaviest stage within ~3 s, the light ones not instant.
## 3. physics unchanged: a hold's run = the same force schedule given without the hand (friction:
##    set_applied_force, the lever: set_hand), every step; a slingshot release = the sidebar values +
##    출발 / 발사, every step.
## 4. empty space: a one-finger drag on empty sky does nothing (no gesture, nothing changes).
## 5. one tap is one: an Android tap (a touch and its emulated mouse press / release) starts one hold
##    and ends it once, and a tap on a slingshot object pulls once and throws nothing.
extends RefCounted

const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const TABLET := Vector2(1152, 720)
const STEP_HZ := 60
const LABS := ["collision", "orbit", "friction", "rotation", "pulley"]
const GESTURE := {"collision": ["ball_a", "slingshot"], "orbit": ["planet", "slingshot"], "friction": ["box", "hold"],
	"rotation": ["effort", "hold"], "pulley": ["rope", "hold"]}

var tree: SceneTree
var expect: Callable


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	for id in LABS:
		await check_no_handles(id)
	await check_hold_rates()
	await check_hold_is_the_force()
	await check_pull_is_the_sidebar("collision")
	await check_pull_is_the_sidebar("orbit")
	for id in LABS:
		await check_empty_space(id)
	await check_one_tap("friction")
	await check_one_tap("collision")


# --- helpers ------------------------------------------------------------------------------------

func _open(id: String) -> Control:
	DirAccess.remove_absolute(ProgressStore.path)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	for i in 3:
		await tree.process_frame
	screen._end_question()
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProgressStore.path)


func _lab(id: String) -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find(id))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _touch(screen: Control, position: Vector2, pressed: bool, index := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	screen.view._gui_input(event)


func _drag(screen: Control, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	screen.view._gui_input(event)


## Android's emulated mouse event of a touch (the duplicate every tap brings).
func _emulated(screen: Control, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	screen.view._gui_input(event)


# --- 1. no handles --------------------------------------------------------------------------------

func check_no_handles(id: String) -> void:
	var screen := await _open(id)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var problems := []
	for pattern in ["*Handle*", "*Knob*", "*Grip*", "*Rod*"]:
		for node in lab.find_children(pattern, "", true, false):
			problems.append("node %s" % node.name)
	for rule_id in m.rules:
		if str(rule_id).contains("handle") or str(rule_id).contains("arrow"):
			problems.append("rule %s" % rule_id)
	var gesture: Array = GESTURE[id]
	if m.draggable_ids() != [gesture[0]]:
		problems.append("gesture objects %s" % str(m.draggable_ids()))
	if gesture[1] == "slingshot" and m.slingshot_id != gesture[0]:
		problems.append("slingshot %s" % m.slingshot_id)
	if gesture[1] == "hold" and not m.rules[gesture[0]].hold:
		problems.append("%s is not a hold" % gesture[0])
	# The press on the object starts its gesture (and nothing else).
	var at: Vector2 = screen.view_point(lab.manipulation_pick_point(gesture[0]))
	m.handle_pointer("press", at)
	if m.mode != gesture[1] or m.active_id != gesture[0]:
		problems.append("a press on %s started '%s' %s" % [gesture[0], m.mode, m.active_id])
	m.cancel()
	expect.call(problems.is_empty(), "no handles (%s, 2026-10-28): no handle, knob, grip or rod; the one gesture is a %s of %s" % [id, gesture[1], gesture[0]], "; ".join(problems))
	await _close(screen)


# --- 2. hold rates --------------------------------------------------------------------------------

## Steps of holding until `reached` (Callable) on lab `id` with `controls` set.
func _steps_to(id: String, controls: Dictionary, hold_id: String, reached: Callable) -> int:
	var lab := await _lab(id)
	for c in controls:
		lab.set_control(c, controls[c])
	lab.hold_started(hold_id)
	var steps := -1
	for i in 6 * STEP_HZ:
		await tree.physics_frame
		if reached.call(lab):
			steps = lab.push.steps if id == "friction" else lab.hand.steps
			break
	lab.hold_ended(hold_id)
	lab.queue_free()
	await tree.process_frame
	return steps


func check_hold_rates() -> void:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.81)
	# [lab, label, controls, hold id, F (N), rate (N/s), reached]
	var cases := [
		["friction", "light 2 kg wood", {"mass": "light"}, "box", 0.4 * 2.0 * g, 25.0],
		["friction", "normal 5 kg wood", {"mass": "normal"}, "box", 0.4 * 5.0 * g, 25.0],
		["friction", "heavy 10 kg wood", {"mass": "heavy"}, "box", 0.4 * 10.0 * g, 25.0],
		["friction", "heaviest: 10 kg clay", {"mass": "heavy", "material": "clay"}, "box", 0.76 * 10.0 * g, 25.0],
		["rotation", "20 kg far", {"effort": "far"}, "effort", 20.0 * g * 2.0 / 3.15, 110.0],
		["rotation", "20 kg mid", {"effort": "mid"}, "effort", 20.0 * g * 2.0 / 2.1, 110.0],
		["rotation", "heaviest: 20 kg near", {"effort": "near"}, "effort", 20.0 * g * 2.0 / 1.225, 110.0],
		["pulley", "20 kg on 4 strands", {"strands": "four"}, "rope", 20.0 * g / 4.0, 65.0],
		["pulley", "20 kg on 2 strands", {"strands": "two"}, "rope", 20.0 * g / 2.0, 65.0],
		["pulley", "heaviest: 20 kg on 1 strand", {"strands": "one"}, "rope", 20.0 * g, 65.0],
	]
	var reached := {
		"friction": func(lab: Experiment) -> bool: return not lab.model.holding,
		"rotation": func(lab: Experiment) -> bool: return lab.model.lifting(),
		"pulley": func(lab: Experiment) -> bool: return lab._moving_steps > 0,
	}
	var problems := []
	var times := []
	var heaviest := {}
	var lightest := {}
	for c in cases:
		var steps := await _steps_to(c[0], c[2], c[3], reached[c[0]])
		var want := ceili(float(c[4]) / float(c[5]) * STEP_HZ - 1e-9)
		if c[0] == "friction":
			want = ceili(float(c[4]) / float(c[5]) * STEP_HZ + 1e-9)   # the box starts above mu_s m g, holds at it
		if steps != want:
			problems.append("%s %s: step %d, formula %d" % [c[0], c[1], steps, want])
		var seconds := steps / float(STEP_HZ)
		times.append("%s %s %.2f s" % [c[0], c[1], seconds])
		heaviest[c[0]] = maxf(heaviest.get(c[0], 0.0), seconds)
		lightest[c[0]] = minf(lightest.get(c[0], INF), seconds)
	for id in heaviest:
		if heaviest[id] > 3.05:
			problems.append("%s heaviest %.2f s" % [id, heaviest[id]])
		if lightest[id] < 0.3:
			problems.append("%s lightest stage %.2f s (instant)" % [id, lightest[id]])
	expect.call(problems.is_empty(), "hold rates: the force reaches each stage's formula force on step ceil(F / rate x 60); the heaviest within ~3 s, no stage instant (%s)" % "; ".join(times),
		"; ".join(problems))


# --- 3. physics unchanged -------------------------------------------------------------------------

## Records the friction lab's formula and engine box for `steps` steps; `drive` (lab, k) runs before
## step k (1-based, from the call).
func _friction_run(drive: Callable, steps: int) -> Array:
	var lab := await _lab("friction")
	lab.set_control("mass", "light")
	var out := []
	var start: int = lab.frames
	for k in range(1, steps + 1):
		drive.call(lab, k)
		while lab.frames < start + k:
			await tree.physics_frame
		out.append([lab.model.applied, lab.model.velocity, lab.model.displacement, lab.status(), lab.box.global_position.x])
	lab.queue_free()
	await tree.process_frame
	return out


func check_hold_is_the_force() -> void:
	# Friction: a 1.5 s hold, then let go; against the same ramp given as set_applied_force.
	var held := await _friction_run(func(lab: Experiment, k: int) -> void:
		if k == 1:
			lab.hold_started("box")
		elif k == 91:
			lab.hold_ended("box"), 180)
	var given := await _friction_run(func(lab: Experiment, k: int) -> void:
		lab.set_applied_force(minf(80.0, 25.0 * k / 60.0) if k <= 90 else 0.0), 180)
	var moved: bool = held[-1][2] > 0.1 and held[100][0] == 0.0
	expect.call(held == given and moved,
		"physics unchanged (friction): a 1.5 s hold and its let-go = the same force ramp given without the hand (applied force, speed, distance, state, engine box every step)",
		"first difference at step %d; moved %s" % [_first_diff(held, given), moved])
	# The lever: the hold's force on the beam = set_hand with the same ramp, step by step.
	var lever_held := []
	var lever_given := []
	for pass_hand in [true, false]:
		var lab := await _lab("rotation")
		if pass_hand:
			lab.hold_started("effort")
		else:
			lab.set_hand(110.0 / 60.0)   # the hold's first step
		var out := []
		for k in range(1, 151):
			await tree.physics_frame   # the record: the state after step k
			out.append([lab.model.applied(), lab.model.lifting(), lab.driver.engine_angle(), lab.load_body.global_position])
			if not pass_hand:
				lab.set_hand(minf(400.0, 110.0 * (k + 1) / 60.0))   # the force of step k + 1
		(lever_held if pass_hand else lever_given).append_array(out)
		lab.queue_free()
		await tree.process_frame
	expect.call(lever_held == lever_given and lever_held[-1][1],
		"physics unchanged (lever): holding the effort end = set_hand with the same 110 N/s ramp (force on the beam, lifting, engine beam and load every step)",
		"first difference at %d: %s" % [_first_diff(lever_held, lever_given), _diff_text(lever_held, lever_given)])


func _diff_text(a: Array, b: Array) -> String:
	var i := _first_diff(a, b)
	if i < 0 or i >= mini(a.size(), b.size()):
		return ""
	return "%s vs %s" % [str(a[i]).substr(0, 400), str(b[i]).substr(0, 400)]


func _first_diff(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


## A slingshot release = the sidebar values + 출발 / 발사: the same run step by step.
func check_pull_is_the_sidebar(id: String) -> void:
	var runs := []
	var value := [0.0, 0.0]   # 64-bit, as the sliders give them
	for by_pull in [true, false]:
		var screen := await _open(id)
		var lab: Experiment = screen.experiment
		if by_pull:
			var body: Node3D = lab.manipulation_body(GESTURE[id][0])
			var at: Vector2 = screen.view_point(body.global_position)
			var to: Vector2 = screen.view_point(lab.launch_point() + (Vector3(-1.4, 0.0, 0.0) if id == "collision" else Vector3(-0.5, 0.0, 1.6)))
			_touch(screen, at, true)
			for i in range(1, 9):
				_drag(screen, at.lerp(to, i / 8.0))
			_touch(screen, to, false)
			value = [lab.control_value("velocity_a"), 0.0] if id == "collision" else [lab.control_value("direction"), lab.control_value("speed")]
		else:
			if id == "collision":
				screen._set_control("velocity_a", value[0])
				screen.experiment_action("release")
			else:
				screen._set_control("direction", value[0])
				screen._set_control("speed", value[1])
				screen.experiment_action("launch")
		var out := []
		for k in 180:
			await tree.physics_frame
			var bodies := []
			for b in lab.find_children("*", "RigidBody3D", true, false):
				bodies.append((b as Node3D).global_position)
			out.append([str(lab.observations()), bodies])
		runs.append(out)
		await _close(screen)
	expect.call(runs[0] == runs[1] and value[0] != 0.0,
		"physics unchanged (%s): a slingshot release (%s) = the same values set in 자세히 and %s, every step (panel and bodies)" % [id, str(value), "출발" if id == "collision" else "발사"],
		"first difference at step %d: %s" % [_first_diff(runs[0], runs[1]), _diff_text(runs[0], runs[1])])


# --- 4. empty space -------------------------------------------------------------------------------

func check_empty_space(id: String) -> void:
	var screen := await _open(id)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var problems := []
	# An empty point: nothing within the pick radius (the sky above the lab).
	var empty := Vector2.INF
	for y in [90.0, 130.0, 170.0]:
		for x in [screen.view.size.x * 0.3, screen.view.size.x * 0.5, screen.view.size.x * 0.7]:
			if empty == Vector2.INF and m._pick(Vector2(x, y)) == "":
				empty = Vector2(x, y)
	if empty == Vector2.INF:
		problems.append("no empty point")
	else:
		var before := [str(lab.observations()), lab.status()]
		var pan_before: Vector3 = screen.view.rig.pan
		_touch(screen, empty, true)
		for i in range(1, 7):
			_drag(screen, empty + Vector2(30.0 * i, 12.0 * i))
			await tree.physics_frame
			if m.mode != "":
				problems.append("drag started '%s'" % m.mode)
				break
		_touch(screen, empty + Vector2(180.0, 72.0), false)
		await tree.physics_frame
		var after := [str(lab.observations()), lab.status()]
		if after != before:
			problems.append("changed: %s -> %s" % [str(before), str(after)])
		# The finger on an empty spot moves the camera (2026-10-30) and nothing else.
		if screen.view.rig.pan == pan_before:
			problems.append("the view did not follow the finger")
	expect.call(problems.is_empty(), "empty space (%s): a one-finger drag on the empty sky moves the camera only (no manipulation, panel or status change)" % id, "; ".join(problems))
	await _close(screen)


# --- 5. one tap is one ----------------------------------------------------------------------------

func check_one_tap(id: String) -> void:
	var screen := await _open(id)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var gesture: Array = GESTURE[id]
	var at: Vector2 = screen.view_point(lab.manipulation_pick_point(gesture[0]))
	var events := []
	m.changed.connect(func() -> void: events.append("changed"))
	m.slingshot.connect(func(state: String, _value: Variant) -> void: events.append(state))
	# Android: the touch, then its emulated mouse press; the finger stays 0.5 s; the emulated release
	# and the touch's release.
	_touch(screen, at, true)
	_emulated(screen, at, true)
	var during := m.mode
	for i in 30:
		await tree.physics_frame
	var force := 0.0
	if id == "friction":
		force = lab.applied_force()
	_emulated(screen, at, false)
	_touch(screen, at, false)
	await tree.physics_frame
	var ok := false
	if id == "friction":
		var steps: int = roundi(force / 25.0 * STEP_HZ)
		ok = during == "hold" and steps >= 29 and steps <= 31 and absf(force - 25.0 * steps / STEP_HZ) < 1e-9 and events == ["changed"] and lab.applied_force() == 0.0
	else:
		ok = during == "slingshot" and events == ["pull", "cancel", "changed"] and not lab.released
	expect.call(ok, "one tap is one (%s): a touch with its emulated mouse duplicate starts one %s and ends it once (%s)" % [id, gesture[1], "the push 25 N/s for 0.5 s" if id == "friction" else "no throw"],
		"mode %s, events %s, force %.2f" % [during, str(events), force])
	await _close(screen)
