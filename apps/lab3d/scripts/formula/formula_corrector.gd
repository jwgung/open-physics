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
##   force_injection ForceInjectionCorrector    formula force (spring, buoyancy, point gravity); the
##                                              representative scenes and the empty lab, not the
##                                              guided spring, buoyancy and orbit labs
##   kinematic_model KinematicModelCorrector    kinematic bodies posed from a stepped formula model
##                                              (pendulum, lever, pulley; BodyModelDriver of the guided
##                                              spring, buoyancy and orbit labs; the collision lab's rail)
class_name FormulaCorrector
extends RefCounted

## Every `method` id (the table above; tests check each corrector's id is one of these).
const METHODS := ["contact_force", "uniform_field", "collision", "force_injection", "kinematic_model"]

var method := ""
## Fixed steps since the last reset() while running.
var steps := 0
## samples[k] = the corrector's measured quantity after k steps since release. Only the first
## `history_steps` are kept (graph window / tests); later steps update last_sample only.
var samples: PackedFloat64Array = PackedFloat64Array()
var history_steps := 600
var last_sample := 0.0
## Optional second series recorded with the sample (record(value, velocity)): velocities[k] is the
## velocity after k steps, always the same length as samples (NAN where a step gave no velocity), so
## the indices of both series stay aligned. last_velocity is that of the last sample (NAN if none).
var velocities: PackedFloat64Array = PackedFloat64Array()
var last_velocity := 0.0
## Leapfrog start: on the first released step only half of the net force acts, so Jolt's
## symplectic Euler (v += a dt, then x += v dt) places the body on the step points of the
## velocity Verlet / exact constant-acceleration solution instead of a (t^2 + t dt) / 2.
## Every corrector that starts a motion takes the factor from start_factor().
var leapfrog_start := true


## Clears the history (subclasses call super() and reset their own state).
func reset_history() -> void:
	steps = 0
	samples.clear()
	last_sample = 0.0
	velocities.clear()
	last_velocity = 0.0


## Stores the sample of this step and its velocity (NAN when not given) in the bounded history.
func record(value: float, velocity := NAN) -> void:
	last_sample = value
	last_velocity = velocity
	if samples.size() < history_steps:
		samples.append(value)
		velocities.append(velocity)


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


## Net-force factor for the current step (the leapfrog start rule, shared by every corrector):
## 0.5 on the first released step when leapfrog_start, else 1. The caller decides what its first
## step is (steps == 0 after a release, or the step that leaves rest) and scales the net force.
func start_factor(first_step: bool) -> float:
	return 0.5 if leapfrog_start and first_step else 1.0
