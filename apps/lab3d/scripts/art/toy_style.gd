## Task 2c style mockups for the incline experiment (`--style=a|b|c`, no argument = the Task 2a
## look). A style only replaces what is drawn: meshes, colours, background and decoration. Physics
## bodies, collision shapes and every displayed number stay exactly as they are.
##   a  playroom desk  warm pastel, soft rounded toy blocks on a wooden desk
##   b  grass island   vivid primaries, faceted low-poly, a floating grass island under a blue sky
##   c  studio stage   calm natural colours, very round clay-like shapes on a seamless backdrop
## Lighting is "baked" in toy.gdshader (no engine light, no realtime shadow on any tier); contact
## comes from vertex AO and soft blob shadows. All static decoration is one mesh (1 draw call).
class_name ToyStyle
extends RefCounted

const SHADER := preload("res://scripts/art/toy.gdshader")
const IDS := ["a", "b", "c"]

var id := ""
var p: Dictionary = {}          # palette + shape parameters of this style
var toy_material: ShaderMaterial
var shadow_mat: StandardMaterial3D

var _world: Node3D
var _ramp_shadow: MeshInstance3D
var _incline_length := 8.0


## Returns null for an unknown / empty id (the Task 2a look is kept).
static func create(style_id: String) -> ToyStyle:
	if style_id not in IDS:
		return null
	var style := ToyStyle.new()
	style.id = style_id
	style.p = _params(style_id)
	style._make_materials()
	return style


static func _params(style_id: String) -> Dictionary:
	match style_id:
		"a":
			return {
				"bg": Color("ffe7d6"), "flat": false,
				"lit": Color("fff6ea"), "shade": Color("c7b0d6"), "threshold": 0.5, "softness": 0.2, "rim": 0.12, "rim_color": Color("fff3e6"), "sky": 0.08,
				"shadow": Color("4a2a45"), "shadow_alpha": 0.24,
				"incline": Color("8fdcc2"), "incline_top": Color("a9ecd4"), "incline_r": 0.12, "incline_seg": 2, "incline_thick": 0.55, "lips": Color("ffffff"),
				"stand": Color("b8a4f0"), "stand_r": 0.12, "stand_w": 0.5, "foot": Color("a08ae6"),
				"box": Color("ff8a73"), "box_top": Color("ffa08c"), "box_r": 0.08, "box_seg": 3,
				"mark": Color("ffffff"),
				"dust": Color("fff1e0"),
			}
		"b":
			return {
				"bg": Color("62c0ff"), "flat": true,
				"lit": Color("ffffff"), "shade": Color("7d8ed8"), "threshold": 0.55, "softness": 0.03, "rim": 0.0, "rim_color": Color.WHITE, "sky": 0.1,
				"shadow": Color("14234d"), "shadow_alpha": 0.32,
				"incline": Color("ffc61a"), "incline_top": Color("ffd84a"), "incline_r": 0.06, "incline_seg": 1, "incline_thick": 0.5, "lips": null,
				"stand": Color("2d7cf6"), "stand_r": 0.05, "stand_w": 0.5, "foot": Color("1f62d6"),
				"box": Color("ff3b3b"), "box_top": Color("ff5a4f"), "box_r": 0.05, "box_seg": 1,
				"mark": Color("ffffff"),
				"dust": Color("e9f5d8"),
			}
		_:
			return {
				"bg": Color("e8e2d6"), "flat": false,
				"lit": Color("fff8ee"), "shade": Color("aaa298"), "threshold": 0.42, "softness": 0.32, "rim": 0.22, "rim_color": Color("fff4e0"), "sky": 0.06,
				"shadow": Color("4a3b2e"), "shadow_alpha": 0.26,
				"incline": Color("8fae8b"), "incline_top": Color("a2bf9d"), "incline_r": 0.16, "incline_seg": 3, "incline_thick": 0.7, "lips": null,
				"stand": Color("c9805e"), "stand_r": 0.2, "stand_w": 0.55, "foot": Color("b86f50"),
				"box": Color("e2b14a"), "box_top": Color("ebc062"), "box_r": 0.13, "box_seg": 3,
				"mark": Color("f7f1e6"),
				"dust": Color("f1ebdf"),
			}


func _make_materials() -> void:
	toy_material = ShaderMaterial.new()
	toy_material.shader = SHADER
	toy_material.set_shader_parameter("lit_color", p.lit)
	toy_material.set_shader_parameter("shade_color", p.shade)
	toy_material.set_shader_parameter("threshold", p.threshold)
	toy_material.set_shader_parameter("softness", p.softness)
	toy_material.set_shader_parameter("rim_strength", p.rim)
	toy_material.set_shader_parameter("rim_color", p.rim_color)
	toy_material.set_shader_parameter("sky_fill", p.sky)
	shadow_mat = StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.vertex_color_use_as_albedo = true
	shadow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shadow_mat.render_priority = -1


func builder() -> ToyMeshBuilder:
	var b := ToyMeshBuilder.new()
	b.flat = p.flat
	return b


func shadow_builder() -> ToyMeshBuilder:
	return ToyMeshBuilder.new()


func instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func shadow_color(alpha_scale := 1.0) -> float:
	return p.shadow_alpha * alpha_scale


## Restyles the incline world. `parts`: environment, sun, floor (MeshInstance3D), incline
## (MeshInstance3D, size `incline_size`), mark, stand (+ `stand_height`), box (MeshInstance3D),
## box_body (RigidBody3D), box_size, pivot, experiment.
func dress(world: Node3D, parts: Dictionary) -> void:
	_world = world
	var environment: Environment = parts.environment
	environment.background_color = p.bg
	var sun: DirectionalLight3D = parts.sun
	sun.visible = false          # lighting lives in the shader
	sun.shadow_enabled = false
	(parts.floor as MeshInstance3D).visible = false

	var incline: MeshInstance3D = parts.incline
	var size: Vector3 = parts.incline_size
	_incline_length = size.x
	# Thicker than the 0.3 m collision box, growing downwards only: the top face (what the box
	# slides on) stays exactly where the collision surface is.
	var b := builder()
	b.ao_min = 0.85
	var thick: float = p.incline_thick
	var visual := Vector3(size.x, thick, size.z)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, (size.y - thick) * 0.5, 0.0)), visual, p.incline_r, p.incline_seg, p.incline, p.incline_top)
	if p.lips != null:   # low side rails along both long edges, like a toy slide
		for z in [-1.0, 1.0]:
			b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, size.y * 0.5 + 0.04, z * (size.z * 0.5 - 0.07))), Vector3(size.x - 0.1, 0.2, 0.14), 0.06, 2, p.lips)
	_restyle(incline, b.commit())

	var mark: MeshInstance3D = parts.mark
	b = builder()
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D.IDENTITY, Vector3(0.07, 0.02, size.z - 0.25), 0.009, 1, p.mark)
	_restyle(mark, b.commit())
	mark.position.y += 0.005

	var stand: MeshInstance3D = parts.stand
	var height: float = parts.stand_height
	b = builder()
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), Vector3(p.stand_w, height, p.stand_w), p.stand_r, 2, p.stand)
	b.ao_height = 0.12
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, -height * 0.5, 0.0)), 0.75, 0.62, 0.16, 16 if not p.flat else 8, p.foot)
	_restyle(stand, b.commit())

	var box_mesh: MeshInstance3D = parts.box
	var box_size: float = parts.box_size
	b = builder()
	b.ao_height = box_size * 0.6
	b.add_rounded_box(Transform3D.IDENTITY, Vector3.ONE * box_size, p.box_r, p.box_seg, p.box, p.box_top)
	_restyle(box_mesh, b.commit())

	# Static decoration and its blob shadows.
	var deco := builder()
	var shadows := shadow_builder()
	match id:
		"a":
			_build_playroom(deco, shadows)
		"b":
			_build_island(deco, shadows)
		_:
			_build_studio(deco, shadows)
	# Stand foot shadow.
	shadows.add_blob(Transform3D(Basis(), Vector3(stand.position.x, 0.012, stand.position.z)), 0.9, shadow_color(0.9))
	world.add_child(instance(deco.commit(), toy_material))
	if not shadows.is_empty():
		var s := instance(shadows.commit(), shadow_mat)
		s.name = "StaticShadows"
		world.add_child(s)
	_ramp_shadow = instance(ArrayMesh.new(), shadow_mat)
	world.add_child(_ramp_shadow)

	var juice := ToyJuice.new()
	juice.setup(self, parts.experiment, parts.box_body, box_mesh, box_size)
	world.add_child(juice)


## The incline casts a soft shadow straight below it (its footprint changes with the angle).
func angle_changed(angle_deg: float) -> void:
	if _ramp_shadow == null:
		return
	var s := shadow_builder()
	var half := _incline_length * 0.5 * cos(deg_to_rad(angle_deg))
	s.add_soft_rect(Transform3D(Basis(), Vector3(0.0, 0.01, 0.0)), Vector2(half - 0.3, 0.7), 0.7, shadow_color(0.45))
	_ramp_shadow.mesh = s.commit()


func _restyle(mi: MeshInstance3D, mesh: Mesh) -> void:
	mi.mesh = mesh
	mi.material_override = toy_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- environments ------------------------------------------------------------------------------

func _at(x: float, y: float, z: float, yaw_deg := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(x, y, z))


## a: wooden desk top with pastel toys.
func _build_playroom(b: ToyMeshBuilder, s: ToyMeshBuilder) -> void:
	b.ao_min = 0.9
	b.add_rounded_box(_at(-1.5, -0.35, -0.5), Vector3(22.0, 0.7, 12.0), 0.25, 2, Color("e9bf88"), Color("f6d6a8"))
	# Plank lines on the desk (thin slightly darker strips).
	for z in [-3.5, -0.5, 2.5]:
		b.add_rounded_box(_at(-1.5, 0.002, z), Vector3(21.6, 0.004, 0.05), 0.0, 0, Color("e2b57d"))
	b.ao_min = 0.72
	# Stacked toy blocks (back right).
	b.ao_height = 0.4
	b.add_rounded_box(_at(3.6, 0.45, -3.6, 12.0), Vector3(0.9, 0.9, 0.9), 0.14, 2, Color("ffb3c7"), Color("ffc4d3"))
	b.add_rounded_box(_at(4.7, 0.45, -3.3, -8.0), Vector3(0.9, 0.9, 0.9), 0.14, 2, Color("ffe08a"), Color("ffe9a8"))
	b.add_rounded_box(_at(4.15, 1.35, -3.45, 30.0), Vector3(0.9, 0.9, 0.9), 0.14, 2, Color("c6b3ff"), Color("d5c6ff"))
	s.add_soft_rect(_at(4.15, 0.012, -3.45), Vector2(1.0, 0.5), 0.45, shadow_color())
	# Ring stacker (back left).
	var rings := [Color("ff9fb4"), Color("ffc08a"), Color("ffe58f"), Color("a9e7b9"), Color("9fd0ff")]
	b.ao_height = 0.08
	for i in rings.size():
		var r := 0.85 - i * 0.12
		b.add_cylinder(_at(-3.6, i * 0.26, -4.2), r, r * 0.92, 0.26, 18, rings[i])
	b.add_cylinder(_at(-3.6, 1.3, -4.2), 0.12, 0.12, 0.35, 10, Color("c6b3ff"))
	b.add_sphere(_at(-3.6, 1.72, -4.2), 0.2, 6, 10, Color("c6b3ff"))
	s.add_blob(_at(-3.6, 0.012, -4.2), 1.25, shadow_color())
	# Ball (left front).
	b.ao_height = 0.6
	b.add_sphere(_at(-8.2, 0.7, 2.3), 0.7, 8, 14, Color("9fd3ff"))
	s.add_blob(_at(-8.2, 0.012, 2.3), 0.95, shadow_color())
	# Crayon lying on the desk (front right).
	var crayon := Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90.0)).rotated(Vector3.UP, deg_to_rad(-25.0)), Vector3(3.4, 0.16, 2.6))
	b.ao_height = 0.0001
	b.ao_min = 1.0
	b.add_cylinder(crayon, 0.16, 0.16, 1.6, 8, Color("ff9a5c"))
	b.add_cylinder(crayon.translated_local(Vector3(0.0, 1.6, 0.0)), 0.16, 0.02, 0.32, 8, Color("ff9a5c"))
	b.add_cylinder(crayon.translated_local(Vector3(0.0, 0.25, 0.0)), 0.165, 0.165, 0.5, 8, Color("fff3e0"), false)
	s.add_soft_rect(Transform3D(Basis(Vector3.UP, deg_to_rad(-25.0)), Vector3(3.4 + 0.75, 0.012, 2.6 - 0.35)), Vector2(0.85, 0.08), 0.25, shadow_color(0.8))
	# Back wall (soft pastel wallpaper with a skirting board), far behind the desk.
	b.ao_min = 1.0
	b.add_rounded_box(_at(-1.5, 5.0, -9.5), Vector3(70.0, 14.0, 0.4), 0.0, 0, Color("ffe1cf"))
	for x in range(-30, 30, 3):
		b.add_rounded_box(_at(x, 5.0, -9.28), Vector3(1.2, 14.0, 0.02), 0.0, 0, Color("ffd8c4"))


## b: floating grass island under a blue sky, faceted primaries.
func _build_island(b: ToyMeshBuilder, s: ToyMeshBuilder) -> void:
	b.ao_min = 0.95
	b.ao_height = 0.3
	b.add_cylinder(_at(-1.5, -0.5, -0.8), 11.0, 11.0, 0.5, 14, Color("4fbf3b"), true, Color("5fd04a"))
	b.ao_min = 0.7
	b.ao_height = 4.0
	b.add_cylinder(_at(-1.5, -4.2, -0.8), 4.0, 11.0, 3.7, 14, Color("b8743f"), false)
	b.add_cylinder(_at(-1.5, -6.5, -0.8), 1.2, 4.0, 2.3, 9, Color("9a5c2e"), false)
	# Trees: trunk + two cones.
	for t in [[-7.0, -4.8, 1.0], [5.5, -4.6, 1.2], [-9.6, 1.4, 0.8], [7.4, -1.2, 0.9], [1.0, -6.6, 1.1]]:
		var x: float = t[0]
		var z: float = t[1]
		var k: float = t[2]
		b.ao_min = 0.8
		b.ao_height = 0.4 * k
		b.add_cylinder(_at(x, 0.0, z), 0.2 * k, 0.16 * k, 0.8 * k, 6, Color("8a5129"))
		b.ao_min = 0.85
		b.add_cylinder(_at(x, 0.7 * k, z, 15.0), 1.1 * k, 0.0, 1.5 * k, 7, Color("1fae4b"))
		b.add_cylinder(_at(x, 1.5 * k, z, 40.0), 0.8 * k, 0.0, 1.2 * k, 7, Color("29c457"))
		s.add_blob(_at(x, 0.012, z), 1.3 * k, shadow_color())
	# Rocks and flowers.
	b.ao_min = 0.75
	b.ao_height = 0.3
	for r in [[3.2, 3.6, 0.45], [-6.0, 4.2, 0.35], [6.6, 2.4, 0.3]]:
		var xf := Transform3D(Basis().scaled(Vector3(1.3, 0.75, 1.0)), Vector3(r[0], r[2] * 0.5, r[1]))
		b.add_sphere(xf, r[2], 4, 6, Color("aab3c4"))
		s.add_blob(_at(r[0], 0.012, r[1]), r[2] * 1.8, shadow_color())
	var petals := [Color("ffd400"), Color("ff4fa3"), Color("ffffff"), Color("ff7a1a")]
	var spots := [[-4.0, 3.0], [-3.4, 3.5], [1.8, 4.4], [5.0, 4.0], [-8.4, -1.6], [2.6, -3.6], [-1.6, -5.2]]
	b.ao_min = 1.0
	for i in spots.size():
		var f: Array = spots[i]
		b.add_cylinder(_at(f[0], 0.0, f[1]), 0.03, 0.03, 0.3, 4, Color("2a9a3e"), false)
		b.add_sphere(_at(f[0], 0.34, f[1]), 0.13, 3, 5, petals[i % petals.size()])
	# Clouds far behind.
	for c in [[-10.0, 8.5, -16.0, 1.6], [3.0, 10.5, -18.0, 2.0], [12.0, 7.5, -14.0, 1.4]]:
		var cx: float = c[0]
		var cy: float = c[1]
		var cz: float = c[2]
		var k: float = c[3]
		for puff in [[0.0, 0.0, 1.0], [1.1, -0.2, 0.75], [-1.1, -0.25, 0.7], [0.4, 0.5, 0.65]]:
			b.add_sphere(_at(cx + puff[0] * k, cy + puff[1] * k, cz), puff[2] * k, 4, 7, Color("ffffff"))


## c: seamless studio backdrop, round turntable stage, a few calm props.
func _build_studio(b: ToyMeshBuilder, s: ToyMeshBuilder) -> void:
	var profile := PackedVector2Array()
	var colors := PackedColorArray()
	var floor_col := Color("e6e0d4")
	var wall_col := Color("c9d6d0")
	profile.append(Vector2(12.0, -0.3))
	colors.append(floor_col)
	var radius := 5.0
	var corner_z := -6.0
	for i in 9:
		var a := PI * 0.5 * i / 8.0
		profile.append(Vector2(corner_z - sin(a) * radius, -0.3 + radius - cos(a) * radius))
		colors.append(floor_col.lerp(wall_col, float(i) / 8.0))
	profile.append(Vector2(corner_z - radius, 16.0))
	colors.append(wall_col.lerp(Color("e6eadc"), 0.6))
	b.ao_min = 1.0
	b.add_sweep(Transform3D(Basis(), Vector3(-1.0, 0.0, 0.0)), profile, 90.0, colors)
	# Turntable stage.
	b.ao_min = 0.8
	b.ao_height = 0.3
	b.add_cylinder(_at(-1.8, -0.3, 0.0), 8.6, 8.8, 0.3, 40, Color("d9c9ad"), true, Color("f0e6d4"))
	s.add_soft_rect(_at(-1.8, -0.295, 0.0), Vector2(8.0, 8.0), 1.2, shadow_color(0.5), Color.BLACK, 8)
	# Potted plant (back right).
	b.ao_min = 0.75
	b.ao_height = 0.5
	b.add_cylinder(_at(4.6, 0.0, -3.4), 0.55, 0.75, 1.0, 18, Color("c9805e"), true, Color("8a5a3c"))
	b.ao_height = 0.6
	b.add_sphere(_at(4.6, 1.55, -3.4), 0.8, 7, 12, Color("8fae8b"))
	b.add_sphere(_at(4.25, 2.05, -3.2), 0.5, 6, 10, Color("9dbb98"))
	s.add_blob(_at(4.6, 0.012, -3.4), 1.0, shadow_color())
	# Pebbles.
	for r in [[-7.4, 2.4, 0.55, Color("b9a48c")], [-6.6, 3.1, 0.35, Color("9aa58c")], [2.6, 3.3, 0.4, Color("d2c3ae")], [-4.6, -4.4, 0.7, Color("a9b2a0")]]:
		var xf := Transform3D(Basis().scaled(Vector3(1.35, 0.65, 1.1)), Vector3(r[0], r[2] * 0.6, r[1]))
		b.add_sphere(xf, r[2], 6, 10, r[3])
		s.add_blob(_at(r[0], 0.012, r[1]), r[2] * 1.9, shadow_color())
