## Buoyancy experiment: BuoyancyRegionLaw injected each step. The submerged fraction is the depth
## of the body's bottom below the waterline over its height (linear: exact for an upright prism
## such as the box used in 3D; the web ball uses the same linear rule). Up force
## m_displaced g f - v_up * drag f m, horizontal drag -v * drag f m. Engine gravity stays on.
## The sample is the submerged fraction; the floating fraction shown is the formula
## rho_object / rho_fluid = m / m_displaced (floating_submerged_fraction).
class_name BuoyancyInjector
extends ForceInjectionCorrector

var waterline := 0.0
var height := 0.4              # body height (m), bottom = centre - height / 2
var displaced_mass := 1.45     # fluid mass displaced when fully submerged (rho_fluid V)
var drag := 1.8                # 1/s


func fraction(body: RigidBody3D) -> float:
	var bottom := body.global_position.y - height * 0.5
	return PhysicsLaws.submerged_fraction(waterline - bottom, height)


func formula_force(body: RigidBody3D) -> Vector3:
	var f := fraction(body)
	var g := -engine_gravity.y
	var v := body.linear_velocity
	return Vector3(
		PhysicsLaws.buoyancy_drag_force(drag, f, mass, v.x),
		PhysicsLaws.buoyancy_region_force(displaced_mass, g, drag, f, mass, v.y),
		PhysicsLaws.buoyancy_drag_force(drag, f, mass, v.z))


func sample(body: RigidBody3D) -> float:
	return fraction(body)


func formula_values() -> Dictionary:
	var g := -engine_gravity.y
	var floating := PhysicsLaws.floating_submerged_fraction(mass, displaced_mass)   # same volume: rho ratio = mass ratio
	return {
		"floating_fraction": minf(1.0, floating),
		"floating_depth": minf(1.0, floating) * height,
		"buoyant_force": PhysicsLaws.buoyancy_region_force(displaced_mass, g, 0.0, last_sample, mass, 0.0),   # rho g V_sub
		"weight": PhysicsLaws.uniform_gravity_force(mass, g),
		"sinks": floating >= 1.0,
	}
