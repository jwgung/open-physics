## Collision correction (method "collision"): two movable bodies (spheres) that hit each other.
## Jolt detects and resolves the contact with the bodies' own materials: setup() does not change
## them, so contacts with the floor, walls and other bodies keep their own bounce and friction. Only
## the outcome of the A-B contact is replaced. Jolt's rule differs from the TS world (Godot-Jolt
## combines materials as min(bounceA + bounceB, 1) and has friction; TS uses min(eA, eB), e = 0
## below a 1 m/s closing speed, which equals Jolt's bounce velocity threshold, and no friction), and
## a pair with bounce 0 is resolved over two steps (speculative contact, then the hit).
## Contact detection uses the engine's contact reports (setup() turns contact_monitor on for both
## bodies; a report describes the previous step). Each fixed step, before the physics server steps:
## - a step whose report newly lists B among A's colliding bodies started an A-B contact; the
##   velocities the bodies started that step with (`_prev`) are frozen (`_before`) until the bodies
##   stop closing in or the report drops the pair, however many steps the engine takes;
## - it is left to the engine (no event) when A or B also newly touched another body in that step
##   (wall, floor, third body: the impulses cannot be split), or when it is a persistent contact: the
##   pair has not been apart (gap > APART_GAP) since its last contact and closes slower than the
##   restitution threshold (pressed together, a flickering report);
## - on resolving, both velocities are set to v_free + n (u' - u) along the contact normal n, where
##   v_free is the frozen velocity plus the external velocity change of the contact steps, u its
##   normal component and u' the PhysicsLaws.world_collision_velocities outcome (TS world order:
##   integrate, then resolve). The external change per step is the measured velocity change of the
##   last step without an A-B contact (so gravity, the floor's support, constant_force and apply_*
##   forces held over the contact are all in it); before such a step exists it is engine gravity +
##   constant_force. The engine's normal and friction impulses of those steps are discarded;
##   tangential motion and the external forces stay.
## Positions of the contact steps keep the engine's outcome (an error <= |dv| dt per step).
class_name CollisionCorrector
extends FormulaCorrector

const APART_GAP := 0.05          # m between the surfaces: the pair has separated since its last contact
const IMPULSE_TOLERANCE := 1e-4   # m/s of relative normal velocity that still counts as closing in
const REPORTED_CONTACTS := 8      # max_contacts_reported setup() ensures on both bodies

var body_a: RigidBody3D
var body_b: RigidBody3D
var radius_a := 0.5
var radius_b := 0.5
var restitution_a := 1.0        # TS material restitution of each body
var restitution_b := 1.0
var threshold := 1.0            # TS restitution velocity threshold (48 px/s = 1 m/s)
## Collisions handled since reset: {step, steps (contact steps), normal, before: [va, vb] (frozen),
## engine: [va, vb], formula: [va, vb], normal_before, normal_after}.
var events: Array[Dictionary] = []
var _prev_a := Vector3.ZERO
var _prev_b := Vector3.ZERO
var _has_prev := false
var _engaged := false
var _before_a := Vector3.ZERO
var _before_b := Vector3.ZERO
var _contact_steps := 0
var _touching := false            # B was in A's contact report on the previous step
var _apart := false               # the surfaces have been more than APART_GAP apart since the last contact
var _reported_a: Array[Node3D] = []   # previous step's contact reports
var _reported_b: Array[Node3D] = []
var _free_dv_a := Vector3.ZERO    # measured velocity change of the last step without an A-B contact
var _free_dv_b := Vector3.ZERO
var _has_free_dv := false
var _dv_a := Vector3.ZERO         # external velocity change per contact step (frozen with _before)
var _dv_b := Vector3.ZERO


func _init() -> void:
	method = "collision"


## Binds the pair and its TS restitutions. The bodies' physics materials are left as they are.
func setup(a: RigidBody3D, b: RigidBody3D, ra: float, rb: float, ea: float, eb: float) -> void:
	body_a = a
	body_b = b
	radius_a = ra
	radius_b = rb
	restitution_a = ea
	restitution_b = eb
	for body in [a, b]:
		body.contact_monitor = true
		body.max_contacts_reported = maxi(body.max_contacts_reported, REPORTED_CONTACTS)
	reset()


func reset() -> void:
	reset_history()
	events.clear()
	_has_prev = false
	_engaged = false
	_contact_steps = 0
	_touching = false
	_apart = false
	_reported_a.clear()
	_reported_b.clear()
	_has_free_dv = false


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


## Velocity change of one step from the forces the engine adds besides contacts (fallback before a
## contact-free step was measured).
static func _external_dv(body: RigidBody3D, dt: float) -> Vector3:
	return (body.get_gravity() * body.gravity_scale + body.constant_force / body.mass) * dt


func step(dt: float) -> void:
	var contact := _contact()
	var normal: PackedFloat64Array = contact[0]
	var gap: float = contact[1]
	var va := body_a.linear_velocity
	var vb := body_b.linear_velocity
	var reported_a := body_a.get_colliding_bodies()
	var reported_b := body_b.get_colliding_bodies()
	var touching := reported_a.has(body_b) or reported_b.has(body_a)   # either side, if one report list is full
	if gap > APART_GAP:
		_apart = true
	if _has_prev:
		if not touching:
			_free_dv_a = va - _prev_a
			_free_dv_b = vb - _prev_b
			_has_free_dv = true
		elif not _touching and not _engaged and _starts_collision(normal, reported_a, reported_b):
			_engaged = true
			_before_a = _prev_a
			_before_b = _prev_b
			_dv_a = _free_dv_a if _has_free_dv else _external_dv(body_a, dt)
			_dv_b = _free_dv_b if _has_free_dv else _external_dv(body_b, dt)
			_contact_steps = 0
		if touching:
			_apart = false
		if _engaged:
			_contact_steps += 1
			var relative := _dot(vb, normal) - _dot(va, normal)
			if relative >= -IMPULSE_TOLERANCE or not touching:
				_resolve(normal, va, vb)
				va = body_a.linear_velocity
				vb = body_b.linear_velocity
	elif touching:
		_apart = false
	record(gap)
	steps += 1
	_prev_a = va
	_prev_b = vb
	_has_prev = true
	_touching = touching
	_reported_a.assign(reported_a)
	_reported_b.assign(reported_b)


## A new A-B contact report is a collision to correct unless another body newly touched A or B in the
## same step, or it is a persistent contact (not apart since the last one, closing below threshold).
func _starts_collision(normal: PackedFloat64Array, reported_a: Array[Node3D], reported_b: Array[Node3D]) -> bool:
	for other in reported_a:
		if other != body_b and not _reported_a.has(other):
			return false
	for other in reported_b:
		if other != body_a and not _reported_b.has(other):
			return false
	var closing := _dot(_prev_a, normal) - _dot(_prev_b, normal)
	return _apart or closing >= threshold


func _resolve(normal: PackedFloat64Array, engine_a: Vector3, engine_b: Vector3) -> void:
	_engaged = false
	var free_a := _before_a + _dv_a * _contact_steps
	var free_b := _before_b + _dv_b * _contact_steps
	var ua := _dot(free_a, normal)
	var ub := _dot(free_b, normal)
	var after := PhysicsLaws.world_collision_velocities(body_a.mass, body_b.mass, ua, 0.0, ub, 0.0, 1.0, 0.0,
		restitution_a, restitution_b, threshold)
	var n := Vector3(normal[0], normal[1], normal[2])
	var formula_a := free_a + n * (after[0] - ua)
	var formula_b := free_b + n * (after[2] - ub)
	body_a.linear_velocity = formula_a
	body_b.linear_velocity = formula_b
	events.append({
		"step": steps, "steps": _contact_steps, "normal": n,
		"before": [_before_a, _before_b], "engine": [engine_a, engine_b], "formula": [formula_a, formula_b],
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
