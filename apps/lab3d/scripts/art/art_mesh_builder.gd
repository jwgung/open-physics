## Procedural low-poly geometry for the grass island style (Phase 1 Task 2c,
## apps/lab3d/docs/art-direction.md). Everything is generated in code, no external assets. Shapes are appended into one ArrayMesh with per-vertex colors, so a
## whole static set (ground + props) is a single draw call with the shared toy material.
## Per-vertex "AO": each shape darkens towards its own base (contact darkening without shadows).
## Soft blob shadows (alpha in the vertex color) are built with add_soft_rect / add_blob.
class_name ArtMeshBuilder
extends RefCounted

## true = faceted (one normal per triangle, the style's rule), false = smooth normals.
var flat := true
## Vertex AO: the base of each shape is multiplied by ao_min, fading to 1 over ao_height (m).
var ao_min := 0.72
var ao_height := 0.35

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
## Optional per-vertex tag in UV.x (0 = none; tag_from): the map's spots, so its shader can light or
## shake one spot of the merged mesh (map_lit.gdshader). Only meshes that tag something get a UV array.
var _tags := PackedVector2Array()


func is_empty() -> bool:
	return _verts.is_empty()


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	if not _tags.is_empty():
		_pad_tags()
		arrays[Mesh.ARRAY_TEX_UV] = _tags
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Rounded (bevelled) box centred on xf.origin. radius = corner radius (m), segments = bevel
## steps per 45 deg (1 = chamfer-like, 3 = smooth). Optional top_color tints the upper face.
func add_rounded_box(xf: Transform3D, size: Vector3, radius: float, segments: int, color: Color, top_color: Variant = null) -> void:
	var h := size * 0.5
	var r := clampf(radius, 0.0, minf(h.x, minf(h.y, h.z)) - 0.0001)
	var inner := h - Vector3.ONE * r
	var lists := [_bevel_coords(h.x, r, segments), _bevel_coords(h.y, r, segments), _bevel_coords(h.z, r, segments)]
	for axis in 3:
		for sign_value in [-1.0, 1.0]:
			var j := (axis + 1) % 3
			var k := (axis + 2) % 3
			var lj: PackedFloat32Array = lists[j]
			var lk: PackedFloat32Array = lists[k]
			var grid: Array = []
			for a in lj.size():
				var row: Array = []
				for b in lk.size():
					var p := Vector3.ZERO
					p[axis] = h[axis] * sign_value
					p[j] = lj[a]
					p[k] = lk[b]
					var c := p.clamp(-inner, inner)
					var d := p - c
					var n := d.normalized() if d.length() > 0.00001 else _axis_vector(axis, sign_value)
					row.append([c + n * r, n])
				grid.append(row)
			for a in lj.size() - 1:
				for b in lk.size() - 1:
					var q := [grid[a][b], grid[a + 1][b], grid[a + 1][b + 1], grid[a][b + 1]]
					_quad_local(xf, q, h.y, color, top_color)


## Upright cylinder / cone frustum with its base centre at xf.origin (y up).
func add_cylinder(xf: Transform3D, radius_bottom: float, radius_top: float, height: float, sides: int, color: Color, caps := true, top_color: Variant = null) -> void:
	var slope := (radius_bottom - radius_top) / maxf(height, 0.0001)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var n0 := (d0 + Vector3(0.0, slope, 0.0)).normalized()
		var n1 := (d1 + Vector3(0.0, slope, 0.0)).normalized()
		var b0 := d0 * radius_bottom
		var b1 := d1 * radius_bottom
		var t0 := d0 * radius_top + Vector3(0.0, height, 0.0)
		var t1 := d1 * radius_top + Vector3(0.0, height, 0.0)
		_tri(xf, [b0, b1, t1], [n0, n1, n1], 0.0, color, null)
		if radius_top > 0.0001:
			_tri(xf, [b0, t1, t0], [n0, n1, n0], 0.0, color, null)
		if caps:
			var top_c: Color = top_color if top_color != null else color
			if radius_top > 0.0001:
				_tri(xf, [Vector3(0.0, height, 0.0), t0, t1], [Vector3.UP, Vector3.UP, Vector3.UP], 0.0, top_c, null)
			_tri(xf, [Vector3.ZERO, b1, b0], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], 0.0, color, null)


## Low-poly UV sphere (or ellipsoid via scale) centred on xf.origin.
func add_sphere(xf: Transform3D, radius: float, rings: int, sides: int, color: Color) -> void:
	var points: Array = []
	for ring in rings + 1:
		var phi := PI * ring / rings
		var row: Array = []
		for i in sides + 1:
			var theta := TAU * i / sides
			row.append(Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)))
		points.append(row)
	for ring in rings:
		for i in sides:
			var a: Vector3 = points[ring][i]
			var b: Vector3 = points[ring + 1][i]
			var c: Vector3 = points[ring + 1][i + 1]
			var d: Vector3 = points[ring][i + 1]
			if ring > 0:
				_tri(xf, [a * radius, c * radius, d * radius], [a, c, d], -radius, color, null)
			if ring < rings - 1:
				_tri(xf, [a * radius, b * radius, c * radius], [a, b, c], -radius, color, null)


## Ground-hugging soft shadow: an inner rounded rectangle (half extents) at full alpha that fades
## to 0 over `fade` metres. half_extents = 0 gives a round blob of radius `fade`.
## Normal is +y of xf; use ArtKit.shadow_builder() + ArtKit.shadow_material().
func add_soft_rect(xf: Transform3D, half_extents: Vector2, fade: float, alpha: float, color := ArtPalette.SHADOW, corner_steps := 6) -> void:
	var inner := Color(color.r, color.g, color.b, alpha)
	var outer := Color(color.r, color.g, color.b, 0.0)
	# Outline of the inner rect, walked counter-clockwise, with the outward direction per point.
	var ring: Array = []
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for ci in 4:
		var corner: Vector2 = corners[ci] * half_extents
		var start := PI * 0.5 * ci
		for s in corner_steps + 1:
			var a := start + PI * 0.5 * s / corner_steps
			ring.append([corner, Vector2(cos(a), sin(a))])
	var centre := xf * Vector3.ZERO
	for i in ring.size():
		var p0: Vector2 = ring[i][0]
		var p1: Vector2 = ring[(i + 1) % ring.size()][0]
		var o0: Vector2 = p0 + ring[i][1] * fade
		var o1: Vector2 = p1 + ring[(i + 1) % ring.size()][1] * fade
		var v_p0 := xf * Vector3(p0.x, 0.0, p0.y)
		var v_p1 := xf * Vector3(p1.x, 0.0, p1.y)
		var v_o0 := xf * Vector3(o0.x, 0.0, o0.y)
		var v_o1 := xf * Vector3(o1.x, 0.0, o1.y)
		var up := (xf.basis * Vector3.UP).normalized()
		if p0.distance_to(p1) > 0.00001:
			_raw_tri([centre, v_p0, v_p1], up, [inner, inner, inner])
		_raw_tri([v_p0, v_o0, v_o1], up, [inner, outer, outer])
		_raw_tri([v_p0, v_o1, v_p1], up, [inner, outer, inner])


func add_blob(xf: Transform3D, radius: float, alpha: float) -> void:
	add_soft_rect(xf, Vector2(radius * 0.35, radius * 0.35), radius * 0.65, alpha)


## One world-space triangle with a colour per corner (sRGB), no vertex AO, lit by its own face
## normal turned towards `facing`: ground and water built point by point (MapIsland, the map's
## terrain and sea), where a shape primitive does not fit.
func add_triangle(points: Array, colors: Array, facing := Vector3.UP) -> void:
	var face: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	if face.length() < 1e-10:
		return
	var n := face.normalized()
	if n.dot(facing) < 0.0:
		n = -n
	_raw_tri(points, n, colors)


## add_triangle's front face towards `facing`, lit by `normal` instead of its own face: a backdrop
## whose vertex colours must show as they are (LabWorld's horizon haze: a normal along the sun's
## level direction is lit full with no sky fill).
func add_triangle_lit(points: Array, colors: Array, facing: Vector3, normal: Vector3) -> void:
	var face: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	if face.length() < 1e-10:
		return
	for i in ([0, 1, 2] if face.dot(facing) < 0.0 else [0, 2, 1]):
		_verts.append(points[i])
		_normals.append(normal)
		_colors.append((colors[i] as Color).srgb_to_linear())


## Vertices appended so far (tests: how much one call added).
func vertex_count() -> int:
	return _verts.size()


## Tags the vertices appended since vertex `from` with `tag` (> 0; UV.x of the committed mesh).
func tag_from(from: int, tag: int) -> void:
	_pad_tags()
	for i in range(from, _verts.size()):
		_tags[i] = Vector2(float(tag), 0.0)


## The tag of vertex `i` (tests; 0 = none).
func tag_of(i: int) -> int:
	return int(_tags[i].x) if i < _tags.size() else 0


func _pad_tags() -> void:
	if _tags.size() < _verts.size():
		var from := _tags.size()
		_tags.resize(_verts.size())
		for i in range(from, _tags.size()):
			_tags[i] = Vector2.ZERO



# --- internals ---------------------------------------------------------------------------------

## Grid coordinates along one axis of a rounded box: the bevel band at each end is split so the
## projected normals step by equal angles (tan spacing, 45 deg per face side).
static func _bevel_coords(half: float, r: float, segments: int) -> PackedFloat32Array:
	var coords := PackedFloat32Array()
	if r <= 0.0 or segments <= 0:
		coords.append(-half)
		coords.append(half)
		return coords
	var inner := half - r
	for s in range(segments, 0, -1):
		coords.append(-inner - r * tan(PI * 0.25 * s / segments))
	coords.append(-inner)
	if inner > 0.0001:
		coords.append(inner)
	for s in range(1, segments + 1):
		coords.append(inner + r * tan(PI * 0.25 * s / segments))
	return coords


static func _axis_vector(axis: int, sign_value: float) -> Vector3:
	var v := Vector3.ZERO
	v[axis] = sign_value
	return v


func _quad_local(xf: Transform3D, q: Array, half_y: float, color: Color, top_color: Variant) -> void:
	_tri(xf, [q[0][0], q[1][0], q[2][0]], [q[0][1], q[1][1], q[2][1]], -half_y, color, top_color)
	_tri(xf, [q[0][0], q[2][0], q[3][0]], [q[0][1], q[2][1], q[3][1]], -half_y, color, top_color)


## One triangle in shape-local space. base_y = the shape's local bottom (for the vertex AO).
## Colours are given in sRGB and stored linear (the shader writes linear ALBEDO).
## Winding is fixed here: Godot front faces are clockwise seen from the front.
func _tri(xf: Transform3D, p: Array, n: Array, base_y: float, color: Color, top_color: Variant) -> void:
	var avg: Vector3 = (n[0] + n[1] + n[2])
	var face: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if face.length() < 1e-10:
		return
	if face.dot(avg) > 0.0:
		p = [p[0], p[2], p[1]]
		n = [n[0], n[2], n[1]]
		face = -face
	var flat_n: Vector3 = -face.normalized()
	# Normals use the inverse transpose so a non-uniformly scaled shape (the rocks) stays lit right.
	var normal_basis := xf.basis.inverse().transposed()
	for i in 3:
		var local: Vector3 = p[i]
		var c := color
		if top_color != null and (n[i] as Vector3).y > 0.7:
			c = top_color
		var ao := lerpf(ao_min, 1.0, clampf((local.y - base_y) / maxf(ao_height, 0.0001), 0.0, 1.0))
		c = Color(c.r * ao, c.g * ao, c.b * ao, c.a).srgb_to_linear()
		_verts.append(xf * local)
		_normals.append((normal_basis * (flat_n if flat else n[i] as Vector3)).normalized())
		_colors.append(c)


func _raw_tri(p: Array, normal: Vector3, c: Array) -> void:
	var face: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if face.length() < 1e-10:
		return
	var order := [0, 1, 2] if face.dot(normal) < 0.0 else [0, 2, 1]
	for i in order:
		_verts.append(p[i])
		_normals.append(normal)
		_colors.append((c[i] as Color).srgb_to_linear())
