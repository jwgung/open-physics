## 퍼피랜드's sea around 과학섬 (the story "별 조각 찾기", 2026-10-28): a few small low-poly islands far
## out on the sea and three little boats near the coast, each with a lantern on its mast. The
## prologue's wide shot shows the country of islands; at night the lanterns are what is seen of the
## boats (lost while the star is broken); the finale lights them again and they sail.
##
## Cheap for SM-P200: the far islands are one static mesh in the map's material (MapIsland.material:
## the map's light, the story's night tint), each boat one small mesh, each lantern a tiny glowing
## sphere (StarArt.glow_material: it stays bright at night). All of it lies outside the map's
## default view (the islands 60 m and more away, the boats beyond the shallows), so the child's map
## draws none of it unless the camera is turned low. Nothing moves unless the story moves it.
class_name MapSea
extends RefCounted

## Far islands [x, z, radius, hills]: most behind 과학섬 from the default view (-z), some to the sides.
const ISLANDS := [
	[-62.0, -78.0, 7.0, 2], [58.0, -96.0, 9.0, 3], [-118.0, -150.0, 12.0, 3], [128.0, -36.0, 8.0, 2],
	[12.0, -170.0, 14.0, 4], [-150.0, 18.0, 9.0, 2], [95.0, 70.0, 7.0, 2], [-88.0, -18.0, 5.0, 1],
]
## Boats [x, z, heading deg, hull colour]: around the coast, beyond the shallow ring.
const BOATS := [[-21.0, 15.0, 30.0, ArtPalette.RED], [24.0, 13.0, -60.0, ArtPalette.BLUE], [19.0, -21.0, 150.0, ArtPalette.ORANGE]]
const LANTERN_Y := 2.05
const SEED := 1028

var islands: MeshInstance3D
var boats: Array[Node3D] = []
var lanterns: Array[MeshInstance3D] = []
var boat_homes: Array[Vector3] = []


## Builds the far islands and the boats under `world`.
func build(world: Node3D) -> void:
	var b := ArtKit.builder()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for spec in ISLANDS:
		_island(b, Vector3(spec[0], MapIsland.SEA_Y, spec[1]), float(spec[2]), int(spec[3]), rng)
	islands = ArtKit.instance(b.commit(), MapIsland.material())
	islands.name = "FarIslands"
	world.add_child(islands)
	var lantern_mesh := _lantern_mesh()
	for spec in BOATS:
		var boat := Node3D.new()
		boat.name = "Boat"
		boat.position = Vector3(spec[0], MapIsland.SEA_Y, spec[1])
		boat.rotation.y = deg_to_rad(spec[2])
		var hull := ArtKit.builder()
		_boat(hull, spec[3])
		boat.add_child(ArtKit.instance(hull.commit(), MapIsland.material()))
		var lantern := ArtKit.instance(lantern_mesh, StarArt.glow_material())
		lantern.name = "Lantern"
		lantern.position = Vector3(0.0, LANTERN_Y, 0.15)
		boat.add_child(lantern)
		world.add_child(boat)
		boats.append(boat)
		lanterns.append(lantern)
		boat_homes.append(boat.position)


## Lanterns on or off (on at night in the prologue and after the finale).
func set_lanterns(on: bool) -> void:
	for lantern in lanterns:
		lantern.visible = on


## The boats back where they rest.
func rest_boats() -> void:
	for i in boats.size():
		boats[i].position = boat_homes[i]


## A far island: a sand ring sloping into the sea, green hills (faceted cones), a tree or two.
func _island(b: ArtMeshBuilder, at: Vector3, radius: float, hills: int, rng: RandomNumberGenerator) -> void:
	b.ao_min = 0.9
	b.ao_height = 0.6
	b.add_cylinder(Transform3D(Basis(), at + Vector3.DOWN * 0.3), radius * 1.12, radius, 0.6, 9, ArtPalette.SAND)
	b.add_cylinder(Transform3D(Basis(), at + Vector3.UP * 0.25), radius * 0.92, radius * 0.7, radius * 0.18, 9, ArtPalette.GRASS, true, ArtPalette.GRASS_TOP)
	for i in hills:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, radius * 0.4)
		var h := radius * rng.randf_range(0.35, 0.7)
		var base := at + Vector3(cos(a) * r, radius * 0.18 + 0.2, sin(a) * r)
		b.add_cylinder(Transform3D(Basis(), base), radius * rng.randf_range(0.3, 0.45), 0.0, h, 7, ArtPalette.GRASS, true, ArtPalette.LEAF_LIGHT)
	for i in 2:
		var a := rng.randf() * TAU
		var p := at + Vector3(cos(a) * radius * 0.55, radius * 0.18 + 0.2, sin(a) * radius * 0.55)
		b.add_cylinder(Transform3D(Basis(), p), 0.35, 0.3, 1.8, 5, ArtPalette.TRUNK)
		b.add_sphere(Transform3D(Basis(), p + Vector3.UP * 2.5), 1.4, 3, 6, ArtPalette.LEAF)


## A little boat (local: bow +z): a rounded hull, a white deck line, a mast and a white sail.
func _boat(b: ArtMeshBuilder, hull: Color) -> void:
	b.ao_min = 0.85
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.25, 0.0)), Vector3(1.2, 0.55, 2.6), 0.22, 1, hull)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.55, 0.0)), Vector3(1.0, 0.08, 2.3), 0.04, 1, ArtPalette.WHITE)
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, 0.55, 0.15)), 0.05, 0.05, 1.45, 5, ArtPalette.TRUNK)
	var sail := [Vector3(0.0, 0.75, 0.25), Vector3(0.0, 1.95, 0.22), Vector3(0.0, 0.75, -0.85)]
	b.add_triangle(sail, [ArtPalette.WHITE, ArtPalette.WHITE, ArtPalette.WHITE], Vector3.RIGHT)
	b.add_triangle(sail, [ArtPalette.CLOUD, ArtPalette.CLOUD, ArtPalette.CLOUD], Vector3.LEFT)


static func _lantern_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_sphere(Transform3D.IDENTITY, 0.22, 3, 6, StarArt.MID)
	return b.commit()
