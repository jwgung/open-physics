## Minimal GDScript port of the TS formula core (src/physics/laws).
## Copied from spikes/godot/scripts/physics_laws.gd. Only the formulas the experiments need are
## ported. Each function names its TS source. Parity with TS is checked by tests/run_tests.gd
## against tests/incline_vectors.json, which tools/incline-vectors.test.ts regenerates/validates
## from the TS core (root `npm test`).
class_name PhysicsLaws
extends RefCounted

## orbit.ts circularOrbitSpeed: v = sqrt(GM / r)
static func circular_orbit_speed(central_mass: float, radius: float, gravitational_constant: float) -> float:
	assert(central_mass > 0.0 and radius > 0.0 and gravitational_constant > 0.0)
	return sqrt(gravitational_constant * central_mass / radius)

## orbit.ts circularOrbitPeriod: T = 2*pi*sqrt(r^3 / GM)
static func circular_orbit_period(central_mass: float, radius: float, gravitational_constant: float) -> float:
	return TAU * sqrt(pow(radius, 3.0) / (gravitational_constant * central_mass))

## mechanics.ts constantAccelerationDisplacement (1D): s = v0*t + a*t^2/2
static func constant_acceleration_displacement(v0: float, a: float, t: float) -> float:
	return v0 * t + 0.5 * a * t * t

## mechanics.ts constantAccelerationVelocity (1D): v = v0 + a*t
static func constant_acceleration_velocity(v0: float, a: float, t: float) -> float:
	return v0 + a * t

## Incline decomposition used by SurfaceContactFrictionModifier (world-mechanics.ts):
## tangential gravity = m g sin(theta), normal load = m g cos(theta).
static func incline_tangential_gravity(mass: float, g: float, theta: float) -> float:
	return mass * g * sin(theta)

static func incline_normal_load(mass: float, g: float, theta: float) -> float:
	return mass * g * cos(theta)

static func max_static_friction(mu_s: float, normal_load: float) -> float:
	return mu_s * normal_load

## Critical angle: theta_c = atan(mu_s)
static func critical_angle(mu_s: float) -> float:
	return atan(mu_s)

## Sliding acceleration down the incline: a = g (sin(theta) - mu_k cos(theta)), 0 while holding.
static func incline_acceleration(g: float, theta: float, mu_s: float, mu_k: float) -> float:
	if sin(theta) <= mu_s * cos(theta):
		return 0.0
	return g * (sin(theta) - mu_k * cos(theta))

## World-mechanics.ts combineCoefficients: geometric mean of body and surface coefficients.
static func combine_coefficients(a: float, b: float) -> float:
	return sqrt(maxf(0.0, a) * maxf(0.0, b))

## 1D port of SurfaceContactFrictionModifier.modifyForce along one contact tangent.
## tangential_force: net non-friction force along the tangent (N), tangential_speed: m/s.
## Returns the corrected tangential force (N) after static/kinetic friction.
static func corrected_tangential_force(
		tangential_force: float, tangential_speed: float, normal_load: float,
		mu_s: float, mu_k: float, mass: float, dt: float) -> float:
	if normal_load <= 0.0:
		return tangential_force
	var max_static := mu_s * normal_load
	if absf(tangential_speed) < 0.01 and absf(tangential_force) <= max_static:
		return 0.0
	var direction := signf(tangential_speed) if absf(tangential_speed) >= 0.01 else signf(tangential_force)
	var next_force := tangential_force - direction * mu_k * normal_load
	if absf(tangential_speed) >= 0.01:
		var next_speed := tangential_speed + next_force / mass * dt
		if tangential_speed * next_speed <= 0.0:
			next_force = -mass * tangential_speed / dt
	return next_force
