## Formula model of the spring lab (Phase 1 Task 4d; web preset "spring"): a ball on a horizontal rod
## pulled by the web's AnchoredSpringLaw (F = -k x - b v along the spring; k = 5 N/m, the web's)
## from its anchor, released from rest at extension x0. The ball moves along the rod (world +x) only.
## Its motion is the law's exact solution (PhysicsLaws.spring_release_displacement / _velocity:
## harmonicDisplacement / harmonicVelocity of oscillation.ts when b = 0), taken at t = steps dt, so
## no integrator error builds up: the period is 2 pi sqrt(m / k) and, without damping, the energy
## K + U = k x0^2 / 2 at every step. Energies are the TS definitions (mechanics.ts kineticEnergy,
## springPotentialEnergy).
class_name SpringModel
extends BodyModel

var anchor_x := -4.5
var rest_length := 3.0
var stiffness := 5.0
var damping := 0.0          # b (N s / m)
var mass := 1.0
## Extension at the release (m, + = stretched) and the extension / velocity now.
var x0 := 0.0
var extension := 0.0
var velocity := 0.0


## The ball at rest at extension `start` (waiting or released from there); y / z = the rod.
func reset(start: float, rod_y: float, rod_z: float) -> void:
	steps = 0
	stopped = false
	x0 = start
	extension = start
	velocity = 0.0
	y = rod_y
	z = rod_z
	_place()


func omega0() -> float:
	return PhysicsLaws.angular_frequency(stiffness, mass)


## gamma = b / 2m (1/s).
func gamma() -> float:
	return damping / (2.0 * mass)


func advance(_step_dt: float) -> void:
	var t := time()
	extension = PhysicsLaws.spring_release_displacement(x0, omega0(), gamma(), t)
	velocity = PhysicsLaws.spring_release_velocity(x0, omega0(), gamma(), t)
	_place()


func _place() -> void:
	x = anchor_x + rest_length + extension
	vx = velocity
	vy = 0.0
	vz = 0.0


## Restoring force along +x (N): AnchoredSpringLaw's radial force (-k x - b v).
func force() -> float:
	return PhysicsLaws.anchored_spring_force(extension, velocity, stiffness, damping)


func kinetic_energy() -> float:
	return PhysicsLaws.kinetic_energy(mass, absf(velocity))


func spring_energy() -> float:
	return PhysicsLaws.spring_potential_energy(stiffness, extension)


## K + U now; without damping it stays k x0^2 / 2 (the release energy).
func total_energy() -> float:
	return kinetic_energy() + spring_energy()


## Natural period 2 pi sqrt(m / k) (oscillation.ts periodFromAngularFrequency of omega0): without damping.
func natural_period() -> float:
	return PhysicsLaws.period_from_angular_frequency(omega0())


## Period of the oscillation actually happening: the natural period, or 2 pi / wd with damping
## (wd = sqrt(w0^2 - gamma^2), the damped angular frequency the TS model integrates with).
func period() -> float:
	if damping == 0.0:
		return natural_period()
	return TAU / PhysicsLaws.damped_angular_frequency(omega0(), gamma())
