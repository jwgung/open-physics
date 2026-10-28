## The guiding star (길잡이 별) and its pieces (the story "별 조각 찾기", 2026-10-28): chunky toon shapes
## in the storybook look (art-direction.md section 15). A puffy five-point star (the rim at z = 0, the
## faces rising to a centre point in front and behind, so each point has two bright facets) and a
## piece of it (one puffy point, a kite), both in sunny yellows with the characters' brown outline
## (an inverted hull: the same shape a little bigger, its front faces culled).
##
## "Glowing" without effects: an unshaded material with the facet light baked into the vertex
## colours (pale lemon facets towards the sun, warm yellow away from it), so the star stays bright
## at night (the story's night tint is not applied to it) and costs two small draws. No light, no
## bloom, no transparency, no texture. Visual only.
class_name StarArt
extends RefCounted

const LIGHT := Color("fff3a6")       # facets towards the sun
const MID := Color("ffd84a")         # ArtPalette.YELLOW_TOP
const DEEP := Color("ffb31a")        # facets away from the sun
const POINTS := 5
const INNER := 0.5                   # inner radius share of the outer one
const DEPTH := 0.38                  # the centre's bulge share of the radius (front and back)
const OUTLINE_GROW := 0.09           # the hull's growth share of the radius (the outline's width)

static var _glow: StandardMaterial3D
static var _outline: StandardMaterial3D
static var _meshes: Dictionary = {}


## The unshaded vertex-colour material of the star and its pieces (no night tint, no light).
static func glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.vertex_color_use_as_albedo = true
	return _glow


## The brown outline hull's material (front faces culled: only the rim behind the shape shows).
static func outline_material() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = ArtPalette.OUTLINE
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	return _outline


## A star of outer radius 1 in the xy plane (facing +z): [body mesh, outline mesh].
static func star_meshes() -> Array:
	if not _meshes.has("star"):
		var rim: Array = []
		for i in POINTS * 2:
			var a := PI * 0.5 + TAU * i / (POINTS * 2)
			rim.append(Vector3(cos(a), sin(a), 0.0) * (1.0 if i % 2 == 0 else INNER))
		_meshes["star"] = [_puffy(rim, Vector3.ZERO, DEPTH, 1.0), _puffy(rim, Vector3.ZERO, DEPTH, 1.0 + OUTLINE_GROW)]
	return _meshes["star"]


## A piece: one point of the star (a kite, outer radius 1 at its tip), centred on its middle.
static func piece_meshes() -> Array:
	if not _meshes.has("piece"):
		var a := TAU / (POINTS * 2)
		var rim: Array = [Vector3(0.0, 1.0, 0.0), Vector3(-sin(a), cos(a), 0.0) * INNER, Vector3(0.0, -0.05, 0.0), Vector3(sin(a), cos(a), 0.0) * INNER]
		var mid := Vector3(0.0, 0.5, 0.0)
		for i in rim.size():
			rim[i] = (rim[i] - mid) * 1.6   # the piece reads as big as a small star
		_meshes["piece"] = [_puffy(rim, Vector3.ZERO, DEPTH * 0.9, 1.0), _puffy(rim, Vector3.ZERO, DEPTH * 0.9, 1.0 + OUTLINE_GROW * 1.4)]
	return _meshes["piece"]


## A puffy solid: the rim polygon (z = 0) joined to a centre point in front (+z) and behind (-z),
## scaled by `grow` about the centre (the outline hull). The facets' colours bake a light from the
## upper left front.
static func _puffy(rim: Array, center: Vector3, depth: float, grow: float) -> ArrayMesh:
	var b := ArtKit.builder()
	var sun := Vector3(-0.45, 0.7, 0.55).normalized()
	for side: float in [1.0, -1.0]:
		var tip := center + Vector3(0.0, 0.0, depth * side * (1.0 + (grow - 1.0) * 2.5))
		for i in rim.size():
			var p0: Vector3 = center + (rim[i] - center) * grow
			var p1: Vector3 = center + (rim[(i + 1) % rim.size()] - center) * grow
			var n := (p1 - p0).cross(tip - p0).normalized() * side
			if n.dot(Vector3(0.0, 0.0, side)) < 0.0:
				n = -n
			var k := clampf(n.dot(sun) * 0.5 + 0.5, 0.0, 1.0)
			var color := DEEP.lerp(MID, smoothstep(0.2, 0.55, k)).lerp(LIGHT, smoothstep(0.6, 0.85, k))
			b.add_triangle([p0, p1, tip], [color, color, color], n)
	return b.commit()


## A star (or a piece) node: the body and its outline, `size` m from the centre to a point.
static func make(piece: bool, size: float) -> Node3D:
	var meshes: Array = piece_meshes() if piece else star_meshes()
	var root := Node3D.new()
	root.name = "StarPiece" if piece else "Star"
	var body := ArtKit.instance(meshes[0], glow_material())
	body.name = "Body"
	var outline := ArtKit.instance(meshes[1], outline_material())
	outline.name = "Outline"
	var holder := Node3D.new()
	holder.name = "Shape"
	holder.scale = Vector3.ONE * size
	holder.add_child(body)
	holder.add_child(outline)
	root.add_child(holder)
	return root
