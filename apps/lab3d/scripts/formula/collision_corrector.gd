## Collision correction (method "collision"): two movable bodies (spheres) that hit each other.
## Jolt detects the contact and resolves it in the step it happens. Its restitution rule differs
## from the TS world (Godot-Jolt combines materials as min(bounceA + bounceB, 1); TS uses
## min(eA, eB) and e = 0 below a 1 m/s closing speed, which equals Jolt's bounce velocity threshold),
## so setup() maps the TS pair onto the Jolt materials (bounce = e on A, 0 on B, friction 0) and the
## corrector then replaces the engine's outcome with the formula outcome:
## at the first pre-step after a step in which the bodies stopped closing in on each other while
## touching, both velocities are set to PhysicsLaws.world_collision_velocities applied along the
## contact normal (tangential components unchanged) from the velocities saved before that step.
## Positions of that one step keep the engine's outcome (an error <= |dv| dt).
class_name CollisionCorrector
extends FormulaCorrector

const TOUCH_TOLERANCE := 0.05   # m between the surfaces that still counts as touching

var body_a: RigidBody3D
var body_b: RigidBody3D
var radius_a := 0.5
var radius_b := 0.5
var restitution_a := 1.0        # TS material restitution of each body
var restitution_b := 1.0
var threshold := 1.0            # TS restitution velocity threshold (48 px/s = 1 m/s)
## Collisions handled since reset: {step, normal, before: [va, vb], engine: [va, vb], formula: [va, vb]}.
var events: Array[Dictionary] = []
var _saved_a := Vector3.ZERO
var _saved_b := Vector3.ZERO
var _was_closing := false


func _init() -> void:
	method = "collision"


func setup(a: RigidBody3D, b: RigidBody3D, ra: float, rb: float, ea: float, eb: float) -> void:
	body_a = a
	body_b = b
	radius_a = ra
	radius_b = rb
	restitution_a = ea
	restitution_b = eb
	var combined := minf(ea, eb)   # TS rule above the threshold; Jolt: bounce A + bounce B
	for pair in [[a, combined], [b, 0.0]]:
		var material := PhysicsMaterial.new()
		material.friction = 0.0
		material.bounce = pair[1]
		pair[0].physics_material_override = material
	reset()


func reset() -> void:
	reset_history()
	events.clear()
	_was_closing = false


## Unit normal from A to B (scalar doubles) and the gap between the surfaces.
func _contact() -> Array:
	var d := body_b.global_position - body_a.global_position
	var x := float(d.x)
	var y := float(d.y)
	var z := float(d.z)
	var distance := sqrt(x * x + y * y + z * z)
	if distance == 0.0:
		return [PackedFloat64Array([1.0, 0.0, 0.0]), -radius_a - radius_b]
	return [PackedFloat64Array([x / distance, y / distance, z / distance]), distance - radius_a - radius_b]


static func _dot(v: Vector3, n: PackedFloat64Array) -> float:
	return float(v.x) * n[0] + float(v.y) * n[1] + float(v.z) * n[2]


func step(dt: float) -> void:
	var contact := _contact()
	var normal: PackedFloat64Array = contact[0]
	var gap: float = contact[1]
	var va := body_a.linear_velocity
	var vb := body_b.linear_velocity
	var relative := _dot(vb, normal) - _dot(va, normal)
	var closing := relative < 0.0
	# After the contact step the bodies may already have separated by up to (relative speed) * dt.
	var reach := TOUCH_TOLERANCE + (absf(relative) + absf(_dot(_saved_b, normal) - _dot(_saved_a, normal))) * dt
	if _was_closing and not closing and gap <= reach:
		_resolve(normal, va, vb)
		va = body_a.linear_velocity
		vb = body_b.linear_velocity
	record(gap)
	steps += 1
	_saved_a = va
	_saved_b = vb
	_was_closing = _dot(vb, normal) - _dot(va, normal) < 0.0


func _resolve(normal: PackedFloat64Array, engine_a: Vector3, engine_b: Vector3) -> void:
	var ua := _dot(_saved_a, normal)
	var ub := _dot(_saved_b, normal)
	var after := PhysicsLaws.world_collision_velocities(body_a.mass, body_b.mass, ua, 0.0, ub, 0.0, 1.0, 0.0,
		restitution_a, restitution_b, threshold)
	var n := Vector3(normal[0], normal[1], normal[2])
	var formula_a := _saved_a + n * (after[0] - ua)
	var formula_b := _saved_b + n * (after[2] - ub)
	body_a.linear_velocity = formula_a
	body_b.linear_velocity = formula_b
	events.append({
		"step": steps, "normal": n,
		"before": [_saved_a, _saved_b], "engine": [engine_a, engine_b], "formula": [formula_a, formula_b],
		"normal_before": [ua, ub], "normal_after": [after[0], after[2]],
	})


## Formula outcome of the last collision along its normal (m/s), momentum before/after (kg m/s).
func formula_values() -> Dictionary:
	if events.is_empty():
		return {}
	var event: Dictionary = events[-1]
	var normal_before: Array = event.normal_before
	return {
		"velocity_a": event.normal_after[0],
		"velocity_b": event.normal_after[1],
		"momentum_before": PhysicsLaws.momentum(body_a.mass, normal_before[0]) + PhysicsLaws.momentum(body_b.mass, normal_before[1]),
		"momentum_after": PhysicsLaws.momentum(body_a.mass, event.normal_after[0]) + PhysicsLaws.momentum(body_b.mass, event.normal_after[1]),
	}


func engine_values() -> Dictionary:
	if events.is_empty():
		return {"collisions": 0}
	var event: Dictionary = events[-1]
	return {"collisions": events.size(), "engine_a": event.engine[0], "engine_b": event.engine[1]}
