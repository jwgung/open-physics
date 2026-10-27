## The labs' ground (2026-10-27 user decision: like a corner of the big island, LabWorld): every lab stands
## on a corner of the home map's island, not on a floating island of its own.
## 1. no disc edge: at the lab's default view and at the corners of its camera limits (turned
##    +-100 deg, level and straight down, nearest and farthest), every view ray below the horizon
##    meets the lab's "Island" mesh (land, beach, sea or the horizon haze): no bare sky under the
##    horizon, no island rim.
## 2. the ground the labs' floors stand on: drawn flat at y = 0 within ArtKit.ISLAND_RADIUS of the
##    lab's centre (clear of its trees, rocks and flowers), where the cast stands.
## 3. zone theme: the ground under the lab is its zone's on the map (meadow / hill grass / the
##    yard's sand / the pond's grass with its pond in view / the lookout's headland high over the
##    sea), and at least one other zone's landmark stands in the default view.
## 4. the projectile's physics edge (its BOUNDS_X.y, "섬 밖으로 날아감"): the flat land reaches it
##    and the sea is just beyond it.
## 5. the map's coast: where the lab's coast is not held off the clearing, it is the map's coast.
## 6. budget: the world is one opaque mesh in the map's material (plus the lab's alpha blob shadows
##    when it has any), within VERTS_MAX vertices.
## Physics is checked by the labs' own checks, untouched (the world has no collision).
extends RefCounted

const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const TABLET := Vector2(1152, 720)
const PHONE := Vector2(1560, 720)
const VERTS_MAX := 30000
## Each lab's zone theme (the map's ZONES), written out here.
const THEMES := {
	"projectile": "meadow", "collision": "meadow", "free-fall": "meadow",
	"incline-friction": "hill", "friction": "hill",
	"spring": "yard", "rotation": "yard", "pulley": "yard", "constraints": "yard",
	"buoyancy": "pond", "orbit": "lookout",
}

var tree: SceneTree
var expect: Callable


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	for definition in ExperimentRegistry.load_all():
		await check_lab(definition.id)


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


func check_lab(id: String) -> void:
	var screen := await _open(id, TABLET)
	var lab: Experiment = screen.experiment
	var island: MeshInstance3D = lab.find_child("Island", true, false)
	if island == null or not island.has_meta("world"):
		expect.call(false, "lab world (%s): the lab stands on its corner of the big island" % id, "no Island with a world")
		await _close(screen)
		return
	var world: RefCounted = island.get_meta("world")   # LabWorld (no static reference: compile order)
	var to_local := island.global_transform.affine_inverse()
	var faces := island.mesh.generate_triangle_mesh()
	var hit := func(from: Vector3, dir: Vector3) -> Dictionary:
		return faces.intersect_ray(to_local * from, (to_local.basis * dir).normalized())
	var down := func(x: float, z: float) -> float:
		var h: Dictionary = hit.call(Vector3(x, 60.0, z), Vector3.DOWN)
		return (island.global_transform * (h.position as Vector3)).y if not h.is_empty() else -INF

	# 1. No disc edge: rays below the horizon meet the world at every camera corner.
	var rig: CameraRig = screen.view.rig
	var start: Dictionary = rig.get_state()
	var problems := []
	var cameras := [start]
	for yaw_deg in [-100.0, 0.0, 100.0]:
		for pitch_deg in [-2.0, -89.0]:
			for distance in [rig.distance_range.x, rig.distance_range.y]:
				cameras.append({"mode": start.mode, "yaw": deg_to_rad(yaw_deg), "pitch": deg_to_rad(pitch_deg), "distance": distance, "pan": start.pan})
	var vp := Vector2(screen.view.viewport.size)
	for camera in cameras:
		rig.set_state(camera)
		for fx in [0.0, 0.25, 0.5, 0.75, 1.0]:
			for fy in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var o := rig.project_ray_origin(vp * Vector2(fx, fy))
				var n := rig.project_ray_normal(vp * Vector2(fx, fy))
				if n.y < -0.01 and (hit.call(o, n) as Dictionary).is_empty():
					problems.append("yaw %.0f pitch %.0f at %.1f m: ray %s sees no ground" % [rad_to_deg(camera.yaw), rad_to_deg(camera.pitch), camera.distance, str(Vector2(fx, fy))])
	rig.set_state(start)
	expect.call(problems.is_empty(), "lab world (%s): every view ray below the horizon meets land, beach or sea (no island rim), default view and camera limits" % id,
		"; ".join(problems.slice(0, 3)))

	# 2. Flat at y = 0 where the floors and the cast are.
	var center: Vector3 = island.get_meta("center")
	var obstacles := ArtKit.island_obstacles(center)
	var worst := 0.0
	var samples := 0
	for i in 24:
		for r in [0.4, 3.0, 6.0, 9.0, ArtKit.ISLAND_RADIUS]:   # off the grid's vertices (a ray through one may slip by)
			var p: Vector2 = Vector2(center.x, center.z) + Vector2.from_angle(TAU * (i + 0.37) / 24.0) * r
			var free := true
			for ob in obstacles:
				if p.distance_to(Vector2(ob[0], ob[1])) < ob[2] + 0.3:
					free = false
			if free:
				worst = maxf(worst, absf(down.call(p.x, p.y)))
				samples += 1
	expect.call(worst < 0.002 and samples > 80, "lab world (%s): the ground is drawn flat at y = 0 within %.0f m of the lab's centre (floors, cast)" % [id, ArtKit.ISLAND_RADIUS],
		"worst %.3f m over %d points" % [worst, samples])

	# 3. Zone theme.
	var want: String = THEMES.get(id, "")
	var c_hit: Dictionary = hit.call(Vector3(center.x + 0.31, 60.0, center.z + 0.17), Vector3.DOWN)
	var ground := _face_color(island.mesh, c_hit)
	var nearest := _nearest(ground, {"meadow": ArtPalette.MEADOW, "grass": ArtPalette.GRASS_TOP, "yard": ArtPalette.YARD_SAND})
	var want_ground: String = {"meadow": "meadow", "yard": "yard"}.get(want, "grass")
	var theme_problems := []
	if world.theme != want:
		theme_problems.append("theme %s" % world.theme)
	if nearest != want_ground:
		theme_problems.append("ground under the centre is %s" % nearest)
	match want:
		"pond":   # the pond's water within 30 m
			var water := false
			for i in 36:
				for r in [16.0, 20.0, 24.0, 28.0]:
					var p: Vector2 = Vector2(center.x, center.z) + Vector2.from_angle(TAU * i / 36.0) * r
					var h: Dictionary = hit.call(Vector3(p.x, 60.0, p.y), Vector3.DOWN)
					if _nearest(_face_color(island.mesh, h), {"water": ArtPalette.POND, "deep": ArtPalette.WATER, "grass": ArtPalette.GRASS_TOP, "sand": ArtPalette.SAND}) in ["water", "deep"]:
						water = true
			if not water:
				theme_problems.append("no pond within 30 m")
		"lookout", "hill":   # the hill tops stand high over the sea; the foot of the hill sees it rise
			var high: bool = world.sea_y < -3.0
			if id == "incline-friction":
				high = false
				for i in 36:
					for r in [30.0, 40.0, 50.0, 60.0]:
						var p: Vector2 = Vector2(center.x, center.z) + Vector2.from_angle(TAU * i / 36.0) * r
						high = high or down.call(p.x, p.y) > 2.0
			if not high:
				theme_problems.append("no hill (sea at %.1f m)" % world.sea_y)
			if want == "lookout" and _nearest_coast(world) > 25.0:
				theme_problems.append("the sea is %.0f m from the lookout" % _nearest_coast(world))
		"yard":   # inside the yard's fence
			if not Geometry2D.is_point_in_polygon(Vector2(center.x, center.z), world._fence):
				theme_problems.append("not inside the yard's fence")
	# A landmark of another zone in the default view.
	var seen := 0
	var landmarks := 0
	for f in world.far_things:
		if f[0] != "landmark":
			continue
		landmarks += 1
		var p := Vector3(f[1], float(world.ground_y(Vector2(f[1], f[2]))) + 2.0, f[2])
		if not rig.is_position_behind(p):
			var s := rig.unproject_position(p)
			if Rect2(Vector2.ZERO, vp).has_point(s):
				seen += 1
	if seen == 0:
		theme_problems.append("no other zone's landmark in the default view (%d built)" % landmarks)
	expect.call(theme_problems.is_empty(), "lab world (%s): the %s zone's ground, and another zone's landmark in view" % [id, want],
		"; ".join(theme_problems) + " (%d landmarks, %d in view)" % [landmarks, seen])

	# 4. The projectile's edge: flat land to BOUNDS_X.y, the sea just beyond.
	if id == "projectile":
		var bound: float = lab.BOUNDS_X.y
		var edge_problems := []
		for z in [-3.0, -1.0, 0.0, 1.0, 3.0]:
			var on: float = down.call(bound - 0.1, z)
			var off: float = down.call(bound + 1.2, z)
			if absf(on) > 0.002:
				edge_problems.append("z %.0f: land at %.3f m just inside the bound" % [z, on])
			if off > world.sea_y + 0.06:
				edge_problems.append("z %.0f: %.2f m just beyond the bound (sea %.2f)" % [z, off, world.sea_y])
		expect.call(edge_problems.is_empty(), "projectile: the island's flat land ends at the ball's bound (x %.1f m) and the sea starts beyond it ('섬 밖으로 날아감')" % bound,
			"; ".join(edge_problems))

	# 5. The map's coast where it is not held off the clearing.
	var coast_err := 0.0
	var checked := 0
	for i in world.SECTORS:
		var theta: float = TAU * i / world.SECTORS
		var r: float = world.coast_at(theta)
		if r > world.COAST_MIN + 0.5 and not (id == "projectile" and cos(theta) > 0.0):
			var m: Vector2 = world.to_map(Vector2(center.x, center.z) + Vector2.from_angle(theta) * r)
			coast_err = maxf(coast_err, absf(world.map.coast_fraction(m.x, m.y) - 1.0))
			checked += 1
	expect.call(coast_err < 0.02, "lab world (%s): its coast is the map's coast (%d directions)" % [id, checked], "worst coast fraction off by %.3f" % coast_err)

	# 6. Budget.
	var verts: int = island.mesh.surface_get_array_len(0)
	var material := island.material_override
	var shadows := lab.find_child("IslandShadows", true, false)
	var budget_ok: bool = island.mesh.get_surface_count() == 1 and material == world.map.material() and verts <= VERTS_MAX
	budget_ok = budget_ok and lab.find_children("*", "GeometryInstance3D", true, false).filter(func(n: Node) -> bool: return n.name in ["Island", "IslandShadows"]).size() <= 2
	expect.call(budget_ok, "lab world (%s): one opaque mesh in the map's material (%d vertices <= %d)%s" % [id, verts, VERTS_MAX, ", plus the lab's blob shadows" if shadows != null else ""],
		"%d surfaces, material %s" % [island.mesh.get_surface_count(), str(material)])
	await _close(screen)


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame


## The nearest coast's distance from the lab's centre (m).
static func _nearest_coast(world: RefCounted) -> float:
	var best := INF
	for i in world.SECTORS:
		best = minf(best, world.coast_at(TAU * i / world.SECTORS))
	return best


## The sRGB colour of the face a ray hit (its first vertex; faces are one colour), or black.
static func _face_color(mesh: Mesh, h: Dictionary) -> Color:
	if h.is_empty() or not h.has("face_index"):
		return Color.BLACK
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var i: int = int(h.face_index) * 3
	return colors[i].linear_to_srgb() if i < colors.size() else Color.BLACK


## The name of the candidate colour nearest to `c` (hue and lightness alike, sRGB).
static func _nearest(c: Color, candidates: Dictionary) -> String:
	var best := ""
	var best_d := INF
	for name in candidates:
		var k: Color = candidates[name]
		var d := Vector3(c.r - k.r, c.g - k.g, c.b - k.b).length()
		if d < best_d:
			best_d = d
			best = name
	return best
