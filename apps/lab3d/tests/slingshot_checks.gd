## Plan G3: the slingshot (Angry Birds, 2026-10-26 user decision) — press the ball and pull it back:
## the ball flies the opposite way of the pull. Angle (5 deg grid, 0..90) and speed (0.5 m/s grid,
## the slider's 1..9 m/s) both from the start; the big readout and the arrow show exactly the
## clamped values the release throws. A tap or a cancel (system cancel, a second finger, the screen
## dropping the hold) throws nothing and changes nothing. No path or landing ring before a throw;
## the dots are the last throw's trail. After a run the next press is the next shot (the run is
## reset). The mission stamp follows the formula range.
## Real touches go through View3D._gui_input (the app's input path), like the other lab checks.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const PHONE := Vector2(1560, 720)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_pull_is_reversed_and_clamped()
	await check_tap_and_cancel_throw_nothing()
	await check_trail_and_next_shot()
	await check_mission_stamp_from_formula()


## The pull starts at the controls' values; inside the dead zone nothing changes; a pull down-left
## throws up-right; pulls outside 0..90 deg clamp to the nearer end, the speed to 1..9 m/s; the
## readout, the arrow and (after the release) the controls and sliders all show the same values.
func check_pull_is_reversed_and_clamped() -> void:
	var screen := await _lab()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	expect.call(m.slingshot_id == "ball", "slingshot: registered on the ball", str(m.slingshot_id))
	var events := []
	m.slingshot.connect(func(state: String, value: Variant) -> void: events.append([state, value]))
	var ball: Vector2 = screen.view_point(lab.ball_center())
	_touch(screen, ball, true)
	await tree.process_frame
	expect.call(m.mode == "slingshot" and events.size() == 1 and events[0][1] == Vector2(45.0, 9.0),
		"slingshot: a press on the ball starts the pull at the controls' angle and speed", str(events))
	_drag(screen, ball + Vector2(-8.0, 6.0))   # inside the dead zone
	expect.call(events.size() == 1, "slingshot: a finger inside the dead zone changes nothing", str(events))
	# Pull down-left (screen +y is down): the launch is up-right, the reversed pull.
	var value := Vector2.ZERO
	for k in range(1, 7):
		_drag(screen, ball + Vector2(-20.0, 20.0) * k)
		await tree.process_frame
		value = events[events.size() - 1][1]
		lab._process(1.0 / 60.0)
		var arrow_deg: float = rad_to_deg(lab.props.arrow.rotation.z)
		var hud: Label = screen._slingshot_hud
		if not (hud.visible and hud.text == screen.slingshot_readout(value) and absf(arrow_deg - value.x) < 1e-3):
			expect.call(false, "slingshot: the readout and the arrow show the pull's value", "hud %s '%s', arrow %.2f, value %s" % [str(hud.visible), hud.text, arrow_deg, str(value)])
			break
	expect.call(value.x > 0.0 and value.x < 90.0 and is_equal_approx(fposmod(value.x, 5.0), 0.0)
		and is_equal_approx(fposmod(value.y, 0.5), 0.0) and value.y >= 1.0 and value.y <= 9.0,
		"slingshot: a pull down-left throws up-right, on the 5 deg / 0.5 m/s grids", str(value))
	var hud_rect: Rect2 = screen._slingshot_hud.get_rect()
	expect.call(hud_rect.size.x > hud_rect.size.y * 2.0 and not hud_rect.intersects(screen._key_row.get_rect())
		and not hud_rect.intersects(screen._mission_text.get_rect()) and not hud_rect.intersects(screen._mission_strip.get_rect()),
		"slingshot: the readout is one line, clear of the key cards and the mission strip", str(hud_rect))
	var hud_text: String = screen._slingshot_hud.text
	expect.call(hud_text.contains("%d도" % int(value.x)) and hud_text.contains("초속") and not hud_text.contains("m/s") and hud_text.contains(Ui.number(value.y, 1)),
		"slingshot: the big readout shows the angle and the speed in words (45도 · 초속 9.0미터)", hud_text)
	# Pulls that point outside 0..90 deg: the nearer end, shown as thrown.
	_drag(screen, ball + Vector2(80.0, 60.0))   # pull down-right: launch up-left (beyond 90)
	var steep: Vector2 = events[events.size() - 1][1]
	_drag(screen, ball + Vector2(-80.0, -40.0))   # pull up-left: launch down-right (below 0)
	var flat: Vector2 = events[events.size() - 1][1]
	_drag(screen, ball + Vector2(-600.0, 400.0))   # a very long pull: the top speed
	var strong: Vector2 = events[events.size() - 1][1]
	expect.call(steep.x == 90.0 and flat.x == 0.0 and strong.y == 9.0,
		"slingshot: directions beyond 0..90 deg clamp to the nearer end, the speed to 9 m/s", "%s %s %s" % [str(steep), str(flat), str(strong)])
	expect.call(screen._slingshot_hud.text == screen.slingshot_readout(strong), "slingshot: the readout shows the clamped value", screen._slingshot_hud.text)
	# Back to a pull in range, then let go: the controls, the sliders and the run take that value.
	_drag(screen, ball + Vector2(-90.0, 70.0))
	value = events[events.size() - 1][1]
	_touch(screen, ball + Vector2(-90.0, 70.0), false)
	await tree.process_frame
	var angle_slider: HSlider = screen._control_widgets.angle.slider
	var speed_slider: HSlider = screen._control_widgets.speed.slider
	expect.call(lab.angle_deg == value.x and lab.speed == value.y and angle_slider.value == value.x and speed_slider.value == value.y,
		"slingshot: the release commits the shown angle and speed (controls and sliders)",
		"lab %.1f° %.1f m/s, sliders %.1f %.1f, shown %s" % [lab.angle_deg, lab.speed, angle_slider.value, speed_slider.value, str(value)])
	expect.call(events[events.size() - 1][0] == "release" and lab.projectile_props().throwing() and not screen._slingshot_hud.visible,
		"slingshot: letting go after a pull throws (the cat winds up), the readout goes", str(events[events.size() - 1]))
	await _free(screen)


## A tap, a wiggle inside the dead zone, a system cancel, a second finger and the screen dropping
## the hold: nothing is thrown, no control changes. A tap shows the ball's launch height handle,
## whose real drag sets the launch height.
func check_tap_and_cancel_throw_nothing() -> void:
	var screen := await _lab()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var ball: Vector2 = screen.view_point(lab.ball_center())
	var problems := []
	for how in ["tap", "wiggle", "system cancel", "second finger", "dropped by the screen"]:
		_touch(screen, ball, true)
		await tree.process_frame
		if how != "tap":
			_drag(screen, ball + (Vector2(5.0, -4.0) if how == "wiggle" else Vector2(-90.0, 70.0)))
		match how:
			"tap", "wiggle":
				_touch(screen, ball, false)
			"system cancel":
				_touch(screen, ball + Vector2(-90.0, 70.0), false, true)
			"second finger":
				_touch(screen, ball + Vector2(200.0, 0.0), true, false, 1)
				_touch(screen, ball + Vector2(200.0, 0.0), false, false, 1)
				_touch(screen, ball + Vector2(-90.0, 70.0), false)
			"dropped by the screen":
				screen._drop_held_object()
				_touch(screen, ball + Vector2(-90.0, 70.0), false)
		await tree.process_frame
		if lab.released or lab.projectile_props().throwing():
			problems.append("%s threw" % how)
		if lab.angle_deg != 45.0 or lab.speed != 9.0:
			problems.append("%s changed the controls to %.1f° %.1f m/s" % [how, lab.angle_deg, lab.speed])
		if screen._slingshot_hud.visible:
			problems.append("%s left the readout" % how)
		if how == "tap" and not (m.selected_id == "ball" and m._knob.visible):
			problems.append("a tap did not show the height handle")
		m.select("")
	expect.call(problems.is_empty(), "slingshot: a tap, a wiggle in the dead zone, a cancel, a second finger and a dropped hold throw nothing and change nothing", "; ".join(problems))
	# The tap's height handle, dragged for real: the launch height in its 0.25 m steps.
	_touch(screen, ball, true)
	_touch(screen, ball, false)
	await tree.process_frame
	var knob: Vector2 = screen.view_point(m._knob.global_position)
	var up: Vector2 = screen.view_point(m._knob.global_position + Vector3.UP * 1.0)
	_touch(screen, knob, true)
	for k in range(1, 7):
		_drag(screen, knob.lerp(up, k / 6.0))
		await tree.process_frame
	_touch(screen, up, false)
	await tree.process_frame
	expect.call(is_equal_approx(lab.start.y, 1.5) and is_equal_approx(lab.start.x, lab.START_X) and not lab.released,
		"slingshot: a tap on the ball shows its height handle; dragging it sets the launch height (0.25 m grid)", "start %s" % str(lab.start))
	# The next pull starts from the raised ball.
	ball = screen.view_point(lab.ball_center())
	_touch(screen, ball, true)
	expect.call(m.mode == "slingshot", "slingshot: the raised ball is pulled from its new launch point", m.mode)
	_touch(screen, ball, false)
	await _free(screen)


## No path or ring before the first throw; the throw's trail grows with the flight (formula time)
## and stays after it; the next press (no 처음으로) resets the run at the launch point and keeps
## the trail and no ring while pulling; the next throw starts a new trail. A press near the launch
## point also starts the next shot when the ball rests far away.
func check_trail_and_next_shot() -> void:
	var screen := await _lab()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var props: ProjectileProps = lab.projectile_props()
	expect.call(props.path.multimesh.visible_instance_count == 0 and not props.ring.visible,
		"slingshot: no formula path or landing ring before the first throw", "dots %d ring %s" % [props.path.multimesh.visible_instance_count, str(props.ring.visible)])
	await _throw(screen, lab, Vector2(-90.0, 70.0))
	var mid := -1
	var grew := true
	var last := 0
	for i in 600:
		await tree.physics_frame
		await tree.process_frame
		var dots: int = props.path.multimesh.visible_instance_count
		if dots < last:
			grew = false
		last = dots
		if lab.released and mid < 0 and lab.shown_time() > lab.flight_time() * 0.5:
			mid = dots
		if lab.status() in ["landed", "fence", "out"] and lab.settled():
			break
	await tree.process_frame
	await tree.process_frame   # process_frame resumes before the nodes' _process: one more for the last frame's dots
	last = props.path.multimesh.visible_instance_count
	expect.call(grew and mid > 0 and mid < ProjectileProps.PATH_DOTS and last == ProjectileProps.PATH_DOTS and not props.ring.visible,
		"slingshot: the trail grows with the flight (formula time) and is whole after the landing, no ring",
		"half-way %d dots, end %d, ring %s" % [mid, last, str(props.ring.visible)])
	var trail_end: Vector3 = props.path_end
	# The next shot without 처음으로: a press on the landed ball.
	var landed_at: Vector2 = screen.view_point(lab.ball.global_position)
	_touch(screen, landed_at, true)
	await tree.process_frame
	lab._process(1.0 / 60.0)
	expect.call(m.mode == "slingshot" and lab.status() == "ready" and lab.ball.global_position.distance_to(lab.ball_center()) < 1e-3,
		"slingshot: after a landing the next press resets the run and starts the next pull", "mode %s status %s" % [m.mode, lab.status()])
	expect.call(props.path.multimesh.visible_instance_count == ProjectileProps.PATH_DOTS and props.path_end == trail_end and not props.ring.visible,
		"slingshot: while the next pull is held only the last throw's trail shows (no new path, no ring)", "")
	_drag(screen, landed_at + Vector2(-50.0, 95.0))   # steeper than the first: another path
	_touch(screen, landed_at + Vector2(-50.0, 95.0), false)
	for i in 60:
		await tree.physics_frame
		if lab.released:
			break
	await tree.process_frame
	expect.call(lab.released and props.path.multimesh.visible_instance_count < ProjectileProps.PATH_DOTS and props.path_end != trail_end,
		"slingshot: the next throw starts its own trail", "released %s, dots %d, end %s (was %s)" % [str(lab.released), props.path.multimesh.visible_instance_count, str(props.path_end), str(trail_end)])
	await _run_to_end(lab)
	# A press near the empty launch point (the ball rests far away) starts the next shot too.
	var launch: Vector2 = screen.view_point(lab.ball_center())
	var far: bool = screen.view_point(lab.ball.global_position).distance_to(launch) > Manipulator.PICK_RADIUS * 2.0
	_touch(screen, launch, true)
	await tree.process_frame
	expect.call(far and m.mode == "slingshot" and lab.status() == "ready",
		"slingshot: a press at the launch point after a run starts the next shot", "far %s mode %s status %s" % [str(far), m.mode, lab.status()])
	_touch(screen, launch, false, true)
	await _free(screen)


## A gentle pull (살살: the first stage's speed band) that lands the ball past 3 m earns one stamp
## (the formula range; one throw, one stage).
func check_mission_stamp_from_formula() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _lab()
	var lab: Experiment = screen.experiment
	await _throw(screen, lab, Vector2(-55.0, 43.0))
	for i in 60:
		await tree.physics_frame
		if lab.released:
			break
	var thrown_range: float = lab.flight_range()
	await _run_to_end(lab)
	var stamps := ProgressStore.stamps(ProgressStore.load(), "projectile")
	expect.call(is_finite(thrown_range) and thrown_range > 3.0 and lab.speed <= 6.0 and stamps == 1,
		"slingshot: a gentle throw (up to 6 m/s) past 3 m (formula range) earns one stamp",
		"range %s, %.1f m/s, stamps %d" % [str(thrown_range), lab.speed, stamps])
	DirAccess.remove_absolute(ProgressStore.path)
	await _free(screen)


# --- helpers ---------------------------------------------------------------------------------------

## A pull from the ball by `pull` (view units) and the release.
func _throw(screen: Control, lab: Experiment, pull: Vector2) -> void:
	var ball: Vector2 = screen.view_point(lab.ball_center())
	_touch(screen, ball, true)
	await tree.process_frame
	for k in range(1, 5):
		_drag(screen, ball + pull * (k / 4.0))
		await tree.process_frame
	_touch(screen, ball + pull, false)
	await tree.process_frame


## Steps until the run has ended and settled, then one poll of the screen (10 Hz) more.
func _run_to_end(lab: Experiment) -> void:
	for i in 900:
		await tree.physics_frame
		if lab.status() in ["landed", "out", "fence"] and lab.settled():
			break
	for i in 8:
		await tree.process_frame


func _touch(screen: Control, position: Vector2, pressed: bool, canceled := false, index := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	screen.view._gui_input(event)


func _drag(screen: Control, position: Vector2, index := 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
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
