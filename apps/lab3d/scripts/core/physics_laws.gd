## GDScript port of the TS formula core (src/physics/laws, plus the guided-lab models in
## src/app/mechanics-scenes.ts and mechanics-challenges.ts). Started from
## spikes/godot/scripts/physics_laws.gd; Task 3 added the laws of the 10 guided mechanics
## experiments. Only the formulas the experiments need are ported. Each function names its TS
## source. Scalars only (GDScript float is 64-bit; Vector2/Vector3 are 32-bit), so a port matches
## the TS value to ~1e-15 relative. Parity is checked by tests/run_tests.gd against
## tests/incline_vectors.json and tests/formula_vectors.json, which tools/incline-vectors.test.ts
## and tools/formula-vectors.test.ts generate/validate from the TS core (root `npm test`).
## Lengths are SI metres; the 2D web app works in px (48 px = 1 m) with the same formulas.
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

## world-mechanics.ts PushFrictionLaw "nearly stopped" speed: 0.01 px/s in the web app's units
## (48 px = 1 m), i.e. 0.01 / 48 m/s here. The tests feed the TS law px values (x 48) for this.
const PUSH_REST_SPEED := 0.01 / 48.0

## world-mechanics.ts PushFrictionLaw.maximumStaticForce: mu_s m a_n (a_n = normal acceleration, g on a level floor).
static func push_max_static_force(mu_s: float, mass: float, normal_acceleration: float) -> float:
	return mu_s * mass * normal_acceleration

## world-mechanics.ts PushFrictionLaw.status == "holding": nearly stopped and |F| <= mu_s m a_n.
static func push_friction_holding(applied_force: float, speed: float, mass: float, mu_s: float, normal_acceleration: float) -> bool:
	return absf(speed) < PUSH_REST_SPEED and absf(applied_force) <= push_max_static_force(mu_s, mass, normal_acceleration)

## world-mechanics.ts PushFrictionLaw.force (1D): net horizontal force = applied - kinetic friction,
## 0 while holding, clamped so one step cannot reverse the motion.
static func push_friction_force(applied_force: float, speed: float, mass: float, mu_s: float, mu_k: float,
		normal_acceleration: float, dt: float) -> float:
	if push_friction_holding(applied_force, speed, mass, mu_s, normal_acceleration):
		return 0.0
	var direction := signf(speed) if absf(speed) >= PUSH_REST_SPEED else signf(applied_force)
	var kinetic := mu_k * mass * normal_acceleration
	var net := applied_force - direction * kinetic
	if speed * net < 0.0 and absf(net) * dt / mass >= absf(speed):
		net = -mass * speed / dt
	return net


## basic.ts KineticFriction.force (magnitude): F = mu N on a moving body (Task 4b: the friction lab's
## "운동 마찰력" readout, N = m g on the level floor).
static func kinetic_friction_force(mu_k: float, normal_load: float) -> float:
	return mu_k * normal_load

## mechanics.ts work (1D): W = F d (Task 4b: friction work turned into heat, step by step).
static func work_1d(force: float, displacement: float) -> float:
	return force * displacement

# --- free fall, projectile (mechanics.ts, gravity.ts) -------------------------------------------

## gravity.ts UniformGravity.force (magnitude): F = m g
static func uniform_gravity_force(mass: float, g: float) -> float:
	return mass * g

## mechanics.ts kineticEnergy: K = m v^2 / 2 (speed = |v|)
static func kinetic_energy(mass: float, speed: float) -> float:
	return 0.5 * mass * (speed * speed)

## mechanics.ts momentum (1D): p = m v
static func momentum(mass: float, velocity: float) -> float:
	return mass * velocity

## mechanics.ts gravitationalPotentialEnergy: U = m g h
static func gravitational_potential_energy(mass: float, g: float, height: float) -> float:
	return mass * g * height

## Landing time in a uniform field (Task 4a: free fall, projectile): the first t > 0 at which
## constantAccelerationDisplacement(v0, a, t) = -drop along one axis (v0 and a along +up; drop: how
## far below the start the landing level is, < 0 above it), i.e. the first positive root of
## a t^2 / 2 + v0 t + drop = 0 for any signs of v0, a and drop. A start on the level (drop = 0) that
## moves below it at once (v0 < 0, or v0 = 0 and a < 0) lands at t = 0. INF when the body never
## reaches the level (no positive root). No closed form in the TS core: the vectors
## (tools/formula-vectors.test.ts) find the same root of the TS function by bisection (ts-oracle.ts).
static func landing_time(v0: float, a: float, drop: float) -> float:
	if drop == 0.0 and (v0 < 0.0 or (v0 == 0.0 and a < 0.0)):
		return 0.0
	if a == 0.0:
		var t := -drop / v0 if v0 != 0.0 else INF
		return t if t > 0.0 else INF
	var disc := v0 * v0 - 2.0 * a * drop
	if disc < 0.0:
		return INF
	var root := sqrt(disc)
	var first := INF
	for t in [(-v0 - root) / a, (-v0 + root) / a]:
		if t > 0.0 and t < first:
			first = t
	return first

## Apex of a throw in a uniform field (Task 4a: projectile): time at which
## constantAccelerationVelocity(v0, a, t) = 0 (0 when the body does not rise: v0 <= 0 or a >= 0 with
## v0 <= 0; INF for a rising body without a field) and the rise to it,
## constantAccelerationDisplacement(v0, a, t_apex). TS vectors: root of the TS velocity by bisection.
static func apex_time(v0: float, a: float) -> float:
	if v0 <= 0.0:
		return 0.0
	return v0 / -a if a < 0.0 else INF

static func apex_rise(v0: float, a: float) -> float:
	if v0 <= 0.0:
		return 0.0
	return v0 * v0 / (-2.0 * a) if a < 0.0 else INF

# --- collision (mechanics.ts, collision.ts, world.ts) --------------------------------------------

## mechanics.ts postCollisionVelocity1D: first body after a 1D collision with restitution e.
static func post_collision_velocity_1d(m1: float, u1: float, m2: float, u2: float, restitution: float) -> float:
	return ((m1 - restitution * m2) * u1 + (1.0 + restitution) * m2 * u2) / (m1 + m2)

## mechanics.ts postCollisionVelocity1DSecond: second body.
static func post_collision_velocity_1d_second(m1: float, u1: float, m2: float, u2: float, restitution: float) -> float:
	return ((m2 - restitution * m1) * u2 + (1.0 + restitution) * m1 * u1) / (m1 + m2)

## collision.ts elasticCollision1D: [vA, vB].
static func elastic_collision_1d(mass_a: float, velocity_a: float, mass_b: float, velocity_b: float) -> PackedFloat64Array:
	assert(mass_a > 0.0 and mass_b > 0.0)
	var denominator := mass_a + mass_b
	return PackedFloat64Array([
		((mass_a - mass_b) * velocity_a + 2.0 * mass_b * velocity_b) / denominator,
		(2.0 * mass_a * velocity_a + (mass_b - mass_a) * velocity_b) / denominator])

## world.ts MultiBodyWorld.resolveCollisions restitution rule: e = min(eA, eB), 0 when the closing
## speed is below the threshold (the web app uses 48 px/s = 1 m/s).
static func collision_restitution(restitution_a: float, restitution_b: float, closing_speed: float, threshold: float) -> float:
	return 0.0 if closing_speed < threshold else minf(restitution_a, restitution_b)

## world.ts MultiBodyWorld.resolveCollisions velocity update for two movable bodies; the normal
## (nx, ny) is unit and points from A to B. Returns [vax, vay, vbx, vby]; unchanged when separating.
static func world_collision_velocities(mass_a: float, mass_b: float, vax: float, vay: float, vbx: float, vby: float,
		nx: float, ny: float, restitution_a: float, restitution_b: float, threshold: float) -> PackedFloat64Array:
	var normal_velocity := (vbx - vax) * nx + (vby - vay) * ny
	var restitution := collision_restitution(restitution_a, restitution_b, -normal_velocity, threshold)
	var inverse_a := 1.0 / mass_a
	var inverse_b := 1.0 / mass_b
	if normal_velocity >= 0.0:
		return PackedFloat64Array([vax, vay, vbx, vby])
	var impulse := -(1.0 + restitution) * normal_velocity / (inverse_a + inverse_b)
	return PackedFloat64Array([vax - nx * (impulse * inverse_a), vay - ny * (impulse * inverse_a),
		vbx + nx * (impulse * inverse_b), vby + ny * (impulse * inverse_b)])

# --- spring (world-mechanics.ts, oscillation.ts, mechanics.ts) -----------------------------------

## world-mechanics.ts AnchoredSpringLaw.force (radial component): F = -k x - b v_r
static func anchored_spring_force(extension: float, radial_velocity: float, stiffness: float, damping: float) -> float:
	return -stiffness * extension - damping * radial_velocity

## mechanics.ts springPotentialEnergy: U = k x^2 / 2
static func spring_potential_energy(stiffness: float, displacement: float) -> float:
	return 0.5 * stiffness * (displacement * displacement)

## oscillation.ts angularFrequency: omega = sqrt(k / m)
static func angular_frequency(stiffness: float, mass: float) -> float:
	assert(stiffness > 0.0 and mass > 0.0)
	return sqrt(stiffness / mass)

## oscillation.ts periodFromAngularFrequency: T = 2 pi / omega
static func period_from_angular_frequency(omega: float) -> float:
	assert(omega > 0.0)
	return TAU / omega

## oscillation.ts harmonicDisplacement: x = A cos(omega t + phi)
static func harmonic_displacement(amplitude: float, omega: float, time: float, phase: float) -> float:
	return amplitude * cos(omega * time + phase)

## oscillation.ts harmonicVelocity: v = -A omega sin(omega t + phi)
static func harmonic_velocity(amplitude: float, omega: float, time: float, phase: float) -> float:
	return -amplitude * omega * sin(omega * time + phase)

## oscillation.ts harmonicEnergy: E = k A^2 / 2
static func harmonic_energy(stiffness: float, amplitude: float) -> float:
	return 0.5 * stiffness * (amplitude * amplitude)

## Spring lab (Task 4d): the motion AnchoredSpringLaw gives a body released from rest at extension
## x0 along the spring (m x'' = -k x - b x'), the exact solution of that law for the underdamped
## case (gamma = b / 2m < omega0 = sqrt(k / m), the lab's every condition):
## x(t) = e^(-gamma t) (x0 cos(wd t) + gamma x0 / wd sin(wd t)), wd = sqrt(omega0^2 - gamma^2).
## The TS core has it only for gamma = 0 (oscillation.ts harmonicDisplacement / harmonicVelocity,
## used then); the vectors check both against an integration of the TS law
## (tools/spring-lab-vectors.test.ts).
static func spring_release_displacement(x0: float, omega0: float, gamma: float, t: float) -> float:
	if gamma == 0.0:
		return harmonic_displacement(x0, omega0, t, 0.0)
	var wd := damped_angular_frequency(omega0, gamma)
	return exp(-gamma * t) * (x0 * cos(wd * t) + gamma * x0 / wd * sin(wd * t))

## Velocity of spring_release_displacement: v(t) = -e^(-gamma t) x0 omega0^2 / wd sin(wd t).
static func spring_release_velocity(x0: float, omega0: float, gamma: float, t: float) -> float:
	if gamma == 0.0:
		return harmonic_velocity(x0, omega0, t, 0.0)
	var wd := damped_angular_frequency(omega0, gamma)
	return -exp(-gamma * t) * x0 * omega0 * omega0 / wd * sin(wd * t)

## Angular frequency of the damped oscillation: wd = sqrt(omega0^2 - gamma^2) (underdamped only).
static func damped_angular_frequency(omega0: float, gamma: float) -> float:
	assert(gamma >= 0.0 and gamma < omega0)
	return sqrt(omega0 * omega0 - gamma * gamma)

# --- lever (mechanics-challenges.ts LeverChallenge, rotation.ts) ---------------------------------

## LeverChallenge.requiredForce: F = m g r_load / r_effort
static func lever_required_force(load_mass: float, g: float, load_arm: float, effort_arm: float) -> float:
	return load_mass * g * load_arm / effort_arm

## LeverChallenge.mechanicalAdvantage: r_effort / r_load
static func lever_mechanical_advantage(load_arm: float, effort_arm: float) -> float:
	return effort_arm / load_arm

## LeverChallenge.applyForce(f).lifting: max(0, f) >= required
static func lever_lifting(applied_force: float, required_force: float) -> bool:
	return maxf(0.0, applied_force) >= required_force

## rotation.ts torque (2D, counter-clockwise positive): tau = r x F
static func torque_2d(rx: float, ry: float, fx: float, fy: float) -> float:
	return rx * fy - ry * fx

# --- pendulum (oscillation.ts, mechanics-scenes.ts PendulumModel) --------------------------------

## oscillation.ts pendulumPeriod (small angle): T = 2 pi sqrt(L / g)
static func pendulum_period(length: float, g: float) -> float:
	assert(length > 0.0 and g > 0.0)
	return TAU * sqrt(length / g)

## oscillation.ts pendulumAngularFrequency: omega = sqrt(g / L)
static func pendulum_angular_frequency(length: float, g: float) -> float:
	assert(length > 0.0 and g > 0.0)
	return sqrt(g / length)

## PendulumModel.step (semi-implicit Euler): returns [angle, angular_velocity, angular_acceleration].
static func pendulum_step(angle: float, angular_velocity: float, dt: float, g: float, length: float, damping: float) -> PackedFloat64Array:
	var angular_acceleration := -(g / length) * sin(angle) - damping * angular_velocity
	var next_velocity := angular_velocity + angular_acceleration * dt
	return PackedFloat64Array([angle + next_velocity * dt, next_velocity, angular_acceleration])

## PendulumModel.pose().position relative to the anchor, in the model's frame (y along gravity):
## [L sin(angle), L cos(angle)].
static func pendulum_offset(length: float, angle: float) -> PackedFloat64Array:
	return PackedFloat64Array([length * sin(angle), length * cos(angle)])

# --- pulley (mechanics-challenges.ts PulleyAdvantageChallenge) -----------------------------------

## PulleyAdvantageChallenge.requiredForce: F = m g / n (n = 1, 2, 4 supporting strands)
static func pulley_required_force(load_mass: float, g: float, strands: int) -> float:
	assert(strands == 1 or strands == 2 or strands == 4)
	return load_mass * g / strands

## PulleyAdvantageChallenge.pullDistanceForLift: d_pull = n d_lift
static func pulley_pull_distance(lift_distance: float, strands: int) -> float:
	return lift_distance * strands

## PulleyAdvantageChallenge.liftDistanceForPull: d_lift = d_pull / n
static func pulley_lift_distance(pull_distance: float, strands: int) -> float:
	return pull_distance / strands

# --- orbit (orbit.ts, gravity.ts, mechanics-challenges.ts OrbitChallenge) -------------------------

## orbit.ts escapeSpeed: v = sqrt(2 G M / r)
static func escape_speed(central_mass: float, radius: float, gravitational_constant: float) -> float:
	assert(central_mass > 0.0 and radius > 0.0 and gravitational_constant > 0.0)
	return sqrt(2.0 * gravitational_constant * central_mass / radius)

## gravity.ts PointGravity.force / m: a = G M / r^2 (toward the source)
static func point_gravity_acceleration(central_mass: float, distance: float, gravitational_constant: float) -> float:
	if distance == 0.0:
		return 0.0
	return gravitational_constant * central_mass / (distance * distance)

## OrbitChallenge.analyze: predicted outcome of a launch around a centre with GM = mu.
## Returns {outcome: "crash"|"orbit"|"escape", speed, circular_speed, escape_speed,
## path: PackedFloat64Array [x0, y0, x1, y1, ...]} (same integration as the TS predictor).
static func orbit_analyze(px: float, py: float, vx: float, vy: float, cx: float, cy: float,
		mu: float, collision_radius: float) -> Dictionary:
	var radius := sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
	var path := PackedFloat64Array([px, py])
	if radius <= collision_radius:
		return _orbit_result("crash", path, radius, vx, vy, mu, collision_radius)
	var x := px
	var y := py
	var svx := vx
	var svy := vy
	var initial_energy := (vx * vx + vy * vy) / 2.0 - mu / radius
	var dt := maxf(0.02, minf(0.12, radius / maxf(sqrt(vx * vx + vy * vy), 1.0) / 140.0))
	for step in 1200:
		var dx := x - cx
		var dy := y - cy
		var distance := sqrt(dx * dx + dy * dy)
		var acceleration_scale := -mu / (distance * distance * distance)
		svx += dx * acceleration_scale * dt
		svy += dy * acceleration_scale * dt
		x += svx * dt
		y += svy * dt
		if step % 3 == 0:
			path.append(x)
			path.append(y)
		var next_distance := sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
		if next_distance <= collision_radius:
			path.append(x)
			path.append(y)
			return _orbit_result("crash", path, radius, vx, vy, mu, collision_radius)
		if initial_energy >= 0.0 and next_distance > radius * 4.0:
			return _orbit_result("escape", path, radius, vx, vy, mu, collision_radius)
	return _orbit_result("escape" if initial_energy >= 0.0 else "orbit", path, radius, vx, vy, mu, collision_radius)

static func _orbit_result(outcome: String, path: PackedFloat64Array, radius: float, vx: float, vy: float,
		mu: float, collision_radius: float) -> Dictionary:
	var safe_radius := maxf(radius, collision_radius)
	return {
		"outcome": outcome,
		"path": path,
		"speed": sqrt(vx * vx + vy * vy),
		"circular_speed": sqrt(mu / safe_radius),
		"escape_speed": sqrt(2.0 * mu / safe_radius),
	}

# --- buoyancy (fluid.ts, world-mechanics.ts BuoyancyRegionLaw) ------------------------------------

## mechanics.ts density: rho = m / V
static func density(mass: float, volume: float) -> float:
	return mass / volume

## fluid.ts buoyantForce: F_b = rho g V
static func buoyant_force(fluid_density: float, g: float, displaced_volume: float) -> float:
	return fluid_density * g * displaced_volume

## fluid.ts buoyancyNetForce: (rho_fluid - rho_object) g V (up positive)
static func buoyancy_net_force(fluid_density: float, object_density: float, g: float, volume: float) -> float:
	return (fluid_density - object_density) * g * volume

## fluid.ts floatingSubmergedFraction: V_sub / V = rho_object / rho_fluid
static func floating_submerged_fraction(object_density: float, fluid_density: float) -> float:
	assert(fluid_density > 0.0)
	return object_density / fluid_density

## BuoyancyRegionLaw submerged fraction: depth of the body's bottom below the waterline over its
## height, clamped to [0, 1] (linear in depth: exact for an upright prism).
static func submerged_fraction(bottom_depth: float, height: float) -> float:
	return maxf(0.0, minf(1.0, bottom_depth / height))

## BuoyancyRegionLaw vertical force (up positive): m_displaced g f - v_up * drag f m.
static func buoyancy_region_force(displaced_mass: float, g: float, drag: float, fraction: float, mass: float, velocity_up: float) -> float:
	if fraction == 0.0:
		return 0.0
	return displaced_mass * g * fraction - velocity_up * (drag * fraction * mass)

## BuoyancyRegionLaw horizontal drag (per axis): -v * drag f m.
static func buoyancy_drag_force(drag: float, fraction: float, mass: float, velocity: float) -> float:
	if fraction == 0.0:
		return 0.0
	return -velocity * (drag * fraction * mass)

# --- model runs -------------------------------------------------------------------------------

## PendulumModel stepped `steps` times from (angle, angular_velocity): [angle, angular_velocity].
static func pendulum_run(angle: float, angular_velocity: float, dt: float, g: float, length: float,
		damping: float, steps: int) -> PackedFloat64Array:
	var state := PackedFloat64Array([angle, angular_velocity, 0.0])
	for i in steps:
		state = pendulum_step(state[0], state[1], dt, g, length, damping)
	return PackedFloat64Array([state[0], state[1]])
