## Shared art kit of the grass island style (Phase 1 Task 2c, apps/lab3d/docs/art-direction.md):
## the lit material, blob shadow material, mesh builders, the 3D environment and the ground every
## experiment stands on (its corner of the big island, LabWorld). Experiments build their own props
## with builder() and put them under their physics bodies as plain MeshInstance3D nodes (visual only).
## No engine light and no realtime shadow on any tier: lighting is "baked" in art_lit.gdshader,
## contact comes from vertex AO and blob shadows (ArtMeshBuilder.add_blob / add_soft_rect).
class_name ArtKit
extends RefCounted

const SHADER := preload("res://scripts/art/art_lit.gdshader")
const TEXTURE_SHADER := preload("res://scripts/art/art_lit_tex.gdshader")
## The characters' storybook look (Task 4g2, art-direction.md section 11): two-step cel shading and
## a brown inverted-hull outline as its next pass (toon_material). Characters only: the apparatus,
## props and island keep the island light.
const TOON_SHADER := preload("res://scripts/art/art_toon_tex.gdshader")
const OUTLINE_SHADER := preload("res://scripts/art/art_outline.gdshader")
## Outline width: the Blender reference renders' 0.010 m, at least OUTLINE_PIXELS render-target
## pixels of the 3D view (art_outline.gdshader, art-direction.md section 11).
const OUTLINE_WORLD := 0.010
const OUTLINE_PIXELS := 1.5
## The cel step's shade multiplier (linear; Blender ramp 0.86 x (0.97, 0.90, 0.93)) and where it
## sits in N.L (art_toon_tex.gdshader).
const TOON_SHADE := Vector4(0.834, 0.774, 0.8, 1.0)
const TOON_THRESHOLD := -0.03
## The lab's own ground (build_island): what was the floating island's 14-sided top of circumradius
## ISLAND_RADIUS around its centre is now the middle of a flat clearing (LabWorld.CLEAR, larger) in
## the big island's land; the cast stands within it and the projectile's fences inside its apothem.
const ISLAND_RADIUS := 11.0
## Island decoration, relative to the island centre: trees (x, z, size), rocks (x, z, radius),
## flowers (x, z). island_obstacles() turns them into footprints (characters stand clear of them).
const TREES := [[-5.5, -4.0, 1.0], [7.0, -3.8, 1.2], [-8.1, 2.2, 0.8], [8.9, -0.4, 0.9], [2.5, -5.8, 1.1]]
const ROCKS := [[4.7, 4.4, 0.45], [-4.5, 5.0, 0.35], [8.1, 3.2, 0.3]]
const FLOWERS := [[-2.5, 3.8], [-1.9, 4.3], [3.3, 5.2], [6.5, 4.8], [-6.9, -0.8], [4.1, -2.8], [-0.1, -4.4]]
const ISLAND_SIDES := 14   # the old top's sides (tests: the fences inside its apothem)
const SUN_DIR := Vector3(-0.35, 0.85, 0.45)   # world direction towards the (baked) light
const LIGHT_THRESHOLD := 0.55
const LIGHT_SOFTNESS := 0.03
const SKY_FILL := 0.1

## The yarn ball (Task 4g, 2026-10-23 user request: every ball is a yarn ball, which cats like):
## art_src/props/yarn_ball.py -> assets/props/yarn_ball.glb, a sphere of radius YARN_RADIUS with a
## grey wound-yarn texture. Loaded once.
const YARN_SCENE := preload("res://assets/props/yarn_ball.glb")
const YARN_RADIUS := 0.25

## The parcel box (Task 4g, 2026-10-23 user decision: the boxes look like parcels):
## art_src/props/parcel_box.py -> assets/props/parcel_box.glb, a 1 m cube with a cardboard texture
## whose tape and label stripe (alpha 0) take an accent colour.
const PARCEL_SCENE := preload("res://assets/props/parcel_box.glb")

static var _lit: ShaderMaterial
static var _parcel_src: Mesh
static var _parcel_meshes := {}   # size -> the parcel baked to it
static var _yarn_mesh: Mesh
static var _yarn_texture_mean := -1.0
static var _yarn_materials := {}   # Color -> ShaderMaterial (one per colour, shared by its balls)
static var _parcel_materials := {} # accent Color -> ShaderMaterial
static var _shadow: StandardMaterial3D
static var _outline: ShaderMaterial


## The one material of every solid prop (vertex colours + baked light ramp).
static func lit_material() -> ShaderMaterial:
	if _lit == null:
		_lit = ShaderMaterial.new()
		_lit.shader = SHADER
		_lit.set_shader_parameter("sun_dir", SUN_DIR)
		_lit.set_shader_parameter("lit_color", ArtPalette.LIGHT)
		_lit.set_shader_parameter("shade_color", ArtPalette.SHADE)
		_lit.set_shader_parameter("threshold", LIGHT_THRESHOLD)
		_lit.set_shader_parameter("softness", LIGHT_SOFTNESS)
		_lit.set_shader_parameter("sky_fill", SKY_FILL)
	return _lit


## The same light on a textured model (art_lit_tex.gdshader: a model with one texture atlas and
## smooth normals, the yarn ball and parcel box; the characters use toon_material since Task 4g2):
## a softer ramp and a lighter shade side than the faceted props.
static func lit_texture_material(texture: Texture2D, softness := 0.18, shade_mix := 0.35) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TEXTURE_SHADER
	m.set_shader_parameter("albedo_texture", texture)
	m.set_shader_parameter("sun_dir", SUN_DIR)
	m.set_shader_parameter("lit_color", ArtPalette.LIGHT)
	m.set_shader_parameter("shade_color", ArtPalette.SHADE)
	m.set_shader_parameter("threshold", LIGHT_THRESHOLD)
	m.set_shader_parameter("softness", softness)
	m.set_shader_parameter("sky_fill", SKY_FILL)
	m.set_shader_parameter("shade_mix", shade_mix)
	return m


## A character's storybook material (Task 4g2): its texture atlas in two flat cel steps under the
## island sun, with the shared brown outline (outline_material) as the next pass. One per atlas;
## every mesh of the character shares it. The bread cat now, Dugi (dugi.glb, one atlas too) later.
static func toon_material(texture: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo_texture", texture)
	m.set_shader_parameter("sun_dir", SUN_DIR)
	m.set_shader_parameter("shade", TOON_SHADE)
	m.set_shader_parameter("threshold", TOON_THRESHOLD)
	m.next_pass = outline_material()
	return m


## The brown inverted-hull outline pass (art_outline.gdshader), shared by every character.
static func outline_material() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = OUTLINE_SHADER
		var c := ArtPalette.OUTLINE.srgb_to_linear()
		_outline.set_shader_parameter("color", Vector4(c.r, c.g, c.b, 1.0))   # linear, as a vector (see yarn_ball)
		_outline.set_shader_parameter("world_width", OUTLINE_WORLD)
		_outline.set_shader_parameter("screen_pixels", OUTLINE_PIXELS)
	return _outline


## A yarn ball of `radius` in `color` (the grey texture times the colour, the island light; the
## strands in many directions show it turning; one cached material per colour, shared: never change
## it on an instance). The node is scaled to the radius: a parent that
## animates it (ArtJuice) must be another node.
static func yarn_ball(radius: float, color: Color) -> MeshInstance3D:
	if _yarn_mesh == null:
		var model: Node = YARN_SCENE.instantiate()
		_yarn_mesh = (model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		model.free()
	if not _yarn_materials.has(color):
		var texture := (_yarn_mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture
		var material := lit_texture_material(texture, 0.18, 0.6)
		# Divided by the texture's mean (linear): the ball's average is its colour, the strands lighter
		# and darker shades of it (2026-10-23 user request: as vivid as the palette colours).
		var lin := color.srgb_to_linear()
		var k := 1.0 / _yarn_mean(texture)
		# A Vector4, not a Color: the renderers convert Color uniforms differently (Compatibility never,
		# Mobile always), a vector reaches the shader as it is (linear).
		material.set_shader_parameter("tint", Vector4(lin.r * k, lin.g * k, lin.b * k, 1.0))
		_yarn_materials[color] = material
	var ball := instance(_yarn_mesh, _yarn_materials[color])
	ball.scale = Vector3.ONE * (radius / YARN_RADIUS)
	return ball


## Mean of the yarn texture in linear light (measured once).
static func _yarn_mean(texture: Texture2D) -> float:
	if _yarn_texture_mean < 0.0:
		var image := texture.get_image()
		image.decompress()
		image.resize(64, 32, Image.INTERPOLATE_BILINEAR)
		var sum := 0.0
		for y in image.get_height():
			for x in image.get_width():
				sum += image.get_pixel(x, y).srgb_to_linear().r
		_yarn_texture_mean = maxf(sum / (image.get_width() * image.get_height()), 0.05)
	return _yarn_texture_mean


static func yarn_mesh() -> Mesh:
	return _yarn_mesh


## The parcel box mesh baked to a cube of `size` (uniform: the texture is not stretched; cached).
static func parcel_mesh(size: float) -> Mesh:
	if _parcel_src == null:
		var model: Node = PARCEL_SCENE.instantiate()
		_parcel_src = (model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		model.free()
	if not _parcel_meshes.has(size):
		var st := SurfaceTool.new()
		st.append_from(_parcel_src, 0, Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3.ZERO))
		_parcel_meshes[size] = st.commit()
	return _parcel_meshes[size]


## A parcel box of `size` with its tape and label stripe in `accent` (brown packing tape by default;
## the development scene's boxes are told apart by it). The island light like the faceted props.
## One material per accent (cached, shared: never change it on an instance), like yarn_ball's per colour.
static func parcel_box(size: float, accent := ArtPalette.TAPE) -> MeshInstance3D:
	var mesh := parcel_mesh(size)
	if not _parcel_materials.has(accent):
		var material := lit_texture_material((_parcel_src.surface_get_material(0) as BaseMaterial3D).albedo_texture, LIGHT_SOFTNESS, 1.0)
		var accent_lin := accent.srgb_to_linear()
		material.set_shader_parameter("accent", Vector4(accent_lin.r, accent_lin.g, accent_lin.b, 1.0))   # linear, as a vector (see yarn_ball)
		_parcel_materials[accent] = material
	return instance(mesh, _parcel_materials[accent])


## Unshaded alpha-blended vertex colour (blob shadows on the ground). It is in the transparent
## pass, so it is drawn after the opaque props and depth-tested against them (no depth write);
## render_priority only orders it among other transparent meshes.
static func shadow_material() -> StandardMaterial3D:
	if _shadow == null:
		_shadow = StandardMaterial3D.new()
		_shadow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow.vertex_color_use_as_albedo = true
		_shadow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_shadow.render_priority = -1
	return _shadow


## Faceted builder for solid props (use with lit_material()).
static func builder() -> ArtMeshBuilder:
	return ArtMeshBuilder.new()


## Builder for blob shadows (use with shadow_material()).
static func shadow_builder() -> ArtMeshBuilder:
	var b := ArtMeshBuilder.new()
	b.flat = false
	return b


## Blob shadow alpha; `scale` > 1 for objects that need a darker contact (the moving body).
static func shadow_alpha(scale := 1.0) -> float:
	return ArtPalette.SHADOW_ALPHA * scale


static func instance(mesh: Mesh, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material if material != null else lit_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A link of length 1 from the origin down along -y (a string, a rod, a rope segment): a 6-sided
## cylinder posed between two points by stretch_link() (Task 4e: pendulum string and rod, the
## pulley's rope).
static func link_mesh(radius: float, color: Color) -> Mesh:
	var b := builder()
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO), radius, radius, 1.0, 6, color)
	return b.commit()


## Poses `link` (a link_mesh() instance whose parent has no transform) from world `from` to `to`:
## turned along the segment and scaled to its length (hidden when the points meet). No allocation.
static func stretch_link(link: Node3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()
	if length < 1e-6:
		link.visible = false
		return
	link.visible = true
	var down := d / length                      # the link's local -y
	var side := down.cross(Vector3.BACK if absf(down.z) < 0.9 else Vector3.RIGHT).normalized()
	var y := -down
	link.transform = Transform3D(Basis(side, y * length, side.cross(y)), from)


## Sky-coloured background, no ambient/sky lighting (the shaders are unshaded).
static func make_environment() -> WorldEnvironment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = ArtPalette.SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var world := WorldEnvironment.new()
	world.environment = environment
	return world


## The usual stage of an experiment: sky environment plus its corner of the island (LabWorld)
## around `center`, with an optional blob shadow of radius `blob_radius` under a prop standing at
## `blob_at` (x, z used). The lab is the experiment's definition id (its spot on the map);
## `edge_x` puts the shore at a physics edge (the projectile's bounds).
static func add_world(parent: Node3D, center: Vector3, blob_at: Variant = null, blob_radius := 0.0, edge_x := INF) -> void:
	parent.add_child(make_environment())
	var definition: Variant = parent.get("definition")
	var id: String = definition.get("id", "") if definition is Dictionary else ""
	if blob_at == null:
		build_island(parent, center, Callable(), id, edge_x)
		return
	build_island(parent, center, func(s: ArtMeshBuilder) -> void:
		s.add_blob(Transform3D(Basis(), Vector3(blob_at.x, 0.012, blob_at.z)), blob_radius, shadow_alpha(0.9)), id, edge_x)


## Footprints [x, z, radius] (world) of the lab's own trees (their blob shadow), rocks and flowers
## around `center` (LabWorld puts them there).
static func island_obstacles(center: Vector3) -> Array:
	var out := []
	for t in TREES:
		out.append([center.x + t[0], center.z + t[1], 1.3 * t[2]])
	for r in ROCKS:
		out.append([center.x + r[0], center.z + r[1], r[2] * 1.3])
	for f in FLOWERS:
		out.append([center.x + f[0], center.z + f[1], 0.15])
	return out


## Adds the lab's corner of the big island (LabWorld: flat ground of radius ISLAND_RADIUS + 1.5 at
## y = 0 around `center` (x/z) with the lab's trees, rocks and flowers, the map's land, landmarks,
## beach and sea beyond) as ONE mesh, "Island"; `extra_shadows` lets an experiment add its static
## blob shadows (one alpha mesh, "IslandShadows"). The decoration leaves a strip of about 8 x 6 m
## around the centre free for the apparatus. `id` is the lab (its spot and zone on the map).
static func build_island(parent: Node3D, center := Vector3(-1.5, 0.0, -0.8), extra_shadows: Callable = Callable(), id := "", edge_x := INF) -> void:
	LabWorld.new(id, center, edge_x).build(parent, extra_shadows)
