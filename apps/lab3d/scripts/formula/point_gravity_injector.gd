## Orbit experiment: PointGravity (a = G M / r^2 toward the centre) injected each step on a body
## with gravity_scale 0. The sample is the distance to the centre. The swept angle in the orbit
## plane is accumulated so a test or the panel can count revolutions. Displayed numbers (circular
## speed, period, escape speed, predicted outcome) come from PhysicsLaws (orbit.ts, OrbitChallenge).
class_name PointGravityInjector
extends ForceInjectionCorrector

var center := Vector3.ZERO
var mu := 1.0                       # G M (G = 1 in the formulas, M = mu)
var plane_normal := Vector3.UP      # orbit plane (for the swept angle)
var collision_radius := 1.0
var swept_angle := 0.0              # rad since reset, counter-clockwise about plane_normal
var _last_direction := Vector3.ZERO


func reset(body: RigidBody3D) -> void:
	super(body)
	swept_angle = 0.0
	_last_direction = (body.global_position - center).normalized()


func formula_force(body: RigidBody3D) -> Vector3:
	var offset := body.global_position - center
	var distance := offset.length()
	if distance == 0.0:
		return Vector3.ZERO
	return -offset / distance * (mass * PhysicsLaws.point_gravity_acceleration(mu, distance, 1.0))


func sample(body: RigidBody3D) -> float:
	var direction := (body.global_position - center).normalized()
	if _last_direction != Vector3.ZERO:
		swept_angle += _last_direction.signed_angle_to(direction, plane_normal)
	_last_direction = direction
	return (body.global_position - center).length()


func formula_values() -> Dictionary:
	var r := last_sample
	return {
		"radius": r,
		"circular_speed": PhysicsLaws.circular_orbit_speed(mu, r, 1.0),
		"period": PhysicsLaws.circular_orbit_period(mu, r, 1.0),
		"escape_speed": PhysicsLaws.escape_speed(mu, r, 1.0),
	}


## OrbitChallenge prediction for the body's current launch state, in the orbit plane's x/z axes
## (plane_normal = up).
func predict(body: RigidBody3D) -> Dictionary:
	var p := body.global_position - center
	var v := body.linear_velocity
	return PhysicsLaws.orbit_analyze(p.x, p.z, v.x, v.z, 0.0, 0.0, mu, collision_radius)
