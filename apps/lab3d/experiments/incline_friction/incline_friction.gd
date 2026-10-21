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
const STAND_HEIGHT := PIVOT_HEIGHT - 0.15   # full height of the support post mesh
const GRAPH_EVERY_STEPS := 6  # graph sample every 6 fixed steps (10 Hz)
const FLOOR_DAMP := 4.0       # 1/s braking of a box lying on the floor after leaving the incline
const FALL_LIMIT_Y := -3.0    # below this the box is stopped (it left the floor)


var angle_deg := 20.0
var material_id := "wood"
var mu_s := 0.4
var mu_k := 0.22
var released := false
var box: InclineBox
var corrector := InclineFrictionCorrector.new()
## Grass island meshes, shadows and the box reactions (visual only, never the bodies).
var props := InclineProps.new()
var _stand: MeshInstance3D

var _pivot: Node3D
var _graph_points := PackedVector2Array()
var _last_status := ""
var _graph_revision := 0


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
	props.angle_changed(angle_deg)
	_fit_stand()
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
	_graph_revision += 1


## Places the box at rest on the incline (frozen) at START_X.
func reset_box() -> void:
	released = false
	box.linear_damp = 0.0
	box.freeze = true
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	var local := Transform3D(Basis(), Vector3(START_X, BOX * 0.5, 0.0))
	box.global_transform = _pivot.global_transform * local
	corrector.reset(box.global_position)
	_graph_points.clear()
	_graph_revision += 1
	_last_status = status()
	state_changed.emit()
	props.status_changed(_last_status)


func release() -> void:
	if released:
		reset_box()
	corrector.reset(box.global_position)
	_graph_points.clear()
	_graph_points.append(Vector2.ZERO)
	_graph_revision += 1
	released = true
	box.freeze = false
	box.sleeping = false
	_last_status = status()
	state_changed.emit()
	props.status_changed(_last_status)


func formula_acceleration() -> float:
	return PhysicsLaws.incline_acceleration(G, deg_to_rad(angle_deg), mu_s, mu_k)


func status() -> String:
	if not released:
		return "ready"
	if corrector.past_end:
		return "left"
	return corrector.status


func _physics_process(_delta: float) -> void:
	if not released:
		return
	# samples[k] is the displacement after k steps; this runs before the box's step (tree order).
	var steps := corrector.steps - 1
	if steps > 0 and steps % GRAPH_EVERY_STEPS == 0 and steps < corrector.samples.size():
		var max_t: float = definition.get("graph", {}).get("x", {}).get("max", 3.0)
		var t := steps / float(Engine.physics_ticks_per_second)
		if t <= max_t + 0.001 and t > _graph_points[-1].x and status() != "left":
			_graph_points.append(Vector2(t, corrector.samples[steps]))
			_graph_revision += 1
	var current := status()
	if current != _last_status:
		_last_status = current
		state_changed.emit()
		props.status_changed(current)
	_settle_off_incline()


## The floor is frictionless like the incline (so the formula layer owns all friction), but a box
## that has left the incline must not run off the end of the finite floor: it brakes once it lies
## on the floor and is stopped if it ever drops far below it. Does not touch the displayed numbers.
func _settle_off_incline() -> void:
	if box.freeze:
		return
	var y := box.global_position.y
	if y < FALL_LIMIT_Y:
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.freeze = true
	elif status() == "left" and y < BOX * 0.5 + 0.05:
		box.linear_damp = FLOOR_DAMP


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
		"distance": minf(corrector.last_sample, START_X + INCLINE_LENGTH * 0.5) if released else 0.0,
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
	return {"formula": formula, "measured": _graph_points.duplicate()}


func graph_revision() -> int:
	return _graph_revision


func follow_point() -> Vector3:
	return box.global_position if box else global_position


func _build_world() -> void:
	var frictionless := PhysicsMaterial.new()
	frictionless.friction = 0.0
	frictionless.bounce = 0.0

	# Collision floor (the island's top surface, y = 0); the island mesh is ArtKit's.
	var floor_body := StaticBody3D.new()
	floor_body.physics_material_override = frictionless
	_add_box_shape(floor_body, Vector3(30.0, 0.4, 12.0))
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	add_child(floor_body)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, PIVOT_HEIGHT, 0.0)
	add_child(_pivot)
	var incline_size := Vector3(INCLINE_LENGTH, 0.3, 2.0)
	var incline := StaticBody3D.new()
	incline.physics_material_override = frictionless
	_add_box_shape(incline, incline_size)
	incline.add_child(ArtKit.instance(props.incline_mesh(incline_size)))
	incline.position = Vector3(0.0, -0.15, 0.0)
	_pivot.add_child(incline)
	# Start line where the box is released (visual only).
	var mark := ArtKit.instance(props.start_line_mesh(incline_size.z))
	mark.position = Vector3(START_X - BOX * 0.5, 0.0, 0.0)
	_pivot.add_child(mark)

	# Support post under the pivot (visual only, no collision).
	_stand = ArtKit.instance(props.stand_mesh(STAND_HEIGHT))
	_stand.name = "Stand"
	_stand.position = Vector3(0.0, 0.0, InclineProps.STAND_Z)
	add_child(_stand)
	_fit_stand()

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
	_add_box_shape(box, Vector3.ONE * BOX)
	var box_visual := ArtKit.instance(props.box_mesh(BOX))
	box_visual.name = "Visual"
	box.add_child(box_visual)
	add_child(box)

	corrector.incline = _pivot
	corrector.half_length = INCLINE_LENGTH * 0.5
	corrector.half_extent = BOX * 0.5
	# The graph window (+ the sample at its end) is all the app reads from the history.
	corrector.history_steps = int(definition.get("graph", {}).get("x", {}).get("max", 3.0) * Engine.physics_ticks_per_second) + 2
	set_coefficients(mu_s, mu_k)
	box.corrector = corrector

	props.dress(self, _stand.position, box, box_visual, BOX)
	props.juice.landed.connect(impact.emit)


## The post is shortened as the incline tilts so its top never shows through the incline.
func _fit_stand() -> void:
	if _stand != null:
		_stand.scale.y = InclineProps.stand_height(STAND_HEIGHT, PIVOT_HEIGHT, angle_deg) / STAND_HEIGHT


func _add_box_shape(body: CollisionObject3D, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
