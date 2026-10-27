## Plan G2: the island home — the 3D island seen from above, the 5 zones and 11 spots, a tap (on a
## landmark or its name label) that hops the bread cat over and opens the experiment, a drag that
## turns the map, the flag display, and the settings button on the map (phone and tablet). The map
## island (2026-10-27 "지도 전체 손보기", MapIsland): sea, coast, zone ground, landmarks, paths.
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
	await check_map_layout()
	await check_labels_and_taps()
	await check_sea_fills_view()
	check_lab_island_unchanged()
	await check_tap_opens_experiment()
	await check_walk_timing()
	await check_stamp_display()
	await check_buttons_and_layout()
	await check_back_navigation()


## The home renders: the map island in 4 static meshes (land, water, landmarks, shadows: the draw
## budget of the map on SM-P200), the cat, the 5 zones and 11 spots, the top bar with the brand and
## the settings button (no list button, 2026-10-27).
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
	var statics: Array = world.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D).map(func(n: Node) -> String: return str(n.name))
	statics.sort()
	if statics != ["Island", "IslandShadows", "MapLandmarks", "MapWater"]:
		problems.append("static map meshes %s (want land, water, landmarks, shadows)" % str(statics))
	var spots: int = world.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Spot_")).size()
	if screen.ZONES.size() != 5:
		problems.append("%d zones (want 5)" % screen.ZONES.size())
	if spots != 11:
		problems.append("%d spots (want 11)" % spots)
	# Each spot node holds only its flag (hidden until 3 stamps): the landmarks are in one mesh.
	for spot in screen._spots:
		var meshes: int = spot.marker.find_children("*", "MeshInstance3D", true, false).size()
		if meshes != 1:
			problems.append("%s holds %d meshes (want its flag only)" % [spot.id, meshes])
	if screen.find_child("TopBar", true, false) == null:
		problems.append("no top bar")
	var buttons: Array = screen.find_children("ListButton", "", true, false)
	var settings: Array = screen.find_children("SettingsButton", "", true, false)
	if buttons.size() != 0 or settings.size() != 1:
		problems.append("list/settings buttons %d/%d (want 0/1)" % [buttons.size(), settings.size()])
	# The camera looks down at 3/4 and the island is on screen.
	var cam_mode: String = screen.view.rig.mode
	if cam_mode != "three_quarter":
		problems.append("camera mode %s (want three_quarter)" % cam_mode)
	var center_screen: Vector2 = screen._world_to_screen(Vector3(0.0, 0.0, 0.0))
	if center_screen == Vector2.INF or not Rect2(Vector2.ZERO, screen.size).has_point(center_screen):
		problems.append("island centre not on screen %s" % str(center_screen))
	expect.call(problems.is_empty(), "island home builds: map in 4 meshes, cat, 5 zones, 11 spots, top bar, 3/4 camera", "; ".join(problems))
	await _free(screen)


## The map's layout: every zone's ground and every spot's stage on the grass (inside the beach),
## the buoyancy drum in the pond and no other spot in water, one landmark per spot, spots apart,
## paths on land, decorations clear of the paths, stages and the square, the cat on land.
func check_map_layout() -> void:
	var screen := await _home(TABLET)
	var map: MapIsland = screen.map
	var edge := MapIsland.grass_edge()
	var problems := []
	var on_grass := func(p: Vector2, margin: float) -> bool:
		return p.length() + margin <= edge * MapIsland.coast_radius(atan2(p.y, p.x))
	for zone in screen.ZONES:
		var spec: Dictionary = screen.ZONES[zone]
		var at := Vector2(spec.at[0], spec.at[1])
		if spec.ground == "yard":
			for p in MapIsland.yard_outline(spec, 0.0):
				if not on_grass.call(p, 0.0):
					problems.append("%s yard corner %s past the grass" % [zone, str(p)])
					break
		elif not on_grass.call(at, float(spec.radius) * (0.8 if spec.ground == "meadow" else 1.0)):
			problems.append("%s (%s) runs past the grass" % [zone, spec.ground])
	var landmarks := {}
	for spot in screen._spots:
		var at := Vector2(spot.at.x, spot.at.z)
		var info: Dictionary = map.spot_info[spot.id]
		if not on_grass.call(at, float(info.radius)):
			problems.append("%s stage past the grass" % spot.id)
		if map.water_at(at.x, at.y) != (spot.id == "buoyancy"):
			problems.append("%s in water %s (only the buoyancy drum floats)" % [spot.id, str(map.water_at(at.x, at.y))])
		var stand := Vector2(spot.stand.x, spot.stand.z)
		if map.water_at(stand.x, stand.y) or not on_grass.call(stand, 0.0):
			problems.append("%s: the cat would wait in water or on the beach %s" % [spot.id, str(stand)])
		if int(info.vertices) <= 0 or float(info.top) < 0.4:
			problems.append("%s has no landmark (%d vertices, top %.2f)" % [spot.id, info.vertices, info.top])
		landmarks[spot.id] = info.vertices
		for other in screen._spots:
			if other.id != spot.id and at.distance_to(Vector2(other.at.x, other.at.z)) < 2.5:
				problems.append("%s and %s closer than 2.5 m" % [spot.id, other.id])
	if landmarks.size() != 11:
		problems.append("%d landmarks (want 11)" % landmarks.size())
	for q in map.path_points:
		if not on_grass.call(q, MapIsland.PATH_WIDTH * 0.5) or map.water_at(q.x, q.y):
			problems.append("path point %s off the grass or in water" % str(q))
			break
	var trees := 0
	for d in map.decorations:
		var p := Vector2(d[1], d[2])
		trees += 1 if d[0] == "tree" else 0
		for q in map.path_points:
			if p.distance_to(q) < MapIsland.PATH_WIDTH * 0.5 + d[3]:
				problems.append("%s at %s on a path" % [d[0], str(p)])
				break
		for spot in screen._spots:
			if p.distance_to(Vector2(spot.at.x, spot.at.z)) < float(map.spot_info[spot.id].radius) + d[3]:
				problems.append("%s at %s on the %s stage" % [d[0], str(p), spot.id])
		if map.water_at(p.x, p.y) or not on_grass.call(p, 0.0):
			problems.append("%s at %s in water or off the grass" % [d[0], str(p)])
	if trees < 8 or map.decorations.size() < 40:
		problems.append("%d trees, %d decorations (want a dressed island)" % [trees, map.decorations.size()])
	var cat := Vector2(screen.cat.position.x, screen.cat.position.z)
	if map.water_at(cat.x, cat.y) or not on_grass.call(cat, 0.0) or absf(screen.cat.position.y - map.walk_height(cat.x, cat.y)) > 0.01:
		problems.append("the cat does not stand on the square %s" % str(screen.cat.position))
	expect.call(problems.is_empty(), "map layout: zones and stages on the grass, drum in the pond, 11 landmarks, paths and decor clear",
		"; ".join(problems.slice(0, 8)))
	# The ground the paths, stages and cat sit on is the drawn top: height_at() agrees with the
	# land mesh's own triangles under a ray from above (hill slopes included).
	var land: MeshInstance3D = screen.find_child("Island", true, false)
	var faces := land.mesh.get_faces()
	var worst := 0.0
	for p in [Vector2(6.6, 3.1), Vector2(5.0, 4.5), Vector2(8.4, -3.9), Vector2(7.4, -2.6), Vector2(-3.0, 3.0), Vector2(1.0, -1.0)]:
		var hit := -INF
		for t in range(0, faces.size(), 3):
			var x: Variant = Geometry3D.ray_intersects_triangle(Vector3(p.x, 10.0, p.y), Vector3.DOWN, faces[t], faces[t + 1], faces[t + 2])
			if x != null and (x as Vector3).y < 3.0:   # the top, not a tree or a cloud
				hit = maxf(hit, (x as Vector3).y)
		worst = maxf(worst, absf(hit - map.height_at(p.x, p.y)) if hit > -INF else INF)
	expect.call(worst < 0.12, "map ground height matches the drawn top (paths, stages and the cat sit on it)", "worst %.3f m" % worst)
	await _free(screen)


## The spot names at the default camera (phone and tablet): none overlap, each sits right above its
## own landmark (the declutter moved none of them), and a tap on each landmark picks that spot.
func check_labels_and_taps() -> void:
	for setup in [[PHONE, "phone"], [TABLET, "tablet"]]:
		var screen := await _home(setup[0])
		await tree.process_frame
		await tree.process_frame
		var problems := []
		var ids: Array = screen._labels.keys()
		for a in ids.size():
			var la: Control = screen._labels[ids[a]]
			if not la.visible:
				problems.append("%s label hidden" % ids[a])
			for b in range(a + 1, ids.size()):
				var lb: Control = screen._labels[ids[b]]
				if Rect2(la.position, la.size).intersects(Rect2(lb.position, lb.size)):
					problems.append("%s and %s overlap" % [ids[a], ids[b]])
		for i in screen._spots.size():
			var spot: Dictionary = screen._spots[i]
			var label: Control = screen._labels[spot.id]
			var own: Vector2 = screen.label_point(spot) - Vector2(label.size.x * 0.5, label.size.y)
			if label.position.distance_to(own) > 0.5:
				problems.append("%s label moved off its landmark" % spot.id)
			var tap: Vector2 = screen._world_to_screen(screen.tap_point(spot))
			if screen._spot_at(tap) != i:
				problems.append("a tap on the %s landmark picks %d" % [spot.id, screen._spot_at(tap)])
		expect.call(problems.is_empty(), "map (%s): spot names apart over their landmarks, every landmark tappable" % setup[1], "; ".join(problems))
		await _free(screen)


## The sea fills the ground of the view at every camera the map allows (turned all round, -30..-85,
## 16-34 m): each view's bottom corners and middle look down onto water inside SEA_FAR.
func check_sea_fills_view() -> void:
	var screen := await _home(TABLET)
	var rig: Camera3D = screen.view.rig
	var problems := []
	for yaw_deg in [0.0, 90.0, 180.0, -135.0]:
		for pitch_deg in [-30.0, -55.0, -85.0]:
			for distance in [16.0, 34.0]:
				rig.set_state({"mode": rig.mode, "yaw": deg_to_rad(yaw_deg), "pitch": deg_to_rad(pitch_deg), "distance": distance})
				var vp: Vector2 = Vector2(screen.view.viewport.size)
				for f in [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(0.5, 0.5), Vector2(0.0, 0.5)]:
					var o := rig.project_ray_origin(vp * f)
					var n := rig.project_ray_normal(vp * f)
					if n.y >= -1e-3:
						continue   # sky above the horizon
					var at := o + n * ((MapIsland.SEA_Y - o.y) / n.y)
					if Vector2(at.x, at.z).length() > MapIsland.SEA_FAR * 0.9:
						problems.append("yaw %d pitch %d %d m: %s sees past the sea" % [yaw_deg, pitch_deg, distance, str(f)])
	expect.call(problems.is_empty(), "the sea fills the map's ground at every allowed camera", "; ".join(problems.slice(0, 4)))
	await _free(screen)


## The labs keep their own island (ArtKit.build_island): the map's island is separate, the lab
## island's mesh is the one it was before the map changed (vertex count and vertex sum).
func check_lab_island_unchanged() -> void:
	var root := Node3D.new()
	ArtKit.build_island(root)
	var got := []
	for name in ["Island", "IslandShadows"]:
		var mi: MeshInstance3D = root.find_child(name, false, false)
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var sum := Vector3.ZERO
		for p in v:
			sum += p
		got.append([v.size(), sum])
	root.free()
	var want := [[3510, Vector3(1630.223, 8495.116, -28445.99)], [864, Vector3(118.8001, 10.36806, -604.7978)]]
	var same := true
	for i in 2:
		same = same and got[i][0] == want[i][0] and (got[i][1] as Vector3).distance_to(want[i][1]) < 0.05
	expect.call(same, "the labs' island is unchanged by the map's island", str(got))


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
	var screen_point: Vector2 = screen._world_to_screen(screen.tap_point(target))
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
	var empty: Vector2 = screen._world_to_screen(Vector3(0.0, 0.0, 5.5))   # open grass below the square
	# Make sure that point is not within reach of a spot.
	var nearest := INF
	for spot in screen._spots:
		nearest = minf(nearest, screen._world_to_screen(screen.tap_point(spot)).distance_to(empty)) if empty != Vector2.INF else INF
	if nearest > 10.0:
		screen._on_pointer("press", empty)
		await tree.process_frame
		screen._on_pointer("release", empty)
		expect.call(chosen.is_empty() and not screen._walking, "a tap on empty grass opens nothing", "chosen %s" % str(chosen))
	else:
		expect.call(true, "empty-grass tap skipped (no clear empty point on this layout)", "")
	# A drag (a move beyond the slop) is not a tap: it turns the map.
	chosen.clear()
	var from: Vector2 = screen._world_to_screen(screen.tap_point(target))
	var yaw_before: float = screen.view.rig.goal_yaw
	screen._on_pointer("press", from)
	await tree.process_frame
	screen._on_pointer("move", from + Vector2(40, 0))
	screen._on_pointer("move", from + Vector2(80, 0))
	screen._on_pointer("release", from + Vector2(80, 0))
	expect.call(chosen.is_empty() and not screen._walking, "a drag over a spot does not open it", "chosen %s" % str(chosen))
	expect.call(not is_equal_approx(screen.view.rig.goal_yaw, yaw_before), "a one-finger drag turns the map",
		"yaw %.3f -> %.3f" % [yaw_before, screen.view.rig.goal_yaw])
	await _free(screen)
	# A tap on a spot's name label (the label takes no input itself) opens that spot.
	screen = await _home(TABLET)
	chosen.clear()
	screen.experiment_chosen.connect(func(d: Dictionary) -> void: chosen.append(d.id))
	await tree.process_frame
	await tree.process_frame
	var label: Control = screen._labels.get("orbit")
	var on_label: Vector2 = label.position + label.size * 0.5 if label != null else Vector2.INF
	expect.call(label != null and label.mouse_filter == Control.MOUSE_FILTER_IGNORE and screen._spot_at(on_label) >= 0
			and screen._spots[screen._spot_at(on_label)].id == "orbit",
		"a tap on a spot's name label picks that spot (the label passes the touch to the map)", str(on_label))
	await _free(screen)


## The cat's hop takes its time in seconds, not in frames: one long frame moves it as far as many
## short ones (a slow device does not make the walk slower).
func check_walk_timing() -> void:
	var screen := await _home(PHONE)
	var chosen := []
	screen.experiment_chosen.connect(func(d: Dictionary) -> void: chosen.append(d.id))
	screen._walk_to_spot(0)
	var total: float = screen._walk_total
	screen._process(total + 0.01)
	expect.call(not screen._walking and chosen == [screen._spots[0].id],
		"the hop ends after its duration in seconds (one %.2f s frame)" % total, "walking %s chosen %s" % [str(screen._walking), str(chosen)])
	await _free(screen)


## A spot label is its name only (no "도전" badge, 2026-10-27); at 3 stamps the flag stands.
## Progress (0/3) is shown only in the experiment screen, not on the map.
func check_stamp_display() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _home(TABLET)
	# A fresh map: the projectile spot's label is its name, one label and nothing else.
	await tree.process_frame
	await tree.process_frame
	var label: Label = _label_text(screen, "projectile")
	var box: Node = screen._labels.get("projectile")
	var labels: int = box.find_children("*", "Label", true, false).size() if box != null else 0
	expect.call(label != null and label.text.contains("던지기") and labels == 1,
		"a spot label shows only its name (no badge)", label.text if label else "")
	# The map reads the store when it opens, never per frame (SM-P200: 11 file reads a frame cost
	# the home its 60 fps).
	var reads := ProgressStore.load_count
	for i in 30:
		await tree.process_frame
	expect.call(ProgressStore.load_count == reads, "the map reads no progress file per frame",
		"%d reads in 30 frames" % (ProgressStore.load_count - reads))
	await _free(screen)
	# Award 3 stamps: the map opened again stands the flag (every spot, the projectile and the other 10).
	var finished := {}
	for spot in ExperimentRegistry.load_all():
		finished[spot.id] = 3
	ProgressStore.save({"projectile": 3})
	screen = await _home(TABLET)
	var flag: Node3D = screen._flags.get("projectile")
	expect.call(flag != null and flag.visible, "a finished spot stands its flag", "flag visible %s" % str(flag.visible if flag else null))
	await _free(screen)
	ProgressStore.save(finished)
	screen = await _home(TABLET)
	var flagless := []
	for id in finished:
		var spot_flag: Node3D = screen._flags.get(id)
		if spot_flag == null or not spot_flag.visible:
			flagless.append(id)
	expect.call(flagless.is_empty(), "every spot with 3 stamps stands its flag", str(flagless))
	await _free(screen)
	# An unfinished spot has no flag.
	ProgressStore.save({"projectile": 1, "orbit": 2})
	screen = await _home(TABLET)
	var orbit_label: Label = _label_text(screen, "orbit")
	var orbit_flag: Node3D = screen._flags.get("orbit")
	expect.call(orbit_label != null and orbit_label.text.contains(ExperimentRegistry.kid_text(ExperimentRegistry.find("orbit"), "place")),
		"a spot label shows the lab's kid place name (orbit = 별 돌기)", orbit_label.text if orbit_label else "")
	expect.call(orbit_flag != null and not orbit_flag.visible, "an unfinished spot has no flag", "flag visible %s" % str(orbit_flag.visible if orbit_flag else null))
	DirAccess.remove_absolute(ProgressStore.path)
	await _free(screen)


## The settings button is on the map and reachable (phone and tablet); there is no list button.
func check_buttons_and_layout() -> void:
	for setup in [[PHONE, "phone"], [TABLET, "tablet"]]:
		var screen := await _home(setup[0])
		await tree.process_frame
		await tree.process_frame
		var bar: PanelContainer = screen.find_child("TopBar", true, false)
		var settings: Button = screen.find_child("SettingsButton", true, false)
		var problems := []
		if bar == null or settings == null:
			problems.append("top bar / settings missing")
		else:
			if not Rect2(Vector2.ZERO, screen.size).encloses(bar.get_global_rect()):
				problems.append("top bar off screen")
			if not Rect2(Vector2.ZERO, screen.size).encloses(settings.get_global_rect()):
				problems.append("the settings button off screen")
		# The 3D view fills the screen under the bar.
		if screen.view.size != setup[0]:
			problems.append("view size %s (want full %s)" % [str(screen.view.size), str(setup[0])])
		expect.call(problems.is_empty(), "island home (%s): top bar with settings on the map, the 3D view full" % setup[1], "; ".join(problems))
		await _free(screen)


## Android back (App._go_back): an experiment and settings go back to the map; only back on the
## map quits (not called here: it would end the run).
func check_back_navigation() -> void:
	var app: Control = load("res://scripts/app/app.gd").new()
	tree.root.add_child(app)
	await tree.process_frame
	var trail := [app._screen.get_class() if not app._screen is IslandHomeScreen else "map"]
	app.show_experiment(ExperimentRegistry.find("free-fall"))
	await tree.process_frame
	app._go_back()
	trail.append("map" if app._screen is IslandHomeScreen else str(app._screen))
	app.show_settings()
	app._go_back()
	trail.append("map" if app._screen is IslandHomeScreen else str(app._screen))
	expect.call(trail == ["map", "map", "map"],
		"back: the app opens on the map; back from an experiment and settings returns to the map", str(trail))
	app.queue_free()
	for i in 3:
		await tree.process_frame


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
