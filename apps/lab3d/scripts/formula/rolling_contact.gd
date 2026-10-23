## Formula friction and spin of a ball (solid sphere, I = 2/5 m r^2) on the level ground (Phase 1
## Task 4f; part of the uniform-field correction: UniformFieldCorrector.rolling,
## docs/formula-correction.md "Task 4f").
## Jolt keeps the normal contact (the floor holds the ball up, a bounce with the materials'
## restitution) and the engine friction is off (ball material friction 0). Every fixed step, before
## the physics server steps, this reads the normal impulse the engine gave in the last step (the
## vertical velocity change beyond the field's) and applies the Coulomb friction for it at the
## contact point:
##   slip u = v + omega x (-r up)  (contact point velocity; 0 = rolling, v = omega r),
##   friction impulse P opposite u, |P| <= mu m j  (j: normal impulse per mass of that step),
##   and no more than the impulse that ends the slip, 2/7 m |u| (then it rolls: v = omega r);
##   dv = P / m, domega = (-r up) x P / I.
## Resting on the floor j = g dt, so this is the kinetic friction force mu m g per step: a ball
## sliding without spin slows by mu g and rolls after t = 2 v0 / (7 mu g) at 5/7 v0. In a bounce j
## is the bounce's impulse (1 + e) |v_n| (+ g dt), so a bounce turns the ball as much as Coulomb
## friction allows. With the slip gone the ball rolls on unchanged (no rolling resistance), and in
## the air no force turns it (gravity acts at the centre): omega stays constant.
## The impulse is found after the engine step that had it, so its velocity and angle changes are
## also put back into that step (position += dv dt, rotation += domega dt): the friction acts in
## the same step as the normal impulse. The first released step has half the field (the leapfrog
## start), so a ball let go on the floor also gets half the friction there (positions on
## x0 + v0 t - mu g t^2 / 2). Velocities are 64-bit here and written to the body every step (the
## engine changes neither: no friction, normal impulses are vertical).
## Limits: one level ground (normal = up) and nothing else to touch (the balls' mask is the world).
class_name RollingContact
extends RefCounted

## Normal impulse per mass (m/s) below which a step counts as no contact (float32 noise of the
## free flight is ~1e-6; resting on the moon gives 1.62 / 60 = 0.027).
const CONTACT_IMPULSE_MIN := 1e-4

var radius := 0.25
var mass := 1.0
## Kinetic friction coefficient between the ball and the ground.
var mu := 0.6
## 64-bit velocity (x, z; m/s) and angular velocity (rad/s) the body is given every step.
var vx := 0.0
var vz := 0.0
var wx := 0.0
var wy := 0.0
var wz := 0.0
## Normal impulse per mass of the last engine step (m/s; 0 without contact) and the friction impulse
## per mass that answered it (m/s) - for tests.
var last_normal := 0.0
var last_friction := 0.0
## Steps with a contact, and the count of steps that ended a slip (it rolls from there) - for tests.
var contact_steps := 0
var stick_steps := 0
var _prev_vy := 0.0
var _expected_dvy := 0.0
var _started := false


## The ball is let go with `velocity` (and `spin`, rad/s; none by default).
func release(body: RigidBody3D, velocity: Vector3, spin := Vector3.ZERO) -> void:
	mass = body.mass
	vx = velocity.x
	vz = velocity.z
	wx = spin.x
	wy = spin.y
	wz = spin.z
	last_normal = 0.0
	last_friction = 0.0
	contact_steps = 0
	stick_steps = 0
	_started = false
	body.angular_velocity = spin


## Slip speed of the contact point (m/s; 0 = rolling).
func slip() -> float:
	var u := _slip()
	return sqrt(u.x * u.x + u.y * u.y)


## Speed along the ground (m/s).
func speed() -> float:
	return sqrt(vx * vx + vz * vz)


## One fixed step before the physics server steps. `field_dvy`: the vertical velocity change the
## field (and the leapfrog start) will give this step without a contact (m/s).
func apply(body: RigidBody3D, dt: float, field_dvy: float) -> void:
	if _started:
		var j := body.linear_velocity.y - _prev_vy - _expected_dvy
		last_normal = j if j > CONTACT_IMPULSE_MIN else 0.0
		last_friction = 0.0
		if last_normal > 0.0:
			contact_steps += 1
			_friction(body, last_normal, dt)
	_started = true
	body.linear_velocity = Vector3(vx, body.linear_velocity.y, vz)
	body.angular_velocity = Vector3(wx, wy, wz)
	_prev_vy = body.linear_velocity.y
	_expected_dvy = field_dvy


func _slip() -> Vector2:
	# omega x (0, -r, 0) = (r wz, 0, -r wx)
	return Vector2(vx + radius * wz, vz - radius * wx)


## Coulomb friction impulse for the normal impulse per mass `j` of the last step, put back into it.
func _friction(body: RigidBody3D, j: float, dt: float) -> void:
	var u := _slip()
	var slip_speed := sqrt(u.x * u.x + u.y * u.y)
	if slip_speed == 0.0:
		return
	var inertia := PhysicsLaws.solid_sphere_moment_of_inertia(mass, radius)
	var stick := slip_speed / (1.0 / mass + radius * radius / inertia)   # impulse that ends the slip
	var limit := mu * mass * j
	var p := minf(stick, limit)
	var px := -p * u.x / slip_speed
	var pz := -p * u.y / slip_speed
	var old_vx := vx
	var old_vz := vz
	var old_w := Vector3(wx, wy, wz)
	vx += px / mass
	vz += pz / mass
	# (-r up) x P = (-r pz, 0, r px)
	wx += -radius * pz / inertia
	wz += radius * px / inertia
	if stick <= limit:
		# Rolling from here: v = omega r exactly (no leftover slip from rounding).
		wz = -vx / radius
		wx = vz / radius
		stick_steps += 1
	last_friction = p / mass
	body.global_position += Vector3(vx - old_vx, 0.0, vz - old_vz) * dt
	var turn := (Vector3(wx, wy, wz) - old_w) * dt
	if turn.length() > 0.0:
		body.global_basis = Basis(turn.normalized(), turn.length()) * body.global_basis
