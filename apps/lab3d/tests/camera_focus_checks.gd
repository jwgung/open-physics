## Headless checks of the close-up (CameraRig.focus; apps/lab3d/README.md, close-up), run by
## run_tests.gd. A character that acts is framed closer for a moment, then the view eases back to the
## whole lab; it is the camera only.
## 1. state machine (the rig alone): a close-up keeps the mode and the user's view (get_state), eases
##    in, ends now or after a delay and eases back to exactly the user's view; a two-finger gesture
##    ends it, a mode change or set_state (처음으로) drops it at once (snap), only the front view
##    takes one, focus_enabled false takes none.
## 2. throw (projectile screen): no close-up (2026-10-28 user): the camera does not move from
##    "공 놓기" to the landing, the ball leaves the paw inside the view, the formula path on screen.
## 3. push (friction screen): no close-up (2026-10-28 user): pressing and holding the box keeps the
##    view while the push grows, and from the step the box slides the camera transform does not
##    change while the box is held (the red handle went on 2026-10-28; before, picking it up framed
##    the cat, box and handle closer).
extends RefCounted

const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const TABLET := Vector2(1152, 720)
const PHONE := Vector2(1560, 720)
## Same as bread_cat_checks.gd: frames before the release frame after "공 놓기" (0.48 s).
const THROW_FRAMES := 28

var tree: SceneTree
var expect: Callable   # (ok: bool, label: String, detail: String)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_state_machine()
	for size in [[TABLET, "tablet"], [PHONE, "phone"]]:
		await check_throw(size[0], size[1])
	await check_push()


# --- helpers ----------------------------------------------------------------------------------

func _open(id: String, size: Vector2) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	for i in 3:
		await tree.process_frame
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame


func _at(screen: Control, world: Vector3) -> Vector2:
	var view: View3D = screen.view
	return view.rig.unproject_position(world) / (Vector2(view.viewport.size) / view.size)


func _screen_rect(screen: Control, box: AABB) -> Rect2:
	var r := Rect2(_at(screen, box.position), Vector2.ZERO)
	for i in 8:
		r = r.expand(_at(screen, box.get_endpoint(i)))
	return r


func _same_view(a: Dictionary, b: Dictionary) -> bool:
	return a.mode == b.mode and is_equal_approx(a.yaw, b.yaw) and is_equal_approx(a.pitch, b.pitch) \
		and is_equal_approx(a.distance, b.distance) and a.pan.is_equal_approx(b.pan) and a.target.is_equal_approx(b.target)


## The drawn view is the user's view `home` (settled there).
func _at_home(rig: CameraRig, home: Dictionary) -> bool:
	return _same_view(rig.get_state(), home) and not rig.is_framing() and rig.is_settled() \
		and is_equal_approx(rig.cur_distance, home.distance) and rig.cur_target.is_equal_approx(home.target + home.pan)


func _clear_of_overlays(screen: Control, point: Vector2) -> bool:
	var spot := Rect2(point - Vector2.ONE * 10.0, Vector2.ONE * 20.0)
	if not Rect2(Vector2.ZERO, screen.view.size).encloses(spot):
		return false
	for c: Control in [screen._title_bar, screen._top_buttons, screen._key_row, screen._action_row]:
		if c.visible and c.get_rect().intersects(spot):
			return false
	return true


func _step(rig: CameraRig, seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		rig._process(1.0 / 60.0)


# --- 1. state machine -------------------------------------------------------------------------

func check_state_machine() -> void:
	var definition := ExperimentRegistry.find("projectile")
	var rig := CameraRig.new()
	tree.root.add_child(rig)
	rig.configure(definition.camera)
	var home := rig.get_state()
	var box := AABB(Vector3(-7.0, 0.0, -0.4), Vector3(1.0, 1.4, 0.8))
	var on := rig.focus({"box": box, "fill": 0.3, "anchor": Vector2(0.36, 0.58)})
	var kept := _same_view(rig.get_state(), home) and rig.mode == "front"
	var goal := rig.focus_goal()
	_step(rig, 1.0)
	var arrived: bool = absf(rig.cur_distance - goal.distance) < 0.01 and rig.cur_target.distance_to(goal.target) < 0.01
	# The box's height takes `fill` of the view height at the close-up's distance.
	var tan_v := tan(deg_to_rad(rig.fov) * 0.5)
	var fill: float = box.size.y / (2.0 * goal.distance * tan_v)
	rig.end_focus(0.25)
	_step(rig, 0.2)
	var waits := rig.is_focused()
	_step(rig, 0.1)
	var ended := not rig.is_focused() and rig.is_framing()
	_step(rig, 1.5)
	var back := _at_home(rig, home)
	expect.call(on and kept and goal.distance < home.distance * 0.6 and arrived and absf(fill - 0.3) < 0.02 and waits and ended and back,
		"close-up: keeps the mode and the user's view, eases in (box height = fill of the view), ends after its delay and eases back to exactly the user's view",
		"on %s kept %s distance %.2f -> %.2f arrived %s fill %.3f waits %s ended %s back %s" % [on, kept, home.distance, goal.distance, arrived, fill, waits, ended, back])
	# A two-finger gesture ends it (the user's view comes back under the gesture).
	var gestures_ok := true
	for g in ["orbit", "zoom", "pan"]:
		rig.set_state(home)
		rig.focus({"box": box})
		_step(rig, 0.3)
		match g:
			"orbit":
				rig.orbit(Vector2(10.0, 0.0))
			"zoom":
				rig.zoom(0.95)
			"pan":
				rig.pan_by(Vector2(5.0, 0.0))
		gestures_ok = gestures_ok and not rig.is_focused()
		_step(rig, 1.5)
		gestures_ok = gestures_ok and not rig.is_framing()
	# 처음으로 (set_state): the user's view on the same call, no close-up, nothing easing.
	rig.set_state(home)
	rig.focus({"box": box})
	_step(rig, 0.3)
	rig.set_state(home)
	var snapped := _at_home(rig, home)
	# A mode change drops it (the mode's own transition, no return of the close-up).
	rig.focus({"box": box})
	rig.set_mode("side")
	var dropped := not rig.is_focused() and not rig.is_framing()
	var other := not rig.focus({"box": box})   # side view: no close-up
	rig.set_mode("front", true)
	rig.focus_enabled = false
	var off := not rig.focus({"box": box}) and not rig.is_framing()
	expect.call(gestures_ok and snapped and dropped and other and off,
		"close-up: a two-finger gesture (turn, pinch, pan) ends it, set_state (처음으로) is the user's view at once, a mode change drops it, only the front view takes one, focus_enabled false takes none",
		"gestures %s snapped %s dropped %s other modes %s off %s" % [gestures_ok, snapped, dropped, other, off])
	# Timed (in / hold / out): exactly the user's view, nothing framing, after in + hold + out.
	rig.focus_enabled = true
	rig.set_state(home)
	rig.focus({"box": box, "in_s": 0.15, "hold_s": 0.12, "out_s": 0.17})
	_step(rig, 0.2)
	var mid: bool = rig.is_focused() and rig.cur_distance < home.distance * 0.6
	_step(rig, 0.25)
	var timed_back: bool = _at_home(rig, home) and not rig.is_focused()
	var held := rig.global_transform
	_step(rig, 0.5)
	timed_back = timed_back and rig.global_transform == held
	# cut_focus: the user's view on the same call, also during a return.
	rig.focus({"box": box})
	_step(rig, 0.3)
	rig.end_focus()
	_step(rig, 0.05)
	var returning := rig.is_framing()
	rig.cut_focus()
	var cut: bool = _at_home(rig, home) and rig.consume_cut() and not rig.consume_cut()
	expect.call(mid and timed_back and returning and cut,
		"close-up: a timed one (0.15 + 0.12 + 0.17 s) is in at 0.2 s and exactly the user's view, still, after 0.44 s; cut_focus is the user's view at once (also during a return) and is reported once",
		"mid %s, timed back %s, returning %s, cut %s" % [mid, timed_back, returning, cut])
	rig.queue_free()
	await tree.process_frame


# --- 2. throw ---------------------------------------------------------------------------------

## No close-up on the throw (2026-10-28 user): from the press through the windup, the release and
## the flight to the landing the camera transform does not change, the ball leaves the paw inside the
## view and clear of the overlays, the whole formula path is on screen.
func check_throw(size: Vector2, label: String) -> void:
	var screen: Control = await _open("projectile", size)
	var rig: CameraRig = screen.view.rig
	var lab: Experiment = screen.experiment
	var home := rig.get_state()
	var release_frame := {}
	lab.props.cat.threw.connect(func() -> void:
		release_frame.merge({"ball": _at(screen, lab.ball.global_position)}), CONNECT_ONE_SHOT)
	var still := rig.global_transform
	var moved := 0
	screen.experiment_action("release")
	var frames := 0
	while not lab.released and frames < 120:
		await tree.process_frame
		if lab.released:
			break
		frames += 1
		if rig.global_transform != still or rig.is_framing():
			moved += 1
	var ball_ok: bool = not release_frame.is_empty() and _clear_of_overlays(screen, release_frame.ball)
	var flight := 0
	while lab.status() == "flying" and flight < 240:
		await tree.process_frame
		if lab.status() != "flying":
			break   # the landing frame: the landing dip (CameraRig.nudge) is the landing's
		flight += 1
		if rig.global_transform != still:
			moved += 1
	var path_ok := true
	for p in lab.formula_path():
		path_ok = path_ok and Rect2(Vector2.ZERO, screen.view.size).has_point(_at(screen, p))
	expect.call(frames == THROW_FRAMES and moved == 0 and flight > 30 and ball_ok and path_ok and _at_home(rig, home),
		"no close-up (throw, %s): from 공 놓기 to the landing the camera does not move; the ball leaves the paw %d frames after the press inside the view, clear of the overlays; the whole formula path on screen" % [label, THROW_FRAMES],
		"frames %d, %d moved of %d, ball %s, path on screen %s" % [frames, moved, frames + flight, str(release_frame.get("ball")), path_ok])
	await _close(screen)


# --- 3. push ----------------------------------------------------------------------------------

func check_push() -> void:
	var screen: Control = await _open("friction", TABLET)
	var rig: CameraRig = screen.view.rig
	var lab: Experiment = screen.experiment
	var manipulator: Manipulator = screen.manipulator
	var home := rig.get_state()
	var finger := _at(screen, lab.box.global_position)
	manipulator.handle_pointer("press", finger)
	var held: bool = manipulator.mode == "hold" and not rig.is_focused()
	var view := rig.global_transform
	var moved_holding := 0
	var forces := {}
	var slid := false
	var moved_sliding := 0
	var sliding_frames := 0
	var guard := 0
	while sliding_frames < 30 and guard < 600:
		guard += 1
		await tree.physics_frame
		await tree.process_frame
		forces[lab.applied_force()] = true
		if not slid:
			if rig.global_transform != view:
				moved_holding += 1
			if lab.status() == "sliding":
				slid = true
		else:
			sliding_frames += 1
			if rig.global_transform != view:
				moved_sliding += 1
	var back := _at_home(rig, home) and manipulator.mode == "hold"
	manipulator.handle_pointer("release", finger)
	await tree.process_frame
	expect.call(held and forces.size() > 30 and moved_holding == 0 and slid and moved_sliding == 0 and back,
		"no close-up (push, 2026-10-28 user): pressing and holding the box keeps the child's view while the push grows and while the box slides",
		"held %s, %d forces, moved %d holding / %d of %d sliding, home %s" % [held, forces.size(), moved_holding, moved_sliding, sliding_frames, back])
	await _close(screen)
