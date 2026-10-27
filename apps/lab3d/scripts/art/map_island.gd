## The island map's own island (home screen, 2026-10-27 user decision "지도 전체 손보기"): an
## irregular coastline with a sand beach in a sea that fills the view, the zones as ground (a
## meadow, hills, a sandy play yard, a pond), dirt paths between the spots, each spot's landmark
## (MapLandmarks) on a round stage, and trees, rocks, flowers and clouds placed clear of them.
## The labs keep ArtKit.build_island; nothing here is shared with them.
##
## Draw calls: one static opaque mesh (landmarks, water: shallows, surf, pond; land: top, beach,
## overlays, trees with their baked blob shadows, clouds) in map_lit.gdshader (art_lit's light,
## encoded per vertex), no texture, no light, no blending, no animation. The open sea is the clear
## colour. Measured on SM-P200 at a 450 MHz GPU lock (2026-10-27), see map_lit.gdshader and _add_sea. The top is a polar grid over the coast whose vertices are jittered for the
## low-poly facets; height_at() reads that same mesh, so the paths, stages and the cat sit on it.
class_name MapIsland
extends RefCounted

## The coast: an ellipse (wide like the tablet screen) plus a few smooth harmonics, and the
## lookout's headland as one bump [angle deg (atan2(z, x)), metres, width deg].
const RADIUS_X := 12.8
const RADIUS_Z := 10.4
const COAST_WAVES := [[3, 0.42, 0.7], [5, 0.28, 2.1], [7, 0.18, 4.0], [9, 0.1, 1.0]]
const COAST_BUMPS := [[-25.0, 1.6, 22.0], [32.0, 0.6, 18.0]]
## The top grid: rings as fractions of the coast radius, SECTORS around. Rings from GRASS_EDGE
## out are the beach, at the heights BEACH_Y (the last ring dips under the sea: the shoreline).
const SECTORS := 60
const RINGS := [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.58, 0.66, 0.73, 0.8, 0.86, 0.93, 1.0]
const GRASS_EDGE := 10
const BEACH_Y := [0.0, -0.06, -0.45]
const JITTER := 0.3                 # share of a grid cell the inner vertices move (facets)
const HILL_PLATEAU := 0.35          # share of a hill's radius that is its flat top
const SEA_Y := -0.2
const SHORE_F := 0.955              # coast fraction where the beach meets the sea (BEACH_Y at SEA_Y)
const SHALLOW := 1.3                # m of light shallow water outside the coast
const PATH_WIDTH := 0.8
const PATH_LIFT := 0.05             # m above the grass (no z-fight at 34 m)
const OVERLAY_LIFT := 0.03          # yard sand, pond shore
const PLAZA_LIFT := 0.07
const PLAZA_RADIUS := 1.35
## Decoration: trees [x, z, size], rocks [x, z, radius]; flowers are scattered (seeded) where
## nothing else stands. Clouds [x, y, z, size] ring the island out of the top view.
const TREES := [
	[-9.4, 0.5, 0.9], [-5.9, -6.8, 0.9], [6.4, -6.3, 0.85], [10.3, 0.8, 0.9], [8.2, 5.9, 0.8],
	[1.4, 7.9, 0.85], [-1.6, 7.6, 0.9], [-7.6, 6.0, 0.75], [2.9, 1.3, 0.7], [-7.0, 0.8, 0.7],
]
const ROCKS := [[10.6, -3.0, 0.4], [11.0, -1.4, 0.35], [-3.8, -1.8, 0.35], [-3.0, 7.2, 0.35], [5.6, 7.2, 0.4], [0.3, 5.6, 0.3]]
const CLOUDS := [[-10.0, 5.5, -22.0, 1.7], [6.0, 6.5, -24.0, 2.0], [22.0, 5.0, -8.0, 1.5], [-23.0, 5.5, 4.0, 1.6], [12.0, 5.0, 21.0, 1.4]]
const WAVES := [[200.0, 15.5, 2.4], [235.0, 18.0, 3.0], [280.0, 14.0, 2.0], [320.0, 17.5, 2.6], [10.0, 16.5, 2.4],
	[55.0, 14.5, 2.2], [100.0, 15.0, 2.6], [145.0, 17.0, 2.2], [170.0, 21.0, 3.0], [300.0, 22.0, 3.0]]
const FLOWER_SEED := 27
const MEADOW_FLOWERS := 22
const OTHER_FLOWERS := 18

var zones: Dictionary
var paths: Array
var home: Vector2
var _grid: Array = []               # rings x sectors of Vector3 (the top's vertices)
var _hills: Array = []              # [centre Vector2, radius, height]
## Built pieces, for tests: path samples (Vector2), decorations [kind, x, z, radius], per spot.
var path_points := PackedVector2Array()
var decorations: Array = []
var spot_info: Dictionary = {}


## `zones` is IslandHomeScreen.ZONES (each zone's "ground" and size), `paths` its polylines of
## [x, z] points, `home` the cat's square.
func _init(zone_specs: Dictionary, path_specs: Array, home_at: Vector2) -> void:
	zones = zone_specs
	paths = path_specs
	home = home_at
	for zone in zones:
		var spec: Dictionary = zones[zone]
		if spec.ground == "hill":
			_hills.append([_v2(spec.at), float(spec.radius), float(spec.height)])
	_build_grid()


# --- the shape --------------------------------------------------------------------------------

## The coast's distance from the island centre in the direction `theta` (atan2(z, x)).
static func coast_radius(theta: float) -> float:
	var c := cos(theta)
	var s := sin(theta)
	var r := 1.0 / sqrt(c * c / (RADIUS_X * RADIUS_X) + s * s / (RADIUS_Z * RADIUS_Z))
	for w in COAST_WAVES:
		r += w[1] * sin(w[0] * theta + w[2])
	for bump in COAST_BUMPS:
		var t := angle_difference(theta, deg_to_rad(bump[0])) / deg_to_rad(bump[2])
		r += bump[1] * exp(-t * t)
	return r


## How far out (x, z) lies: 0 at the centre, 1 on the coast; the grass ends at RINGS[GRASS_EDGE].
static func coast_fraction(x: float, z: float) -> float:
	return Vector2(x, z).length() / coast_radius(atan2(z, x))


static func grass_edge() -> float:
	return RINGS[GRASS_EDGE]


## The top's height at (x, z): the mesh itself (its triangle there), so what stands on it sits on
## the faces drawn, not on the smooth curve they approximate. Off the island: the sunk last ring.
func height_at(x: float, z: float) -> float:
	var theta := atan2(z, x)
	var f := coast_fraction(x, z)
	if f >= 1.0:
		return BEACH_Y[-1]
	var i0 := int(floor(fposmod(theta, TAU) / TAU * SECTORS))
	var j0 := 0
	while j0 < RINGS.size() - 2 and RINGS[j0 + 1] <= f:
		j0 += 1
	var p := Vector2(x, z)
	for dj in [0, -1, 1]:
		var j: int = j0 + dj
		if j < 0 or j >= RINGS.size() - 1:
			continue
		for di in [0, -1, 1, -2, 2]:
			var i := posmod(i0 + di, SECTORS)
			var quad := _quad(j, i)
			for tri in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]:
				var w := _bary(p, tri)
				if w.x >= -1e-4 and w.y >= -1e-4 and w.z >= -1e-4:
					return w.x * tri[0].y + w.y * tri[1].y + w.z * tri[2].y
	return _ground_height(x, z, f, RINGS.size() - 1)


## Where the cat stands at (x, z): the ground plus the square or path it is on.
func walk_height(x: float, z: float) -> float:
	var lift := PLAZA_LIFT if Vector2(x, z).distance_to(home) < PLAZA_RADIUS else PATH_LIFT
	return height_at(x, z) + lift


## True when (x, z) is in the pond's water.
func water_at(x: float, z: float) -> bool:
	for zone in zones:
		var spec: Dictionary = zones[zone]
		if spec.ground == "pond" and Vector2(x, z).distance_to(_v2(spec.at)) < _pond_radius(spec, atan2(z - spec.at[1], x - spec.at[0])):
			return true
	return false


func _hill_height(x: float, z: float) -> float:
	var h := 0.0
	for hill in _hills:
		var d: float = Vector2(x, z).distance_to(hill[0]) / hill[1]
		if d < 1.0:
			var t := clampf((d - HILL_PLATEAU) / (1.0 - HILL_PLATEAU), 0.0, 1.0)
			h = maxf(h, hill[2] * (1.0 - t * t * (3.0 - 2.0 * t)))
	return h


## The height of a grid vertex at (x, z) on ring `ring`: hills inside the grass, the beach
## profile from the grass edge out.
func _ground_height(x: float, z: float, f: float, ring: int) -> float:
	if ring >= GRASS_EDGE:
		return BEACH_Y[ring - GRASS_EDGE]
	return _hill_height(x, z) * (1.0 - smoothstep(0.76, RINGS[GRASS_EDGE], f))


func _build_grid() -> void:
	_grid.clear()
	for j in RINGS.size():
		var row: Array = []
		for i in SECTORS:
			var theta := TAU * i / SECTORS
			var f: float = RINGS[j]
			if j > 0 and j < GRASS_EDGE:
				var step: float = minf(RINGS[j + 1] - RINGS[j], RINGS[j] - RINGS[j - 1])
				theta += _hash(i, j, 1) * JITTER * TAU / SECTORS
				f += _hash(i, j, 2) * JITTER * step
			var r := f * coast_radius(theta)
			var x := r * cos(theta)
			var z := r * sin(theta)
			row.append(Vector3(x, _ground_height(x, z, f, j), z))
		_grid.append(row)


func _quad(j: int, i: int) -> Array:
	var i1 := (i + 1) % SECTORS
	return [_grid[j][i], _grid[j][i1], _grid[j + 1][i1], _grid[j + 1][i]]


static func _bary(p: Vector2, tri: Array) -> Vector3:
	var a := Vector2(tri[0].x, tri[0].z)
	var v0 := Vector2(tri[1].x, tri[1].z) - a
	var v1 := Vector2(tri[2].x, tri[2].z) - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return Vector3(-1.0, -1.0, -1.0)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)


## A fixed pseudo-random value in [-1, 1] for grid cell (i, j) (deterministic facets).
static func _hash(i: int, j: int, salt: int) -> float:
	var v := sin(float(i) * 12.9898 + float(j) * 78.233 + float(salt) * 37.719) * 43758.5453
	return (v - floor(v)) * 2.0 - 1.0


## The map's environment: ArtKit's, with the open sea as the clear colour (SEA as an upward
## face of art_lit.gdshader shows it: lit plus the sky fill, so the shallow ring meets it cleanly).
const SHADER := preload("res://scripts/art/map_lit.gdshader")
static var _material: ShaderMaterial


## The map's one solid material (map_lit.gdshader: ArtKit.lit_material's light, encoded per vertex).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("sun_dir", ArtKit.SUN_DIR)
		_material.set_shader_parameter("lit_color", ArtPalette.LIGHT)
		_material.set_shader_parameter("shade_color", ArtPalette.SHADE)
		_material.set_shader_parameter("threshold", ArtKit.LIGHT_THRESHOLD)
		_material.set_shader_parameter("softness", ArtKit.LIGHT_SOFTNESS)
		_material.set_shader_parameter("sky_fill", ArtKit.SKY_FILL)
		# art_lit encodes where OUTPUT_IS_SRGB: the Compatibility renderer (Mobile converts itself).
		_material.set_shader_parameter("encode_srgb", RenderingServer.get_current_rendering_method() == "gl_compatibility")
	return _material


static func make_environment() -> WorldEnvironment:
	var world := ArtKit.make_environment()
	world.environment.background_color = sea_color()
	return world


static func sea_color() -> Color:
	var lin := ArtPalette.SEA.srgb_to_linear()
	var k := 1.0 + ArtKit.SKY_FILL
	return Color(lin.r * k, lin.g * k, lin.b * k).linear_to_srgb()


static func _v2(at: Array) -> Vector2:
	return Vector2(float(at[0]), float(at[1]))


# --- building ---------------------------------------------------------------------------------

## Builds the map under `world` as ONE mesh, "Island": landmarks, water and land in one builder, in
## the order they cover each other (what lies on the grass first, the grass and beach last), so
## the covered ground fails the depth test instead of being shaded and drawn over (SM-P200 fill).
## `spots` are [id, Vector2 at, yaw deg]; returns spot_info: id -> {at (stage top), top (landmark
## height above at), stand (where the cat waits), flag (where the flag stands), radius, vertices}.
func build(world: Node3D, spots: Array) -> Dictionary:
	var land := ArtKit.builder()
	var water := land
	var marks := land
	for spot in spots:
		_add_spot(marks, spot)
	for zone in zones:
		var spec: Dictionary = zones[zone]
		match spec.ground:
			"yard":
				_add_yard(land, spec)
			"pond":
				_add_pond(land, water, spec)
	_add_sea(water)
	_add_paths(land)
	_add_plaza(land)
	_add_decor(land)
	_add_clouds(land)
	# The grass and beach last: drawn after the yard, paths, square and trees that lie on them, the
	# covered grass fails the depth test before it is shaded (overdraw on SM-P200).
	_add_top(land)
	var mi := ArtKit.instance(land.commit(), material())
	mi.name = "Island"
	world.add_child(mi)
	return spot_info


## The top: grass (the meadow lighter, a little shade jitter per face for the facets, slopes
## darker as they turn from the sun so a hill reads from above) and the sand beach ring sloping
## into the sea.
func _add_top(b: ArtMeshBuilder) -> void:
	var meadows: Array = []
	for zone in zones:
		if zones[zone].ground == "meadow":
			meadows.append([_v2(zones[zone].at), float(zones[zone].radius)])
	for j in RINGS.size() - 1:
		for i in SECTORS:
			var q := _quad(j, i)
			for k in 2:
				var tri: Array = [q[0], q[1], q[2]] if k == 0 else [q[0], q[2], q[3]]
				var color := _top_color(j, i, k, tri, meadows)
				b.add_triangle(tri, [color, color, color])


func _top_color(j: int, i: int, k: int, tri: Array, meadows: Array) -> Color:
	if j >= GRASS_EDGE:
		return ArtPalette.SAND
	var c: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
	var color := ArtPalette.GRASS_TOP
	for m in meadows:
		if Vector2(c.x, c.z).distance_to(m[0]) < m[1]:
			color = ArtPalette.MEADOW
	var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
	if n.y < 0.0:
		n = -n
	var sun := n.dot(ArtKit.SUN_DIR.normalized())   # the face's light, 0.83 when flat
	color = color.darkened(clampf((0.83 - sun) * 0.8, 0.0, 0.25)) if sun < 0.83 else color.lightened(clampf((sun - 0.83) * 1.5, 0.0, 0.2))
	return color.lightened(0.05 * (_hash(i, j, 3 + k) * 0.5 + 0.5))


## The sea's geometry: only the light shallow ring (a wavy outer edge) hugging the coast, the white
## surf line along the shore and a few wave strokes. The open sea is the view's clear colour
## (make_environment): the map camera never looks above the horizon, so the background is always
## sea, and a sea plane filling the screen cost the home a third of its frame on SM-P200
## (2026-10-27: 13.5 -> 9.4 M GPU cycles a frame without it).
func _add_sea(b: ArtMeshBuilder) -> void:
	var inner := func(t: float) -> float: return (SHORE_F - 0.015) * coast_radius(t)   # just under the wet sand
	var shallow := func(t: float) -> float: return coast_radius(t) + SHALLOW + 0.45 * sin(4.0 * t + 0.6)
	# Surf along the shoreline and the wave strokes first: the shallows under them are then
	# rejected by depth instead of shaded twice.
	var surf_in := func(t: float) -> float: return SHORE_F * coast_radius(t) - 0.1
	var surf_out := func(t: float) -> float: return SHORE_F * coast_radius(t) + 0.3 + 0.08 * sin(9.0 * t)
	_ring_band(b, [surf_in, ArtPalette.FOAM], [surf_out, ArtPalette.FOAM], SEA_Y + 0.02)
	for w in WAVES:
		_wave(b, deg_to_rad(w[0]), w[1], w[2])
	_ring_band(b, [inner, ArtPalette.SEA_SHALLOW], [shallow, ArtPalette.SEA_SHALLOW], SEA_Y)


## A band between two rings [radius fn, colour] at height y (one quad per sector).
func _ring_band(b: ArtMeshBuilder, a: Array, c: Array, y: float) -> void:
	var sectors := SECTORS * 2
	for i in sectors:
		var t0 := TAU * i / sectors
		var t1 := TAU * (i + 1) / sectors
		var p := [_polar(t0, a[0].call(t0), y), _polar(t1, a[0].call(t1), y), _polar(t1, c[0].call(t1), y), _polar(t0, c[0].call(t0), y)]
		b.add_triangle([p[0], p[1], p[2]], [a[1], a[1], c[1]])
		b.add_triangle([p[0], p[2], p[3]], [a[1], c[1], c[1]])


static func _polar(theta: float, r: float, y: float) -> Vector3:
	return Vector3(r * cos(theta), y, r * sin(theta))


## A wave stroke: a short white arc on the sea, thick in the middle.
func _wave(b: ArtMeshBuilder, theta: float, radius: float, length: float) -> void:
	var steps := 6
	var span := length / radius
	var white := [ArtPalette.FOAM, ArtPalette.FOAM, ArtPalette.FOAM]
	for k in steps:
		var u0 := float(k) / steps
		var u1 := float(k + 1) / steps
		var w0 := 0.16 * sin(PI * u0) + 0.02
		var w1 := 0.16 * sin(PI * u1) + 0.02
		var t0 := theta + span * (u0 - 0.5)
		var t1 := theta + span * (u1 - 0.5)
		var y := SEA_Y + 0.02
		var q := [_polar(t0, radius - w0, y), _polar(t1, radius - w1, y), _polar(t1, radius + w1, y), _polar(t0, radius + w0, y)]
		b.add_triangle([q[0], q[1], q[2]], white)
		b.add_triangle([q[0], q[2], q[3]], white)


## A flat polygon (a fan around `center`) lifted `lift` above the ground under each point.
func _add_flat(b: ArtMeshBuilder, center: Vector2, outline: Array, lift: float, color: Color) -> void:
	var c := Vector3(center.x, height_at(center.x, center.y) + lift, center.y)
	var colors := [color, color, color]
	for i in outline.size():
		var p0: Vector2 = outline[i]
		var p1: Vector2 = outline[(i + 1) % outline.size()]
		b.add_triangle([c, Vector3(p0.x, height_at(p0.x, p0.y) + lift, p0.y), Vector3(p1.x, height_at(p1.x, p1.y) + lift, p1.y)], colors)


## A ring between two outlines of the same point count.
func _add_flat_ring(b: ArtMeshBuilder, inner: Array, outer: Array, lift: float, color: Color) -> void:
	var colors := [color, color, color]
	for i in inner.size():
		var k := (i + 1) % inner.size()
		var p := [inner[i], inner[k], outer[k], outer[i]]
		var q: Array = []
		for v in p:
			q.append(Vector3(v.x, height_at(v.x, v.y) + lift, v.y))
		b.add_triangle([q[0], q[1], q[2]], colors)
		b.add_triangle([q[0], q[2], q[3]], colors)


## The play yard: a rounded sand rectangle with a low white picket fence, open towards the path.
func _add_yard(b: ArtMeshBuilder, spec: Dictionary) -> void:
	var center := _v2(spec.at)
	var outline := yard_outline(spec, 0.0)
	_add_flat(b, center, outline, OVERLAY_LIFT, ArtPalette.YARD_SAND)
	var ring := yard_outline(spec, 0.15)
	ring.append(ring[0])
	var fence := _resample(PackedVector2Array(ring), 0.9)   # a post about every 0.9 m
	var gate := center + Vector2(0.0, float(spec.size[1]) * 0.5)   # the side facing the square
	b.ao_min = 0.85
	b.ao_height = 0.3
	for k in fence.size() - 1:
		var p := fence[k]
		var next := fence[k + 1]
		if p.distance_to(gate) < 1.0:
			continue
		b.add_rounded_box(Transform3D(Basis(), Vector3(p.x, height_at(p.x, p.y) + 0.22, p.y)), Vector3(0.11, 0.44, 0.11), 0.0, 0, ArtPalette.WHITE)
		if next.distance_to(gate) >= 1.0 and p.distance_to(next) > 0.05:
			for h in [0.18, 0.34]:
				_rail(b, p, next, h)


func _rail(b: ArtMeshBuilder, from: Vector2, to: Vector2, h: float) -> void:
	var a := Vector3(from.x, height_at(from.x, from.y) + h, from.y)
	var c := Vector3(to.x, height_at(to.x, to.y) + h, to.y)
	var d := c - a
	var x := d.normalized()
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	b.add_rounded_box(Transform3D(basis, (a + c) * 0.5), Vector3(d.length() + 0.04, 0.06, 0.05), 0.0, 0, ArtPalette.WHITE)


## The yard's rounded rectangle, inset by `inset` m, as points (counter-clockwise in x/z).
static func yard_outline(spec: Dictionary, inset: float) -> Array:
	var center := _v2(spec.at)
	var half := Vector2(float(spec.size[0]), float(spec.size[1])) * 0.5 - Vector2.ONE * inset
	var corner := 1.0 - inset
	var inner := half - Vector2.ONE * corner
	var out: Array = []
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for ci in 4:
		for s in 7:
			var a := PI * 0.5 * ci + PI * 0.5 * s / 6.0
			out.append(center + corners[ci] * inner + Vector2(cos(a), sin(a)) * corner)
	return out


func _pond_radius(spec: Dictionary, theta: float) -> float:
	return float(spec.radius) * (1.0 + 0.07 * sin(3.0 * theta + 0.5) + 0.04 * sin(5.0 * theta))


## The pond: a sand shore ring, the water (in the water mesh), lily pads and stones on its edge.
func _add_pond(land: ArtMeshBuilder, water: ArtMeshBuilder, spec: Dictionary) -> void:
	var center := _v2(spec.at)
	var edge: Array = []
	var shore: Array = []
	var sides := 22
	for i in sides:
		var t := TAU * i / sides
		var r := _pond_radius(spec, t)
		edge.append(center + Vector2(cos(t), sin(t)) * (r - 0.05))
		shore.append(center + Vector2(cos(t), sin(t)) * (r + 0.45))
	_add_flat_ring(land, edge, shore, OVERLAY_LIFT, ArtPalette.SAND)
	var deep: Array = []
	for p in edge:
		deep.append(center + (p - center) * 0.55)
	_add_flat(water, center, deep, 0.06, ArtPalette.WATER)   # a ring round the deep middle: no layer on another
	_add_flat_ring(water, deep, edge, 0.06, ArtPalette.POND)
	land.ao_min = 1.0
	for pad in [[-0.9, 0.7, 0.32], [0.2, 1.1, 0.25], [0.95, -0.6, 0.28]]:
		var at := center + Vector2(pad[0], pad[1])
		land.add_cylinder(Transform3D(Basis(Vector3.UP, pad[0]), Vector3(at.x, 0.08, at.y)), pad[2], pad[2], 0.02, 7, ArtPalette.LEAF_LIGHT)
	land.ao_min = 0.75
	land.ao_height = 0.3
	for k in 6:
		var t := TAU * (k + 0.3) / 6.0 + 0.4
		var at: Vector2 = center + Vector2(cos(t), sin(t)) * (_pond_radius(spec, t) + 0.35)
		if _near_spot_line(at):
			continue
		var r := 0.16 + 0.06 * (k % 3)
		land.add_sphere(Transform3D(Basis().scaled(Vector3(1.3, 0.7, 1.0)), Vector3(at.x, OVERLAY_LIFT + r * 0.3, at.y)), r, 3, 6, ArtPalette.ROCK)


## True when (at) is by the dock: the line from a stageless spot (the buoyancy drum) to where
## the cat waits ashore.
func _near_spot_line(at: Vector2) -> bool:
	for id in spot_info:
		var info: Dictionary = spot_info[id]
		if info.radius == 0.0:
			var a := Vector2(info.at.x, info.at.z)
			var c := Vector2(info.stand.x, info.stand.z)
			if at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, c)) < 0.8:
				return true
	return false


## The dirt paths: each polyline smoothed (Chaikin), sampled every 0.35 m and laid as a ribbon on
## the ground, with round ends.
func _add_paths(b: ArtMeshBuilder) -> void:
	path_points = PackedVector2Array()
	var colors := [ArtPalette.PATH, ArtPalette.PATH, ArtPalette.PATH]
	for line in paths:
		var points := _smooth(line)
		var samples := _resample(points, 0.35)
		for p in samples:
			path_points.append(p)
		var left: Array = []
		var right: Array = []
		for k in samples.size():
			var t: Vector2 = (samples[mini(k + 1, samples.size() - 1)] - samples[maxi(k - 1, 0)]).normalized()
			var n := Vector2(-t.y, t.x) * PATH_WIDTH * 0.5
			var l: Vector2 = samples[k] + n
			var r: Vector2 = samples[k] - n
			left.append(Vector3(l.x, height_at(l.x, l.y) + PATH_LIFT, l.y))
			right.append(Vector3(r.x, height_at(r.x, r.y) + PATH_LIFT, r.y))
		for k in samples.size() - 1:
			b.add_triangle([left[k], left[k + 1], right[k + 1]], colors)
			b.add_triangle([left[k], right[k + 1], right[k]], colors)
		for end in [samples[0], samples[samples.size() - 1]]:
			var disc: Array = []
			for s in 10:
				disc.append(end + Vector2(cos(TAU * s / 10.0), sin(TAU * s / 10.0)) * PATH_WIDTH * 0.5)
			_add_flat(b, end, disc, PATH_LIFT, ArtPalette.PATH)


static func _smooth(line: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in line:
		points.append(_v2(p))
	for pass_i in 2:
		var out := PackedVector2Array()
		out.append(points[0])
		for k in points.size() - 1:
			out.append(points[k].lerp(points[k + 1], 0.25))
			out.append(points[k].lerp(points[k + 1], 0.75))
		out.append(points[points.size() - 1])
		points = out
	return points


static func _resample(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(points[0])
	for k in points.size() - 1:
		var a := points[k]
		var c := points[k + 1]
		var n := maxi(1, int(ceil(a.distance_to(c) / step)))
		for s in range(1, n + 1):
			out.append(a.lerp(c, float(s) / n))
	return out


## The cat's home square where the paths meet, with a signpost.
func _add_plaza(b: ArtMeshBuilder) -> void:
	var inner: Array = []
	var outer: Array = []
	for s in 16:
		var d := Vector2(cos(TAU * s / 16.0), sin(TAU * s / 16.0))
		inner.append(home + d * PLAZA_RADIUS)
		outer.append(home + d * (PLAZA_RADIUS + 0.18))
	_add_flat(b, home, inner, PLAZA_LIFT, ArtPalette.PLAZA)
	_add_flat_ring(b, inner, outer, PLAZA_LIFT, ArtPalette.ROCK)
	var post := home + Vector2(-1.05, -0.75)
	var y := height_at(post.x, post.y) + PLAZA_LIFT
	b.ao_min = 0.8
	b.ao_height = 0.4
	b.add_cylinder(Transform3D(Basis(), Vector3(post.x, y, post.y)), 0.06, 0.06, 1.2, 6, ArtPalette.TRUNK)
	for board in [[0.95, 25.0, ArtPalette.CRATE_TOP], [0.7, -30.0, ArtPalette.CRATE], [0.45, 70.0, ArtPalette.CRATE_TOP]]:
		var basis := Basis(Vector3.UP, deg_to_rad(board[1]))
		b.add_rounded_box(Transform3D(basis, Vector3(post.x, y + board[0], post.y) + basis * Vector3(0.22, 0.0, 0.0)),
			Vector3(0.5, 0.16, 0.05), 0.0, 0, board[2])


## A spot: its round stage (levelled over the ground under it) and its landmark on top.
func _add_spot(b: ArtMeshBuilder, spot: Array) -> void:
	var id: String = spot[0]
	var at: Vector2 = spot[1]
	var yaw := deg_to_rad(float(spot[2]))
	var radius := MapLandmarks.stage_radius(id)
	var low := height_at(at.x, at.y)
	var high := low
	for s in 8:
		var p := at + Vector2(cos(TAU * s / 8.0), sin(TAU * s / 8.0)) * maxf(radius, 0.4)
		var h := height_at(p.x, p.y)
		low = minf(low, h)
		high = maxf(high, h)
	var y := height_at(at.x, at.y) + (OVERLAY_LIFT if radius > 0.0 else 0.06)   # stageless: the pond's water
	var before := b.vertex_count()
	if radius > 0.0:
		y = high + 0.06
		b.ao_min = 0.8
		b.ao_height = 0.25
		b.add_cylinder(Transform3D(Basis(), Vector3(at.x, low - 0.15, at.y)), radius + 0.06, radius, y - low + 0.15, 14, ArtPalette.ROCK, true, ArtPalette.PLATE)
	var top := MapLandmarks.add(b, id, Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.y)))
	var to_home := (home - at).normalized() if home.distance_to(at) > 0.01 else Vector2(0.0, 1.0)
	var stand := at + to_home * (radius + 0.4 if radius > 0.0 else 2.0)   # stageless: ashore, past the dock
	var side := Vector2(-to_home.y, to_home.x)
	var flag := at + (side * 0.75 - to_home * 0.35).normalized() * maxf(radius - 0.1, 0.5)
	spot_info[id] = {
		"at": Vector3(at.x, y, at.y),
		"top": top,
		"radius": radius,
		"stand": Vector3(stand.x, walk_height(stand.x, stand.y), stand.y),
		"flag": Vector3(flag.x, y, flag.y),
		"vertices": b.vertex_count() - before,
	}


## Trees, rocks and flowers: each placed only where nothing else is (clear()); the flowers seeded
## in the meadow and over the rest of the grass.
func _add_decor(b: ArtMeshBuilder) -> void:
	decorations.clear()
	for t in TREES:
		var x: float = t[0]
		var z: float = t[1]
		var k: float = t[2]
		if not clear(x, z, 1.0 * k):
			continue
		var y := height_at(x, z)
		b.ao_min = 0.8
		b.ao_height = 0.4 * k
		b.add_cylinder(_at(x, y, z), 0.2 * k, 0.16 * k, 0.8 * k, 6, ArtPalette.TRUNK)
		b.ao_min = 0.85
		b.add_cylinder(_at(x, y + 0.7 * k, z, 15.0), 1.1 * k, 0.0, 1.5 * k, 7, ArtPalette.LEAF)
		b.add_cylinder(_at(x, y + 1.5 * k, z, 40.0), 0.8 * k, 0.0, 1.2 * k, 7, ArtPalette.LEAF_LIGHT)
		_ground_blob(b, Vector3(x, y, z), 1.3 * k)
		decorations.append(["tree", x, z, 1.0 * k])
	b.ao_min = 0.75
	b.ao_height = 0.3
	for r in ROCKS:
		var x: float = r[0]
		var z: float = r[1]
		var radius: float = r[2]
		if not clear(x, z, radius * 1.3):
			continue
		var y := height_at(x, z)
		b.add_sphere(Transform3D(Basis().scaled(Vector3(1.3, 0.75, 1.0)), Vector3(x, y + radius * 0.5, z)), radius, 4, 6, ArtPalette.ROCK)
		_ground_blob(b, Vector3(x, y, z), radius * 1.8)
		decorations.append(["rock", x, z, radius * 1.3])
	var rng := RandomNumberGenerator.new()
	rng.seed = FLOWER_SEED
	var placed := 0
	b.ao_min = 1.0
	for zone in zones:
		var spec: Dictionary = zones[zone]
		if spec.ground != "meadow":
			continue
		var meadow_tries := 0
		while placed < MEADOW_FLOWERS and meadow_tries < 400:
			meadow_tries += 1
			var p := _v2(spec.at) + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * float(spec.radius)
			if clear(p.x, p.y, 0.2):
				_flower(b, p, placed)
				placed += 1
	var tries := 0
	while placed < MEADOW_FLOWERS + OTHER_FLOWERS and tries < 600:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 11.0
		if coast_fraction(p.x, p.y) < 0.78 and clear(p.x, p.y, 0.2):
			_flower(b, p, placed)
			placed += 1


## A blob shadow on the grass without blending: ArtKit's blob (full SHADOW_ALPHA inside 35 % of the
## radius, fading out) as an opaque gradient from the shadowed grass to the grass colour itself.
## The ground under a tree or rock is known grass, so it looks the same, and the map has no
## alpha-blended layer over the island (fill on SM-P200, 2026-10-27).
func _ground_blob(b: ArtMeshBuilder, at: Vector3, radius: float) -> void:
	var ground := ArtPalette.GRASS_TOP.lightened(0.025)
	for zone in zones:
		var spec: Dictionary = zones[zone]
		if spec.ground == "meadow" and Vector2(at.x, at.z).distance_to(_v2(spec.at)) < float(spec.radius):
			ground = ArtPalette.MEADOW.lightened(0.025)
	var dark := ground.lerp(ArtPalette.SHADOW, ArtKit.shadow_alpha())
	var c := at + Vector3(0.0, 0.012, 0.0)
	var sides := 12
	for i in sides:
		var d0 := Vector3(cos(TAU * i / sides), 0.0, sin(TAU * i / sides))
		var d1 := Vector3(cos(TAU * (i + 1) / sides), 0.0, sin(TAU * (i + 1) / sides))
		var i0 := c + d0 * radius * 0.35
		var i1 := c + d1 * radius * 0.35
		var o0 := c + d0 * radius
		var o1 := c + d1 * radius
		o0.y = height_at(o0.x, o0.z) + 0.012
		o1.y = height_at(o1.x, o1.z) + 0.012
		b.add_triangle([c, i0, i1], [dark, dark, dark])
		b.add_triangle([i0, o0, o1], [dark, ground, ground])
		b.add_triangle([i0, o1, i1], [dark, ground, dark])


func _flower(b: ArtMeshBuilder, p: Vector2, i: int) -> void:
	var y := height_at(p.x, p.y)
	# Seen from 27 m a flower is a dot: a 3-sided stem and a diamond head (a tenth of the lab's).
	b.add_cylinder(_at(p.x, y, p.y), 0.035, 0.035, 0.3, 3, ArtPalette.STEM, false)
	b.add_sphere(_at(p.x, y + 0.34, p.y), 0.14, 2, 4, ArtPalette.FLOWERS[i % ArtPalette.FLOWERS.size()])
	decorations.append(["flower", p.x, p.y, 0.2])


## True when a thing of footprint `radius` at (x, z) stands on open grass: inside the grass edge,
## off the paths, the square, the yard, the pond and its shore, clear of every spot's stage and of
## the decorations already placed.
func clear(x: float, z: float, radius: float) -> bool:
	var p := Vector2(x, z)
	if p.length() + radius * 0.6 > grass_edge() * coast_radius(atan2(z, x)):   # crowns may lean over the sand
		return false
	if p.distance_to(home) < PLAZA_RADIUS + 0.3 + radius:
		return false
	for q in path_points:
		if p.distance_to(q) < PATH_WIDTH * 0.5 + 0.15 + radius:
			return false
	for id in spot_info:
		var info: Dictionary = spot_info[id]
		var at := Vector2(info.at.x, info.at.z)
		if p.distance_to(at) < maxf(info.radius, 1.0) + 0.5 + radius:
			return false
	for zone in zones:
		var spec: Dictionary = zones[zone]
		var c := _v2(spec.at)
		match spec.ground:
			"pond":
				if p.distance_to(c) < float(spec.radius) * 1.15 + 0.6 + radius:
					return false
			"yard":
				var half := Vector2(float(spec.size[0]), float(spec.size[1])) * 0.5 + Vector2.ONE * (0.3 + radius)
				if absf(x - c.x) < half.x and absf(z - c.y) < half.y:
					return false
	for d in decorations:
		if p.distance_to(Vector2(d[1], d[2])) < d[3] + radius:
			return false
	return true


## A few clouds far around the island (the low views see them; the top view does not).
func _add_clouds(b: ArtMeshBuilder) -> void:
	b.ao_min = 0.85
	b.ao_height = 0.6
	for c in CLOUDS:
		var k: float = c[3]
		for puff in [[0.0, 0.0, 1.0], [1.1, -0.2, 0.75], [-1.1, -0.25, 0.7], [0.4, 0.5, 0.65]]:
			b.add_sphere(_at(c[0] + puff[0] * k, c[1] + puff[1] * k, c[2]), puff[2] * k, 3, 6, ArtPalette.CLOUD)


static func _at(x: float, y: float, z: float, yaw_deg := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(x, y, z))
