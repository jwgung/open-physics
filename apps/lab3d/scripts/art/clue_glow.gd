## The clue's faint glow (2026-10-29 user: while Puppy says a clue, "해당 포인트를 희미하게 강조"): a
## soft warm light on the thing the clue is about, slowly pulsing, that fades in while the clue is
## told and out when its box closes. Two shapes from one material recipe:
## - `halo(radius)`: a round soft glow facing the camera (billboard) at an object's centre. The
##   object in front of it hides its middle, so it reads as a faint rim of light around the object
##   (the labs' game objects: a crate, the ice, a house, a clock …; also in space or under water).
## - `ring(radius)`: a soft ring with a faint fill lying flat (a stage on the map, a floor button).
## Cheap on purpose: one small mesh (vertex alpha, no texture), unshaded additive, no depth write, no
## light, no new shader; built only when a clue first asks for it, hidden when faded out. Visual only:
## nothing reads it. Faint: its brightest pulse adds PEAK of the warm colour at the very centre.
class_name ClueGlow
extends MeshInstance3D

const COLOR := Color(1.0, 0.84, 0.42)    # warm lamp yellow (the lit spots' warmth, LAMP_ON's family)
const PEAK := 0.55                       # the brightest alpha (at the centre, top of the pulse)
const LOW := 0.45                        # the pulse's low as a share of PEAK (it never goes dark)
const PERIOD_S := 1.8                    # one slow breath
const FADE_IN_S := 0.45
const FADE_OUT_S := 0.6
const SEGMENTS := 24

static var _meshes := {}

## Asked on (the clue is told) or off; `level` follows it (0 hidden … 1 full).
var on := false
var level := 0.0
var _t := 0.0
var _material: StandardMaterial3D


## A camera-facing soft glow of `radius` (m) for an object's centre.
static func halo(radius: float) -> ClueGlow:
	var glow := ClueGlow.new()
	glow.name = "ClueHalo"
	glow.mesh = _mesh("halo")
	glow.scale = Vector3.ONE * radius
	glow._make_material(true)
	return glow


## A flat soft ring of outer `radius` (m) lying on the xz plane (a stage, a button).
static func ring(radius: float) -> ClueGlow:
	var glow := ClueGlow.new()
	glow.name = "ClueRing"
	glow.mesh = _mesh("ring")
	glow.scale = Vector3.ONE * radius
	glow._make_material(false)
	return glow


## Unit meshes (radius 1): "halo" in the xy plane (alpha high in the middle, 0 at the rim), "ring"
## in the xz plane (a faint fill, a soft band near the rim, 0 at the rim).
static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	# [radius share, alpha share] from the centre out. The halo stays bright out to half its radius:
	# its middle is behind the object, the part that shows is the rim (device check 2026-10-29: the
	# first, steeper falloff hardly showed around the free fall's house on the bright grass).
	var bands: Array = [[0.0, 1.0], [0.55, 0.8], [0.8, 0.38], [1.0, 0.0]] if kind == "halo" \
		else [[0.0, 0.22], [0.6, 0.3], [0.82, 1.0], [1.0, 0.0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var point := func(r: float, a: float) -> Vector3:
		return Vector3(cos(a) * r, sin(a) * r, 0.0) if kind == "halo" else Vector3(cos(a) * r, 0.0, sin(a) * r)
	for s in SEGMENTS:
		var a0 := TAU * s / SEGMENTS
		var a1 := TAU * (s + 1) / SEGMENTS
		for k in bands.size() - 1:
			var r0: float = bands[k][0]
			var r1: float = bands[k + 1][0]
			var c0 := Color(1.0, 1.0, 1.0, float(bands[k][1]))
			var c1 := Color(1.0, 1.0, 1.0, float(bands[k + 1][1]))
			var quad := [[point.call(r0, a0), c0], [point.call(r1, a0), c1], [point.call(r1, a1), c1],
				[point.call(r0, a0), c0], [point.call(r1, a1), c1], [point.call(r0, a1), c0]]
			for v in quad:
				st.set_color(v[1])
				st.add_vertex(v[0])
	_meshes[kind] = st.commit()
	return _meshes[kind]


func _make_material(billboard: bool) -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.vertex_color_use_as_albedo = true
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_material.billboard_keep_scale = true
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	_apply()


func set_on(value: bool) -> void:
	on = value


## Seen now (tests): asked on, or still fading out.
func shown() -> bool:
	return visible and level > 0.0


func _process(delta: float) -> void:
	step(delta)


## Moves the fade and the pulse on by `delta` s (tests step it).
func step(delta: float) -> void:
	_t += delta
	level = move_toward(level, 1.0 if on else 0.0, delta / (FADE_IN_S if on else FADE_OUT_S))
	_apply()


## The pulse now: LOW … 1 (a slow sine).
func pulse() -> float:
	return lerpf(LOW, 1.0, 0.5 - 0.5 * cos(TAU * _t / PERIOD_S))


func _apply() -> void:
	visible = level > 0.0
	if _material != null:
		_material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, PEAK * level * pulse())
