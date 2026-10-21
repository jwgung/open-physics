## Visual-only reactions of one moving body (grass island style, apps/lab3d/docs/art-direction.md
## section 6). It only ever writes its own nodes and the `mesh` it was given (a MeshInstance3D child
## of the body): scale/position of that mesh, a dust puff, and a blob shadow. The body, its
## collision shape and its velocity are only read (one ray per physics step for the shadow).
## Squash/stretch keeps the volume roughly constant and the mesh's bottom on the contact surface.
##   pop()          the body was (re)placed: grows in from POP_START with an overshoot
##   stretch()      the body was let go: short stretch upwards
##   puff(s)        small dust puff under the body (0..1)
##   automatic      landing on the ground (fast downward speed stopping near ground_y): squash by
##                  the fall speed + dust + `landed(strength)`; coming to rest after that: wobble
class_name ArtJuice
extends Node3D

## A landing with strength 0..1 (the shell turns it into a small camera dip).
signal landed(strength: float)

## Spring of the squash and pop (k in 1/s^2, damping in 1/s): ~0.4 s period, settles in ~0.4 s.
const SPRING_K := 260.0
const SPRING_DAMP := 11.0
## Kick speeds of the squash spring (1/s; at 60 fps the peak deformation is about kick / 30,
## reached after ~0.07 s, back within 10 % after ~0.33 s).
const STRETCH_KICK := 3.5       # release: +12 % taller
const LAND_KICK := 9.0          # landing: -8 % (strength 0.25) to -30 % (strength 1)
const REST_KICK := 2.0          # coming to rest: -7 % wobble
const SQUASH_LIMIT := 0.38
const POP_START := 0.5          # reset: starts at half size, overshoots to +16 %, settles in ~0.45 s
const LAND_SPEED := 1.2         # m/s downward speed that counts as a landing
const LAND_FULL_SPEED := 6.0    # m/s for a full-strength landing
const REST_SPEED := 0.15        # m/s

var body: RigidBody3D
var mesh: MeshInstance3D
var size := 0.4                 # body height along its local y (m)
var ground_y := 0.0             # world height of the ground the body lands on

var _squash := 0.0              # +: taller/thinner, -: flatter/wider
var _squash_v := 0.0
var _pop := 1.0
var _pop_v := 0.0
var _prev_vy := 0.0
var _landed := false
var _resting := false
var _shadow: MeshInstance3D
var _dust: CPUParticles3D
var _ray := PhysicsRayQueryParameters3D.new()


func setup(target_body: RigidBody3D, target_mesh: MeshInstance3D, body_size: float, ground := 0.0) -> void:
	body = target_body
	mesh = target_mesh
	size = body_size
	ground_y = ground
	var s := ArtKit.shadow_builder()
	s.add_blob(Transform3D.IDENTITY, 1.0, ArtKit.shadow_alpha(1.35))
	_shadow = ArtKit.instance(s.commit(), ArtKit.shadow_material())
	_shadow.name = "BodyShadow"
	add_child(_shadow)
	_dust = CPUParticles3D.new()
	_dust.name = "Dust"
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 0.95
	_dust.amount = 16
	_dust.lifetime = 0.55
	_dust.local_coords = false
	var puff := ArtKit.builder()
	puff.ao_min = 1.0
	puff.add_sphere(Transform3D.IDENTITY, 0.11, 3, 6, ArtPalette.DUST)
	_dust.mesh = puff.commit()
	_dust.material_override = ArtKit.lit_material()
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


func pop() -> void:
	_landed = false
	_resting = false
	_squash = 0.0
	_squash_v = 0.0
	_pop = POP_START
	_pop_v = 0.0
	if is_inside_tree():
		_update_shadow()   # the body was moved: do not leave the shadow behind for a frame


func stretch() -> void:
	_squash_v += STRETCH_KICK


func puff(strength: float) -> void:
	if body == null:
		return
	var up := body.global_transform.basis.y.normalized()
	_dust.global_position = body.global_position - up * size * 0.48
	_dust.global_basis = Basis(Quaternion(Vector3.UP, up))
	_dust.amount = int(lerpf(8.0, 16.0, strength))
	_dust.initial_velocity_max = lerpf(0.9, 1.8, strength)
	_dust.restart()


## Current visual scale of the mesh (tests, style guide checks).
func mesh_scale() -> Vector3:
	return mesh.scale if mesh else Vector3.ONE


func _physics_process(_delta: float) -> void:
	if body == null:
		return
	var vy := body.linear_velocity.y
	var near_ground := body.global_position.y < ground_y + size * 0.5 + 0.12
	if not body.freeze and near_ground and not _landed and _prev_vy < -LAND_SPEED and vy > _prev_vy * 0.5:
		_landed = true
		var strength := clampf(-_prev_vy / LAND_FULL_SPEED, 0.25, 1.0)
		_squash_v -= LAND_KICK * strength
		puff(strength)
		landed.emit(strength)
	if _landed and not _resting and body.linear_velocity.length() < REST_SPEED:
		_resting = true
		_squash_v -= REST_KICK
	_prev_vy = vy
	_update_shadow()


func _process(delta: float) -> void:
	if mesh == null:
		return
	# Damped springs (semi-implicit Euler, clamped step).
	var dt := minf(delta, 1.0 / 30.0)
	_squash_v += (-SPRING_K * _squash - SPRING_DAMP * _squash_v) * dt
	_squash = clampf(_squash + _squash_v * dt, -SQUASH_LIMIT, SQUASH_LIMIT)
	_pop_v += (-SPRING_K * 0.7 * (_pop - 1.0) - SPRING_DAMP * 0.8 * _pop_v) * dt
	_pop += _pop_v * dt
	var sy := (1.0 + _squash) * _pop
	var sxz := (1.0 - _squash * 0.5) * _pop
	mesh.scale = Vector3(sxz, sy, sxz)
	# Keep the bottom face on the surface while the mesh squashes (body-local y = surface normal).
	mesh.position = Vector3(0.0, -size * 0.5 * (1.0 - sy), 0.0)


## Blob shadow straight below the body, on whatever is there; smaller and lighter when high.
func _update_shadow() -> void:
	var from := body.global_position
	_ray.from = from
	_ray.to = from + Vector3.DOWN * 12.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		_shadow.visible = false
		return
	_shadow.visible = true
	var height := maxf(0.0, from.y - (hit.position as Vector3).y - size * 0.5)
	var radius := size * 0.85 * clampf(1.0 - height * 0.18, 0.45, 1.0)
	var normal: Vector3 = hit.normal
	var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis.from_scale(Vector3(radius, 1.0, radius))
	_shadow.global_transform = Transform3D(basis, (hit.position as Vector3) + normal * 0.015)
