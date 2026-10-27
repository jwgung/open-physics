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
	await check_cast_on_map()
	await check_camera_limits()
	await check_sea_fills_view()
	check_lab_island_unchanged()
	await check_tap_opens_experiment()
	await check_walk_timing()
	await check_stamp_display()
	await check_buttons_and_layout()
	await check_back_navigation()


## The home renders: the map island as one static opaque mesh (landmarks, water, land with its baked
## blob shadows: the draw and fill budget of the map on SM-P200), the cat, the 5 zones and 11 spots, the top bar with the brand and
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
	if statics != ["Island", "MapSky"]:
		problems.append("static map meshes %s (want the island: land, water, landmarks, baked shadows; and the sky)" % str(statics))
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
	expect.call(problems.is_empty(), "island home builds: map in 1 mesh, cat, 5 zones, 11 spots, top bar, 3/4 camera", "; ".join(problems))
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
	# map mesh's own triangles under a ray from above (hill slopes included, clear of landmarks).
	var land: MeshInstance3D = screen.find_child("Island", true, false)
	var faces := land.mesh.get_faces()
	var worst := 0.0
	for p in [Vector2(7.8, 1.4), Vector2(5.0, 4.5), Vector2(9.6, -5.0), Vector2(7.4, -2.6), Vector2(-3.0, 3.0), Vector2(1.0, -1.0)]:   # hill slopes, off the stages
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


## Dugi and Puppy are on the map with the cat (2026-10-27 user requests): the three in one row on
## the square, evenly spaced, the cat in the middle, all facing the camera, at the default view and
## after the map is turned (the row follows the camera's yaw); on land, clear of the stages and of
## every spot name at the default camera (phone and tablet); the puppy's flag waves.
func check_cast_on_map() -> void:
	for setup in [[PHONE, "phone"], [TABLET, "tablet"]]:
		var screen := await _home(setup[0])
		await tree.process_frame
		await tree.process_frame
		var map: MapIsland = screen.map
		var problems := []
		var home := Vector2(screen.HOME[0], screen.HOME[1])
		for actor in [screen.dugi, screen.puppy]:
			if actor == null or not actor.is_visible_in_tree():
				problems.append("an actor is missing")
				continue
			var at := Vector2(actor.position.x, actor.position.z)
			if at.distance_to(home) > MapIsland.PLAZA_RADIUS or map.water_at(at.x, at.y) or absf(actor.position.y - map.walk_height(at.x, at.y)) > 0.01:
				problems.append("%s not standing on the square" % str(actor.position))
			for spot in screen._spots:
				if at.distance_to(Vector2(spot.at.x, spot.at.z)) < float(spot.radius) + 0.6:
					problems.append("%s on the %s stage" % [str(at), spot.id])
			var box: AABB = actor.bounds()
			var rect := Rect2(screen._world_to_screen(box.position), Vector2.ZERO)
			for i in 8:
				rect = rect.expand(screen._world_to_screen(box.get_endpoint(i)))
			for id in screen._labels:
				var label: Control = screen._labels[id]
				if Rect2(label.position, label.size).intersects(rect):
					problems.append("%s under the %s name" % [str(at), id])
		problems.append_array(_trio_problems(screen, "default"))
		# Turn the map: the row and the faces follow the camera (eased, settled after a moment).
		screen.view.rig.set_state({"mode": screen.view.rig.mode, "yaw": deg_to_rad(110.0), "pitch": deg_to_rad(-40.0), "distance": 27.0})
		for i in 90:
			screen._process(1.0 / 60.0)
		problems.append_array(_trio_problems(screen, "turned 110 deg"))
		var wave: float = screen.puppy.wave_angle()
		for i in 20:
			await tree.process_frame
		if is_equal_approx(wave, screen.puppy.wave_angle()):
			problems.append("puppy's flag does not wave")
		expect.call(problems.is_empty(), "map (%s): cat, Dugi and Puppy in a row facing the camera (default and turned), on the square, clear of stages and names" % setup[1],
			"; ".join(problems))
		await _free(screen)


## The trio's row: Dugi, cat, Puppy colinear (within 2 cm) and evenly spaced, the row across the
## view (square to the camera's ground direction), all three facing the camera within 10 deg.
func _trio_problems(screen: Control, view_name: String) -> Array:
	var out := []
	var actors: Array = screen.trio()
	var p: Array = actors.map(func(a: Node3D) -> Vector2: return Vector2(a.position.x, a.position.z))
	var line: Vector2 = (p[2] - p[0]).normalized()
	var off := absf(line.cross(p[1] - p[0]))
	if off > 0.02 or absf(p[1].distance_to(p[0]) - p[1].distance_to(p[2])) > 0.02:
		out.append("%s: not one even row (off %.3f m)" % [view_name, off])
	var yaw: float = screen.view.rig.cur_yaw
	var toward := Vector2(sin(yaw), cos(yaw))   # from the square towards the camera, on the ground
	if absf(line.dot(toward)) > sin(deg_to_rad(10.0)):
		out.append("%s: the row is not across the view" % view_name)
	var fronts := [0.0, PI, 0.0]   # the cat's model faces -z, Dugi's and Puppy's +z
	for i in 3:
		var facing: float = actors[i].rotation.y - fronts[i]
		if absf(angle_difference(facing, yaw)) > deg_to_rad(10.0):
			out.append("%s: %s faces %.0f deg off the camera" % [view_name, actors[i].name, rad_to_deg(angle_difference(facing, yaw))])
	return out


## The map camera is almost free (2026-10-27 user decision): straight down to almost level, 6-60 m,
## moved over the ground within its radius; the island stays reachable (the look-at point never
## leaves PAN_RADIUS of the centre, and the pan stays on the ground).
func check_camera_limits() -> void:
	var screen := await _home(TABLET)
	var rig: CameraRig = screen.view.rig
	var problems := []
	if not is_equal_approx(rad_to_deg(rig.pitch_range.x), -89.0) or not is_equal_approx(rad_to_deg(rig.pitch_range.y), -8.0):
		problems.append("pitch range %s" % str(rig.pitch_range))
	if rig.distance_range != Vector2(6.0, 60.0):
		problems.append("distance range %s" % str(rig.distance_range))
	if not screen.view.two_finger_pan or not rig.pan_ground:
		problems.append("two fingers do not move the map over the ground")
	for i in 40:
		rig.pan_by(Vector2(-300.0, 200.0))
	if rig.pan.length() > rig.pan_radius + 1e-3 or absf(rig.pan.y) > 1e-4 or rig.pan_radius < 12.0:
		problems.append("pan %s (radius %.1f)" % [str(rig.pan), rig.pan_radius])
	expect.call(problems.is_empty(), "map camera: -89..-8 deg, 6-60 m, two-finger pan over the ground within the island", "; ".join(problems))
	# A close, low view: spots behind the camera have no label and cannot be tapped.
	rig.set_state({"mode": rig.mode, "yaw": 0.0, "pitch": deg_to_rad(-8.0), "distance": 6.0, "pan": Vector3.ZERO})
	for i in 4:
		await tree.process_frame
	var behind := []
	var wrong := []
	for spot in screen._spots:
		var is_behind: bool = rig.is_position_behind(screen.tap_point(spot))
		var label: Control = screen._labels[spot.id]
		if is_behind:
			behind.append(spot.id)
			if label.visible:
				wrong.append(spot.id + " label shown")
	expect.call(not behind.is_empty() and wrong.is_empty(), "map: names of spots behind a low, close camera hide", "behind %s; %s" % [str(behind), str(wrong)])
	await _free(screen)


## The sea and sky at every camera the map allows (turned all round, -89..-8 deg, 6-60 m, moved to
## its edge; phone and tablet): the open sea is the clear colour (MapIsland.make_environment, no
## sea plane: SM-P200 fill cost); every view ray below the horizon meets the sea inside the sky
## backdrop, every ray above it meets the backdrop below its top (no bare clear colour as sky).
func check_sea_fills_view() -> void:
	var problems := []
	for size in [PHONE, TABLET]:
		var screen := await _home(size)
		var rig: CameraRig = screen.view.rig
		var environment: Environment = screen.view.viewport.find_children("*", "WorldEnvironment", true, false)[0].environment
		if not environment.background_color.is_equal_approx(MapIsland.sea_color()):
			problems.append("clear colour %s is not the sea" % str(environment.background_color))
		for yaw_deg in [0.0, 90.0, 180.0, -135.0]:
			for pitch_deg in [-8.0, -30.0, -89.0]:
				for distance in [6.0, 60.0]:
					var pan := Vector3(cos(deg_to_rad(yaw_deg)), 0.0, sin(deg_to_rad(yaw_deg))) * rig.pan_radius
					rig.set_state({"mode": rig.mode, "yaw": deg_to_rad(yaw_deg), "pitch": deg_to_rad(pitch_deg), "distance": distance, "pan": pan})
					var vp: Vector2 = Vector2(screen.view.viewport.size)
					for f in [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 0.5), Vector2(0.0, 1.0), Vector2(1.0, 1.0)]:
						var o := rig.project_ray_origin(vp * f)
						var n := rig.project_ray_normal(vp * f)
						var flat := Vector2(n.x, n.z)
						if n.y < -0.09:   # clearly below the horizon (5 deg): the sea
							var at := o + n * ((MapIsland.SEA_Y - o.y) / n.y)
							if Vector2(at.x, at.z).length() > MapIsland.SKY_RADIUS:
								problems.append("%s: ray %s meets the backdrop, not the sea" % [str([yaw_deg, pitch_deg, distance]), str(f)])
						elif n.y > 0.0 and flat.length() > 1e-3:   # the sky: the backdrop's height where the ray meets it
							var o2 := Vector2(o.x, o.z)
							var d := flat.normalized()
							var b := o2.dot(d)
							var t := -b + sqrt(b * b - o2.length_squared() + MapIsland.SKY_RADIUS * MapIsland.SKY_RADIUS)
							if o.y + n.y * t / flat.length() > 650.0:
								problems.append("%s: ray %s above the backdrop" % [str([yaw_deg, pitch_deg, distance]), str(f)])
		await _free(screen)
	expect.call(problems.is_empty(), "the sea fills the ground and the sky backdrop the sky at every allowed camera", "; ".join(problems.slice(0, 4)))


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
