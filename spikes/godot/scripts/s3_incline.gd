## S3 guided incline friction lab: adjustable incline, 1 kg box, g = 9.81, mu_s = 0.5, mu_k = 0.4.
## Displayed quantities are computed by PhysicsLaws (formula port); motion is Jolt + correction layer.
extends Node3D

const G := 9.81
const MU_S := 0.5
const MU_K := 0.4
const MASS := 1.0
const BOX := 0.4
const INCLINE_LENGTH := 8.0
const START_X := 3.5          # release point along the incline (pivot local x), uphill end is +x
const PIVOT_HEIGHT := 3.2

var angle_deg := 20.0
var released := false
var release_time := 0.0
var box: S3Box
var corrector := InclineFrictionCorrector.new()
var headless_ui := false     # tests skip building the UI

var _pivot: Node3D
var _camera: OrbitCamera
var _info: Label
var _slider: HSlider
var _angle_label: Label


func _ready() -> void:
	_build_world()
	if not headless_ui:
		_build_ui()
	set_angle(angle_deg)


func set_angle(degrees: float) -> void:
	angle_deg = clampf(degrees, 0.0, 45.0)
	_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(angle_deg))
	reset_box()


## Places the box at rest on the incline (frozen) at START_X.
func reset_box() -> void:
	released = false
	box.freeze = true
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	var local := Transform3D(Basis(), Vector3(START_X, BOX * 0.5, 0.0))
	box.global_transform = _pivot.global_transform * local
	corrector.reset(box.global_position)
	_refresh_ui()


func release() -> void:
	corrector.reset(box.global_position)
	released = true
	release_time = 0.0
	box.freeze = false
	box.sleeping = false


func _physics_process(delta: float) -> void:
	if released:
		release_time += delta
	_refresh_ui()


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.86, 0.89, 0.93)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	environment.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var frictionless := PhysicsMaterial.new()
	frictionless.friction = 0.0
	frictionless.bounce = 0.0

	var floor_body := StaticBody3D.new()
	floor_body.physics_material_override = frictionless
	_add_box_shape(floor_body, Vector3(30.0, 0.4, 10.0), Color(0.55, 0.57, 0.6))
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	add_child(floor_body)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, PIVOT_HEIGHT, 0.0)
	add_child(_pivot)
	var incline := StaticBody3D.new()
	incline.physics_material_override = frictionless
	_add_box_shape(incline, Vector3(INCLINE_LENGTH, 0.3, 2.0), Color(0.62, 0.48, 0.32))
	incline.position = Vector3(0.0, -0.15, 0.0)
	_pivot.add_child(incline)

	box = S3Box.new()
	box.mass = MASS
	box.physics_material_override = frictionless
	box.can_sleep = false
	box.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	box.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	box.linear_damp = 0.0
	box.angular_damp = 0.0
	box.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	box.freeze = true
	_add_box_shape(box, Vector3.ONE * BOX, Color(0.85, 0.35, 0.2))
	add_child(box)

	corrector.mu_s = MU_S
	corrector.mu_k = MU_K
	corrector.incline = _pivot
	corrector.half_length = INCLINE_LENGTH * 0.5
	corrector.half_extent = BOX * 0.5
	box.corrector = corrector

	if not headless_ui:
		_camera = OrbitCamera.new()
		_camera.target = Vector3(0.0, 2.0, 0.0)
		_camera.distance = 12.0
		_camera.yaw = 0.0
		_camera.pitch = -0.25
		add_child(_camera)
		_camera.current = true


func _add_box_shape(body: CollisionObject3D, size: Vector3, color: Color) -> void:
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	body.add_child(instance)


# --- guided UI ------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_right = -16.0
	panel.offset_top = -470.0
	panel.offset_bottom = -16.0
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var question := Label.new()
	question.text = "빗면을 얼마나 기울이면 상자가 미끄러지기 시작할까?"
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question.add_theme_font_size_override("font_size", 28)
	column.add_child(question)

	_angle_label = Label.new()
	_angle_label.add_theme_font_size_override("font_size", 26)
	column.add_child(_angle_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 45.0
	_slider.step = 0.5
	_slider.value = angle_deg
	_slider.custom_minimum_size = Vector2(0, 56)
	_slider.value_changed.connect(set_angle)
	column.add_child(_slider)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	for spec in [["상자 놓기", release], ["처음으로", reset_box], ["26°", set_angle.bind(26.0)], ["27°", set_angle.bind(27.0)], ["35°", set_angle.bind(35.0)]]:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(spec[1])
		buttons.add_child(button)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 24)
	column.add_child(_info)


func _refresh_ui() -> void:
	if _info == null:
		return
	var theta := deg_to_rad(angle_deg)
	var tangential := PhysicsLaws.incline_tangential_gravity(MASS, G, theta)
	var normal := PhysicsLaws.incline_normal_load(MASS, G, theta)
	var max_static := PhysicsLaws.max_static_friction(MU_S, normal)
	var accel := PhysicsLaws.incline_acceleration(G, theta, MU_S, MU_K)
	var t := release_time if released else 0.0
	var formula_distance := PhysicsLaws.constant_acceleration_displacement(0.0, accel, t)
	var measured := corrector.samples[-1] if corrector.samples.size() > 0 else 0.0
	_angle_label.text = "빗면 각도 θ = %.1f°   (임계각 %.2f°)" % [angle_deg, rad_to_deg(PhysicsLaws.critical_angle(MU_S))]
	_slider.set_value_no_signal(angle_deg)
	_info.text = "\n".join([
		"중력 접선 성분 mg·sinθ = %.3f N" % tangential,
		"최대 정지 마찰력 μs·mg·cosθ = %.3f N" % max_static,
		"가속도 a = g(sinθ − μk·cosθ) = %.3f m/s²" % accel,
		"이동 거리 ½at² = %.3f m   (t = %.2f s)" % [formula_distance, t],
		"시뮬레이션 이동 거리 = %.3f m" % measured,
	])
