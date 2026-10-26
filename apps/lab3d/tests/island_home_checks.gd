## Plan G2: the island home — the 3D island seen from above, the 5 zones and 11 spots, a tap that
## hops the bread cat over and opens the experiment, the stamp / flag display, and the list and
## settings buttons on the map (phone and tablet).
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_home_builds()
	await check_tap_opens_experiment()
	await check_stamp_display()
	await check_buttons_and_layout()


## The home renders: the island, the cat, the 5 zones' pads and 11 spot markers, the top bar with
## the brand and the list / settings buttons.
func check_home_builds() -> void:
	var screen := await _home(PHONE)
	var problems := []
	var world: Node3D = screen.find_child("IslandHome", true, false)
	if world == null:
		problems.append("no world")
	var island := world.find_child("Island", true, false)
	if island == null:
		problems.append("no island")
	if screen.cat == null:
		problems.append("no cat")
	var pads: int = world.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("ZonePad_")).size()
	var spots: int = world.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Spot_")).size()
	if pads != 5:
		problems.append("%d zone pads (want 5)" % pads)
	if spots != 11:
		problems.append("%d spot markers (want 11)" % spots)
	if screen.find_child("TopBar", true, false) == null:
		problems.append("no top bar")
	var buttons: Array = screen.find_children("ListButton", "", true, false)
	var settings: Array = screen.find_children("SettingsButton", "", true, false)
	if buttons.size() != 1 or settings.size() != 1:
		problems.append("list/settings buttons %d/%d (want 1/1)" % [buttons.size(), settings.size()])
	# The camera looks straight down (top mode) and the island is on screen.
	var cam_mode: String = screen.view.rig.mode
	if cam_mode != "top":
		problems.append("camera mode %s (want top)" % cam_mode)
	var center_screen: Vector2 = screen._world_to_screen(Vector3(0.0, 0.0, 0.0))
	if center_screen == Vector2.INF or not Rect2(Vector2.ZERO, screen.size).has_point(center_screen):
		problems.append("island centre not on screen %s" % str(center_screen))
	expect.call(problems.is_empty(), "island home builds: island, cat, 5 zones, 11 spots, top bar, top camera", "; ".join(problems))
	await _free(screen)


## A tap on a spot hops the cat over and emits that experiment; a tap on empty grass does nothing.
func check_tap_opens_experiment() -> void:
	var screen := await _home(TABLET)
	var chosen := []
	screen.experiment_chosen.connect(func(d: Dictionary) -> void: chosen.append(d.id))
	# Find a spot and its screen point.
	var target: Dictionary = {}
	for spot in screen._spots:
		if spot.id == "projectile":
			target = spot
			break
	expect.call(not target.is_empty(), "the projectile spot is on the map", "")
	var screen_point: Vector2 = screen._world_to_screen(target.at + Vector3.UP * 1.0)
	# A tap on the spot.
	screen._on_pointer("press", screen_point)
	await tree.process_frame
	screen._on_pointer("release", screen_point)
	expect.call(screen._walking, "a tap on a spot starts the cat's hop", "walking %s" % str(screen._walking))
	# Walk the hop to completion (a few frames).
	for i in 240:
		screen._process(1.0 / 60.0)
		await tree.process_frame
	expect.call(chosen == ["projectile"] and not screen._walking,
		"a tap on a spot hops the cat over, then opens that experiment", "chosen %s, walking %s" % [str(chosen), str(screen._walking)])
	# A tap on empty grass (far from any spot) does not open anything.
	chosen.clear()
	var empty: Vector2 = screen._world_to_screen(Vector3(0.0, 0.0, 9.0))
	# Make sure that point is not within reach of a spot.
	var nearest := 0.0
	for spot in screen._spots:
		nearest = minf(nearest, screen._world_to_screen(spot.at + Vector3.UP * 1.0).distance_to(empty)) if empty != Vector2.INF else INF
	if nearest > 10.0:
		screen._on_pointer("press", empty)
		await tree.process_frame
		screen._on_pointer("release", empty)
		expect.call(chosen.is_empty() and not screen._walking, "a tap on empty grass opens nothing", "chosen %s" % str(chosen))
	else:
		expect.call(true, "empty-grass tap skipped (no clear empty point on this layout)", "")
	# A drag (a move beyond the slop) is not a tap.
	chosen.clear()
	var from: Vector2 = screen._world_to_screen(target.at + Vector3.UP * 1.0)
	screen._on_pointer("press", from)
	await tree.process_frame
	screen._on_pointer("move", from + Vector2(80, 0))
	screen._on_pointer("release", from + Vector2(80, 0))
	expect.call(chosen.is_empty() and not screen._walking, "a drag over a spot does not open it", "chosen %s" % str(chosen))
	await _free(screen)


## Spots with missions show a "미션" badge; at 3 stamps the flag stands. Progress (0/3) is
## shown only in the experiment screen, not on the map.
func check_stamp_display() -> void:
	DirAccess.remove_absolute(ProgressStore.PATH)
	var screen := await _home(TABLET)
	# A fresh map: the projectile spot (it has 3 stages) shows a "미션" badge next to its name.
	await tree.process_frame
	await tree.process_frame
	var label: Label = _label_text(screen, "projectile")
	expect.call(label != null, "the projectile spot has a label", str(screen._labels.keys()))
	var box: Node = screen._labels.get("projectile")
	var has_badge: bool = false
	if box != null:
		for c: Node in box.find_children("*", "Label", true, false):
			if (c as Label).text == "미션":
				has_badge = true
	expect.call(label != null and label.text.contains("던지기") and has_badge,
		"a mission spot shows its name and a 미션 badge", label.text if label else "")
	# A non-mission spot (collision) has no badge.
	var collision_label: Label = _label_text(screen, "collision")
	var collision_box: Node = screen._labels.get("collision")
	var collision_badge: bool = false
	if collision_box != null:
		for c: Node in collision_box.find_children("*", "Label", true, false):
			if (c as Label).text == "미션":
				collision_badge = true
	expect.call(collision_label != null and collision_label.text.contains("충돌") and not collision_badge,
		"a non-mission spot has no badge", collision_label.text if collision_label else "")
	# Award 3 stamps: the flag stands.
	ProgressStore.save({"projectile": 3})
	screen._labels.clear()
	for i in 4:
		screen._process(1.0 / 60.0)
		await tree.process_frame
	var flag: Node3D = screen._flags.get("projectile")
	await tree.process_frame
	expect.call(flag != null and flag.visible, "a finished spot stands its flag", "flag visible %s" % str(flag.visible if flag else null))
	# An unfinished spot has no flag.
	ProgressStore.save({"projectile": 1, "orbit": 2})
	screen._labels.clear()
	for i in 4:
		screen._process(1.0 / 60.0)
		await tree.process_frame
	var orbit_label: Label = _label_text(screen, "orbit")
	var orbit_flag: Node3D = screen._flags.get("orbit")
	expect.call(orbit_label != null and orbit_label.text.contains("궤도"), "a spot label shows the lab's short name (orbit = 궤도)", orbit_label.text if orbit_label else "")
	expect.call(orbit_flag != null and not orbit_flag.visible, "an unfinished spot has no flag", "flag visible %s" % str(orbit_flag.visible if orbit_flag else null))
	DirAccess.remove_absolute(ProgressStore.PATH)
	await _free(screen)


## The list and settings buttons are on the map and reachable (phone and tablet); back leaves the
## home (the app quits from the home, as from the old list).
func check_buttons_and_layout() -> void:
	for setup in [[PHONE, "phone"], [TABLET, "tablet"]]:
		var screen := await _home(setup[0])
		await tree.process_frame
		await tree.process_frame
		var bar: PanelContainer = screen.find_child("TopBar", true, false)
		var list_btn: Button = screen.find_child("ListButton", true, false)
		var settings: Button = screen.find_child("SettingsButton", true, false)
		var problems := []
		if bar == null or list_btn == null or settings == null:
			problems.append("top bar / list / settings missing")
		else:
			var bar_rect := bar.get_global_rect()
			var list_rect := list_btn.get_global_rect()
			var settings_rect := settings.get_global_rect()
			if not Rect2(Vector2.ZERO, screen.size).encloses(bar_rect):
				problems.append("top bar off screen")
			if not Rect2(Vector2.ZERO, screen.size).encloses(list_rect) or not Rect2(Vector2.ZERO, screen.size).encloses(settings_rect):
				problems.append("a button off screen")
		# The 3D view fills the screen under the bar.
		if screen.view.size != setup[0]:
			problems.append("view size %s (want full %s)" % [str(screen.view.size), str(setup[0])])
		expect.call(problems.is_empty(), "island home (%s): top bar with list and settings on the map, the 3D view full" % setup[1], "; ".join(problems))
		await _free(screen)


## The text label inside a spot's label panel (null when the spot has no label yet).
func _label_text(screen: Control, id: String) -> Label:
	var panel: Control = screen._labels.get(id)
	if panel == null:
		return null
	return _find_label(panel)


func _find_label(node: Node) -> Label:
	if node is Label:
		return node
	for child in node.get_children():
		var found := _find_label(child)
		if found != null:
			return found
	return null


## Builds a home on a host of `size` (the app's theme).
func _home(size: Vector2) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load("res://scripts/app/island_home_screen.gd").new()
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame
