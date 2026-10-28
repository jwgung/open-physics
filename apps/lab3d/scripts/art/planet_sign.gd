## Where the lab is (2026-10-28 user request: the other labs' conditions should read at a glance
## too): the gravity control (지구 / 달 / 목성 / 무중력) as a signpost beside the apparatus, so a
## 7-year-old sees which world the balls fall on. A wooden post carries a globe drawn like the
## picture buttons (PickPictures: the earth = sea blue with green land, the moon = grey with craters,
## Jupiter = tan stripes with a red spot; no gravity = night blue with stars). Visual only: the
## gravity is the lab's, nothing here is a body. One node and one mesh per world (post and globe
## together, about 700 vertices, built once and swapped), inside the labs' drawn-node budget.
class_name PlanetSign
extends MeshInstance3D

const GLOBE_RADIUS := 0.65
const POST_HEIGHT := 2.0           # m: the post's top; the globe sits on it
const RINGS := 8
const SIDES := 12
const WORLDS := ["earth", "moon", "jupiter", "zero"]
const EARTH_LAND := [[Vector3(-0.4, 0.5, 0.75), 0.55], [Vector3(0.6, -0.3, 0.75), 0.5], [Vector3(-0.2, -0.75, 0.6), 0.35], [Vector3(0.0, 0.2, -1.0), 0.7]]
const MOON_CRATERS := [[Vector3(-0.35, 0.3, 0.88), 0.3], [Vector3(0.45, -0.35, 0.82), 0.25], [Vector3(0.2, 0.75, 0.6), 0.2], [Vector3(-0.5, -0.6, 0.6), 0.2], [Vector3(0.1, 0.0, -1.0), 0.4]]

## The world shown now ("" = none yet).
var planet := ""
static var _meshes: Dictionary = {}


func _init() -> void:
	name = "PlanetSign"
	material_override = ArtKit.lit_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Shows world `id` (a gravity option id: earth, moon, jupiter, zero; another id shows the earth).
func show_planet(id: String) -> void:
	planet = id
	mesh = sign_mesh(id if id in WORLDS else "earth")


## The post (on a small foot, the node origin on the ground) with world `id`'s globe on it (built once).
static func sign_mesh(id: String) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var b := ArtKit.builder()
	b.ao_height = 0.3
	b.add_cylinder(Transform3D.IDENTITY, 0.28, 0.24, 0.1, 8, ArtPalette.TRUNK)
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, POST_HEIGHT * 0.5, 0.0)), Vector3(0.12, POST_HEIGHT, 0.12), 0.02, 1, ArtPalette.TRUNK)
	var centre := Vector3(0.0, POST_HEIGHT + GLOBE_RADIUS - 0.05, 0.0)
	var rows: Array = []
	for ring in RINGS + 1:
		var phi := PI * ring / RINGS
		var row: Array = []
		for i in SIDES + 1:
			var theta := TAU * i / SIDES
			row.append(Vector3(sin(phi) * sin(theta), cos(phi), sin(phi) * cos(theta)))
		rows.append(row)
	for ring in RINGS:
		for i in SIDES:
			var a: Vector3 = rows[ring][i]
			var c: Vector3 = rows[ring + 1][i + 1]
			for tri in [[a, rows[ring + 1][i], c], [a, c, rows[ring][i + 1]]]:
				var mid: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				if (tri[1] - tri[0]).cross(tri[2] - tri[0]).length() < 1e-8:
					continue   # the poles' degenerate halves
				var colour := face_colour(id, mid.normalized())
				b.add_triangle([centre + tri[0] * GLOBE_RADIUS, centre + tri[1] * GLOBE_RADIUS, centre + tri[2] * GLOBE_RADIUS], [colour, colour, colour], mid)
	var m := b.commit()
	_meshes[id] = m
	return m


## The colour of the globe's face pointing along `d` (unit, +z faces the front camera).
static func face_colour(id: String, d: Vector3) -> Color:
	match id:
		"earth":
			for land in EARTH_LAND:
				if d.dot((land[0] as Vector3).normalized()) > cos(land[1]):
					return ArtPalette.GRASS
			return ArtPalette.SEA
		"moon":
			for crater in MOON_CRATERS:
				if d.dot((crater[0] as Vector3).normalized()) > cos(crater[1]):
					return Color("aeb3c0")
			return Color("d9dbe2")
		"jupiter":
			if d.dot(Vector3(0.45, -0.3, 0.84).normalized()) > cos(0.22):
				return Color("c4573a")   # the red spot
			return Color("b9784a") if int(floorf((d.y + 1.0) * 3.5)) % 2 == 1 else Color("e8b77d")
		_:
			# No gravity: the night sky with a few stars.
			var star := absf(sin(d.x * 23.0) * sin(d.y * 17.0) * sin(d.z * 29.0)) > 0.82
			return ArtPalette.WHITE if star else ArtPalette.SPACE
