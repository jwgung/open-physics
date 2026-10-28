## The guiding star (길잡이 별) and its pieces (the story "별 조각 찾기", 2026-10-28): chunky toon shapes
## in the storybook look (art-direction.md section 15). A chubby five-point star with round tips, a
## pillow (the rim at z = 0 rising to a flat face in front and behind) with a face on both sides:
## shiny eyes, pink cheeks, a little smile (2026-10-28 user: make the star pieces cute). The pieces
## are the same little star. Sunny yellows with the characters' brown outline (an inverted hull: the
## same shape a little bigger, its front faces culled).
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
const DEPTH := 0.3                   # the flat faces' height share of the radius (front and back)
const OUTLINE_GROW := 0.09           # the hull's growth share of the radius (the outline's width)
## The cute look (2026-10-28 user: make the star pieces cute): chubby round points and a face.
const ROUND_INNER := 0.62            # inner radius share of the outer one (chubby arms)
const FACE_SHRINK := 0.72            # the flat face's share of the rim
const FACE_INK := Color("4a2e1f")    # the eyes and the smile (dark brown, the storybook ink)
const CHEEK := Color("ff9db5")
const EYE_X := 0.17
const EYE_Y := 0.06
const EYE_R := 0.075
const CHEEK_R := 0.065
const MOUTH_Y := -0.12
const MOUTH_R := 0.07
const MOUTH_W := 0.03

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


## A star of outer radius 1 in the xy plane (facing +z): [body mesh, outline mesh]. The pieces are
## the same little star (2026-10-28 user: make the star pieces cute): a chubby pillow with round points and a
## face on both sides.
static func star_meshes() -> Array:
	if not _meshes.has("star"):
		var rim := _round_rim()
		_meshes["star"] = [_pillow(rim, DEPTH, 1.0, true), _pillow(rim, DEPTH, 1.0 + OUTLINE_GROW, false)]
	return _meshes["star"]


## A piece: the same chubby star with its face (the size comes from make()).
static func piece_meshes() -> Array:
	return star_meshes()


## The rim of a five-point star with round tips and soft inner corners (Chaikin corner cutting).
static func _round_rim() -> Array:
	var rim: Array = []
	for i in POINTS * 2:
		var a := PI * 0.5 + TAU * i / (POINTS * 2)
		rim.append(Vector3(cos(a), sin(a), 0.0) * (1.0 if i % 2 == 0 else ROUND_INNER))
	for pass_i in 3:
		var out: Array = []
		for i in rim.size():
			var p0: Vector3 = rim[i]
			var p1: Vector3 = rim[(i + 1) % rim.size()]
			out.append(p0.lerp(p1, 0.25))
			out.append(p0.lerp(p1, 0.75))
		rim = out
	var far := 0.0
	for p: Vector3 in rim:
		far = maxf(far, p.length())
	for i in rim.size():
		rim[i] = rim[i] / far   # the round tips still reach radius 1
	return rim


## A pillow: the rim (z = 0) rising to a flat face (the rim shrunk by FACE_SHRINK) at z = +-depth,
## all scaled by `grow` (the outline hull). The facets bake a light from the upper left front; the
## face (eyes, cheeks, smile) sits on both flat sides when `face`.
static func _pillow(rim: Array, depth: float, grow: float, face: bool) -> ArrayMesh:
	var b := ArtKit.builder()
	var sun := Vector3(-0.45, 0.7, 0.55).normalized()
	var n_rim := rim.size()
	for side: float in [1.0, -1.0]:
		var z := depth * side * (1.0 + (grow - 1.0) * 2.5)
		var top: Array = []
		for p: Vector3 in rim:
			top.append(Vector3(p.x * FACE_SHRINK, p.y * FACE_SHRINK, 0.0) * grow + Vector3(0.0, 0.0, z))
		for i in n_rim:
			var r0: Vector3 = rim[i] * grow
			var r1: Vector3 = rim[(i + 1) % n_rim] * grow
			var t0: Vector3 = top[i]
			var t1: Vector3 = top[(i + 1) % n_rim]
			var n := (r1 - r0).cross(t0 - r0).normalized()
			if n.dot(Vector3(r0.x, r0.y, 0.0)) < 0.0:
				n = -n
			var color := _lit(n, sun)
			b.add_triangle([r0, r1, t1], [color, color, color], n)
			b.add_triangle([r0, t1, t0], [color, color, color], n)
			var face_color := MID.lerp(LIGHT, 0.55)
			b.add_triangle([Vector3(0.0, 0.0, z), t0, t1], [face_color, face_color, face_color], Vector3(0.0, 0.0, side))
		if face:
			_face(b, z + side * 0.01, side)
	return b.commit()


static func _lit(n: Vector3, sun: Vector3) -> Color:
	var k := clampf(n.dot(sun) * 0.5 + 0.5, 0.0, 1.0)
	return DEEP.lerp(MID, smoothstep(0.2, 0.55, k)).lerp(LIGHT, smoothstep(0.6, 0.85, k))


## Two shiny eyes, pink cheeks and a little smile on the flat side at height z (side +1: facing +z;
## -1: the back, mirrored so it reads the same from behind).
static func _face(b: ArtMeshBuilder, z: float, side: float) -> void:
	var facing := Vector3(0.0, 0.0, side)
	for x in [-EYE_X, EYE_X]:
		_disc(b, Vector2(x * side, EYE_Y), EYE_R, z, facing, FACE_INK)
		_disc(b, Vector2((x - EYE_R * 0.3) * side, EYE_Y + EYE_R * 0.35), EYE_R * 0.38, z + side * 0.004, facing, Color.WHITE)
		_disc(b, Vector2((x * 1.75) * side, EYE_Y - 0.13), CHEEK_R, z - side * 0.002, facing, CHEEK)
	# The smile: a short thick arc under the eyes.
	var steps := 8
	for i in steps:
		var a0 := PI * (1.15 + 0.7 * i / steps)
		var a1 := PI * (1.15 + 0.7 * (i + 1) / steps)
		var c := Vector2(0.0, MOUTH_Y + MOUTH_R)
		var p0 := c + Vector2(cos(a0), sin(a0)) * MOUTH_R
		var p1 := c + Vector2(cos(a1), sin(a1)) * MOUTH_R
		var q0 := c + Vector2(cos(a0), sin(a0)) * (MOUTH_R + MOUTH_W)
		var q1 := c + Vector2(cos(a1), sin(a1)) * (MOUTH_R + MOUTH_W)
		var pts := [p0, p1, q1, q0]
		var v: Array = []
		for p: Vector2 in pts:
			v.append(Vector3(p.x * side, p.y, z))
		b.add_triangle([v[0], v[1], v[2]], [FACE_INK, FACE_INK, FACE_INK], facing)
		b.add_triangle([v[0], v[2], v[3]], [FACE_INK, FACE_INK, FACE_INK], facing)


static func _disc(b: ArtMeshBuilder, c: Vector2, r: float, z: float, facing: Vector3, color: Color) -> void:
	var sides := 12
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		b.add_triangle([Vector3(c.x, c.y, z), Vector3(c.x + cos(a0) * r, c.y + sin(a0) * r, z),
			Vector3(c.x + cos(a1) * r, c.y + sin(a1) * r, z)], [color, color, color], facing)


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


## Turns a star (or piece) to show its face to `camera`, swaying a little about that (2026-10-28: a
## full spin showed the cute face edge-on half the time). `t` is the node's own clock (s).
static func face_camera(node: Node3D, camera: Camera3D, t: float) -> void:
	if node == null or camera == null or not node.is_inside_tree():
		return
	var to := camera.global_position - node.global_position
	if to.length_squared() < 1e-6:
		return
	node.rotation = Vector3(0.0, atan2(to.x, to.z) + sin(t * 2.2) * 0.35, sin(t * 1.7) * 0.12)
