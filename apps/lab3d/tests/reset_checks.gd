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
