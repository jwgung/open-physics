## String / rod pendulum (the "constraints" experiment): PendulumModel (semi-implicit Euler,
## angular damping) stepped at the fixed step; the bob is posed at anchor + L (sin a * side,
## -cos a * up). The fixed length is exact by construction. The sample is the bob angle measured
## from its position. Displayed: small-angle period 2 pi sqrt(L / g), length, angle.
class_name PendulumModelDriver
extends KinematicModelCorrector

var anchor := Vector3.ZERO
var side := Vector3.RIGHT          # swing plane: side and up
var length := 2.0
var angle := 0.0                   # rad, 0 = hanging straight down
var angular_velocity := 0.0
var damping := 0.08                # 1/s, TS PendulumModel default (src/physics/mechanics-scenes.ts)
var g := 9.81


func set_angle(value: float) -> void:
	angle = value
	angular_velocity = 0.0
	if body != null:
		reset_history()
		body.global_transform = pose()


func advance(dt: float) -> void:
	var state := PhysicsLaws.pendulum_step(angle, angular_velocity, dt, g, length, damping)
	angle = state[0]
	angular_velocity = state[1]


func pose() -> Transform3D:
	var offset := PhysicsLaws.pendulum_offset(length, angle)
	return Transform3D(body.global_transform.basis, anchor + side * offset[0] + Vector3.DOWN * offset[1])


func measure() -> float:
	var d := body.global_position - anchor
	return atan2(d.dot(side), -d.y)


func formula_values() -> Dictionary:
	return {"period": PhysicsLaws.pendulum_period(length, g), "length": length, "angle": angle}


func engine_values() -> Dictionary:
	return {"angle": last_sample, "length": (body.global_position - anchor).length()}
