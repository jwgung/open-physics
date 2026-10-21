## Visual-only reactions of the incline box for the Task 2c mockups: squash & stretch of the box
## mesh (never the body or its collision shape), a little dust puff, and a blob shadow that follows
## the box onto whatever is below it (one ray per physics step, read-only).
##   placed (reset)   pop in with an overshoot
##   released         short stretch, then settle
##   starts sliding   small puff behind the box
##   lands on floor   squash proportional to the fall speed + dust ring
##   stops on floor   small wobble
class_name ToyJuice
extends Node3D

const SPRING_K := 260.0     # 1/s^2
const SPRING_DAMP := 11.0   # 1/s

var experiment: Node
var body: RigidBody3D
var mesh: MeshInstance3D
var box_size := 0.4

var _squash := 0.0          # +: taller/thinner, -: flatter/wider
var _squash_v := 0.0
var _pop := 1.0             # uniform scale for the pop-in
var _pop_v := 0.0
var _prev_vy := 0.0
var _landed := false
var _resting := false
var _last_status := ""
var _shadow: MeshInstance3D
var _dust: CPUParticles3D
var _ray := PhysicsRayQueryParameters3D.new()


func setup(style: ToyStyle, owner_experiment: Node, box_body: RigidBody3D, box_mesh: MeshInstance3D, size: float) -> void:
	experiment = owner_experiment
	body = box_body
	mesh = box_mesh
	box_size = size
	var s := style.shadow_builder()
	s.add_blob(Transform3D.IDENTITY, 1.0, style.shadow_color(1.35))
	_shadow = style.instance(s.commit(), style.shadow_mat)
	add_child(_shadow)
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 0.95
	_dust.amount = 16
	_dust.lifetime = 0.55
	_dust.local_coords = false
	var puff := style.builder()
	puff.ao_min = 1.0
	puff.add_sphere(Transform3D.IDENTITY, 0.11, 3, 6, style.p.dust)
	_dust.mesh = puff.commit()
	_dust.material_override = style.toy_material
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_dust.emission_ring_axis = Vector3.UP
	_dust.emission_ring_radius = size * 0.6
	_dust.emission_ring_inner_radius = size * 0.45
	_dust.emission_ring_height = 0.02
	_dust.direction = Vector3(0.0, 1.0, 0.0)
	_dust.spread = 75.0
	_dust.gravity = Vector3(0.0, -2.0, 0.0)
	_dust.initial_velocity_min = 0.8
	_dust.initial_velocity_max = 1.6
	_dust.damping_min = 2.0
	_dust.damping_max = 3.0
	_dust.scale_amount_min = 0.7
	_dust.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_dust.scale_amount_curve = curve
	add_child(_dust)
	_ray.exclude = [body.get_rid()]
	_ray.collide_with_areas = false
	if experiment.has_signal("state_changed"):
		experiment.state_changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	var status: String = experiment.status()
	if status == _last_status:
		return
	var previous := _last_status
	_last_status = status
	match status:
		"ready":
			_landed = false
			_resting = false
			_pop = 0.55
			_pop_v = 0.0
		"holding", "sliding":
			if previous == "ready":
				_squash_v += 3.5   # release: stretch up
			if status == "sliding":
				_puff(0.6)


func _physics_process(_delta: float) -> void:
	if body == null:
		return
	var vy := body.linear_velocity.y
	var near_floor := body.global_position.y < box_size * 0.5 + 0.12
	if not body.freeze and near_floor and not _landed and _prev_vy < -1.2 and vy > _prev_vy * 0.5:
		_landed = true
		var strength := clampf(-_prev_vy / 6.0, 0.25, 1.0)
		_squash_v -= 10.0 * strength
		_puff(strength)
	if _landed and not _resting and body.linear_velocity.length() < 0.15:
		_resting = true
		_squash_v -= 1.4
	_prev_vy = vy
	_update_shadow()


func _process(delta: float) -> void:
	if mesh == null:
		return
	# Damped springs (semi-implicit Euler, clamped step).
	var dt := minf(delta, 1.0 / 30.0)
	_squash_v += (-SPRING_K * _squash - SPRING_DAMP * _squash_v) * dt
	_squash += _squash_v * dt
	_squash = clampf(_squash, -0.45, 0.45)
	_pop_v += (-SPRING_K * 0.7 * (_pop - 1.0) - SPRING_DAMP * 0.8 * _pop_v) * dt
	_pop += _pop_v * dt
	var sy := (1.0 + _squash) * _pop
	var sxz := (1.0 - _squash * 0.5) * _pop
	mesh.scale = Vector3(sxz, sy, sxz)
	# Keep the bottom face on the surface while the mesh squashes (box-local y = surface normal).
	mesh.position = Vector3(0.0, -box_size * 0.5 * (1.0 - sy), 0.0)


func _puff(strength: float) -> void:
	_dust.global_position = body.global_position - body.global_transform.basis.y * box_size * 0.48
	_dust.global_basis = Basis(Quaternion(Vector3.UP, body.global_transform.basis.y.normalized()))
	_dust.amount = int(lerpf(8.0, 16.0, strength))
	_dust.initial_velocity_max = lerpf(0.9, 1.8, strength)
	_dust.restart()


## Blob shadow straight below the box, on the incline or the floor; smaller and lighter when high.
func _update_shadow() -> void:
	var from := body.global_position
	_ray.from = from
	_ray.to = from + Vector3.DOWN * 12.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		_shadow.visible = false
		return
	_shadow.visible = true
	var height := maxf(0.0, from.y - (hit.position as Vector3).y - box_size * 0.5)
	var radius := box_size * 0.85 * clampf(1.0 - height * 0.18, 0.45, 1.0)
	var normal: Vector3 = hit.normal
	var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis.from_scale(Vector3(radius, 1.0, radius))
	_shadow.global_transform = Transform3D(basis, (hit.position as Vector3) + normal * 0.015)
