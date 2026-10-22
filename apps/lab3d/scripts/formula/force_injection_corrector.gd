## Force injection (method "force_injection"): forces Jolt does not model the way the TS core does
## (Hooke spring, Archimedes buoyancy with drag, inverse-square point gravity) are computed by
## PhysicsLaws from the body's state each fixed step and applied before the step. Jolt integrates
## (symplectic Euler) and owns contacts. Leapfrog start: on the first released step half of the net
## force (formula force + engine gravity) acts, so the positions are those of velocity Verlet: the
## period of an oscillation or orbit is right to O((omega dt)^2) and energy does not drift.
## Jolt alternatives that were measured and rejected are in docs/formula-correction.md
## (Generic6DOFJoint3D spring: energy not conserved; Area3D point gravity: no TS-matching law).
## Subclasses implement formula_force() and sample().
class_name ForceInjectionCorrector
extends FormulaCorrector

var mass := 1.0
var dt := 1.0 / 60.0
## Engine gravity acting on the body (m/s^2), read on reset.
var engine_gravity := Vector3.ZERO


func _init() -> void:
	method = "force_injection"


## Starts a run with the body at its current state (call when it is released).
func reset(body: RigidBody3D) -> void:
	reset_history()
	mass = body.mass
	engine_gravity = body.get_gravity() * body.gravity_scale


## Formula force (N) on the body in its current state.
func formula_force(_body: RigidBody3D) -> Vector3:
	return Vector3.ZERO


## The measured quantity recorded each step.
func sample(_body: RigidBody3D) -> float:
	return 0.0


func apply(body: RigidBody3D, step_dt: float) -> void:
	dt = step_dt
	record(sample(body))
	var force := formula_force(body)
	var factor := start_factor(steps == 0)
	if factor != 1.0:
		force = factor * force - (1.0 - factor) * mass * engine_gravity   # net (F + m g) / 2 on the first step
	body.apply_central_force(force)
	steps += 1


## Velocity at the step point (engine velocities are half a step behind under leapfrog):
## v_k = v_(k-1/2) + a(x_k) dt / 2.
func synced_velocity(body: RigidBody3D) -> Vector3:
	return body.linear_velocity + (formula_force(body) / mass + engine_gravity) * (0.5 * dt)
