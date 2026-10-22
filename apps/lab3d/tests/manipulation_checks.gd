## Headless checks of the shell's object manipulation (Phase 1 Task 2b), run by run_tests.gd:
## surface projection and snap (ManipSurface), the camera assist, registry rules, and the real
## input path (View3D touches -> Manipulator -> experiment) on the incline experiment and the
## development scene: drag along the incline with grid snap, places that cannot be used, cancel
## (second finger, system cancel), the height handle and overlap with other objects.
## The displayed numbers after a new start position are checked against the TS-core vectors
## (tests/incline_vectors.json "runs").
extends RefCounted

const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60

var tree: SceneTree
var expect: Callable   # (ok: bool, label: String, detail: String)
var vectors: Dictionary


func _init(scene_tree: SceneTree, expect_fn: Callable, parity_vectors: Dictionary) -> void:
	tree = scene_tree
	expect = expect_fn
	vectors = parity_vectors


func run(definition: Dictionary) -> void:
	check_surface()
	check_registry(definition)
	check_assist(definition)
	check_assist_search(definition)
	check_assist_limited_yaw(definition)
	check_assist_user_turn(definition)
	check_height_snap()
	await check_incline_drag(definition)
	await check_incline_relanding(definition)
	await check_incline_runs(definition)
	await check_dev_scene()
	await check_dev_review()
	await check_follow_camera()
	await check_review2()
	await check_incline_snap_rule(definition)


# --- pure parts -----------------------------------------------------------------------------------

func check_surface() -> void:
	var floor := ManipSurface.new(Transform3D.IDENTITY, Vector2(-4, -3), Vector2(4, 3), Vector2(0.25, 0.25))
	var p: Variant = floor.project_ray(Vector3(1.3, 10.0, -0.7), Vector3(0.0, -1.0, 0.0), 0.25)
	expect.call(p is Vector2 and p.is_equal_approx(Vector2(1.3, -0.7)), "projection: a ray straight down lands below it", str(p))
	var slanted: Variant = floor.project_ray(Vector3(0.0, 5.0, 5.0), Vector3(0.0, -1.0, -1.0), 1.0)
	expect.call(slanted is Vector2 and slanted.is_equal_approx(Vector2(0.0, 1.0)), "projection: the object's centre height is the plane", str(slanted))
	var grazing: Variant = floor.project_ray(Vector3(0.0, 1.0, 10.0), Vector3(0.0, -0.05, -1.0), 0.0)
	var away: Variant = floor.project_ray(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0), 0.0)
	expect.call(grazing == null and away == null, "projection: a grazing ray or a ray pointing away does not move the object", "%s / %s" % [str(grazing), str(away)])
	expect.call(floor.snap_point(Vector2(1.13, -0.62)).is_equal_approx(Vector2(1.25, -0.5)) and floor.contains(Vector2(4, 3)) and not floor.contains(Vector2(4.1, 0)),
		"snap to the 0.25 m grid; region bounds", str(floor.snap_point(Vector2(1.13, -0.62))))
	expect.call(floor.clamp_soft(Vector2(50, -50), 0.6).is_equal_approx(Vector2(4.6, -3.6)), "a dragged object leaves the region by at most the soft margin", str(floor.clamp_soft(Vector2(50, -50), 0.6)))
	# A line (incline): the closest point of the line to the ray, also when the plane is grazed.
	var tilt := Transform3D(Basis(Vector3.BACK, deg_to_rad(30.0)), Vector3(0.0, 3.0, 0.0))
	var line := ManipSurface.new(tilt, Vector2(-3, 0), Vector2(3.5, 0), Vector2(0.5, 0))
	var along := tilt * Vector3(2.0, 0.2, 0.0)
	var from_side := along + Vector3(0.0, 0.0, 6.0)
	var q: Variant = line.project_ray(from_side, (along - from_side).normalized(), 0.2)
	var flat_eye := tilt * Vector3(2.0, 0.2, 6.0)
	var flat: Variant = line.project_ray(flat_eye, (along - flat_eye).normalized(), 0.2)   # in the incline's own plane
	var parallel: Variant = line.project_ray(tilt * Vector3(9.0, 0.2, 0.0), tilt.basis * Vector3(-1.0, 0.0, 0.0), 0.2)
	expect.call(q is Vector2 and absf(q.x - 2.0) < 1e-4 and flat is Vector2 and absf(flat.x - 2.0) < 1e-4 and parallel == null,
		"line projection: closest point along the incline, works in its plane, none when looking along it", "%s %s %s" % [str(q), str(flat), str(parallel)])
	expect.call(line.nearest_inside(Vector2(3.9, 0.0)).is_equal_approx(Vector2(3.5, 0.0)) and line.nearest_inside(Vector2(-2.8, 0.0)).is_equal_approx(Vector2(-3.0, 0.0)),
		"nearest grid point inside the region", str(line.nearest_inside(Vector2(3.9, 0.0))))


func check_registry(definition: Dictionary) -> void:
	expect.call(ExperimentRegistry.validate(definition).is_empty() and definition.has("manipulation"), "incline declares its manipulation rules", "")
	var broken := definition.duplicate(true)
	broken.manipulation.objects.append({"id": "box", "surface": "incline"})
	broken.manipulation.objects.append({"id": "x", "surface": "floor", "height": {"max": 0}})
	broken.manipulation.objects.append({"id": "y", "surface": "floor", "snap": -1})
	broken.manipulation.objects.append({"id": "z"})
	broken.manipulation.objects.append({"id": "w", "surface": "floor", "height": {"max": 1.0, "step": 0.4}})
	broken.manipulation.objects.append({"id": "v", "surface": "floor", "height": {"max": 5, "step": 2}})  # ints: no integer division
	var problems := ExperimentRegistry.validate(broken)
	expect.call(problems.size() == 6, "registry rejects bad manipulation rules (duplicate, height, snap, surface, max not a step multiple, int max/step)", ", ".join(problems))
	var listed := ExperimentRegistry.load_all().map(func(d: Dictionary) -> String: return d.id)
	var dev := ExperimentRegistry.find("manipulation-dev")
	expect.call(not dev.is_empty() and "manipulation-dev" not in listed, "the development scene opens by id but is not listed", str(listed))


func check_assist(definition: Dictionary) -> void:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var rig := CameraRig.new()
	holder.add_child(rig)
	var probe := Node3D.new()
	probe.set_script(load("res://tests/follow_probe.gd"))
	holder.add_child(probe)
	rig.follow_source = probe
	rig.configure(definition.camera)
	var tilt := Basis(Vector3.BACK, deg_to_rad(20.0))
	var downhill := tilt * Vector3(-1.0, 0.0, 0.0)
	var normal := tilt * Vector3.UP
	rig.set_mode("top", true)
	var turned := rig.begin_assist(normal, downhill)
	rig.end_assist()
	expect.call(not turned, "assist leaves a view that already shows the incline's face (top)", "")
	for preset in ["three_quarter", "side"]:
		rig.set_mode(preset, true)
		var yaw := rig.goal_yaw
		var pitch_before := rig.goal_pitch
		var face_before := rad_to_deg(asin(absf(CameraRig.view_direction(yaw, pitch_before).dot(normal))))
		turned = rig.begin_assist(normal, downhill)
		var ok := CameraRig.assist_ok(rig.goal_yaw, rig.goal_pitch, normal, downhill)
		var change := rad_to_deg(absf(rig.goal_yaw - yaw) + absf(rig.goal_pitch - pitch_before))
		var face := rad_to_deg(asin(absf(CameraRig.view_direction(rig.goal_yaw, rig.goal_pitch).dot(normal))))
		rig.end_assist()
		expect.call(turned and ok and change < 60.0 and is_equal_approx(rig.goal_yaw, yaw) and is_equal_approx(rig.goal_pitch, pitch_before) and rig.mode == preset,
			"assist turns the %s view to see the incline's face (and turns back)" % preset, "face %.1f -> %.1f deg, turned %.1f deg" % [face_before, face, change])
	rig.set_mode("front", true)
	turned = rig.begin_assist(Vector3.UP, Vector3.ZERO)
	var pitch := rad_to_deg(rig.goal_pitch)
	rig.end_assist()
	expect.call(turned and pitch <= -24.9 and pitch > -35.0, "assist looks down at the floor from the flat front view", "pitch %.1f deg" % pitch)
	rig.set_mode("follow", true)
	probe.position = Vector3(1, 2, 3)
	rig.begin_assist(Vector3.UP, Vector3.ZERO)
	var held := rig._goal_target()
	probe.position = Vector3(4, 2, 3)
	var still := rig._goal_target().is_equal_approx(held)
	rig.end_assist()
	expect.call(still and rig._goal_target().is_equal_approx(Vector3(4, 2, 3)), "follow target is held while dragging", str(held))
	holder.queue_free()


## Brute-force reference of the assist search (the 2.5 deg grid over the whole limits): the least
## yaw + pitch change of a satisfying view, INF if none.
func _brute_assist_cost(rig: CameraRig, normal: Vector3, axis: Vector3) -> float:
	var best := INF
	var step := deg_to_rad(2.5)   # the grid of the former exhaustive search
	var yaw := rig.yaw_range.x
	while yaw <= rig.yaw_range.y + 0.0001:
		var pitch := rig.pitch_range.x
		while pitch <= rig.pitch_range.y + 0.0001:
			var cost := absf(angle_difference(rig.goal_yaw, yaw)) + absf(pitch - rig.goal_pitch)
			if cost < best and CameraRig.assist_ok(yaw, pitch, normal, axis):
				best = cost
			pitch += step
		yaw += step
	return best


func _rig_for(definition: Dictionary) -> CameraRig:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var rig := CameraRig.new()
	holder.add_child(rig)
	rig.configure(definition.camera)
	return rig


## The assist search finds a view at least as close as the full grid search, with a few dozen checks.
func check_assist_search(definition: Dictionary) -> void:
	var rig := _rig_for(definition)
	var tilt := Basis(Vector3.BACK, deg_to_rad(20.0))
	var downhill := tilt * Vector3(-1.0, 0.0, 0.0)
	var normal := tilt * Vector3.UP
	var cases := [
		["front", normal, downhill], ["three_quarter", normal, downhill], ["side", normal, downhill],
		["front", Vector3.UP, Vector3.ZERO], ["side", Vector3.UP, Vector3.ZERO],
		["three_quarter", Vector3.ZERO, normal], ["front", Vector3.ZERO, Vector3.UP],
	]
	var worst_checks := 0
	var worse := ""
	var unsatisfied := ""
	for c in cases:
		rig.set_mode(c[0], true)
		var yaw := rig.goal_yaw
		var pitch := rig.goal_pitch
		var brute := _brute_assist_cost(rig, c[1], c[2])
		var stats := {}
		var turned := rig.begin_assist(c[1], c[2], stats)
		worst_checks = maxi(worst_checks, stats.checks)
		var cost := absf(angle_difference(yaw, rig.goal_yaw)) + absf(pitch - rig.goal_pitch)
		if turned and not CameraRig.assist_ok(rig.goal_yaw, rig.goal_pitch, c[1], c[2]):
			unsatisfied += " %s" % c[0]
		if turned and cost > brute + 1e-6:
			worse += " %s(%.1f>%.1f)" % [c[0], rad_to_deg(cost), rad_to_deg(brute)]
		rig.end_assist()
	expect.call(unsatisfied == "" and worse == "", "assist search: the turn is never bigger than the full-grid search finds, and satisfies the limits", "unsatisfied:%s worse:%s" % [unsatisfied, worse])
	expect.call(worst_checks <= 120, "assist search takes about a hundred checks at most, not the whole grid (~2800)", "worst %d checks" % worst_checks)
	rig.get_parent().queue_free()


## A limited yaw range is crossed directly: the refinement must not go the "short way round" out of it.
func check_assist_limited_yaw(definition: Dictionary) -> void:
	var rig := _rig_for(definition)
	var pitch := deg_to_rad(-58.1203689575195)
	rig.yaw_range = Vector2(deg_to_rad(-100.0), deg_to_rad(100.0))
	rig.pitch_range = Vector2(pitch, pitch)
	rig.goal_yaw = deg_to_rad(95.0)
	rig.goal_pitch = pitch
	# Only yaw -100..-90 deg satisfies these (found by search), 185 deg from the goal.
	var normal := Vector3(-0.553838, 0.15916, -0.817271)
	var axis := Vector3(-0.159272, -0.516561, 0.841307)
	var turned := rig.begin_assist(normal, axis)
	var yaw := rad_to_deg(rig.goal_yaw)
	var ok := CameraRig.assist_ok(rig.goal_yaw, rig.goal_pitch, normal, axis)
	rig.end_assist()
	expect.call(turned and ok and yaw >= -100.001 and yaw <= -89.9 and is_equal_approx(rad_to_deg(rig.goal_yaw), 95.0),
		"assist in a limited yaw range stays inside it (goal 95 deg, answer near -90 deg)", "yaw %.2f deg" % yaw)
	rig.get_parent().queue_free()


## The user turning the view while an object is held keeps that view after the drop.
func check_assist_user_turn(definition: Dictionary) -> void:
	var rig := _rig_for(definition)
	rig.set_mode("front", true)
	rig.orbit(Vector2(0.0, -40000.0))   # as flat as the limits allow
	var original := rig.get_state()
	var turned := rig.begin_assist(Vector3.UP, Vector3.ZERO)
	var during := rig.get_state()
	rig.orbit(Vector2(120.0, 20.0))   # the user turns the view while holding
	var yaw := rig.goal_yaw
	var pitch := rig.goal_pitch
	var state := rig.get_state()
	rig.end_assist()
	expect.call(turned and is_equal_approx(during.pitch, original.pitch) and is_equal_approx(state.yaw, yaw) and is_equal_approx(state.pitch, pitch)
		and is_equal_approx(rig.goal_yaw, yaw) and is_equal_approx(rig.goal_pitch, pitch) and not is_equal_approx(pitch, original.pitch),
		"a view the user turned while holding is kept after the drop (and is what get_state reports)", "pitch %.3f -> %.3f (was %.3f)" % [during.pitch, rig.goal_pitch, original.pitch])
	rig.get_parent().queue_free()


func check_height_snap() -> void:
	var m := Manipulator.new()
	var rule := {"height_max": 1.0, "height_step": 0.4}
	var top: float = m._snap_height(rule, 1.0)
	var over: float = m._snap_height(rule, 7.0)
	var mid: float = m._snap_height(rule, 0.9)
	var below: float = m._snap_height(rule, -0.3)
	expect.call(top <= 1.0 and over <= 1.0 and is_equal_approx(mid, 0.8) and is_equal_approx(below, 0.0),
		"height snap never exceeds the maximum (also when it is not a step multiple)", "%.2f %.2f %.2f %.2f" % [top, over, mid, below])
	m.free()


# --- incline: the real input path ------------------------------------------------------------------

func _open(definition: Dictionary) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(720, 1560)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame


## View position (UI units) of a world point.
func _at(screen: Control, world: Vector3) -> Vector2:
	var view: View3D = screen.view
	return view.rig.unproject_position(world) / (Vector2(view.viewport.size) / view.size)


func _touch(screen: Control, index: int, position: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	screen.view._gui_input(event)


func _drag(screen: Control, index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	screen.view._gui_input(event)


## One finger from `from` to `to` in `steps` drag events (no release).
func _swipe(screen: Control, from: Vector2, to: Vector2, steps := 8) -> void:
	_touch(screen, 0, from, true)
	for i in range(1, steps + 1):
		_drag(screen, 0, from.lerp(to, float(i) / steps))


## Screen point of the incline box centre at run length `run` (m from the lower end).
func _run_point(screen: Control, run: float) -> Vector2:
	var lab: Experiment = screen.experiment
	return _at(screen, lab._pivot.global_transform * Vector3(run - lab.INCLINE_LENGTH * 0.5, lab.BOX * 0.5, 0.0))


func check_incline_drag(definition: Dictionary) -> void:
	var screen: Control = await _open(definition)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var box: RigidBody3D = lab.box
	expect.call(m != null and m.rules.has("box"), "incline screen has a manipulator for the box", "")
	# Drag the box from its default start (run 7.5 m) to run 4.0 m.
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 4.0))
	var held_lift: float = lab.props.juice._lift_goal
	var markers: Array = m._markers.get("box", [])
	var ok_marker_shown: bool = markers.size() == 2 and markers[0].visible and not markers[1].visible
	expect.call(m.mode == "drag" and box.freeze and held_lift > 0.0 and ok_marker_shown and m.valid,
		"picking the box freezes it, lifts its mesh and shows the white footprint", "mode %s, lift %.2f" % [m.mode, held_lift])
	_touch(screen, 0, _run_point(screen, 4.0), false)
	expect.call(m.mode == "" and is_equal_approx(lab.run_length(), 4.0) and box.freeze and lab.status() == "ready"
		and absf(lab._pivot.to_local(box.global_position).x - 0.0) < 1e-4 and is_equal_approx(lab.observations().run, 4.0),
		"putting the box down moves the start to run 4.0 m (box at rest on the incline)", "run %.3f, x %.3f" % [lab.run_length(), lab._pivot.to_local(box.global_position).x])
	expect.call(absf(lab._mark.position.x - (0.0 - lab.BOX * 0.5)) < 1e-4 and not markers[0].visible, "start line follows the box; footprint hidden after", "")
	# Snap: 5.2 m -> 5.0, 5.3 m -> 5.5.
	for pair in [[5.2, 5.0], [5.3, 5.5]]:
		_swipe(screen, _at(screen, box.global_position), _run_point(screen, pair[0]), 6)
		_touch(screen, 0, _run_point(screen, pair[0]), false)
		expect.call(is_equal_approx(lab.run_length(), pair[1]), "start snaps to the 0.5 m ticks (%.1f -> %.1f m)" % pair, "%.3f" % lab.run_length())
	# Below the shortest run (and past the lower end): blocked, shakes, puts the box back.
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 0.6), 8)
	var blocked_marker: bool = markers[1].visible and not markers[0].visible
	var wobbling: bool = lab.props.juice.is_animating() and (absf(lab.props.juice._wobble_v) > 0.0 or absf(lab.props.juice._wobble) > 0.0)
	var held_inside: float = lab._pivot.to_local(box.global_position).x
	expect.call(not m.valid and blocked_marker and wobbling and held_inside >= -3.0 - m.SOFT_MARGIN - 1e-4,
		"a place off the allowed part of the incline shows the dark footprint and wobbles; the box stays near it", "x %.2f" % held_inside)
	_touch(screen, 0, _run_point(screen, 0.6), false)
	expect.call(is_equal_approx(lab.run_length(), 5.5) and m.mode == "" and lab.status() == "ready", "letting go there puts the box back at its start", "run %.2f" % lab.run_length())
	# Far past the lower end (3 m beyond the incline): the box stops at the soft margin.
	var far := _run_point(screen, -3.0)
	_swipe(screen, _at(screen, box.global_position), far, 4)
	var x: float = lab._pivot.to_local(box.global_position).x
	expect.call(absf(x - (-3.0 - m.SOFT_MARGIN)) < 1e-3 and not m.valid, "dragging far past the incline keeps the box at the soft margin", "x %.2f" % x)
	_touch(screen, 0, far, false)
	# Second finger: cancel, box back at the start, no camera jump.
	var start := box.global_transform
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 2.0), 6)
	_touch(screen, 1, Vector2(600, 200), true)
	expect.call(m.mode == "" and box.global_transform.is_equal_approx(start) and is_equal_approx(lab.run_length(), 5.5) and not screen.view.rig.is_assisting(),
		"a second finger cancels the drag (box back at its start)", "run %.2f" % lab.run_length())
	_touch(screen, 1, Vector2(600, 200), false)
	_touch(screen, 0, _run_point(screen, 2.0), false)
	expect.call(is_equal_approx(lab.run_length(), 5.5), "lifting the fingers after a cancelled drag does not place it", "run %.2f" % lab.run_length())
	# System cancel (the touch is cancelled): same as the second finger.
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 2.0), 6)
	_touch(screen, 0, _run_point(screen, 2.0), false, true)
	expect.call(m.mode == "" and box.global_transform.is_equal_approx(start), "a cancelled touch puts the box back", "")
	# Mouse: left drag works like one finger.
	var mouse_from := _at(screen, box.global_position)
	var mouse_to := _run_point(screen, 3.0)
	screen.view._gui_input(_mouse(MOUSE_BUTTON_LEFT, true, mouse_from))
	var motion := InputEventMouseMotion.new()
	motion.position = mouse_to
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	screen.view._gui_input(motion)
	screen.view._gui_input(_mouse(MOUSE_BUTTON_LEFT, false, mouse_to))
	expect.call(is_equal_approx(lab.run_length(), 3.0), "left mouse drag moves the box like a finger", "run %.2f" % lab.run_length())
	# Mouse held while the view is left (settings opened / tree exit): same as a system cancel.
	var held_from := _at(screen, box.global_position)
	var held_run: float = lab.run_length()
	var held_xf := box.global_transform
	screen.view._gui_input(_mouse(MOUSE_BUTTON_LEFT, true, held_from))
	var held_motion := InputEventMouseMotion.new()
	held_motion.position = _run_point(screen, 1.5)
	held_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	screen.view._gui_input(held_motion)
	var held_by_mouse: bool = m.mode == "drag" and box.freeze and not box.global_transform.is_equal_approx(held_xf)
	screen.view.reset_input()
	expect.call(held_by_mouse and m.mode == "" and box.global_transform.is_equal_approx(held_xf)
		and is_equal_approx(lab.run_length(), held_run) and not screen.view.rig.is_assisting(),
		"leaving the view while the mouse holds the box puts it back (back at its start, assist off)", "held %s, mode %s, run %.2f" % [held_by_mouse, m.mode, lab.run_length()])
	screen.view._gui_input(_mouse(MOUSE_BUTTON_LEFT, false, held_motion.position))
	expect.call(is_equal_approx(lab.run_length(), held_run), "the mouse release after that does not place the box", "run %.2f" % lab.run_length())
	# A camera mode button pressed while holding: the new mode wins over the assist's old view.
	var rig: CameraRig = screen.view.rig
	rig.set_mode("front", true)
	rig.orbit(Vector2(0.0, -40000.0))   # as flat as the limits allow
	var flat_pitch := rig.goal_pitch
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 2.0), 4)
	var turned: bool = rig.is_assisting() and not is_equal_approx(rig.goal_pitch, flat_pitch)
	rig.set_mode("top")
	var top_pitch := rig.goal_pitch
	_touch(screen, 0, _run_point(screen, 2.0), false)
	expect.call(turned and rig.mode == "top" and is_equal_approx(rig.goal_pitch, top_pitch) and not is_equal_approx(top_pitch, flat_pitch),
		"switching the camera mode while holding keeps the new view after the drop", "pitch %.3f -> %.3f" % [top_pitch, rig.goal_pitch])
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, held_run), 2)
	_touch(screen, 0, _run_point(screen, held_run), false)
	# A sliding box can be picked up: the run stops, it waits at rest.
	lab.set_control("angle", 40.0)
	screen.experiment_action("release")
	for i in 20:
		await tree.physics_frame
	var sliding_status: String = lab.status()
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 2.5), 4)
	expect.call(sliding_status == "sliding" and lab.status() == "ready" and not lab.released and box.freeze and box.linear_velocity == Vector3.ZERO,
		"picking up a sliding box stops the run", "%s -> %s" % [sliding_status, lab.status()])
	_touch(screen, 0, _run_point(screen, 2.5), false)
	expect.call(is_equal_approx(lab.run_length(), 2.5), "the stopped box is put down at the new start", "run %.2f" % lab.run_length())
	# A control change while holding puts the box back first.
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 6.0), 4)
	screen._set_control("angle", 30.0)
	expect.call(m.mode == "" and is_equal_approx(lab.run_length(), 2.5), "changing a condition while holding cancels the drag", "run %.2f" % lab.run_length())
	_touch(screen, 0, _run_point(screen, 6.0), false)
	# The screen rebuild keeps the placed start.
	var state: Dictionary = screen.capture_state()
	var host: Control = screen.get_parent()
	var again: Control = load(EXPERIMENT_SCREEN).new()
	again.setup(definition, state)
	host.add_child(again)
	await tree.process_frame
	expect.call(is_equal_approx(again.experiment.run_length(), 2.5) and is_equal_approx(again.experiment.angle_deg, 30.0), "a rebuilt screen keeps the placed start", "run %.2f" % again.experiment.run_length())
	await _close(screen)


## A box that landed and is dragged to a new start reacts to its next landing again, and the
## auto-release timer goes through the same path as the buttons (it puts a held box down first).
func check_incline_relanding(definition: Dictionary) -> void:
	var screen: Control = await _open(definition)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var box: RigidBody3D = lab.box
	var juice: ArtJuice = lab.props.juice
	var impacts := [0]
	lab.impact.connect(func(_strength: float) -> void: impacts[0] += 1)
	screen._set_control("angle", 40.0)
	screen.experiment_action("release")
	for i in 400:
		await tree.physics_frame
		if juice._landed:
			break
	var first_landing: bool = juice._landed and impacts[0] == 1
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 2.5), 4)
	var rearmed: bool = not juice._landed and not juice._resting and lab.status() == "ready"
	_touch(screen, 0, _run_point(screen, 2.5), false)
	screen.experiment_action("release")
	for i in 400:
		await tree.physics_frame
		if juice._landed:
			break
	expect.call(first_landing and rearmed and juice._landed and impacts[0] == 2,
		"a box that landed, dragged to a new start and released lands with squash, dust and impact again", "first %s, rearmed %s, impacts %d" % [first_landing, rearmed, impacts[0]])
	# --auto-release while a box is held: the held box goes back first (like the buttons).
	screen.experiment_action("reset")
	_swipe(screen, _at(screen, box.global_position), _run_point(screen, 3.0), 4)
	screen._auto_release_every = 5.0
	screen._auto_release_left = 0.0
	screen._process(0.016)
	expect.call(m.mode == "" and lab.released and not screen.view.rig.is_assisting(),
		"the auto-release timer puts a held box back before releasing", "mode %s, released %s" % [m.mode, lab.released])
	_touch(screen, 0, _run_point(screen, 3.0), false)
	await _close(screen)


func _mouse(button: int, pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	return event


## The displayed numbers after a new start follow the TS-core vectors: s(t) = a t^2 / 2 until the
## run length, the distance shown stops at the run length (the cap that was 7.5 m), the formula
## curve ends there, and the box leaves the incline when s reaches it.
func check_incline_runs(definition: Dictionary) -> void:
	var screen: Control = await _open(definition)
	var lab: Experiment = screen.experiment
	for run in vectors.get("runs", []):
		lab.set_material(run.material)
		lab.set_angle(run.theta_deg)
		lab.set_run_length(run.run_length)
		lab.release()
		var left_step := -1
		var limit := int(ceil(float(run.t_leave) * STEP_HZ)) + 30
		while lab.corrector.steps <= limit:
			await tree.physics_frame
			if left_step < 0 and lab.status() == "left":
				left_step = lab.corrector.steps
		var samples_ok := true
		for row in run.displacement:
			var k := int(roundf(float(row.t) * STEP_HZ))
			samples_ok = samples_ok and k < lab.corrector.samples.size() and absf(lab.corrector.samples[k] - float(row.s)) <= float(row.s) * 0.01 + 1e-4
		var shown: float = lab.observations().distance
		var formula: PackedVector2Array = lab.graph_series().formula
		var curve_ok := formula.size() > 2 and formula[-1].y <= float(run.run_length) + 1e-9
		var left_t := left_step / float(STEP_HZ)
		expect.call(samples_ok and is_equal_approx(shown, float(run.run_length)) and curve_ok and absf(left_t - float(run.t_leave)) <= 3.0 / STEP_HZ
			and is_equal_approx(lab.observations().run, float(run.run_length)),
			"run %.1f m (%s, %.0f deg): s(t) ±1%%, distance stops at the run, curve ends there, leaves at %.3f s" % [run.run_length, run.material, run.theta_deg, run.t_leave],
			"shown %.4f m, left at %.3f s, curve end %.3f m" % [shown, left_t, formula[-1].y if formula.size() > 0 else -1.0])
	await _close(screen)


# --- development scene: floor plane, height handle, overlap ------------------------------------

func check_dev_scene() -> void:
	var definition := ExperimentRegistry.find("manipulation-dev")
	var screen: Control = await _open(definition)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var red: RigidBody3D = lab.bodies.red
	var orange: RigidBody3D = lab.bodies.orange
	# Floor drag with the 0.25 m grid.
	var goal := Vector3(-1.1, 0.25, 0.4)   # -> (-1.0, 0.5) on the grid
	_swipe(screen, _at(screen, red.global_position), _at(screen, goal))
	_touch(screen, 0, _at(screen, goal), false)
	expect.call(red.global_position.is_equal_approx(Vector3(-1.0, 0.25, 0.5)) and red.freeze, "floor drag puts the box on the 0.25 m grid", str(red.global_position))
	expect.call(m.selected_id == "red" and m._knob.visible and m._rods["red"].visible, "a placed box with a height rule shows the height handle", "")
	# Height handle: drag the knob up by about 1 m, then release.
	var knob_at := _at(screen, m._knob.global_position)
	var up := _at(screen, m._knob.global_position + Vector3(0, 1.0, 0))
	_swipe(screen, knob_at, up, 6)
	var lifting: bool = m.mode == "height"
	_touch(screen, 0, up, false)
	var h: float = lab.observations().red
	expect.call(lifting and absf(h - 1.0) < 0.13 and is_equal_approx(fmod(h, 0.25), 0.0) and is_equal_approx(red.global_position.x, -1.0) and is_equal_approx(red.global_position.z, 0.5),
		"the height knob raises the box only, in 0.25 m steps", "height %.2f, at %s" % [h, str(red.global_position)])
	# Height: a second finger cancels back to the previous height.
	var before := red.global_transform
	knob_at = _at(screen, m._knob.global_position)
	_swipe(screen, knob_at, knob_at + Vector2(0, -120), 4)
	_touch(screen, 1, Vector2(100, 100), true)
	expect.call(red.global_transform.is_equal_approx(before) and m.mode == "", "a second finger cancels a height drag", "")
	_touch(screen, 1, Vector2(100, 100), false)
	_touch(screen, 0, knob_at + Vector2(0, -120), false)
	# Overlap: another box's place is blocked; the fixed block too (on the floor), but above it is free.
	var orange_at := orange.global_position
	var grounded_red := Vector3(-2.0, 0.25, 0.5)
	red.global_transform = Transform3D(Basis(), grounded_red)   # back on the floor (height 0)
	_swipe(screen, _at(screen, red.global_position), _at(screen, Vector3(orange_at.x, 0.25, orange_at.z)))
	var blocked_by_box: bool = not m.valid
	_touch(screen, 0, _at(screen, Vector3(orange_at.x, 0.25, orange_at.z)), false)
	expect.call(blocked_by_box and red.global_position.is_equal_approx(grounded_red), "placing onto another box is blocked (box goes back)", str(red.global_position))
	var block_top := Vector3(1.75, 0.25, -0.75)
	_swipe(screen, _at(screen, red.global_position), _at(screen, block_top))
	var blocked_by_block: bool = not m.valid
	_touch(screen, 0, _at(screen, block_top), false)
	expect.call(blocked_by_block and red.global_position.is_equal_approx(grounded_red), "placing into the fixed block is blocked", str(red.global_position))
	red.global_transform = Transform3D(Basis(), Vector3(-2.0, 0.25 + 1.0, 0.5))   # held 1 m up
	_swipe(screen, _at(screen, red.global_position), _at(screen, Vector3(1.75, 1.25, -0.75)))
	_touch(screen, 0, _at(screen, Vector3(1.75, 1.25, -0.75)), false)
	expect.call(red.global_position.is_equal_approx(Vector3(1.75, 1.25, -0.75)), "a box 1 m up can be placed above the block", str(red.global_position))
	# Outside the floor area: blocked.
	var outside := Vector3(4.4, 1.25, 0.0)
	_swipe(screen, _at(screen, red.global_position), _at(screen, outside))
	var blocked_outside: bool = not m.valid
	_touch(screen, 0, _at(screen, outside), false)
	expect.call(blocked_outside and red.global_position.is_equal_approx(Vector3(1.75, 1.25, -0.75)), "outside the floor area is blocked", str(red.global_position))
	# Tapping empty ground deselects (the handle goes away).
	_touch(screen, 0, _at(screen, Vector3(-3.5, 0.0, 2.5)), true)
	_touch(screen, 0, _at(screen, Vector3(-3.5, 0.0, 2.5)), false)
	expect.call(m.selected_id == "" and not m._knob.visible, "tapping empty ground hides the height handle", "")
	# Drop: the raised box falls onto the block and comes to rest (landing reaction shown).
	screen.experiment_action("drop")
	for i in 90:
		await tree.physics_frame
	expect.call(not red.freeze and absf(red.global_position.y - (0.6 + 0.25)) < 0.05, "after 상자 떨어뜨리기 the raised box falls onto the block", str(red.global_position))
	await _close(screen)


## Review fixes on the development scene: the handle goes away on an action, a falling box is not
## saved as placed, the handle drag follows the rod beside the box (also near the screen edge).
func check_dev_review() -> void:
	var definition := ExperimentRegistry.find("manipulation-dev")
	var screen: Control = await _open(definition)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var red: RigidBody3D = lab.bodies.red
	# Handle drag near the left edge of the area, from three views: the finger on the knob reads the knob's height.
	var worst := 0.0
	var goal := Vector3(-3.75, 0.25, 1.0)
	_swipe(screen, _at(screen, red.global_position), _at(screen, goal))
	_touch(screen, 0, _at(screen, goal), false)
	for view_mode in ["front", "three_quarter", "side"]:
		screen.view.rig.set_mode(view_mode, true)
		m._update_handle()
		var knob_at := _at(screen, m._knob.global_position)
		_touch(screen, 0, knob_at, true)
		if m.mode == "height":
			var s: Variant = m._knob_line_point(knob_at)
			worst = maxf(worst, absf(float(s) - (m._lift + m.height)))
		else:
			worst = 99.0
		_touch(screen, 0, knob_at, false)
	expect.call(worst < 0.02, "the height drag measures along the rod beside the box (finger on the knob = the knob's height)", "worst error %.3f m" % worst)
	# An action deselects: the handle does not follow a box that starts to fall.
	m.select("red")
	expect.call(m._knob.visible, "the placed box shows its handle", "")
	screen.experiment_action("drop")
	expect.call(m.selected_id == "" and not m._knob.visible, "an action hides the height handle (a falling box is not followed)", "selected '%s'" % m.selected_id)
	await tree.physics_frame
	await tree.physics_frame
	expect.call(lab.placements().is_empty(), "boxes that are falling are not saved as placed", str(lab.placements().keys()))
	screen.experiment_action("reset")
	expect.call(lab.placements().size() == 3, "frozen boxes are saved as placed", str(lab.placements().keys()))
	await _close(screen)


# --- second review: the object follows the finger while the camera turns, release/pick rules -----------

## Frames until the camera has settled (the assist turns it with easing).
func _settle(screen: Control, limit := 240) -> int:
	var frames := 0
	while frames < limit and not screen.view.rig.is_settled():
		await tree.process_frame
		frames += 1
	return frames


func check_follow_camera() -> void:
	var definition := ExperimentRegistry.find("manipulation-dev")
	var screen: Control = await _open(definition)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var rig: CameraRig = screen.view.rig
	var red: RigidBody3D = lab.bodies.red
	rig.set_mode("front", true)
	rig.orbit(Vector2(0.0, -40000.0))   # as flat as the limits allow
	rig.snap()
	await tree.process_frame
	var flat_pitch := rig.goal_pitch
	# Drag: pick the box in the flat view; the assist turns the camera over the next frames while the
	# finger stays where it is. The box stays under the finger (no jump, no lag) and the next event
	# at the same place does not move it.
	var at := _at(screen, red.global_position)
	_touch(screen, 0, at, true)
	var turned: bool = m.mode == "drag" and rig.is_assisting() and not is_equal_approx(rig.goal_pitch, flat_pitch)
	var last := red.global_position
	var worst_step := 0.0
	var worst_off := 0.0
	var frames := 0
	while frames < 240 and not rig.is_settled():
		await tree.process_frame
		frames += 1
		worst_step = maxf(worst_step, red.global_position.distance_to(last))
		last = red.global_position
		worst_off = maxf(worst_off, _at(screen, red.global_position).distance_to(at))
	await tree.process_frame
	var rest := red.global_position
	_drag(screen, 0, at)
	var jump := red.global_position.distance_to(rest)
	_touch(screen, 0, at, false)
	expect.call(turned and frames > 3 and worst_step < 0.5 and worst_off < 40.0 and jump < 1e-3,
		"a dragged box stays under the unmoved finger while the assist turns the camera (no jump at the next event)",
		"turned %s, %d frames, step %.3f m, off %.1f units, jump %.4f m" % [turned, frames, worst_step, worst_off, jump])
	# Height: grab the knob in the top view (the assist turns it to see the rod); with the finger still the
	# height stays, also at the first event after the turn.
	_swipe(screen, _at(screen, red.global_position), _at(screen, Vector3(-1.0, 0.25, 0.5)), 3)
	_touch(screen, 0, _at(screen, Vector3(-1.0, 0.25, 0.5)), false)
	var h0: float = m.height
	rig.set_mode("top", true)
	await tree.process_frame
	m._update_handle()
	var knob_at := _at(screen, m._knob.global_position)
	var offset := m._handle_offset
	_touch(screen, 0, knob_at, true)
	var height_turned: bool = m.mode == "height" and rig.is_assisting()
	var drift := 0.0
	frames = 0
	while frames < 240 and not rig.is_settled():
		await tree.process_frame
		frames += 1
		drift = maxf(drift, absf(m.height - h0))
	await tree.process_frame
	_drag(screen, 0, knob_at)
	drift = maxf(drift, absf(m.height - h0))
	var offset_kept: bool = m._handle_offset.is_equal_approx(offset)
	_touch(screen, 0, knob_at, false)
	expect.call(m.mode == "" and height_turned and frames > 3 and drift < 1e-6 and offset_kept,
		"the height stays while the camera turns under an unmoved finger (handle line fixed at the grab)",
		"%d frames, height drift %.3f, offset kept %s" % [frames, drift, offset_kept])
	await _close(screen)


func check_review2() -> void:
	var definition := ExperimentRegistry.find("manipulation-dev")
	var screen: Control = await _open(definition)
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var red: RigidBody3D = lab.bodies.red
	# manipulation_started re-arms the landing reaction (like the incline).
	var juice: ArtJuice = lab.juices.red
	juice._landed = true
	juice._resting = true
	_touch(screen, 0, _at(screen, red.global_position), true)
	expect.call(m.mode == "drag" and not juice._landed and not juice._resting, "picking a box up re-arms its landing reaction", "")
	_touch(screen, 0, _at(screen, red.global_position), false)
	# A wall between the camera and a box: tapping the wall near the box does not pick the box behind it.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1.0, 1.0, 0.2)
	shape.shape = box_shape
	wall.add_child(shape)
	lab.add_child(wall)
	var eye: Vector3 = screen.view.rig.global_position
	var orange: RigidBody3D = lab.bodies.orange
	wall.global_position = orange.global_position.lerp(eye, 0.5)
	await tree.physics_frame
	await tree.physics_frame
	var wall_at := _at(screen, wall.global_position)
	_touch(screen, 0, wall_at, true)
	var picked_behind: String = m.active_id
	_touch(screen, 0, wall_at, false)
	wall.queue_free()
	await tree.physics_frame
	await tree.physics_frame
	# Without the wall, a finger a little beside the box (an empty floor hit) still picks it.
	var beside := _at(screen, orange.global_position) + Vector2(20.0, 10.0)
	_touch(screen, 0, beside, true)
	var picked_near: String = m.active_id
	_touch(screen, 0, beside, false)
	expect.call(picked_behind == "" and picked_near == "orange", "a wall in front of a box is not picked through; a finger beside it on the floor still picks it", "behind '%s', near '%s'" % [picked_behind, picked_near])
	# The auto-drag demo reports a put-down only when the box was put down: not when the place is refused.
	var placed := [0]
	m.demo_placed.connect(func() -> void: placed[0] += 1)
	m.start_demo(100.0)
	m._demo_left = 0.0
	for i in 200:
		m._process(1.0 / 60.0)
	var accepted: int = placed[0]
	var blocker: RigidBody3D = lab.bodies.pink   # pink goes to the demo's far stop: the place is taken
	var surface: ManipSurface = lab.manipulation_surface("floor")
	var goal := surface.nearest_inside(surface.region_max)
	blocker.global_transform = surface.pose(goal, 0.3)
	await tree.physics_frame
	await tree.physics_frame
	m._demo_flip = false   # the next run goes to the far stop again
	m._demo_left = 0.0
	for i in 200:
		m._process(1.0 / 60.0)
	expect.call(accepted == 1 and placed[0] == 1 and m.mode == "", "the demo reports a put-down only when the box was put down (a refused place does not count)", "accepted %d, total %d, mode %s" % [accepted, placed[0], m.mode])
	await _close(screen)


## The grid of the incline start comes from the JSON `snap` of the box (one source).
func check_incline_snap_rule(definition: Dictionary) -> void:
	var coarse := definition.duplicate(true)
	coarse.manipulation.objects[0].snap = 1.0
	var screen: Control = await _open(coarse)
	var lab: Experiment = screen.experiment
	_swipe(screen, _at(screen, lab.box.global_position), _run_point(screen, 5.6), 6)
	_touch(screen, 0, _run_point(screen, 5.6), false)
	var run: float = lab.run_length()
	expect.call(is_equal_approx(run, 6.0), "the incline start snaps to the JSON snap of the box (1 m: 5.6 -> 6.0, not the 0.5 m grid)", "run %.2f" % run)
	await _close(screen)
