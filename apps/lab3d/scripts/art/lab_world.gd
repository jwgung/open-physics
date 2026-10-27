## The ground every lab stands on (2026-10-27 user decision: like a corner of the big island): a close-up
## corner of the home map's island (MapIsland), not a floating island of its own. The lab's centre
## is its spot on the map (MapIsland.ZONES), the map is K times larger around it and turned
## so the lab's front view (-z) looks inland (towards the cat's square; the lookout along the
## north coast, FACING). Seen from the lab:
## - a flat clearing of radius CLEAR at y = 0 in the zone's ground (the meadow's lighter grass,
##   the hill's grass, the play yard's sand inside its white picket fence, the pond's grass with
##   the pond just behind the apparatus, the lookout's railing over the sea), where
##   the apparatus, the cast and the old decoration (ArtKit.TREES / ROCKS / FLOWERS) stand;
## - beyond it the map's land: its hills (the hill labs stand on top, the far ground falls away),
##   zone ground, the pond, the yard fence, the other zones' landmarks (MapLandmarks, LANDMARK_SCALE)
##   on their stages, trees and rocks, down to the beach and the sea at the map's coast (never
##   nearer than COAST_MIN);
## - the sea to the horizon (shallows, surf, deep sea fading into haze), a haze band at the horizon
##   rising into the sky colour (the clear colour, ArtKit.make_environment) and clouds.
## A physics edge gets the coast: `edge_x` (the projectile's "섬 밖으로 날아감" box) puts the shore
## there, the flat sand ending at x = edge_x and dropping into the sea.
##
## Draw calls: ONE opaque mesh in MapIsland's material (map_lit.gdshader: the island light per
## vertex, no texture, no blending; the trees' blob shadows baked as opaque gradients) instead of
## the old island's two (lit prop mesh + alpha shadows); the lab's own static blob shadows keep the
## alpha shadow mesh (IslandShadows). The sea and the haze cover only what the old sky did below
## the horizon; the sky is still the clear colour.
## Visual only: no collision; the labs' floors, fences and bounds are their own (unchanged).
class_name LabWorld
extends RefCounted

const K := 5.0                       # lab metres per map metre (where things are)
const HILL_SCALE := 3.0              # lab metres per map metre of hill height
const LANDMARK_SCALE := 3.0          # the other zones' landmarks, map size x this
const BEHIND_DEG := 125.0            # no landmark farther round from the front view (never seen)
const TREE_SCALE := 1.5              # the map's trees in the far ground, size x this
const CLEAR := ArtKit.ISLAND_RADIUS + 1.5   # flat ground (y = 0) around the lab centre
const BLEND := 6.0                   # m over which the far ground leaves y = 0
const COAST_MIN := CLEAR + 7.0       # the coast is never nearer than this (but at edge_x)
const BEACH := 5.0                   # m of sand from the grass to the sea floor
const SHORE_W := 0.8                 # m from the last sand ring above the sea to the sea floor
const SEA_DROP := -0.6               # the sea below the beach top
## The camera's reach (the labs' farthest view, 30 m, plus their pan, 7 m) and the ground's ceiling
## within it: the lowest views (pitch -2 deg) look from about 1.5 m + 3.5 % of the distance.
const CAMERA_REACH := 37.0
const CAMERA_FLOOR := 0.5
const CAMERA_SLOPE := 0.03
const SECTORS := 48
const LAND_U := [0.12, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]   # far ground rings between CLEAR and the beach
const INNER := [0.0, 4.5, 8.5]
const GRASS_EDGE := 10               # ring index where the sand starts (INNER + CLEAR + LAND_U)
const JITTER := 0.3
const SEA_FAR := 400.0
const HAZE_TOP := 30.0               # m above the sea where the haze band meets the sky colour
const HAZE_BOTTOM := -60.0           # below the sea: rays just under the horizon hit it
const POND_SCALE := 0.9              # the pond's radius in the lab, map radius x K x this
## The pond lab's own pond: just beyond the clearing in this direction (lab x, z: ahead, a little
## left), behind the tank in the front view (the map has the drum in the pond, the lab on its shore).
const OWN_POND_DIR := Vector2(-0.3, -1.0)
const REEDS := 7                     # reed clumps on a pond's near shore
const FENCE_STEP := 4.0              # m between the yard fence's posts
const FENCE_HEIGHT := 0.9
const FENCE_CLEAR := CLEAR + 1.5     # the own yard's fence never comes nearer
const RAILING_STEP := 2.0            # m between the lookout railing's posts
const RAILING_COAST := COAST_MIN + 6.0
## The zones' look in the lab (MapIsland.ZONES names).
const THEMES := {"들판": "meadow", "언덕": "hill", "놀이터": "yard", "연못": "pond", "전망대": "lookout"}
## Where a lab looks (map angle of its -z, deg, atan2(z, x)) when not towards the square: the
## lookout along the north coast (the sea on its right, the island on its left).
const FACING := {"orbit": -135.0}
## Clouds in the lab's sky [angle from the front view deg, distance, height above the sea, size]:
## over the far land and sea within the camera's turn (+-100 deg) and a few far ones.
const CLOUDS := [[-38.0, 75.0, 15.0, 4.5], [-4.0, 95.0, 19.0, 5.5], [30.0, 80.0, 14.0, 4.2], [62.0, 70.0, 17.0, 4.0],
	[-75.0, 85.0, 13.0, 4.0], [-110.0, 160.0, 26.0, 7.0], [105.0, 170.0, 28.0, 7.0], [15.0, 190.0, 34.0, 8.0]]

var id := ""
var zone := ""
var theme := "meadow"
var spot := Vector2.ZERO             # map x, z of the lab centre
var center := Vector3.ZERO
var edge_x := INF
var facing := 0.0                    # rad, map angle of the lab's front
var sea_y := SEA_DROP
var map: MapIsland
var _c := Vector2.ZERO
var _f := Vector2(0.0, -1.0)         # map direction of the lab's -z
var _r := Vector2(1.0, 0.0)          # map direction of the lab's +x
var _h0 := 0.0
var _coast := PackedFloat32Array()   # coast distance (lab m) from the centre per sector
var _fence := PackedVector2Array()   # the own yard's fence outline (lab x, z), yard labs
var _ponds: Array = []               # [lab centre Vector2, lab radius, map spec]
var _yards: Array = []               # map specs of the yards (their fences are drawn)
## Built pieces, for tests: [kind, lab x, z, radius] of the far landmarks and trees.
var far_things: Array = []


## The world of lab `lab_id` around `lab_center`; an unknown id stands in the meadow.
func _init(lab_id: String, lab_center: Vector3, physics_edge_x := INF) -> void:
	id = lab_id
	center = lab_center
	_c = Vector2(center.x, center.z)
	edge_x = physics_edge_x
	var zones: Dictionary = MapIsland.ZONES
	zone = "들판"
	spot = _v2(zones[zone].at)
	for name in zones:
		for s in zones[name].spots:
			if s[0] == lab_id:
				zone = name
				spot = _v2(s[1])
	theme = THEMES.get(zone, "meadow")
	var home := _v2(MapIsland.HOME)
	facing = deg_to_rad(FACING[lab_id]) if FACING.has(lab_id) else (home - spot).angle()
	_f = Vector2.from_angle(facing)
	_r = Vector2(-_f.y, _f.x)
	map = MapIsland.new(zones, MapIsland.PATHS, home)
	_h0 = map.hill_height(spot.x, spot.y) * HILL_SCALE
	sea_y = -_h0 + SEA_DROP
	for i in SECTORS:
		_coast.append(_coast_from_map(TAU * i / SECTORS))
	for name in zones:
		var spec: Dictionary = zones[name]
		match spec.ground:
			"pond":
				var radius := float(spec.radius) * K * POND_SCALE
				var at := to_lab(_v2(spec.at))
				if name == zone:   # the pond lab: on its shore, the pond behind the tank
					at = _c + OWN_POND_DIR.normalized() * (CLEAR + radius + 1.0)
				_ponds.append([at, radius, spec])
			"yard":
				_yards.append(spec)
	if theme == "yard":
		for p in MapIsland.yard_outline(zones[zone], 0.15):
			var q := to_lab(p)
			if q.distance_to(_c) < FENCE_CLEAR:
				q = _c + (q - _c).normalized() * FENCE_CLEAR
			_fence.append(q)


static func _v2(at: Array) -> Vector2:
	return Vector2(float(at[0]), float(at[1]))


# --- the mapping ------------------------------------------------------------------------------

## Map x, z of lab x, z.
func to_map(l: Vector2) -> Vector2:
	var o := l - _c
	return spot + (_r * o.x - _f * o.y) / K


## Lab x, z of map x, z.
func to_lab(m: Vector2) -> Vector2:
	var o := (m - spot) * K
	return _c + Vector2(o.dot(_r), -o.dot(_f))


## Map directions as lab directions (y up).
func lab_basis() -> Basis:
	return Basis(Vector3(_r.x, 0.0, -_f.x), Vector3.UP, Vector3(_r.y, 0.0, -_f.y))


## The coast's distance (lab m) from the centre along lab angle `theta` (atan2(z, x) in the lab):
## the map's coast, at least COAST_MIN, and the shore at edge_x on that side.
func coast_at(theta: float) -> float:
	var u := fposmod(theta, TAU) / TAU * SECTORS
	var i := int(floor(u)) % SECTORS
	return lerpf(_coast[i], _coast[(i + 1) % SECTORS], u - floor(u))


func _coast_from_map(theta: float) -> float:
	var dir := Vector2.from_angle(theta)
	var m_dir := (_r * dir.x - _f * dir.y)
	var lo := 0.0
	var hi := 40.0
	for k in 22:
		var mid := (lo + hi) * 0.5
		var p := spot + m_dir * mid
		if MapIsland.coast_fraction(p.x, p.y) < 1.0:
			lo = mid
		else:
			hi = mid
	var r := maxf(lo * K, COAST_MIN)
	if is_finite(edge_x) and dir.x > 0.0:
		r = minf(r, (edge_x - _c.x) / dir.x + SHORE_W)
	return r


## Ground height before the clearing flattens it (lab x, z).
func _land_h(l: Vector2) -> float:
	var m := to_map(l)
	return map.hill_height(m.x, m.y) * HILL_SCALE - _h0


## The ground's height at lab (x, z) (the smooth surface the faces approximate; the clearing is 0).
func ground_y(l: Vector2) -> float:
	var s := l.distance_to(_c)
	var theta := (l - _c).angle()
	var radii := _ring_radii(coast_at(theta))
	var j := 0
	while j < radii.size() - 2 and radii[j + 1] <= s:
		j += 1
	if s >= radii[-1]:
		return sea_y + SEA_DROP
	var t := inverse_lerp(radii[j], radii[j + 1], s) if radii[j + 1] > radii[j] else 1.0
	var dir := Vector2.from_angle(theta)
	return lerpf(_vertex_y(j, radii[j], _c + dir * radii[j]), _vertex_y(j + 1, radii[j + 1], _c + dir * radii[j + 1]), t)


func _ring_radii(coast: float) -> Array:
	var land_end := coast - BEACH
	var c0 := minf(CLEAR, land_end)
	var radii: Array = INNER.duplicate()
	radii.append(c0)
	for u in LAND_U:
		radii.append(lerpf(c0, land_end, u))
	radii.append(coast - BEACH * 0.45)
	radii.append(coast - SHORE_W)
	radii.append(coast)
	for i in range(radii.size() - 2, -1, -1):
		radii[i] = minf(radii[i], radii[i + 1])
	return radii


## Height of ring `j`'s vertex at distance `s`, lab point `l`: the land, the beach down to the
## wet sand just above the sea, the sea floor; flat (0) in the clearing except the sea floor, and
## all flat to the sea floor where edge_x holds the coast (the sand ends at x = edge_x). Within the
## camera's reach the ground stays under the lowest camera (CAMERA_FLOOR + CAMERA_SLOPE per metre:
## never inside a hill), rising freely beyond it.
func _vertex_y(j: int, s: float, l: Vector2) -> float:
	var y: float
	if j <= GRASS_EDGE:
		y = _land_h(l)
	elif j == GRASS_EDGE + 1:
		y = lerpf(_land_h(l), sea_y + 0.05, 0.5)
	elif j == GRASS_EDGE + 2:
		y = sea_y + 0.05
	else:
		return sea_y + SEA_DROP
	if _edge_held((l - _c).angle()):
		return 0.0
	y *= smoothstep(CLEAR, CLEAR + BLEND, s)
	return minf(y, CAMERA_FLOOR + CAMERA_SLOPE * s + 0.6 * maxf(s - CAMERA_REACH, 0.0))


## True when edge_x holds the coast in lab direction `theta` (the coast is the edge's shore there).
func _edge_held(theta: float) -> bool:
	var dir := Vector2.from_angle(theta)
	return is_finite(edge_x) and dir.x > 0.0 and coast_at(theta) <= (edge_x - _c.x) / dir.x + SHORE_W + 1e-3


# --- colours ----------------------------------------------------------------------------------

## The zone's ground colour at lab (x, z), `s` from the centre (no facet shading).
func ground_color(l: Vector2, s := -1.0) -> Color:
	if s < 0.0:
		s = l.distance_to(_c)
	if theme == "yard" and (s < CLEAR or Geometry2D.is_point_in_polygon(l, _fence)):
		return ArtPalette.YARD_SAND
	if s < CLEAR:
		return ArtPalette.MEADOW if theme == "meadow" else ArtPalette.GRASS_TOP
	var m := to_map(l)
	for name in map.zones:
		var spec: Dictionary = map.zones[name]
		match spec.ground:
			"meadow":
				if m.distance_to(_v2(spec.at)) < float(spec.radius):
					return ArtPalette.MEADOW
			"yard":
				var c := _v2(spec.at)
				if absf(m.x - c.x) < float(spec.size[0]) * 0.5 and absf(m.y - c.y) < float(spec.size[1]) * 0.5:
					return ArtPalette.YARD_SAND
	return ArtPalette.GRASS_TOP


## A face's colour: the ground (sand from the grass edge out), darker as it turns from the sun
## (MapIsland's facets), earth on the steep slopes, a little jitter per face.
func _face_color(j: int, i: int, k: int, tri: Array) -> Color:
	var c: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
	var l := Vector2(c.x, c.z)
	var color := ArtPalette.SAND if j >= GRASS_EDGE else ground_color(l)
	var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
	if n.y < 0.0:
		n = -n
	if n.y < 0.6 and j < GRASS_EDGE:
		color = color.lerp(ArtPalette.SOIL, clampf((0.6 - n.y) * 4.0, 0.0, 1.0))
	var sun := n.dot(ArtKit.SUN_DIR.normalized())
	color = color.darkened(clampf((0.83 - sun) * 0.8, 0.0, 0.25)) if sun < 0.83 else color.lightened(clampf((sun - 0.83) * 1.5, 0.0, 0.2))
	return color.lightened(0.05 * (MapIsland._hash(i, j, 3 + k) * 0.5 + 0.5))


## An up-facing face's vertex colour that shows as `target` (map_lit adds the sky fill on top).
static func _under_fill(target: Color) -> Color:
	var lin := target.srgb_to_linear()
	var k := 1.0 / (1.0 + ArtKit.SKY_FILL)
	return Color(lin.r * k, lin.g * k, lin.b * k).linear_to_srgb()


# --- building ---------------------------------------------------------------------------------

## Builds the world under `parent`: "Island" (one mesh, MapIsland's material) and, when
## `extra_shadows` adds any, "IslandShadows" (the lab's own alpha blob shadows).
func build(parent: Node3D, extra_shadows: Callable = Callable()) -> void:
	var b := ArtKit.builder()
	# What stands on the ground first, the ground, then the sea and the haze: the covered ground and
	# sea fail the depth test before they are shaded (MapIsland.build).
	_add_near_decor(b)
	_add_landmarks(b)
	_add_far_trees(b)
	_add_fences(b)
	_add_railing(b)
	_add_clouds(b)
	_add_ponds(b)
	_add_ground(b)
	_add_sea(b)
	_add_haze(b)
	var island := ArtKit.instance(b.commit(), MapIsland.material())
	island.name = "Island"
	island.set_meta("center", center)   # tests: where the cast may stand (ArtKit.island_obstacles)
	island.set_meta("world", self)
	parent.add_child(island)
	if extra_shadows.is_valid():
		var s := ArtKit.shadow_builder()
		extra_shadows.call(s)
		if not s.is_empty():
			var shadows := ArtKit.instance(s.commit(), ArtKit.shadow_material())
			shadows.name = "IslandShadows"
			parent.add_child(shadows)


## The lab's own trees, rocks and flowers (ArtKit.TREES / ROCKS / FLOWERS around the centre, as on
## the old island: ArtKit.island_obstacles keeps the cast clear of them); flowers not in the sand yard.
func _add_near_decor(b: ArtMeshBuilder) -> void:
	for t in ArtKit.TREES:
		_tree(b, Vector2(_c.x + t[0], _c.y + t[1]), t[2])
	b.ao_min = 0.75
	b.ao_height = 0.3
	for r in ArtKit.ROCKS:
		_rock(b, Vector2(_c.x + r[0], _c.y + r[1]), r[2])
	if theme == "yard":
		return
	b.ao_min = 1.0
	for i in ArtKit.FLOWERS.size():
		var f: Array = ArtKit.FLOWERS[i]
		var x: float = _c.x + f[0]
		var z: float = _c.y + f[1]
		b.add_cylinder(_at(x, 0.0, z), 0.03, 0.03, 0.3, 4, ArtPalette.STEM, false)
		b.add_sphere(_at(x, 0.34, z), 0.13, 3, 5, ArtPalette.FLOWERS[i % ArtPalette.FLOWERS.size()])


func _tree(b: ArtMeshBuilder, at: Vector2, k: float, blob := true) -> void:
	var y := ground_y(at)
	b.ao_min = 0.8
	b.ao_height = 0.4 * k
	b.add_cylinder(_at(at.x, y, at.y), 0.2 * k, 0.16 * k, 0.8 * k, 6, ArtPalette.TRUNK)
	b.ao_min = 0.85
	b.add_cylinder(_at(at.x, y + 0.7 * k, at.y, 15.0), 1.1 * k, 0.0, 1.5 * k, 7, ArtPalette.LEAF)
	b.add_cylinder(_at(at.x, y + 1.5 * k, at.y, 40.0), 0.8 * k, 0.0, 1.2 * k, 7, ArtPalette.LEAF_LIGHT)
	if blob:
		_ground_blob(b, at, 1.3 * k)


func _rock(b: ArtMeshBuilder, at: Vector2, radius: float) -> void:
	var y := ground_y(at)
	b.add_sphere(Transform3D(Basis().scaled(Vector3(1.3, 0.75, 1.0)), Vector3(at.x, y + radius * 0.5, at.y)), radius, 4, 6, ArtPalette.ROCK)
	_ground_blob(b, at, radius * 1.8)


## ArtKit's blob shadow as an opaque gradient from the shadowed ground to the ground colour
## (MapIsland._ground_blob): no blended layer over the ground.
func _ground_blob(b: ArtMeshBuilder, at: Vector2, radius: float) -> void:
	var ground := ground_color(at).lightened(0.025)
	var dark := ground.lerp(ArtPalette.SHADOW, ArtKit.shadow_alpha())
	var c := Vector3(at.x, ground_y(at) + 0.012, at.y)
	var sides := 12
	for i in sides:
		var d0 := Vector3(cos(TAU * i / sides), 0.0, sin(TAU * i / sides))
		var d1 := Vector3(cos(TAU * (i + 1) / sides), 0.0, sin(TAU * (i + 1) / sides))
		var i0 := c + d0 * radius * 0.35
		var i1 := c + d1 * radius * 0.35
		var o0 := c + d0 * radius
		var o1 := c + d1 * radius
		o0.y = ground_y(Vector2(o0.x, o0.z)) + 0.012
		o1.y = ground_y(Vector2(o1.x, o1.z)) + 0.012
		b.add_triangle([c, i0, i1], [dark, dark, dark])
		b.add_triangle([i0, o0, o1], [dark, ground, ground])
		b.add_triangle([i0, o1, i1], [dark, ground, dark])


## The other zones' landmarks where the map has them, LANDMARK_SCALE x, on their stages (the
## buoyancy drum in its pond); none in the clearing.
func _add_landmarks(b: ArtMeshBuilder) -> void:
	var basis := lab_basis()
	for name in map.zones:
		if name == zone:
			continue
		for s in map.zones[name].spots:
			var at := to_lab(_v2(s[1]))
			var radius := MapLandmarks.stage_radius(s[0]) * LANDMARK_SCALE
			if at.distance_to(_c) < CLEAR + radius + 2.0 or at.distance_to(_c) > coast_at((at - _c).angle()) - BEACH \
					or absf(Vector2(0.0, -1.0).angle_to(at - _c)) > deg_to_rad(BEHIND_DEG):
				continue
			var y := ground_y(at)
			if radius > 0.0:
				var low := y
				var high := y
				for k in 8:
					var p := at + Vector2.from_angle(TAU * k / 8.0) * radius
					low = minf(low, ground_y(p))
					high = maxf(high, ground_y(p))
				y = high + 0.15
				b.ao_min = 0.8
				b.ao_height = 0.6
				b.add_cylinder(Transform3D(Basis(), Vector3(at.x, low - 0.3, at.y)), radius + 0.15, radius, y - low + 0.3, 10, ArtPalette.ROCK, true, ArtPalette.PLATE)
			else:
				y = _pond_y(at) if _in_pond(at) else y
			var xf := Transform3D((basis * Basis(Vector3.UP, deg_to_rad(float(s[2])))).scaled(Vector3.ONE * LANDMARK_SCALE), Vector3(at.x, y, at.y))
			MapLandmarks.add(b, s[0], xf)
			far_things.append(["landmark", at.x, at.y, maxf(radius, 1.5)])


## The map's trees and rocks (TREE_SCALE x) on the far ground: not in the clearing, the yards, the
## ponds, on the sand or by a landmark.
func _add_far_trees(b: ArtMeshBuilder) -> void:
	for t in MapIsland.TREES:
		var at := to_lab(Vector2(t[0], t[1]))
		var k: float = t[2] * TREE_SCALE
		if _far_clear(at, 1.4 * k):
			_tree(b, at, k, false)   # no blob shadow this far off (vertices)
			far_things.append(["tree", at.x, at.y, 1.3 * k])
	b.ao_min = 0.75
	b.ao_height = 0.6
	for r in MapIsland.ROCKS:
		var at := to_lab(Vector2(r[0], r[1]))
		var radius: float = r[2] * TREE_SCALE * 1.5
		if _far_clear(at, radius * 1.5):
			_rock(b, at, radius)
			far_things.append(["rock", at.x, at.y, radius * 1.3])


func _far_clear(at: Vector2, radius: float) -> bool:
	var s := at.distance_to(_c)
	if s < CLEAR + radius + 1.0 or s > coast_at((at - _c).angle()) - BEACH - radius:
		return false
	if _in_pond(at, radius + 2.0) or ground_color(at) == ArtPalette.YARD_SAND:
		return false
	for f in far_things:
		if at.distance_to(Vector2(f[1], f[2])) < f[3] + radius:
			return false
	return true


func _in_pond(at: Vector2, margin := 0.0) -> bool:
	for p in _ponds:
		if at.distance_to(p[0]) < p[1] + margin:
			return true
	return false


func _pond_y(at: Vector2) -> float:
	for p in _ponds:
		if at.distance_to(p[0]) < p[1] + 3.0:
			return ground_y(p[0]) + 0.08
	return ground_y(at)


## The yards' white picket fences (lab size, FENCE_HEIGHT: posts and one board between them),
## open at the gate towards the square: the own yard's pushed out of the clearing (_fence), the
## other yards' where the map has them.
func _add_fences(b: ArtMeshBuilder) -> void:
	for spec in _yards:
		var outline := PackedVector2Array()
		if spec == map.zones[zone]:
			outline = _fence.duplicate()
		else:
			for p in MapIsland.yard_outline(spec, 0.15):
				outline.append(to_lab(p))
		outline.append(outline[0])
		var gate := to_lab(_v2(spec.at) + Vector2(0.0, float(spec.size[1]) * 0.5))
		var posts := MapIsland._resample(outline, FENCE_STEP)
		b.ao_min = 0.85
		b.ao_height = 0.5
		for k in posts.size() - 1:
			var p := posts[k]
			var next := posts[k + 1]
			if p.distance_to(gate) < 3.0 or p.distance_to(next) < 0.05:
				continue
			var y := ground_y(p)
			b.add_rounded_box(Transform3D(Basis(), Vector3(p.x, y + FENCE_HEIGHT * 0.5, p.y)), Vector3(0.18, FENCE_HEIGHT, 0.18), 0.0, 0, ArtPalette.WHITE)
			if next.distance_to(gate) >= 3.0:
				var a := Vector3(p.x, y + FENCE_HEIGHT * 0.6, p.y)
				var c := Vector3(next.x, ground_y(next) + FENCE_HEIGHT * 0.6, next.y)
				var d := c - a
				var x := d.normalized()
				b.add_rounded_box(Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), (a + c) * 0.5), Vector3(d.length(), FENCE_HEIGHT * 0.4, 0.06), 0.0, 0, ArtPalette.WHITE)


## The lookout's railing: white posts and a rail along the clearing's edge where the headland falls
## to the sea (the coast within RAILING_COAST of the centre).
func _add_railing(b: ArtMeshBuilder) -> void:
	if theme != "lookout":
		return
	var r := CLEAR + 0.4
	var steps := int(TAU * r / RAILING_STEP)
	b.ao_min = 0.85
	b.ao_height = 0.5
	for k in steps:
		var t0 := TAU * k / steps
		var t1 := TAU * (k + 1) / steps
		if coast_at(t0) > RAILING_COAST:
			continue
		var p := Vector3(_c.x + r * cos(t0), 0.0, _c.y + r * sin(t0))
		b.add_rounded_box(Transform3D(Basis(), p + Vector3.UP * 0.5), Vector3(0.14, 1.0, 0.14), 0.0, 0, ArtPalette.WHITE)
		if coast_at(t1) <= RAILING_COAST:
			var q := Vector3(_c.x + r * cos(t1), 0.0, _c.y + r * sin(t1))
			var x := (q - p).normalized()
			b.add_rounded_box(Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), (p + q) * 0.5 + Vector3.UP * 0.92), Vector3(p.distance_to(q) + 0.1, 0.1, 0.1), 0.0, 0, ArtPalette.WHITE)


## The ponds: a sand shore ring, the water (deep middle, lighter edge) and lily pads, as the map's.
func _add_ponds(b: ArtMeshBuilder) -> void:
	for p in _ponds:
		var center2: Vector2 = p[0]
		var radius: float = p[1]
		var y := _pond_y(center2)
		var sides := 22
		var edge: Array = []
		var shore: Array = []
		var deep: Array = []
		for i in sides:
			var t := TAU * i / sides
			var r := radius * (1.0 + 0.07 * sin(3.0 * t + 0.5) + 0.04 * sin(5.0 * t))
			var d := Vector2.from_angle(t)
			edge.append(Vector3(center2.x + d.x * r, y, center2.y + d.y * r))
			shore.append(Vector3(center2.x + d.x * (r + 2.2), y - 0.02, center2.y + d.y * (r + 2.2)))
			deep.append(Vector3(center2.x + d.x * r * 0.55, y, center2.y + d.y * r * 0.55))
		b.ao_min = 0.9
		b.ao_height = 0.6
		for k in (REEDS if p[2] == map.zones[zone] else 0):   # reed clumps on the own pond's near shore
			var t := (_c - center2).angle() + (float(k) / (REEDS - 1) - 0.5) * PI * 1.3
			var base := center2 + Vector2.from_angle(t) * (radius + 0.6)
			for e in 3:
				var at := base + Vector2.from_angle(t + e * 2.1) * 0.35
				var h := 1.1 + 0.25 * e
				b.add_cylinder(_at(at.x, y, at.y), 0.05, 0.04, h, 4, ArtPalette.STEM, false)
				b.add_cylinder(_at(at.x, y + h - 0.05, at.y), 0.1, 0.08, 0.38, 4, ArtPalette.TRUNK)
		b.ao_min = 1.0
		for pad in [[-0.45, 0.35, 0.8], [0.1, 0.55, 0.65], [0.48, -0.3, 0.7]]:
			b.add_cylinder(Transform3D(Basis(Vector3.UP, pad[0]), Vector3(center2.x + pad[0] * radius, y, center2.y + pad[1] * radius)), pad[2], pad[2], 0.04, 7, ArtPalette.LEAF_LIGHT)
		var mid := Vector3(center2.x, y, center2.y)
		for i in sides:
			var n := (i + 1) % sides
			b.add_triangle([mid, deep[i], deep[n]], [ArtPalette.WATER, ArtPalette.WATER, ArtPalette.WATER])
			b.add_triangle([deep[i], edge[i], edge[n]], [ArtPalette.WATER, ArtPalette.POND, ArtPalette.POND])
			b.add_triangle([deep[i], edge[n], deep[n]], [ArtPalette.WATER, ArtPalette.POND, ArtPalette.WATER])
			b.add_triangle([edge[i], shore[i], shore[n]], [ArtPalette.SAND, ArtPalette.SAND, ArtPalette.SAND])
			b.add_triangle([edge[i], shore[n], edge[n]], [ArtPalette.SAND, ArtPalette.SAND, ArtPalette.SAND])


## The ground: a polar grid round the centre to the coast (MapIsland's facets: the far rings
## jittered), one colour per face.
func _add_ground(b: ArtMeshBuilder) -> void:
	var grid: Array = []
	var rings := INNER.size() + 1 + LAND_U.size() + 3
	for j in rings:
		var row: Array = []
		for i in SECTORS:
			var theta := TAU * i / SECTORS
			var jitter := j > INNER.size() and j < GRASS_EDGE
			if jitter:
				theta += MapIsland._hash(i, j, 1) * JITTER * TAU / SECTORS
			var radii := _ring_radii(coast_at(theta))
			var s: float = radii[j]
			if jitter:
				s += MapIsland._hash(i, j, 2) * JITTER * minf(radii[j + 1] - radii[j], radii[j] - radii[j - 1])
			var l := _c + Vector2.from_angle(theta) * s
			row.append(Vector3(l.x, _vertex_y(j, s, l), l.y))
		grid.append(row)
	for j in rings - 1:
		for i in SECTORS:
			var n := (i + 1) % SECTORS
			var q := [grid[j][i], grid[j][n], grid[j + 1][n], grid[j + 1][i]]
			for k in 2:
				var tri: Array = [q[0], q[1], q[2]] if k == 0 else [q[0], q[2], q[3]]
				var color := _face_color(j, i, k, tri)
				b.add_triangle(tri, [color, color, color])


## The sea from under the wet sand to SEA_FAR: the surf line, the light shallows with a wavy edge,
## the deep sea (MapIsland's sea colour) fading into the horizon haze.
func _add_sea(b: ArtMeshBuilder) -> void:
	var haze := _haze()
	var sea := ArtPalette.SEA
	var far := _under_fill(MapIsland.sea_color().lerp(haze, 0.6))
	var bands := [
		[func(t: float) -> float: return coast_at(t) - SHORE_W - 0.05, ArtPalette.FOAM, func(t: float) -> float: return coast_at(t) - 0.3 + 0.12 * sin(9.0 * t), ArtPalette.FOAM, 0.05],
		[func(t: float) -> float: return coast_at(t) - SHORE_W - 0.1, ArtPalette.SEA_SHALLOW, func(t: float) -> float: return coast_at(t) + 6.0 + 2.0 * sin(5.0 * t + 0.6), ArtPalette.SEA_SHALLOW, 0.0],
		[func(t: float) -> float: return coast_at(t) + 6.0 + 2.0 * sin(5.0 * t + 0.6), ArtPalette.SEA_SHALLOW, func(t: float) -> float: return coast_at(t) + 16.0, sea, 0.0],
		[func(t: float) -> float: return coast_at(t) + 16.0, sea, func(_t: float) -> float: return 150.0, sea, 0.0],
		[func(_t: float) -> float: return 150.0, sea, func(_t: float) -> float: return SEA_FAR, far, 0.0],
	]
	for band in bands:
		var sectors := SECTORS * 2 if band[4] > 0.0 else SECTORS
		for i in sectors:
			var t0 := TAU * i / sectors
			var t1 := TAU * (i + 1) / sectors
			var y: float = sea_y + band[4]
			var p := [_ring_point(t0, band[0].call(t0), y), _ring_point(t1, band[0].call(t1), y),
				_ring_point(t1, band[2].call(t1), y), _ring_point(t0, band[2].call(t0), y)]
			b.add_triangle([p[0], p[1], p[2]], [band[1], band[1], band[3]])
			b.add_triangle([p[0], p[2], p[3]], [band[1], band[3], band[3]])


func _ring_point(theta: float, r: float, y: float) -> Vector3:
	return Vector3(_c.x + r * cos(theta), y, _c.y + r * sin(theta))


## MapIsland's horizon haze.
static func _haze() -> Color:
	return ArtPalette.SKY.lerp(Color.WHITE, 0.45)


## The horizon: a ring SEA_FAR round the centre from below the sea to HAZE_TOP, the far sea's haze
## rising into the sky colour (lit full, no fill: add_triangle_lit along the sun's level direction).
func _add_haze(b: ArtMeshBuilder) -> void:
	var haze := _haze()
	var level := Vector3(ArtKit.SUN_DIR.x, 0.0, ArtKit.SUN_DIR.z).normalized()
	var far := MapIsland.sea_color().lerp(haze, 0.6)
	var bands := [[sea_y + HAZE_BOTTOM, far], [sea_y, far], [sea_y + HAZE_TOP * 0.3, haze], [sea_y + HAZE_TOP, ArtPalette.SKY]]
	var sides := SECTORS
	for i in sides:
		var d0 := Vector3(cos(TAU * i / sides), 0.0, sin(TAU * i / sides))
		var d1 := Vector3(cos(TAU * (i + 1) / sides), 0.0, sin(TAU * (i + 1) / sides))
		var inward := -(d0 + d1).normalized()
		var o := Vector3(_c.x, 0.0, _c.y)
		for k in bands.size() - 1:
			var y0: float = bands[k][0]
			var y1: float = bands[k + 1][0]
			var c0: Color = bands[k][1]
			var c1: Color = bands[k + 1][1]
			var p := [o + d0 * SEA_FAR + Vector3.UP * y0, o + d1 * SEA_FAR + Vector3.UP * y0, o + d1 * SEA_FAR + Vector3.UP * y1, o + d0 * SEA_FAR + Vector3.UP * y1]
			b.add_triangle_lit([p[0], p[1], p[2]], [c0, c0, c1], inward, level)
			b.add_triangle_lit([p[0], p[2], p[3]], [c0, c1, c1], inward, level)


## Clouds in the lab's sky (CLOUDS: around its front view, where the camera turns).
func _add_clouds(b: ArtMeshBuilder) -> void:
	b.ao_min = 0.85
	b.ao_height = 0.6
	for c in CLOUDS:
		var d := Vector2(0.0, -1.0).rotated(deg_to_rad(c[0]))
		var at := Vector3(_c.x + d.x * c[1], sea_y + c[2], _c.y + d.y * c[1])
		var side := Vector3(-d.y, 0.0, d.x)
		var k: float = c[3]
		for puff in [[0.0, 0.0, 1.0], [1.15, -0.25, 0.72], [-1.1, -0.3, 0.75]]:
			b.add_sphere(Transform3D(Basis().scaled(Vector3(1.0, 0.65, 1.0)), at + side * puff[0] * k + Vector3.UP * puff[1] * k), puff[2] * k, 3, 6, ArtPalette.CLOUD)


static func _at(x: float, y: float, z: float, yaw_deg := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(x, y, z))
