## S1 orbit: graphics ceiling scene. Emissive sun + glow, 8 PBR planets (2048 albedo + normal),
## one ringed planet (web build uses the 1024 px texture set), 8 orbit lines, 5,000-point starfield, automatic 30 s camera loop.
## Positions come from the analytic circular orbit (PhysicsLaws.circular_orbit_speed, orbit.ts).
extends Node3D

const GM := 60.0  # scene units: G * M_sun
const STAR_COUNT := 5000
const CAMERA_CYCLE := 30.0
const ORBIT_SEGMENTS := 256

var _planets: Array[Node3D] = []
var _angular_speeds: PackedFloat32Array = PackedFloat32Array()
var _phases: PackedFloat32Array = PackedFloat32Array()
var _camera: Camera3D
var _time := 0.0


func _ready() -> void:
	_build_environment()
	_build_sun()
	_build_starfield()
	for index in PlanetPalette.PLANETS.size():
		_build_planet(index)
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 62.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	_update_planets()
	_camera.global_transform = _camera_target()


func _process(delta: float) -> void:
	_time += delta
	_update_planets()
	var target := _camera_target()
	var weight := 1.0 - exp(-3.0 * delta)
	_camera.global_transform = _camera.global_transform.interpolate_with(target, weight)


func _update_planets() -> void:
	for index in _planets.size():
		var orbit: float = PlanetPalette.PLANETS[index].orbit
		var angle := _phases[index] + _angular_speeds[index] * _time
		_planets[index].position = Vector3(cos(angle) * orbit, 0.0, sin(angle) * orbit)
		_planets[index].rotation.y = _time * 0.4


## 0-15 s of each 30 s cycle: overview; 15-30 s: follow planet (cycle index mod 8).
func _camera_target() -> Transform3D:
	var cycle := int(_time / CAMERA_CYCLE)
	var phase := fmod(_time, CAMERA_CYCLE)
	if phase < CAMERA_CYCLE * 0.5:
		var yaw := _time * 0.05
		var eye := Vector3(sin(yaw) * 48.0, 30.0, cos(yaw) * 48.0)
		return Transform3D(Basis(), eye).looking_at(Vector3.ZERO, Vector3.UP)
	var planet := _planets[cycle % _planets.size()]
	var radius: float = PlanetPalette.PLANETS[cycle % _planets.size()].radius
	var outward := planet.position.normalized()
	var side := outward.cross(Vector3.UP)
	var eye := planet.position + (side * 3.5 - outward * 1.5 + Vector3.UP * 1.0) * radius  # sun-lit side
	return Transform3D(Basis(), eye).looking_at(planet.position, Vector3.UP)


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.01)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.08, 0.09, 0.12)
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = Quality.get_value("glow")
	environment.glow_intensity = 1.0
	environment.glow_strength = 1.1
	environment.glow_bloom = 0.15
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


func _build_sun() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 2.2
	mesh.height = 4.4
	mesh.radial_segments = 64
	mesh.rings = 32
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.0, 0.0, 0.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.22)
	material.emission_energy_multiplier = 6.0
	mesh.material = material
	var sun := MeshInstance3D.new()
	sun.mesh = mesh
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun)
	var light := OmniLight3D.new()
	light.omni_range = 80.0
	light.omni_attenuation = 0.6
	light.light_energy = 3.0
	light.light_color = Color(1.0, 0.92, 0.8)
	add_child(light)


func _build_starfield() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261021
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for i in STAR_COUNT:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		points.append(direction * rng.randf_range(250.0, 400.0))
		var brightness := rng.randf_range(0.4, 1.0)
		colors.append(Color(brightness, brightness, brightness * rng.randf_range(0.85, 1.1)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.use_point_size = true
	material.point_size = 2.0
	mesh.surface_set_material(0, material)
	var stars := MeshInstance3D.new()
	stars.mesh = mesh
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


func _build_planet(index: int) -> void:
	var planet: Dictionary = PlanetPalette.PLANETS[index]
	var orbit: float = planet.orbit
	var speed := PhysicsLaws.circular_orbit_speed(1.0, orbit, GM)
	_angular_speeds.append(speed / orbit)
	_phases.append(index * 2.399963)  # golden-angle spread

	var mesh := SphereMesh.new()
	mesh.radius = planet.radius
	mesh.height = planet.radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var material := StandardMaterial3D.new()
	material.roughness = 0.85 if index < 4 else 0.6
	material.metallic = 0.0
	var web := OS.has_feature("web")
	var albedo := _load_texture(PlanetPalette.albedo_path(index, web))
	var normal := _load_texture(PlanetPalette.normal_path(index, web))
	if albedo:
		material.albedo_texture = albedo
	else:
		material.albedo_color = planet.colors[1]
	if normal:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 1.0
	mesh.material = material
	var body := MeshInstance3D.new()
	body.mesh = mesh
	add_child(body)
	_planets.append(body)

	if planet.get("ring", false):
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = planet.radius * 1.4
		ring_mesh.outer_radius = planet.radius * 2.3
		ring_mesh.rings = 96
		ring_mesh.ring_segments = 8
		var ring_material := StandardMaterial3D.new()
		ring_material.albedo_color = Color(0.85, 0.78, 0.62, 0.75)
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_material.roughness = 0.9
		ring_mesh.material = ring_material
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.scale = Vector3(1.0, 0.03, 1.0)
		ring.rotation = Vector3(deg_to_rad(18.0), 0.0, 0.0)
		body.add_child(ring)

	_build_orbit_line(orbit)


func _build_orbit_line(orbit: float) -> void:
	var points := PackedVector3Array()
	for i in ORBIT_SEGMENTS + 1:
		var angle := TAU * i / ORBIT_SEGMENTS
		points.append(Vector3(cos(angle) * orbit, 0.0, sin(angle) * orbit))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.45, 0.6, 0.9, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, material)
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("missing baked texture %s (run tools/bake_textures.gd)" % path)
	return null
