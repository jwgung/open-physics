## A formula model of one moving body (Phase 1 Task 4d): the 64-bit state of a guided lab's body
## (position and velocity in world metres), stepped once per fixed step by BodyModelDriver, which
## poses the engine body on it. The lab's model owns the motion and every displayed number; the
## engine body is where the formula puts it (method "kinematic_model", docs/formula-correction.md).
## Subclasses (SpringModel, BuoyancyModel, OrbitModel) implement advance(); step() counts the steps.
class_name BodyModel
extends RefCounted

## Fixed steps since the last reset.
var steps := 0
## Position (m) and velocity (m/s), world axes, 64-bit.
var x := 0.0
var y := 0.0
var z := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
## True when the model stopped for good (resting on a floor, crashed, out of range): step() then
## only counts steps.
var stopped := false
## Length of the last fixed step (s); time() = steps * dt.
var dt := 1.0 / 60.0


## One fixed step of `dt` seconds.
func step(step_dt: float) -> void:
	dt = step_dt
	steps += 1
	if not stopped:
		advance(step_dt)


## Seconds since the last reset (steps of dt).
func time() -> float:
	return steps * dt


## Advances the state by one fixed step (subclasses).
func advance(_dt: float) -> void:
	pass


## Position as an engine vector (rounded to 32 bit).
func position() -> Vector3:
	return Vector3(x, y, z)

