## Visual-only reactions of one moving body (grass island style, apps/lab3d/docs/art-direction.md
## section 6). It only ever writes its own nodes and the `mesh` it was given (a MeshInstance3D child
## of the body): scale/position of that mesh, a dust puff, and a blob shadow. The body, its
## collision shape and its velocity are only read (one ray per physics step for the shadow).
## Squash/stretch keeps the volume roughly constant and the mesh's bottom on the contact surface.
## "Up" is the surface normal under the body (world up on the ground, the incline's normal on the
## incline), not the body's own y axis, so a body that landed rotated still flattens against the
## surface and its dust appears under it.
##   pop()          the body was (re)placed: grows in from POP_START with an overshoot
##   stretch()      the body was let go: short stretch upwards
##   puff(s)        small dust puff under the body (0..1)
##   hold(on)       picked up by a finger (Task 2b): the mesh floats HOLD_LIFT above the body;
##                  hold(false) lowers it again
##   settle()       put down by a finger: lowers the mesh with a small squash and dust
##   wobble()       cannot be placed here: a short sideways shake
##   automatic      landing on the ground (fast downward speed stopping near ground_y): squash by
##                  the fall speed + dust + `landed(strength)`; coming to rest after that: wobble
## Springs closer to rest than SETTLED_VALUE / SETTLED_SPEED stop updating (set_process(false)).
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
const HOLD_LIFT := 0.12         # m the mesh floats above a held body
const LIFT_K := 400.0           # critically damped (2 sqrt(k) = 40): reaches the lift in ~0.15 s
const LIFT_DAMP := 40.0
const WOBBLE_KICK := 1.6        # m/s sideways: ~4 cm shake
const WOBBLE_K := 900.0         # ~0.2 s period, gone in ~0.4 s
const WOBBLE_DAMP := 14.0
const SETTLE_KICK := 3.0        # put down: -10 % squash
const SETTLED_VALUE := 0.002    # springs closer than this to rest (and slower than SETTLED_SPEED) stop updating
const SETTLED_SPEED := 0.05

var body: RigidBody3D
var mesh: MeshInstance3D
var size := 0.4                 # body height along its local y (m)
## Dust grains of a full-strength puff (half of it for the weakest). Experiments with several
## bodies lower it to stay inside the particle budget (art-direction.md section 8).
var dust_amount := 16
var ground_y := 0.0             # world height of the ground the body lands on

var _squash := 0.0              # +: taller/thinner, -: flatter/wider
var _squash_v := 0.0
var _pop := 1.0
var _pop_v := 0.0
var _lift := 0.0                # mesh offset along the surface normal (m), see hold()
var _lift_v := 0.0
var _lift_goal := 0.0
var _wobble := 0.0              # sideways mesh offset (m), see wobble()
var _wobble_v := 0.0
var _scale := Vector3.ONE       # current squash scale along (sxz, sy, sxz), sy along `_normal`
var _normal := Vector3.UP       # surface normal under the body (world)
var _shadow_xf := Transform3D() # body transform at the last shadow update
var _prev_vy := 0.0
var _landed := false
var _resting := false
var _shadow: MeshInstance3D
var _dust: CPUParticles3D
var _ray := PhysicsRayQueryParameters3D.new()


## `ground_mask`: the layers the shadow ray hits (the ground the body lands on; default the world's
## layer 1, so handles on other layers, like the projectile arrow knob, are no shadow target).
func setup(target_body: RigidBody3D, target_mesh: MeshInstance3D, body_size: float, ground := 0.0, ground_mask := 1) -> void:
	body = target_body
	mesh = target_mesh
	size = body_size
	ground_y = ground
	set_process(false)   # woken by the first kick; a settled body costs no per-frame work
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
	_ray.collision_mask = ground_mask


## The next landing counts as a new one (squash, dust, landed signal), without any animation.
func rearm() -> void:
	_landed = false
	_resting = false


func pop() -> void:
	rearm()
	_squash = 0.0
	_squash_v = 0.0
	_pop = POP_START
	_pop_v = 0.0
	set_process(true)
	if is_inside_tree():
		_update_shadow()   # the body was moved: do not leave the shadow behind for a frame


func stretch() -> void:
	_squash_v += STRETCH_KICK
	set_process(true)


func hold(on: bool) -> void:
	_lift_goal = HOLD_LIFT if on else 0.0
	if on:
		_squash_v += STRETCH_KICK * 0.6
	set_process(true)


func settle() -> void:
	_lift_goal = 0.0
	_squash_v -= SETTLE_KICK
	set_process(true)
	puff(0.3)


func wobble() -> void:
	_wobble_v += WOBBLE_KICK
	set_process(true)


## True while a reaction is still moving the mesh (tests).
func is_animating() -> bool:
	return is_processing()


func puff(strength: float) -> void:
	if body == null:
		return
	var up := _normal
	_dust.global_position = body.global_position - up * _half_extent(up) * 0.96
	_dust.global_basis = Basis(Quaternion(Vector3.UP, up))
	_dust.amount = int(lerpf(dust_amount * 0.5, dust_amount, strength))
	_dust.initial_velocity_max = lerpf(0.9, 1.8, strength)
	_dust.restart()


## Current visual scale of the mesh (tests, style guide checks).
func mesh_scale() -> Vector3:
	return _scale


func _physics_process(_delta: float) -> void:
	if body == null:
		return
	var vy := body.linear_velocity.y
	var near_ground := body.global_position.y < ground_y + size * 0.5 + 0.12
	if not body.freeze and near_ground and not _landed and _prev_vy < -LAND_SPEED and vy > _prev_vy * 0.5:
		_landed = true
		var strength := clampf(-_prev_vy / LAND_FULL_SPEED, 0.25, 1.0)
		_squash_v -= LAND_KICK * strength
		set_process(true)
		puff(strength)
		landed.emit(strength)
	if _landed and not _resting and body.linear_velocity.length() < REST_SPEED:
		_resting = true
		_squash_v -= REST_KICK
		set_process(true)
	_prev_vy = vy
	# A body that has not moved or turned since the last update keeps its shadow and normal.
	if body.global_transform != _shadow_xf:
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
	_lift_v += (-LIFT_K * (_lift - _lift_goal) - LIFT_DAMP * _lift_v) * dt
	_lift += _lift_v * dt
	_wobble_v += (-WOBBLE_K * _wobble - WOBBLE_DAMP * _wobble_v) * dt
	_wobble += _wobble_v * dt
	if absf(_squash) < SETTLED_VALUE and absf(_squash_v) < SETTLED_SPEED and absf(_pop - 1.0) < SETTLED_VALUE and absf(_pop_v) < SETTLED_SPEED \
			and absf(_lift - _lift_goal) < SETTLED_VALUE and absf(_lift_v) < SETTLED_SPEED and absf(_wobble) < SETTLED_VALUE and absf(_wobble_v) < SETTLED_SPEED:
		_squash = 0.0
		_squash_v = 0.0
		_pop = 1.0
		_pop_v = 0.0
		_lift = _lift_goal
		_lift_v = 0.0
		_wobble = 0.0
		_wobble_v = 0.0
		set_process(false)   # at rest: one last write below, then nothing until the next kick
	var sy := (1.0 + _squash) * _pop
	var sxz := (1.0 - _squash * 0.5) * _pop
	_scale = Vector3(sxz, sy, sxz)
	# Scale by sy along the surface normal `u` and by sxz across it: M = sxz I + (sy - sxz) u u^T,
	# in the body's local space (the mesh is the body's child). The bottom face stays on the surface.
	var u := body.global_basis.inverse() * _normal
	var m := Basis.IDENTITY * sxz
	for r in 3:
		for c in 3:
			m[c][r] += (sy - sxz) * u[r] * u[c]
	var side := _normal.cross(Vector3.FORWARD)
	if side.length_squared() < 0.01:
		side = _normal.cross(Vector3.RIGHT)
	var offset := u * (_half_extent(_normal) * (sy - 1.0) + _lift) + body.global_basis.inverse() * side.normalized() * _wobble
	mesh.transform = Transform3D(m, offset)


## Half extent of the body (a cube of `size`) along the world direction `dir`.
func _half_extent(dir: Vector3) -> float:
	var l := body.global_basis.inverse() * dir
	return size * 0.5 * (absf(l.x) + absf(l.y) + absf(l.z))


## Blob shadow straight below the body, on whatever is there; smaller and lighter when high.
func _update_shadow() -> void:
	var from := body.global_position
	_shadow_xf = body.global_transform
	_ray.from = from
	_ray.to = from + Vector3.DOWN * 12.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		_shadow.visible = false
		_normal = Vector3.UP   # nothing below (fell off the island): no stale surface normal for puff/squash
		return
	_shadow.visible = true
	var height := maxf(0.0, from.y - (hit.position as Vector3).y - size * 0.5)
	var radius := size * 0.85 * clampf(1.0 - height * 0.18, 0.45, 1.0)
	var normal: Vector3 = hit.normal
	_normal = normal
	var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis.from_scale(Vector3(radius, 1.0, radius))
	_shadow.global_transform = Transform3D(basis, (hit.position as Vector3) + normal * 0.015)
