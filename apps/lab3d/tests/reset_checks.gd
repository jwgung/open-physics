## Headless checks of "처음으로" (Phase 1 Task 4g bug fix, 2026-10-23 user report: 처음으로 did
## not bring the bodies back; "누르자마자 처음 상태로"), run by run_tests.gd. Through the real input path: a screen
## touch on the action button (InputEventScreenTouch pushed into the viewport, not the signal), and
## with frames that have no fixed step (physics ticks lowered to 20 /s while it is checked, as on a
## device): the first action of each of the 11 experiments, then 처음으로 at several moments (the
## bread cat winding up, just after a release, in flight, landed / rolling, with the sidebar open, with
## the push handle held). From the press frame on, for the next frames: every rigid body at its start
## pose, every ArtJuice mesh at rest (no grow-in), the camera at the view the screen opened with, the
## panel values, graph and status as at the start, the bread cat holding the ball. The engine bug this
## guards (a pose set from input reverted by the next step's state report) is in BodyResync.
## The same guard for the other changes from input (PR #16 review): 공 놓기 pressed again after the
## ball landed (the ball and its shadow at the launch point during the wind-up, the release from
## there), and the landed ball picked up and put down on the launch line, or picked up, dragged and
## put back (a cancelled touch).
extends RefCounted

const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const POSE_TOL := 1e-4
const CHECK_FRAMES := 10
const SLOW_TICKS := 20

var tree: SceneTree
var expect: Callable


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	for definition in ExperimentRegistry.load_all():
		var waits := [10, 60, 200]
		var problems := []
		for wait in waits:
			problems.append_array(await _case(definition, wait, false, false))
		problems.append_array(await _case(definition, 60, true, false))
		if definition.id == "friction":
			problems.append_array(await _case(definition, 60, false, true))
		expect.call(problems.is_empty(),
			"처음으로 (%s, touch on the button, frames without a step): from the press frame every body at its start, meshes at rest, camera, panel, graph and status as at the start (after %s steps, sidebar open%s)" % [definition.id, str(waits), ", handle held" if definition.id == "friction" else ""],
			"; ".join(problems))
		if definition.id == "spring":
			var home := await _rebuilt_home_case(definition)
			expect.call(home.is_empty(), "처음으로 on a rebuilt screen (the camera turned before the rebuild) snaps to the experiment's opening view, not the turned one", "; ".join(home))
		if definition.id == "friction":
			var moving := await _moved_after_reset_case(definition)
			expect.call(moving.is_empty(), "friction: a box set moving by other code after 처음으로, before the next step, keeps that motion (BodyResync leaves it alone)", "; ".join(moving))
		if definition.id == "projectile":
			for ending in ["landed", "rolling", "out"]:
				var again := await _rerelease_case(definition, ending)
				var what: String = {"landed": "landed", "rolling": "landed and still rolls fast (SM-P200 2026-10-24: the cat went to the rolling ball)", "out": "flew off the island (stopped there, frozen)"}[ending]
				expect.call(again.is_empty(), "공 놓기 again after the ball %s (touch, frames without a step): the ball body and its shadow at the launch point through the wind-up, the release from there" % what, "; ".join(again))
			var report := await _stale_report_case()
			expect.call(report.is_empty(), "BodyResync: the stale report of a body moving at the change (one step of its motion on, as on SM-P200) is put back; a body other code moved, or set moving slowly from rest, is left alone", "; ".join(report))
			for cancel in [false, true]:
				var moved := await _manipulation_case(definition, cancel)
				expect.call(moved.is_empty(), "the landed ball pressed (the slingshot's next shot: the run is reset, the ball back at its launch point), pulled and %s (touch, frames without a step): from that frame on it stays there" % ("cancelled: nothing thrown" if cancel else "let go: the cat throws"), "; ".join(moved))


## BodyResync with the report a device gives (SM-P200, 2026-10-24): the input change runs before the
## frame's engine steps, so the stale report carries the moving body's pose one step on (here a ball
## rolling at 1 m/s and turning, then frozen at the launch point by 공 놓기). It is still the stale
## report: the body goes back to the launch point. A move by other code (1 m away) is left alone.
func _stale_report_case() -> Array:
	var problems := []
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for other in [false, true]:
		var root := Node3D.new()
		tree.root.add_child(root)
		var body := RigidBody3D.new()
		body.gravity_scale = 0.0
		root.add_child(body)
		var rolling := Transform3D(Basis(Vector3.BACK, 0.3), Vector3(6.52, 0.25, 0.0))
		body.global_transform = rolling
		body.linear_velocity = Vector3(-0.98, 0.16, 0.0)
		body.angular_velocity = Vector3(0.0, 0.0, 3.9)
		var resync := BodyResync.new()
		root.add_child(resync)
		resync.mark(root)
		var launch := Transform3D(Basis(), Vector3(-6.0, 0.75, 0.0))
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.global_transform = launch
		resync.hold(root)
		# The engine's report of the step under way: one step of the old motion on.
		var report := Transform3D(Basis(Vector3.BACK, 0.3 + 3.9 * dt), rolling.origin + Vector3(-0.98, 0.16, 0.0) * dt)
		if other:
			report.origin += Vector3(1.0, 0.0, 0.0)
		body.global_transform = report
		resync._physics_process(dt)
		var want := report if other else launch
		if body.global_transform.origin.distance_to(want.origin) > POSE_TOL:
			problems.append("%s: ball at %s, want %s" % ["moved by other code" if other else "stale report", body.global_transform.origin, want.origin])
		root.queue_free()
	# A free body at rest put back by the change, then set moving slowly (0.3 m/s) by other code
	# before the step: it keeps that motion.
	var root2 := Node3D.new()
	tree.root.add_child(root2)
	var box := RigidBody3D.new()
	box.gravity_scale = 0.0
	root2.add_child(box)
	box.global_transform = Transform3D(Basis(), Vector3(2.0, 0.35, 0.0))
	var resync2 := BodyResync.new()
	root2.add_child(resync2)
	resync2.mark(root2)
	box.global_transform = Transform3D(Basis(), Vector3(-3.0, 0.35, 0.0))
	resync2.hold(root2)
	box.linear_velocity = Vector3(0.3, 0.0, 0.0)
	resync2._physics_process(dt)
	if box.linear_velocity != Vector3(0.3, 0.0, 0.0):
		problems.append("box set moving at 0.3 m/s by other code: velocity %s" % box.linear_velocity)
	root2.queue_free()
	await tree.process_frame
	return problems


func _tap(screen_pos: Vector2, index := 0, press := true, release := true) -> void:
	for pressed in [true, false]:
		if (pressed and not press) or (not pressed and not release):
			continue
		var e := InputEventScreenTouch.new()
		e.index = index
		e.position = screen_pos
		e.pressed = pressed
		tree.root.push_input(e)
		await tree.process_frame


## The graph as drawn: each series' points with repeated identical points dropped (a run's first
## sample may be added once or twice at t = 0; it draws the same).
static func _graph_key(lab: Experiment) -> String:
	var series: Dictionary = lab.graph_series()
	var out := []
	for id in series:
		var pts := []
		for p in series[id]:
			if pts.is_empty() or pts[-1] != p:
				pts.append(p)
		out.append("%s:%s" % [id, str(pts)])
	return " ".join(out)


func _bodies(lab: Node) -> Dictionary:
	var d := {}
	for b in lab.find_children("*", "RigidBody3D", true, false):
		d[b] = (b as Node3D).global_transform
	return d


func _open(definition: Dictionary) -> Control:
	tree.root.size = Vector2i(1560, 720)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(1560, 720)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	for i in 5:
		await tree.process_frame
	await tree.physics_frame
	await tree.process_frame
	if screen._asking:
		screen._end_question()   # the child answers Dugi first: his question takes every touch
	return screen


func _close(screen: Control, root_size: Vector2i) -> void:
	Engine.physics_ticks_per_second = 60
	screen.get_parent().queue_free()
	await tree.process_frame
	await tree.physics_frame
	tree.root.size = root_size


## 공 놓기, the ball lands (or, without gravity, flies off the island and is stopped there, frozen),
## 공 놓기 again: from the press until the ball leaves the paw the ball body and its shadow are at the
## launch point (the stale report put the frozen one back where it stopped), and the release starts there.
func _rerelease_case(definition: Dictionary, ending: String) -> Array:
	var flies_off := ending == "out"
	var problems := []
	var root_size := tree.root.size
	var screen := await _open(definition)
	var lab: Experiment = screen.experiment
	if flies_off:
		screen._set_control("gravity", "zero")
		screen._set_control("speed", 9.0)
		screen._set_control("angle", 80.0)   # up through the top of the box (the fence stops a level throw)
	var button: Control = screen._action_buttons["release"]
	await _tap(button.get_global_rect().get_center())
	for i in (150 if ending == "rolling" else 260):
		await tree.physics_frame
	if lab.status() != ("out" if flies_off else "landed") or lab.ball.freeze != flies_off:
		problems.append("first run ended %s (frozen %s)" % [lab.status(), lab.ball.freeze])
	if ending == "rolling" and lab.ball.linear_velocity.length() < 2.0:
		problems.append("not rolling fast: %.2f m/s" % lab.ball.linear_velocity.length())
	var landed: Vector3 = lab.ball.global_position
	Engine.physics_ticks_per_second = SLOW_TICKS
	await _tap(button.get_global_rect().get_center())
	var shadow: Node3D = lab.props.juice._shadow
	var frames := 0
	while not lab.released and frames < 120 and problems.is_empty():
		var center: Vector3 = lab.ball_center()
		if lab.ball.global_position.distance_to(center) > POSE_TOL:
			problems.append("wind-up frame %d: ball at %s, launch point %s (landed at %s)" % [frames, lab.ball.global_position, center, landed])
		elif Vector2(shadow.global_position.x - center.x, shadow.global_position.z - center.z).length() > 1e-3:
			problems.append("wind-up frame %d: shadow at %s, launch point %s" % [frames, shadow.global_position, center])
		frames += 1
		await tree.process_frame
	if problems.is_empty() and not lab.released:
		problems.append("never released")
	elif problems.is_empty():
		var reach: float = lab.launch_velocity().length() * 2.0 / SLOW_TICKS + POSE_TOL
		if lab.ball.global_position.distance_to(lab.ball_center()) > reach:
			problems.append("released from %s, launch point %s" % [lab.ball.global_position, lab.ball_center()])
	await _close(screen, root_size)
	return problems


## The ball lands; a finger presses it (the slingshot, Plan G3: the run is reset and the ball waits
## at its launch point for the next shot), pulls it back and lets go (the cat throws: the ball
## stays in its paw through the wind-up) or the touch is cancelled (nothing is thrown).
## From that frame on, for CHECK_FRAMES frames, the ball stays at the launch point.
func _manipulation_case(definition: Dictionary, cancel: bool) -> Array:
	var problems := []
	var root_size := tree.root.size
	var screen := await _open(definition)
	var lab: Experiment = screen.experiment
	await _tap((screen._action_buttons["release"] as Control).get_global_rect().get_center())
	for i in 260:
		await tree.physics_frame
	Engine.physics_ticks_per_second = SLOW_TICKS
	var view: View3D = screen.view
	var scale := Vector2(view.viewport.size) / view.size
	var from: Vector2 = view.rig.unproject_position(lab.ball.global_position) / scale
	var to: Vector2 = view.rig.unproject_position(Vector3(-6.5, 0.2, 0.0)) / scale
	_view_touch(view, from, true)
	await tree.process_frame
	for i in range(1, 7):
		var drag := InputEventScreenDrag.new()
		drag.position = from.lerp(to, i / 6.0)
		view._gui_input(drag)
		await tree.process_frame
	if screen.manipulator.mode != "slingshot":
		problems.append("the ball's press did not start a pull (mode %s)" % screen.manipulator.mode)
	if lab.released:
		problems.append("the press did not reset the landed run")
	_view_touch(view, to, false, cancel)
	var expected: Transform3D = lab.ball.global_transform
	if expected.origin.distance_to(lab.ball_center()) > POSE_TOL:
		problems.append("%s at %s, launch point %s" % ["cancelled" if cancel else "let go", expected.origin, lab.ball_center()])
	if cancel == lab.projectile_props().throwing():
		problems.append("cancelled, yet the cat throws" if cancel else "let go, yet no throw")
	for f in CHECK_FRAMES + 1:
		if not problems.is_empty():
			break
		if lab.ball.global_transform.origin.distance_to(expected.origin) > POSE_TOL:
			problems.append("frame %d: ball at %s, %s at %s" % [f, lab.ball.global_position, "cancelled" if cancel else "let go", expected.origin])
		await tree.process_frame
	await _close(screen, root_size)
	return problems


## The camera is turned, the screen rebuilt from capture_state() (a resize / rotation does that),
## then 처음으로: the view is the experiment's opening one (PR #16 review: the rebuilt screen took the
## restored, turned view as its home).
func _rebuilt_home_case(definition: Dictionary) -> Array:
	var problems := []
	var root_size := tree.root.size
	var screen := await _open(definition)
	var opening: Dictionary = screen.view.rig.get_state()
	var turned := opening.duplicate()
	turned.yaw = opening.yaw + 0.6
	turned.distance = opening.distance * 1.3
	screen.view.rig.set_state(turned)
	await tree.process_frame
	var state: Dictionary = screen.capture_state()
	await _close(screen, root_size)
	screen = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition, state)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(1560, 720)
	tree.root.add_child(host)
	host.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	var restored: Dictionary = screen.view.rig.get_state()
	if absf(restored.yaw - turned.yaw) > 1e-6:
		problems.append("the rebuild did not restore the turned view (yaw %.3f, turned %.3f)" % [restored.yaw, turned.yaw])
	screen.experiment_action("reset")
	var home: Dictionary = screen.view.rig.get_state()
	if absf(home.yaw - opening.yaw) > 1e-6 or absf(home.distance - opening.distance) > 1e-6:
		problems.append("처음으로 went to yaw %.3f distance %.2f, opening yaw %.3f distance %.2f" % [home.yaw, home.distance, opening.yaw, opening.distance])
	await _close(screen, root_size)
	return problems


## 처음으로 puts the pushed box back (at rest, free: recorded); then, in the same frame, other code
## sets it moving. The next step must not put it back and stop it.
func _moved_after_reset_case(definition: Dictionary) -> Array:
	var problems := []
	var root_size := tree.root.size
	var screen := await _open(definition)
	var lab: Experiment = screen.experiment
	lab.set_applied_force(60.0)
	for i in 60:
		await tree.physics_frame
	lab.set_applied_force(0.0)
	Engine.physics_ticks_per_second = SLOW_TICKS
	await tree.physics_frame
	screen.experiment_action("reset")
	var start: Vector3 = lab.box.global_position
	if not lab.held_bodies().has(lab.box):
		problems.append("the box put back is not recorded")
	lab.box.linear_velocity = Vector3(2.0, 0.0, 0.0)
	for i in 3:
		await tree.physics_frame
	if lab.box.global_position.x - start.x < 0.01:
		problems.append("the box stayed at %s (start %s): put back and stopped" % [lab.box.global_position, start])
	await _close(screen, root_size)
	return problems


func _view_touch(view: View3D, position: Vector2, pressed: bool, canceled := false) -> void:
	var e := InputEventScreenTouch.new()
	e.position = position
	e.pressed = pressed
	e.canceled = canceled
	view._gui_input(e)


## One case: the screen opened, the first action pressed (and for friction a push), `wait` fixed
## steps, then 처음으로 pressed; the state checked in the press frame and CHECK_FRAMES frames after.
func _case(definition: Dictionary, wait: int, sidebar: bool, hold_handle: bool) -> Array:
	var problems := []
	var root_size := tree.root.size
	tree.root.size = Vector2i(1560, 720)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = Vector2(1560, 720)
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	for i in 5:
		await tree.process_frame
	await tree.physics_frame
	await tree.process_frame
	var lab: Experiment = screen.experiment
	var bodies0 := _bodies(lab)
	var obs0 := str(lab.observations())
	var graph0 := _graph_key(lab)
	var status0 := lab.status()
	var camera0: Dictionary = screen.view.rig.get_state()
	var actions: Array = definition.actions.map(func(a: Dictionary) -> String: return a.id).filter(func(id: String) -> bool: return id != "reset")
	if lab.has_method("set_applied_force") and not hold_handle:
		lab.set_applied_force(60.0)
	if not actions.is_empty():
		await _tap((screen._action_buttons[actions[0]] as Control).get_global_rect().get_center())
	if hold_handle:
		# A finger takes the handle and pulls it (touch index 0); 처음으로 is the second finger.
		var at: Vector2 = screen.view.rig.unproject_position(lab.handle.global_position) / (Vector2(screen.view.viewport.size) / screen.view.size)
		await _tap(at, 0, true, false)
		for i in 6:
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			drag.position = at + Vector2(12.0 * (i + 1), 0.0)
			tree.root.push_input(drag)
			await tree.process_frame
	for i in wait:
		await tree.physics_frame
	if lab.has_method("set_applied_force") and not hold_handle:
		lab.set_applied_force(0.0)
	if sidebar:
		screen.open_sidebar(false)
		await tree.process_frame
	var reset: Control = screen._action_buttons["reset"]
	Engine.physics_ticks_per_second = SLOW_TICKS
	await _tap(reset.get_global_rect().get_center(), 1 if hold_handle else 0)
	for f in CHECK_FRAMES + 1:
		for b: RigidBody3D in bodies0:
			if is_instance_valid(b) and b.global_transform.origin.distance_to((bodies0[b] as Transform3D).origin) > POSE_TOL:
				problems.append("%s %s frame %d: %s at %s, start %s" % [definition.id, "wait %d%s" % [wait, " sidebar" if sidebar else ""], f, b.name, b.global_position, (bodies0[b] as Transform3D).origin])
				break
		for juice: ArtJuice in lab.find_children("*", "ArtJuice", true, false):
			if juice.mesh != null and not (juice.mesh_scale() - Vector3.ONE).is_zero_approx():
				problems.append("%s frame %d: %s mesh scale %s" % [definition.id, f, juice.name, juice.mesh_scale()])
				break
		var camera: Dictionary = screen.view.rig.get_state()
		if not hold_handle and (camera.mode != camera0.mode or absf(camera.yaw - camera0.yaw) > 1e-6 or absf(camera.distance - camera0.distance) > 1e-6 or camera.target != camera0.target):
			problems.append("%s frame %d: camera %s" % [definition.id, f, camera])
		if f == 0 and not hold_handle:
			if str(lab.observations()) != obs0:
				problems.append("%s: panel %s vs %s" % [definition.id, str(lab.observations()).substr(0, 80), obs0.substr(0, 80)])
			if _graph_key(lab) != graph0:
				problems.append("%s: graph not cleared" % definition.id)
			if lab.status() != status0:
				problems.append("%s: status %s vs %s" % [definition.id, lab.status(), status0])
		if definition.id == "projectile" and (lab.props.cat.mode != "hold" or lab.props.juice.carry() != Vector3.ZERO):
			problems.append("projectile frame %d: cat %s" % [f, lab.props.cat.mode])
		if not problems.is_empty():
			break
		await tree.process_frame
	Engine.physics_ticks_per_second = 60
	if hold_handle:
		await _tap(Vector2.ZERO, 0, false, true)
	host.queue_free()
	await tree.process_frame
	await tree.physics_frame
	tree.root.size = root_size
	return problems
