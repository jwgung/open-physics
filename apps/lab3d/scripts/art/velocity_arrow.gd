## A low-poly arrow prop (grass island style): a 6-sided shaft and a cone head along the node's +x,
## turned about world z by `angle_deg`. Used for the velocity arrows the user drags (projectile,
## collision: the web's purple arrows) and the collision lab's momentum and force arrows. The mesh
## (about 60 vertices) is rebuilt only when the length or the colour changes; turning or moving the
## arrow only sets the node transform. Visual only.
class_name VelocityArrow
extends MeshInstance3D

const RADIUS := 0.05
const HEAD_LENGTH := 0.22
const MIN_LENGTH := 0.3       # shorter arrows are drawn at this length (the head must fit)

var color := ArtPalette.PURPLE
var top_color := ArtPalette.PURPLE_TOP
## Length and colours the mesh was built for.
var _built_length := -1.0
var _built_color := Color.TRANSPARENT


func _init(arrow_color := ArtPalette.PURPLE, arrow_top := ArtPalette.PURPLE_TOP) -> void:
	color = arrow_color
	top_color = arrow_top
	material_override = ArtKit.lit_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Points the arrow from `origin` (world, when the node's parent has no transform) along
## `angle_deg` (about z, 0 = +x, 180 = -x) with total length `length` (m, at least MIN_LENGTH).
func point(origin: Vector3, angle_deg: float, length: float) -> void:
	position = origin
	rotation = Vector3(0.0, 0.0, deg_to_rad(angle_deg))
	var l := maxf(length, MIN_LENGTH)
	if l == _built_length and color == _built_color:
		return
	_built_length = l
	_built_color = color
	mesh = arrow_mesh(l, color, top_color)


## Colours for the next point() (rebuilds the mesh only when they differ from the built ones).
func set_colors(arrow_color: Color, arrow_top: Color) -> void:
	color = arrow_color
	top_color = arrow_top


## An arrow of `length` along +x from the origin (cylinders grow along +y from their base: they are
## turned by -90 deg about z).
static func arrow_mesh(length: float, arrow_color: Color, arrow_top: Color) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	add_arrow(b, Transform3D.IDENTITY, length, arrow_color, arrow_top)
	return b.commit()


## Adds an arrow of `length` along the +x of `xf` (mesh space) to a builder (props that put several
## arrows in one mesh).
static func add_arrow(b: ArtMeshBuilder, xf: Transform3D, length: float, arrow_color: Color, arrow_top: Color) -> void:
	var shaft := length - HEAD_LENGTH
	var along := xf.basis * Basis(Vector3.BACK, -PI * 0.5)
	b.add_cylinder(Transform3D(along, xf.origin), RADIUS, RADIUS, shaft, 6, arrow_color, true, arrow_top)
	b.add_cylinder(Transform3D(along, xf * Vector3(shaft, 0.0, 0.0)), RADIUS * 2.6, 0.0, HEAD_LENGTH, 6, arrow_color, true, arrow_top)


## The yellow knob at an arrow tip that a finger drags (a bevelled cube of `size`).
static func knob_mesh(size: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D.IDENTITY, Vector3.ONE * size, 0.05, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	return b.commit()
