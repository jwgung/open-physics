## Base of the formula correction layer (docs/formula-correction.md).
## A guided experiment runs on Jolt, but its key motion and every displayed number must match the TS
## formula core (src/physics/laws, ported in PhysicsLaws). A corrector owns one experiment's
## correction: it runs once per fixed step *before* the physics server steps (call `step` or
## `apply` from `_physics_process`; FormulaBody / FormulaDriver do that), keeps a bounded history of
## one measured sample per step, and separates two kinds of values:
## - formula_values(): what the panel shows as numbers (always computed by PhysicsLaws),
## - engine_values(): engine measurements, shown only with a simulation label or as graph points.
## Methods (the `method` id; one subclass each):
##   contact_force   ContactFrictionCorrector   engine friction 0, formula friction force per step
##   uniform_field   UniformFieldCorrector      engine gravity, leapfrog start, flight samples
##   collision       CollisionCorrector         engine contact detection, formula outcome velocities
##   force_injection ForceInjectionCorrector    formula force (spring, buoyancy, point gravity)
##   kinematic_model KinematicModelCorrector    kinematic bodies posed from a stepped formula model
class_name FormulaCorrector
extends RefCounted

const METHODS := ["contact_force", "uniform_field", "collision", "force_injection", "kinematic_model"]

var method := ""
## Fixed steps since the last reset() while running.
var steps := 0
## samples[k] = the corrector's measured quantity after k steps since release. Only the first
## `history_steps` are kept (graph window / tests); later steps update last_sample only.
var samples: PackedFloat64Array = PackedFloat64Array()
var history_steps := 600
var last_sample := 0.0
## Leapfrog start: on the first released step only half of the net force acts, so Jolt's
## symplectic Euler (v += a dt, then x += v dt) places the body on the step points of the
## velocity Verlet / exact constant-acceleration solution instead of a (t^2 + t dt) / 2.
var leapfrog_start := true


## Clears the history (subclasses call super() and reset their own state).
func reset_history() -> void:
	steps = 0
	samples.clear()
	last_sample = 0.0


## Stores the sample of this step (bounded history).
func record(value: float) -> void:
	last_sample = value
	if samples.size() < history_steps:
		samples.append(value)


## One fixed step before the physics server steps. Body-bound correctors also accept apply().
func step(_dt: float) -> void:
	pass


## Called by FormulaBody._physics_process with the body it is attached to.
func apply(_body: RigidBody3D, dt: float) -> void:
	step(dt)


## Numbers for the panel: computed from PhysicsLaws (never from engine state alone).
func formula_values() -> Dictionary:
	return {}


## Engine measurements (labelled as simulation when shown).
func engine_values() -> Dictionary:
	return {}


## Net-force factor for the current step: 0.5 on the first released step when leapfrog_start.
func start_factor(first_step: bool) -> float:
	return 0.5 if leapfrog_start and first_step else 1.0
