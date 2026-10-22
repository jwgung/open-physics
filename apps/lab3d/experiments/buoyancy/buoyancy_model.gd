## Formula model of the buoyancy lab (Phase 1 Task 4d; web preset "buoyancy"): an upright cylinder
## (a drum) in a water tank under the web's BuoyancyRegionLaw (world-mechanics.ts: up force
## rho_water V g f - v drag f m with the submerged fraction f linear in the depth of its bottom,
## exact for an upright prism) and uniform gravity m g (gravity.ts UniformGravity). It moves up and
## down only (released from rest: the law's sideways drag never acts).
## Stepping: semi-implicit Euler (v += a h, then y += v h) with SUBSTEPS per fixed step (h = dt / 4):
## the web's explicit Euler (y += v h first) adds energy to the bobbing and does not settle a light
## drum at 60 Hz (tools/buoyancy-lab-vectors.test.ts, "web integrator"). The tank floor is the web's
## world bound (resolveWorldBounds bottom): the drum is put on it and a downward velocity rebounds
## with e = 0.5 (the web's wood), or stops when the rebound is slower than 1 m/s (RESTING_REBOUND_SPEED).
## Displayed values: PhysicsLaws (fluid.ts floatingSubmergedFraction, mechanics.ts density, the law's
## forces); the floating depth and the judgement come from the densities, not from the motion.
class_name BuoyancyModel
extends BodyModel

const SUBSTEPS := 4
const FLOOR_RESTITUTION := 0.5      # physics-playground buoyancy ball material "wood"
const REBOUND_MIN := 1.0            # m/s, physics-playground RESTING_REBOUND_SPEED (48 px/s)
const NEUTRAL_TOLERANCE := 1e-9     # |rho_object / rho_water - 1| that counts as neutral buoyancy
const HIT_SPEED := 0.05             # m/s: a floor contact faster than this is a hit (resting on it is not)

var mass := 70.0
var displaced_mass := 100.0         # rho_water V: the water a fully submerged drum pushes away (kg)
var height := 0.5                   # drum height (m)
var waterline := 1.5
var floor_y := 0.2                  # tank floor (the drum's bottom stops here)
var g := 9.81
var drag := 1.8                     # 1/s, BuoyancyRegionLaw default
## The drum's bottom hit the tank floor (faster than HIT_SPEED) in the last step, and how fast.
var hit_floor := false
var hit_speed := 0.0
## Fast entries into the water (the bottom crossed the waterline going down) and that speed.
var entered := false
var entry_speed := 0.0


## The drum at rest with its centre at `centre_y` (waiting or released from there).
func reset(centre_y: float, at_x: float, at_z: float) -> void:
	steps = 0
	stopped = false
	x = at_x
	y = centre_y
	z = at_z
	vx = 0.0
	vy = 0.0
	vz = 0.0
	hit_floor = false
	entered = false


func advance(dt: float) -> void:
	hit_floor = false
	entered = false
	var h := dt / SUBSTEPS
	for i in SUBSTEPS:
		var was_dry := bottom() >= waterline
		vy += net_force() / mass * h
		y += vy * h
		if was_dry and bottom() < waterline and vy < 0.0:
			entered = true
			entry_speed = -vy
		if bottom() < floor_y:
			y = floor_y + height * 0.5
			if vy < 0.0:
				if -vy > HIT_SPEED:
					hit_floor = true
					hit_speed = -vy
				var rebound := -vy * FLOOR_RESTITUTION
				vy = 0.0 if rebound < REBOUND_MIN else rebound


func bottom() -> float:
	return y - height * 0.5


## Submerged fraction f (0..1, linear in the bottom's depth).
func fraction() -> float:
	return PhysicsLaws.submerged_fraction(waterline - bottom(), height)


func depth() -> float:
	return fraction() * height


## Buoyant force now: rho_water g V_submerged = m_displaced g f (N, up).
func buoyant_force() -> float:
	return PhysicsLaws.buoyancy_region_force(displaced_mass, g, 0.0, fraction(), mass, 0.0)


func weight() -> float:
	return PhysicsLaws.uniform_gravity_force(mass, g)


## The law's up force (buoyancy and water drag) plus gravity (N, up +).
func net_force() -> float:
	return PhysicsLaws.buoyancy_region_force(displaced_mass, g, drag, fraction(), mass, vy) - weight()


## rho_object / rho_water (same volume: the mass ratio).
func density_ratio() -> float:
	return PhysicsLaws.floating_submerged_fraction(mass, displaced_mass)


## "floats", "neutral" (stays at any depth) or "sinks", from the densities.
func judgement() -> String:
	var ratio := density_ratio()
	if ratio < 1.0 - NEUTRAL_TOLERANCE:
		return "floats"
	if ratio > 1.0 + NEUTRAL_TOLERANCE:
		return "sinks"
	return "neutral"


## Depth the drum floats at (m): rho_object / rho_water of its height; all of it when it does not float.
func floating_depth() -> float:
	return minf(1.0, density_ratio()) * height

