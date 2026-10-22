## Formula model of the collision lab (Phase 1 Task 4c): the web's collision preset on the 3D rail,
## stepped in 64 bit. It owns everything the panel shows (state, velocities and momenta now, the first
## collision's velocities before / after, momentum, impulse, kinetic energy, restitution), the graph
## and the balls' motion: CollisionRailDriver poses the engine balls on its state every step.
## One fixed step = the web's advance() for this preset (src/app/physics-playground.ts) on the TS world
## (src/physics/world.ts MultiBodyWorld, explicit Euler solver):
##   1. integrate: x += v dt (no force acts along the rail),
##   2. resolveCollisions for the pair A-B (circles of radius_a / radius_b along x): when they touch,
##      push them apart by the penetration (in inverse mass ratio) and, closing in, apply
##      PhysicsLaws.world_collision_velocities (restitution min(eA, eB), 0 below `threshold`),
##   3. applyPresetDamping: v *= exp(-damping dt); slower than sleep_speed -> 0,
##   4. resolveWorldBounds: a ball past a wall is put on it and, moving outwards, v *= -e (its own).
## Checked against tests/collision_lab_vectors.json (tools/collision-lab-vectors.test.ts).
class_name CollisionModel
extends RefCounted

var mass_a := 1.0
var mass_b := 2.0
var radius_a := 0.4
var radius_b := 0.5
var restitution_a := 0.88       # TS material restitution of each ball (MATERIALS[material].restitution)
var restitution_b := 0.88
var threshold := 1.0            # m/s: physics-playground RESTING_REBOUND_SPEED (48 px/s)
var damping := 0.15             # 1/s: physics-playground COLLISION_WORLD_DAMPING
var sleep_speed := 2.0 / 48.0   # m/s: physics-playground MOTION_SLEEP_SPEED (2 px/s)
var wall := 7.0                 # m: the walls (bumper faces) at x = +-wall
## Centres and velocities along the rail (m, m/s; + = to the right).
var xa := 0.0
var xb := 0.0
var va := 0.0
var vb := 0.0
var steps := 0
## Collision resolutions that changed the velocities (impulses) since the reset.
var collisions := 0
## Step of the last impulse (-1 = none yet).
var last_collision_step := -1
## The first collision (the web's collisionResult; here also below the threshold, with e = 0):
## velocities just before / after it (m/s) and the restitution it used.
var collided := false
var _bound_x := 0.0
var _bound_v := 0.0
var first_step := -1
var before := PackedFloat64Array([0.0, 0.0])
var after := PackedFloat64Array([0.0, 0.0])
var restitution_used := 0.0


func reset(start_a: float, start_b: float, velocity_a: float, velocity_b: float) -> void:
	xa = start_a
	xb = start_b
	va = velocity_a
	vb = velocity_b
	steps = 0
	collisions = 0
	last_collision_step = -1
	collided = false
	first_step = -1
	before = PackedFloat64Array([0.0, 0.0])
	after = PackedFloat64Array([0.0, 0.0])
	restitution_used = 0.0


func step(dt: float) -> void:
	steps += 1
	xa += va * dt
	xb += vb * dt
	_resolve_collision()
	var k := exp(-damping * dt)
	va = _damped(va, k)
	vb = _damped(vb, k)
	_bound(xa, va, radius_a, restitution_a)
	xa = _bound_x
	va = _bound_v
	_bound(xb, vb, radius_b, restitution_b)
	xb = _bound_x
	vb = _bound_v


## world.ts resolveCollisions for the pair (A first, then B: the normal points from A to B).
func _resolve_collision() -> void:
	var d := xb - xa
	var distance := absf(d)
	var reach := radius_a + radius_b
	if distance > reach:
		return
	var n := 1.0 if d >= 0.0 else -1.0
	var inverse_a := 1.0 / mass_a
	var inverse_b := 1.0 / mass_b
	var push := maxf(0.0, reach - distance) / (inverse_a + inverse_b)
	xa -= n * push * inverse_a
	xb += n * push * inverse_b
	var normal_velocity := (vb - va) * n
	if normal_velocity >= 0.0:
		return
	var out := PhysicsLaws.world_collision_velocities(mass_a, mass_b, va, 0.0, vb, 0.0, n, 0.0,
		restitution_a, restitution_b, threshold)
	collisions += 1
	last_collision_step = steps
	if not collided:
		collided = true
		first_step = steps
		before = PackedFloat64Array([va, vb])
		after = PackedFloat64Array([out[0], out[2]])
		restitution_used = PhysicsLaws.collision_restitution(restitution_a, restitution_b, -normal_velocity, threshold)
	va = out[0]
	vb = out[2]


## physics-playground applyPresetDamping for one velocity.
func _damped(v: float, k: float) -> float:
	var damped := v * k
	return 0.0 if absf(damped) < sleep_speed else damped


## physics-playground resolveWorldBounds along the rail: (_bound_x, _bound_v) after the walls
## (64-bit floats, no per-step array).
func _bound(x: float, v: float, radius: float, restitution: float) -> void:
	var low := -wall + radius
	var high := wall - radius
	_bound_x = x
	_bound_v = v
	if x < low:
		_bound_x = low
		_bound_v = v * -restitution if v < 0.0 else v
	elif x > high:
		_bound_x = high
		_bound_v = v * -restitution if v > 0.0 else v


func at_rest() -> bool:
	return va == 0.0 and vb == 0.0


func momentum_a() -> float:
	return PhysicsLaws.momentum(mass_a, va)


func momentum_b() -> float:
	return PhysicsLaws.momentum(mass_b, vb)


## Momentum sum (kg m/s) and kinetic energy sum (J) of velocities (va, vb).
func momentum_of(velocity_a: float, velocity_b: float) -> float:
	return PhysicsLaws.momentum(mass_a, velocity_a) + PhysicsLaws.momentum(mass_b, velocity_b)


func kinetic_of(velocity_a: float, velocity_b: float) -> float:
	return PhysicsLaws.kinetic_energy(mass_a, absf(velocity_a)) + PhysicsLaws.kinetic_energy(mass_b, absf(velocity_b))


## Impulse each ball got in the first collision (kg m/s): its momentum change (J = F dt = dp).
func impulse_a() -> float:
	return PhysicsLaws.momentum(mass_a, after[0]) - PhysicsLaws.momentum(mass_a, before[0])


func impulse_b() -> float:
	return PhysicsLaws.momentum(mass_b, after[1]) - PhysicsLaws.momentum(mass_b, before[1])
