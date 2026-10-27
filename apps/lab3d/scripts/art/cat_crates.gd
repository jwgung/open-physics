## The stand of wooden bread crates under a bread cat that stands above its floor (Task 4g: the
## projectile's launch point; 2026-10-27: the free-fall ball, the pendulum bob, the lever, the
## buoyancy drum, the orbit's planet). A stack of n crates of the stand's height / n each (n the
## fewest with crates no taller than CRATE_H, at most max_count), the cat's footprint plus a rim; the
## mesh is rebuilt only when n changes, the node is scaled to the height. Visual only, no body.
class_name CatCrates
extends MeshInstance3D

const CRATE_H := 0.42
const CRATE_RIM := 0.04

var footprint := Vector2.ONE
var max_count := 10
## Crates in the mesh now.
var count := 0


func _init(cat_footprint: Vector2, most := 10) -> void:
	name = "CatCrates"
	footprint = cat_footprint
	max_count = most
	material_override = ArtKit.lit_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## The stack from `floor_y` up to the base of `cat` (exactly under its bag); hidden when the cat
## stands on the floor.
func fit(cat: CatActor, floor_y: float) -> void:
	var height := cat.position.y - floor_y
	visible = height > 0.01
	if not visible:
		return
	var n := clampi(ceili(height / CRATE_H - 1e-6), 1, max_count)
	if n != count:
		count = n
		mesh = stack_mesh(footprint, n)
	position = Vector3(cat.position.x, floor_y, cat.position.z)
	scale = Vector3(1.0, height, 1.0)


## A stack of `count` wooden bread crates `footprint` wide, of total height 1 (the node is scaled
## to the stand height): each a dark inside, two plank bands around it, four corner posts and a
## dark seam to the next one.
static func stack_mesh(cat_footprint: Vector2, count: int) -> Mesh:
	var b := ArtKit.builder()
	var size := Vector2(cat_footprint.x + CRATE_RIM, cat_footprint.y + CRATE_RIM)
	var h := 1.0 / count
	b.ao_height = 0.3
	for i in count:
		var y0 := h * i
		b.ao_min = 0.8 if i == 0 else 0.95
		b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, y0 + h * 0.5, 0.0)), Vector3(size.x - 0.04, h, size.y - 0.04), 0.0, 1, ArtPalette.TRUNK)
		b.ao_min = 1.0
		for k in 2:
			b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, y0 + h * (0.3 + 0.42 * k), 0.0)), Vector3(size.x - 0.01, h * 0.3, size.y - 0.01), 0.0, 1, ArtPalette.CRATE, ArtPalette.CRATE_TOP)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				b.add_rounded_box(Transform3D(Basis(), Vector3(cx * (size.x * 0.5 - 0.035), y0 + h * 0.5, cz * (size.y * 0.5 - 0.035))), Vector3(0.07, h * 0.9, 0.07), 0.0, 1, ArtPalette.CRATE_TOP)
	return b.commit()
