## S2 mechanics sandbox: floor, 30 deg incline, 3 fixed blocks, 50 bodies (25 boxes, 25 balls)
## in rubber / wood / steel (MATERIALS in src/physics/materials.ts), one shadowed directional
## light. Fixed-seed drop from 3-6 m, 10 bodies re-dropped every 20 s. Single pointer drags a body
## on the surface plane under it with 0.25 m snapping; two fingers orbit / pinch-zoom the camera.
## Quality (autoload) decides the shadow mode and procedural sky vs flat background.
extends Node3D

const BODY_COUNT := 50
const REDROP_INTERVAL := 20.0
const REDROP_BATCH := 10
const DROP_SEED := 20261021
const SNAP := 0.25
const BOX_SIZE := 0.5
const BALL_RADIUS := 0.25

## src/physics/materials.ts MATERIALS (rubber, wood, steel). Density is spike-only.
const MATERIALS := {
	"rubber": {"restitution": 0.88, "friction": 0.42, "color": Color(0.80, 0.18, 0.15), "metallic": 0.0, "roughness": 0.9, "density": 1100.0},
	"wood": {"restitution": 0.5, "friction": 0.22, "color": Color(0.62, 0.42, 0.24), "metallic": 0.0, "roughness": 0.7, "density": 700.0},
	"steel": {"restitution": 0.72, "friction": 0.08, "color": Color(0.78, 0.80, 0.83), "metallic": 1.0, "roughness": 0.28, "density": 7800.0},
}
const MATERIAL_ORDER := ["rubber", "wood", "steel"]

var _bodies: Array[RigidBody3D] = []
var _rng := RandomNumberGenerator.new()
var _redrop_timer := 0.0
var _redrop_cursor := 0
var _camera: OrbitCamera
var _dragged: RigidBody3D = null
var _drag_surface: CollisionObject3D = null
var _drag_lift := 0.0
var _visual_materials: Dictionary = {}
var _physics_materials: Dictionary = {}


func _ready() -> void:
	_rng.seed = DROP_SEED
	for key in MATERIAL_ORDER:
		var spec: Dictionary = MATERIALS[key]
		var visual := StandardMaterial3D.new()
		visual.albedo_color = spec.color
		visual.metallic = spec.metallic
		visual.roughness = spec.roughness
		_visual_materials[key] = visual
		var physics := PhysicsMaterial.new()
		physics.bounce = spec.restitution
		physics.friction = spec.friction
		_physics_materials[key] = physics
	_build_environment()
	_build_statics()
	for index in BODY_COUNT:
		_bodies.append(_build_body(index))
		_drop(_bodies[index])
	_camera = OrbitCamera.new()
	_camera.distance = 13.0
	_camera.target = Vector3(0.0, 1.0, 0.0)
	add_child(_camera)
	_camera.current = true
	_camera.single_pointer.connect(_on_pointer)


func _physics_process(delta: float) -> void:
	_redrop_timer += delta
	if _redrop_timer >= REDROP_INTERVAL:
		_redrop_timer -= REDROP_INTERVAL
		for i in REDROP_BATCH:
			var body := _bodies[_redrop_cursor]
			_redrop_cursor = (_redrop_cursor + 1) % _bodies.size()
			if body != _dragged:
				_drop(body)


func _drop(body: RigidBody3D) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	var basis := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
	var origin := Vector3(_rng.randf_range(-5.0, 5.0), _rng.randf_range(3.0, 6.0), _rng.randf_range(-5.0, 5.0))
	body.global_transform = Transform3D(basis, origin)
	body.sleeping = false


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.48, 0.72)
	sky_material.sky_horizon_color = Color(0.70, 0.76, 0.82)
	sky_material.ground_horizon_color = Color(0.55, 0.55, 0.55)
	sky_material.ground_bottom_color = Color(0.25, 0.24, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	if Quality.get_value("sky"):
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		# Flat stand-in for the sky: horizon-colored background and ambient; steel reflects the
		# background color instead of the sky radiance map.
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = sky_material.sky_horizon_color
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.55, 0.62, 0.72)
		environment.ambient_light_energy = 0.8
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.2
	sun.directional_shadow_max_distance = 40.0
	Quality.configure_sun(sun, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	add_child(sun)


func _build_statics() -> void:
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.30, 0.31, 0.33)
	floor_material.roughness = 0.95
	_static_box(Vector3(24.0, 0.5, 24.0), Transform3D(Basis(), Vector3(0.0, -0.25, 0.0)), floor_material, "wood")
	var incline_material := StandardMaterial3D.new()
	incline_material.albedo_color = Color(0.55, 0.47, 0.36)
	incline_material.roughness = 0.8
	var incline_basis := Basis(Vector3.BACK, deg_to_rad(30.0))
	_static_box(Vector3(6.0, 0.4, 4.0), Transform3D(incline_basis, Vector3(-6.5, 1.3, 0.0)), incline_material, "wood")
	var block_material := StandardMaterial3D.new()
	block_material.albedo_color = Color(0.30, 0.42, 0.55)
	block_material.roughness = 0.6
	_static_box(Vector3(1.5, 1.0, 1.5), Transform3D(Basis(), Vector3(4.0, 0.5, -3.0)), block_material, "steel")
	_static_box(Vector3(1.0, 1.5, 3.0), Transform3D(Basis(), Vector3(6.0, 0.75, 2.5)), block_material, "steel")
	_static_box(Vector3(3.0, 0.8, 1.0), Transform3D(Basis(), Vector3(0.0, 0.4, 5.5)), block_material, "steel")


func _static_box(size: Vector3, xform: Transform3D, visual: Material, material_key: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = xform
	body.physics_material_override = _physics_materials[material_key]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = visual
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	body.add_child(instance)
	body.set_meta("half_height", size.y * 0.5)
	add_child(body)
	return body


func _build_body(index: int) -> RigidBody3D:
	var key: String = MATERIAL_ORDER[index % MATERIAL_ORDER.size()]
	var spec: Dictionary = MATERIALS[key]
	var body := RigidBody3D.new()
	body.physics_material_override = _physics_materials[key]
	var shape := CollisionShape3D.new()
	var instance := MeshInstance3D.new()
	if index % 2 == 0:
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * BOX_SIZE
		shape.shape = box
		var mesh := BoxMesh.new()
		mesh.size = box.size
		instance.mesh = mesh
		body.mass = spec.density * pow(BOX_SIZE, 3.0)
		body.set_meta("half_extent", BOX_SIZE * 0.5)
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = BALL_RADIUS
		shape.shape = sphere
		var mesh := SphereMesh.new()
		mesh.radius = BALL_RADIUS
		mesh.height = BALL_RADIUS * 2.0
		instance.mesh = mesh
		body.mass = spec.density * 4.0 / 3.0 * PI * pow(BALL_RADIUS, 3.0)
		body.set_meta("half_extent", BALL_RADIUS)
	instance.material_override = _visual_materials[key]
	body.add_child(shape)
	body.add_child(instance)
	add_child(body)
	return body


# --- pointer drag on the manipulation plane -------------------------------------------------

func _on_pointer(event_type: String, screen_position: Vector2) -> void:
	match event_type:
		"press":
			_begin_drag(screen_position)
		"move":
			if _dragged:
				_move_drag(screen_position)
		"release", "cancel":
			_end_drag()


func _ray(screen_position: Vector2, exclude: Array[RID] = []) -> Dictionary:
	var from := _camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(from, from + _camera.project_ray_normal(screen_position) * 200.0)
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query)


func _begin_drag(screen_position: Vector2) -> void:
	var hit := _ray(screen_position)
	if hit.is_empty() or not (hit.collider is RigidBody3D):
		return
	var body: RigidBody3D = hit.collider
	# The manipulation plane is the static surface directly under the body (floor, incline, block top).
	var down := PhysicsRayQueryParameters3D.create(body.global_position, body.global_position + Vector3.DOWN * 50.0)
	down.exclude = _body_rids()
	var surface_hit := get_world_3d().direct_space_state.intersect_ray(down)
	if surface_hit.is_empty():
		return
	_dragged = body
	_drag_surface = surface_hit.collider
	_drag_lift = body.get_meta("half_extent") + 0.02
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	_move_drag(screen_position)


func _move_drag(screen_position: Vector2) -> void:
	var surface_xform := _drag_surface.global_transform
	var normal := surface_xform.basis.y.normalized()
	var top := surface_xform.origin + normal * float(_drag_surface.get_meta("half_height", 0.0))
	var plane := Plane(normal, top + normal * _drag_lift)
	var from := _camera.project_ray_origin(screen_position)
	var point = plane.intersects_ray(from, _camera.project_ray_normal(screen_position))
	if point == null:
		return
	# Snap in the surface's own frame so incline drags stay on the incline.
	var local: Vector3 = surface_xform.affine_inverse() * point
	local.x = snappedf(local.x, SNAP)
	local.z = snappedf(local.z, SNAP)
	var snapped_point: Vector3 = surface_xform * local
	_dragged.global_transform = Transform3D(surface_xform.basis.orthonormalized(), snapped_point)


func _end_drag() -> void:
	if _dragged == null:
		return
	_dragged.freeze = false
	_dragged.linear_velocity = Vector3.ZERO
	_dragged.angular_velocity = Vector3.ZERO
	_dragged = null
	_drag_surface = null


func _body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for body in _bodies:
		rids.append(body.get_rid())
	return rids
