## Plan G3: the slingshot — pulling the ball (direction = angle, length = speed, 5 deg grid)
## shows the big angle / speed readout with no formula path, and letting go commits the pulled
## angle and speed as the controls and throws (the same run as setting the controls and pressing
## "공 놓기"). A press on empty ground still does nothing, and the mission stamp follows the
## formula range (one throw, at most one stage).
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const PHONE := Vector2(1560, 720)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_pull_preview_and_release()
	await check_mission_stamp_from_formula()


## A pull on the ball: the big readout moves with the pull (5 deg grid), the formula path is
## hidden, and the release commits the pulled (angle, speed) and throws the same run.
func check_pull_preview_and_release() -> void:
	DirAccess.remove_absolute(ProgressStore.PATH)
	var screen := await _lab(PHONE)
	var exp: Node = screen.experiment
	expect.call(exp != null and screen.manipulator != null, "the projectile lab has a manipulator", "")
	expect.call(screen.manipulator.slingshot_id == "ball", "the slingshot is registered on the ball",
		"id %s" % str(screen.manipulator.slingshot_id))

	# The pull's start: the ball's screen point (the pick).
	var ball_point: Vector2 = screen.view_point(exp.ball_center())
	var events := []
	screen.manipulator.slingshot.connect(func(state: String, value: Variant) -> void:
		events.append([state, value]))
	# Press the ball: the pull begins (the first "pull" reports the current angle / speed).
	screen.manipulator.handle_pointer("press", ball_point)
	await tree.process_frame
	expect.call(screen.manipulator.mode == "slingshot", "pressing the ball begins a slingshot pull",
		"mode %s" % str(screen.manipulator.mode))
	expect.call(not events.is_empty() and events[0][0] == "pull", "the pull's first report is a pull", str(events))

	# Move the finger up-right of the ball: the readout shows the pulled angle and speed.
	var pulled: Vector2 = Vector2.ZERO
	for delta in [Vector2(0.0, -30.0), Vector2(60.0, -60.0), Vector2(120.0, -120.0)]:
		screen.manipulator.handle_pointer("move", ball_point + delta)
		await tree.process_frame
		# The preview follows (the arrow points where the pull says, no path dots).
		exp._process(1.0 / 60.0)
		var hud: Label = screen._slingshot_hud
		expect.call(hud != null and hud.visible, "the pull shows the big readout", "hud %s" % str(hud != null))
		if not events.is_empty():
			pulled = events[events.size() - 1][1]
			# The formula path is hidden while the pull is held.
			expect.call(not exp.projectile_props().path.visible and not exp.projectile_props().ring.visible,
				"no formula path or landing ring while pulling", "path %s ring %s"
					% [str(exp.projectile_props().path.visible), str(exp.projectile_props().ring.visible)])
	# The pulled values are on the pull's grid (5 deg, 0.5 m/s) and point up-right (0..90 deg).
	expect.call(pulled != Vector2.ZERO, "a pull changes the angle and speed", str(pulled))
	expect.call(absf(pulled.x / 5.0 - roundf(pulled.x / 5.0)) < 1e-6 and pulled.x > 0.0 and pulled.x <= 90.0,
		"the pull's angle is on the 5 deg grid, 0..90 deg", str(pulled.x))
	expect.call(pulled.y >= ArrowSurface.SPEED_MIN and pulled.y <= ArrowSurface.SPEED_MAX,
		"the pull's speed is within the lab's range", str(pulled.y))
	# The readout text carries both numbers.
	var hud: Label = screen._slingshot_hud
	expect.call(hud.text.contains(str(int(roundf(pulled.x)))) and hud.text.contains(str(pulled.y)),
		"the readout shows the pulled angle and speed", hud.text)

	# The release: the controls take the pulled values and the lab throws.
	var before_range: float = exp.flight_range()
	screen.manipulator.handle_pointer("release", ball_point + Vector2(120.0, -120.0))
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	expect.call(is_equal_approx(exp.angle_deg, pulled.x) and is_equal_approx(exp.speed, pulled.y),
		"the release commits the pulled angle and speed to the controls",
		"angle %s want %s; speed %s want %s" % [str(exp.angle_deg), str(pulled.x), str(exp.speed), str(pulled.y)])
	expect.call(exp.released or exp.projectile_props().throwing(), "the release throws",
		"released %s throwing %s" % [str(exp.released), str(exp.projectile_props().throwing())])
	# The sliders in the sidebar followed the pull.
	var angle_slider: HSlider = screen._control_widgets.get("angle", {}).get("slider")
	var speed_slider: HSlider = screen._control_widgets.get("speed", {}).get("slider")
	expect.call(angle_slider != null and is_equal_approx(angle_slider.value, pulled.x)
		and speed_slider != null and is_equal_approx(speed_slider.value, pulled.y),
		"the sidebar sliders follow the pull", "angle %s speed %s" % [str(angle_slider.value if angle_slider else null), str(speed_slider.value if speed_slider else null)])
	# The formula path is back after the release (the run shows its points again once settled).
	await _run_to_end(exp)
	expect.call(exp.projectile_props().path.visible, "the formula path is back after the release", "")
	await _free(screen)


## A pull that lands the ball past 3 m earns one stamp (the mission judges the formula range; one
## throw clears at most the current stage). The first check's run already landed and was judged,
## so the stamp file is removed again: this check's throw is judged against the first stage.
func check_mission_stamp_from_formula() -> void:
	DirAccess.remove_absolute(ProgressStore.PATH)
	var screen := await _lab(PHONE)
	var exp: Node = screen.experiment
	expect.call(ProgressStore.stamps(ProgressStore.load(), "projectile") == 0, "fresh progress: no stamps", "")
	var ball_point: Vector2 = screen.view_point(exp.ball_center())
	# A pull: up-right, a firm pull (a throw of several metres on earth).
	screen.manipulator.handle_pointer("press", ball_point)
	await tree.process_frame
	for delta in [Vector2(0.0, -20.0), Vector2(80.0, -80.0), Vector2(140.0, -140.0)]:
		screen.manipulator.handle_pointer("move", ball_point + delta)
		await tree.process_frame
		exp._process(1.0 / 60.0)
	screen.manipulator.handle_pointer("release", ball_point + Vector2(140.0, -140.0))
	await tree.process_frame
	var thrown_range: float = exp.flight_range()
	await _run_to_end(exp)
	var stamps := ProgressStore.stamps(ProgressStore.load(), "projectile")
	expect.call(is_finite(thrown_range) and thrown_range > 3.0, "the thrown ball's formula range passes 3 m",
		"range %s" % str(thrown_range))
	expect.call(stamps == 1, "a throw past 3 m earns one stamp (one throw, one stage)", "stamps %d" % stamps)
	await _free(screen)


## Steps the physics until the lab settles (a bounded number of frames: a landed or out-of-bounds
## flight ends in well under a second of wall time).
func _run_to_end(exp: Node) -> void:
	for i in 3600:
		await tree.process_frame
		if exp.status() in ["landed", "out", "fence"] and exp.settled():
			# One more frame: the screen's 10 Hz poll (the mission's judge) runs on its own cadence.
			await tree.process_frame
			return


## Builds a projectile lab screen on a host of `size` (the app's theme), the way the app does
## (setup before the screen enters the tree: its _ready builds from the definition).
func _lab(size: Vector2) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load("res://scripts/shell/experiment_screen.gd").new()
	screen.setup(ExperimentRegistry.find("projectile"), {}, false)
	host.add_child(screen)
	for i in 6:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame
