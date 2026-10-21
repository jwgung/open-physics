## Guided incline friction experiment (port of spike S3 with the web app's surface materials).
## 1 kg box on an adjustable incline, g = 9.81. Box and incline share one material whose static /
## kinetic coefficients come from the content JSON (TS MATERIALS: mu_s = friction + 0.18,
## mu_k = friction; checked by tools/incline-vectors.test.ts).
## Every displayed number comes from PhysicsLaws (formula port); the motion is Jolt + the formula
## correction layer (friction_corrector.gd), and only "이동 거리 (시뮬레이션)" / the graph's
## measured points are engine measurements.
extends Experiment

const G := 9.81
const MASS := 1.0
const BOX := 0.4
const INCLINE_LENGTH := 8.0
const START_X := 3.5          # release point along the incline (pivot local x), uphill end is +x
const PIVOT_HEIGHT := 3.2
const GRAPH_EVERY_STEPS := 6  # graph sample every 6 fixed steps (10 Hz)

const COLOR_FLOOR := Color("c9d3e0")
const COLOR_INCLINE := Color("c8a27a")
const COLOR_STAND := Color("8e9bb0")
const COLOR_BOX := Color("ef7754")
const COLOR_MARK := Color("365eea")

var angle_deg := 20.0
var material_id := "wood"
var mu_s := 0.4
var mu_k := 0.22
var released := false
var box: InclineBox
var corrector := InclineFrictionCorrector.new()

var _pivot: Node3D
var _stand: MeshInstance3D
var _graph_points := PackedVector2Array()
var _last_status := ""


func _ready() -> void:
	_build_world()
	for control in definition.get("controls", []):
		set_control(control.id, control.default)


func set_control(id: String, value: Variant) -> void:
	match id:
		"angle":
			set_angle(float(value))
		"material":
			set_material(str(value))


func control_value(id: String) -> Variant:
	match id:
		"angle":
			return angle_deg
		"material":
			return material_id
	return super(id)


func run_action(id: String) -> void:
	match id:
		"release":
			release()
		"reset":
			reset_box()


func set_angle(degrees: float) -> void:
	angle_deg = clampf(degrees, 0.0, 45.0)
	_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(angle_deg))
	_update_stand()
	reset_box()


## Selects a material option from the "material" control (unknown ids are ignored).
func set_material(option_id: String) -> void:
	for control in definition.get("controls", []):
		if control.id != "material":
			continue
		for option in control.options:
			if option.id == option_id:
				set_coefficients(float(option.mu_s), float(option.mu_k))
				material_id = option_id
				reset_box()
				return
	push_warning("incline: unknown material %s" % option_id)


func set_coefficients(static_mu: float, kinetic_mu: float) -> void:
	mu_s = static_mu
	mu_k = kinetic_mu
	corrector.mu_s = mu_s
	corrector.mu_k = mu_k


## Places the box at rest on the incline (frozen) at START_X.
func reset_box() -> void:
	released = false
	box.freeze = true
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	var local := Transform3D(Basis(), Vector3(START_X, BOX * 0.5, 0.0))
	box.global_transform = _pivot.global_transform * local
	corrector.reset(box.global_position)
	_graph_points.clear()
	state_changed.emit()


func release() -> void:
	if released:
		reset_box()
	corrector.reset(box.global_position)
	_graph_points.clear()
	_graph_points.append(Vector2.ZERO)
	released = true
	box.freeze = false
	box.sleeping = false
	state_changed.emit()


## Seconds since release, in fixed steps (exact, independent of the frame rate).
func elapsed() -> float:
	return corrector.steps / float(Engine.physics_ticks_per_second) if released else 0.0


func formula_acceleration() -> float:
	return PhysicsLaws.incline_acceleration(G, deg_to_rad(angle_deg), mu_s, mu_k)


func status() -> String:
	if not released:
		return "ready"
	if not corrector._in_contact(box.global_position) and corrector.steps > 0:
		return "left"
	return corrector.status


func _physics_process(_delta: float) -> void:
	if not released:
		return
	# samples[k] is the displacement after k steps; this runs before the box's step (tree order).
	var steps := corrector.samples.size() - 1
	if steps > 0 and steps % GRAPH_EVERY_STEPS == 0:
		var max_t: float = definition.get("graph", {}).get("x", {}).get("max", 3.0)
		var t := steps / float(Engine.physics_ticks_per_second)
		if t <= max_t + 0.001 and t > _graph_points[-1].x and status() != "left":
			_graph_points.append(Vector2(t, corrector.samples[steps]))
	var current := status()
	if current != _last_status:
		_last_status = current
		state_changed.emit()


func observations() -> Dictionary:
	var theta := deg_to_rad(angle_deg)
	var normal := PhysicsLaws.incline_normal_load(MASS, G, theta)
	var state_text: String = {
		"ready": "놓기 전",
		"holding": "버티는 중 (정지)",
		"sliding": "미끄러지는 중",
		"left": "빗면을 벗어남",
	}.get(status(), "")
	return {
		"critical_angle": rad_to_deg(PhysicsLaws.critical_angle(mu_s)),
		"state": state_text,
		"tangential": PhysicsLaws.incline_tangential_gravity(MASS, G, theta),
		"max_static": PhysicsLaws.max_static_friction(mu_s, normal),
		"acceleration": formula_acceleration(),
		# Distance along the incline; after the box runs off the end it stays at the run length.
		"distance": minf(corrector.samples[-1], START_X + INCLINE_LENGTH * 0.5) if released and corrector.samples.size() > 0 else 0.0,
	}


func graph_series() -> Dictionary:
	var max_t: float = definition.get("graph", {}).get("x", {}).get("max", 3.0)
	var a := formula_acceleration()
	var limit := START_X + INCLINE_LENGTH * 0.5  # the box leaves the incline after this distance
	var formula := PackedVector2Array()
	for i in 31:
		var t := max_t * i / 30.0
		var s := PhysicsLaws.constant_acceleration_displacement(0.0, a, t)
		if s > limit:
			break
		formula.append(Vector2(t, s))
	return {"formula": formula, "measured": _graph_points}


func follow_point() -> Vector3:
	return box.global_position if box else global_position


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("eef2f7")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.81, 0.86)
	environment.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	sun.light_energy = 0.9
	Quality.configure_sun(sun, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	add_child(sun)

	var frictionless := PhysicsMaterial.new()
	frictionless.friction = 0.0
	frictionless.bounce = 0.0

	var floor_body := StaticBody3D.new()
	floor_body.physics_material_override = frictionless
	_add_box_shape(floor_body, Vector3(30.0, 0.4, 12.0), COLOR_FLOOR)
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	add_child(floor_body)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, PIVOT_HEIGHT, 0.0)
	add_child(_pivot)
	var incline := StaticBody3D.new()
	incline.physics_material_override = frictionless
	_add_box_shape(incline, Vector3(INCLINE_LENGTH, 0.3, 2.0), COLOR_INCLINE)
	incline.position = Vector3(0.0, -0.15, 0.0)
	_pivot.add_child(incline)
	# Start line where the box is released (visual only).
	var mark := MeshInstance3D.new()
	var mark_mesh := BoxMesh.new()
	mark_mesh.size = Vector3(0.04, 0.01, 2.0)
	mark_mesh.material = _material(COLOR_MARK)
	mark.mesh = mark_mesh
	mark.position = Vector3(START_X - BOX * 0.5, 0.005, 0.0)
	_pivot.add_child(mark)

	# Support post under the pivot (visual only, no collision).
	_stand = MeshInstance3D.new()
	var stand_mesh := BoxMesh.new()
	stand_mesh.material = _material(COLOR_STAND)
	_stand.mesh = stand_mesh
	add_child(_stand)

	box = InclineBox.new()
	box.mass = MASS
	box.physics_material_override = frictionless
	box.can_sleep = false
	box.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	box.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	box.linear_damp = 0.0
	box.angular_damp = 0.0
	box.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	box.freeze = true
	_add_box_shape(box, Vector3.ONE * BOX, COLOR_BOX)
	add_child(box)

	corrector.incline = _pivot
	corrector.half_length = INCLINE_LENGTH * 0.5
	corrector.half_extent = BOX * 0.5
	set_coefficients(mu_s, mu_k)
	box.corrector = corrector


func _update_stand() -> void:
	var height := PIVOT_HEIGHT - 0.15
	(_stand.mesh as BoxMesh).size = Vector3(0.3, height, 0.3)
	_stand.position = Vector3(0.0, height * 0.5, -0.7)


func _add_box_shape(body: CollisionObject3D, size: Vector3, color: Color) -> void:
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	body.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
