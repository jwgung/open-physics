## Puts the bodies an input-driven change just moved (처음으로, any action, a condition change, an
## object picked up, put down or put back) back once more at the start of the next fixed step, before
## the engine steps (Phase 1 Task 4g bug fix, 2026-10-23 user report: 처음으로 did not bring the bodies
## back; the bug is older, origin/dev 17a9c79 has it). Experiment.change_from_input() is the only caller.
##
## Why: the screen changes the experiment from input, between two fixed steps. A frozen (kinematic)
## body moved there is taken by Jolt as a move over the next step, and the next step's state sync
## (PhysicsServer3D sync / flush before the scene's _physics_process) reports the pose the body had,
## so the node takes the old pose again and, frozen, keeps it: the box, the spring ball, the pendulum
## bobs, the collision balls or the thrown ball stayed where the run had left them while the panel
## showed the start. Setting the pose on the physics server as well does not help (same report).
## Doing the same move inside the fixed step (after that sync, before the engine step) sticks: that
## is what this node does, once, in the first _physics_process after the change (lowest priority
## value, so before every lab's own physics callback). The change itself still runs at once, so the
## press frame and every frame until that step already draw the start (the report only arrives with
## the step). Exactly one re-application: it follows the engine's order (one sync per step), not a
## number of steps.
##
## Recorded: the bodies the change moved (pose before mark() != pose at hold()) that are frozen, or
## free and at rest (a box back at its start, with its zero velocity). A body that moves on after
## the record is left alone (PR #16 review): a body moving at hold() is not recorded; a later change
## from input in the same frame goes through mark()/hold() again (it updates or drops the records of
## the bodies it moves, keeps the others); other code that changes a recorded body before the step
## (a lab's _process letting the ball go, a free body set moving) is seen either at the end of that
## frame (_process, after every lab's: pose, freeze or velocity no longer the recorded ones) or at the
## step itself, where the body's pose is then neither the recorded one nor the stale report's (the
## state at the first mark() since the last step), or, for a free body, its velocity is neither zero
## nor the stale report's. Such a body is dropped from the records and keeps what that code gave it.
class_name BodyResync
extends Node

const POSE_TOL := 1e-4      # m: "the same pose" for the step's check
## The stale report of a body that was moving at mark() carries its pose one engine step on (a rolling
## ball reset by 공 놓기: 1.6 cm on SM-P200, 2026-10-24) and that step's velocity change: it still
## counts as the report within this many steps of its velocity, plus REPORT_SLACK (m, rad, m/s).
const REPORT_STEPS := 1.5
const REPORT_SLACK := 0.005
const REPORT_ACCEL := 40.0  # m/s^2: the most a step changes a lab body's velocity (gravity, contact)

var _before := {}           # RigidBody3D -> Transform3D before the change (mark)
var _targets := {}          # RigidBody3D -> [Transform3D, freeze, linear_velocity, angular_velocity] at hold()
var _free := {}             # the targets that are free bodies (at rest when recorded)
var _stale := {}            # RigidBody3D -> [Transform3D, linear, angular velocity] at the first mark() since the last step (what the stale report carries)


func _init() -> void:
	name = "BodyResync"
	process_physics_priority = -1000
	process_priority = 1000
	set_physics_process(false)
	set_process(false)


## Records the poses before a change (call, then change the experiment, then hold()).
func mark(root: Node) -> void:
	_before.clear()
	for node in root.find_children("*", "RigidBody3D", true, false):
		_before[node] = (node as Node3D).global_transform
		if not _stale.has(node):
			var body := node as RigidBody3D
			_stale[body] = [_before[body], body.linear_velocity, body.angular_velocity]


## Records the bodies under `root` that the change put somewhere else than at mark() and that stay
## there (frozen, or free at rest); at the start of the next fixed step they are put there again (the
## stale report carries the pose of the step that was under way, the old run's). Records of an
## earlier change still waiting for that step are kept for the bodies this change did not move.
func hold(root: Node) -> void:
	for node in root.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if not _before.has(body) or _before[body] == body.global_transform:
			continue   # not moved by this change
		_targets.erase(body)
		_free.erase(body)
		var at_rest := body.linear_velocity == Vector3.ZERO and body.angular_velocity == Vector3.ZERO
		if body.freeze or at_rest:
			_targets[body] = [body.global_transform, body.freeze, body.linear_velocity, body.angular_velocity]
			if not body.freeze:
				_free[body] = true
	_before.clear()
	if _targets.is_empty():
		_stop()
	else:
		set_physics_process(true)
		set_process(true)


## True until the next fixed step has put the poses back (tests).
func holding() -> bool:
	return is_physics_processing()


## The bodies still recorded (tests).
func held_bodies() -> Array:
	return _targets.keys()


## End of a frame without a fixed step since hold(): drops the bodies that changed since (see above).
func _process(_delta: float) -> void:
	for body: RigidBody3D in _targets.keys():
		if not is_instance_valid(body) or _changed(body):
			_targets.erase(body)
			_free.erase(body)
	if _targets.is_empty():
		_stop()


func _changed(body: RigidBody3D) -> bool:
	var record: Array = _targets[body]
	return body.global_transform != record[0] or body.freeze != record[1] \
		or body.linear_velocity != record[2] or body.angular_velocity != record[3]


func _physics_process(_delta: float) -> void:
	for body: RigidBody3D in _targets:
		if not is_instance_valid(body):
			continue
		if _moved_since(body):
			continue
		body.global_transform = _targets[body][0]
		if _free.has(body):
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	_stop()


## Between hold() and this step other code moved the body or set it moving: its pose (or velocity)
## is neither the recorded one nor the stale report's (the state at the first mark()).
func _moved_since(body: RigidBody3D) -> bool:
	var record: Array = _targets[body]
	var stale: Array = _stale.get(body, record.slice(0, 1) + record.slice(2))
	var now := body.global_transform
	if not (_near(now, record[0]) or _near_report(now, stale)):
		return true
	if not _free.has(body):
		return false   # frozen: only its pose counts (a kinematic move's report carries a velocity)
	var still := (body.linear_velocity.is_equal_approx(record[2]) and body.angular_velocity.is_equal_approx(record[3])) \
		or _report_velocity(body, stale)
	return not still


## The body's velocities are the stale report's: exactly them for a body at rest at mark() (so a
## body other code sets moving, however slowly, is left alone), within one report's change
## (REPORT_ACCEL over REPORT_STEPS steps, both linear and angular) for one that was moving.
static func _report_velocity(body: RigidBody3D, stale: Array) -> bool:
	var linear: Vector3 = stale[1]
	var angular: Vector3 = stale[2]
	if linear == Vector3.ZERO and angular == Vector3.ZERO:
		return body.linear_velocity.is_equal_approx(linear) and body.angular_velocity.is_equal_approx(angular)
	var change := REPORT_ACCEL * _step() * REPORT_STEPS + REPORT_SLACK
	return body.linear_velocity.distance_to(linear) <= change and body.angular_velocity.distance_to(angular) <= change / 0.1   # rad/s: a lab body is at least 0.1 m across


static func _step() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## `now` is what the stale report carries: the pose at mark() moved on by up to REPORT_STEPS engine
## steps of the velocity it had then (exactly that pose for a body at rest).
static func _near_report(now: Transform3D, stale: Array) -> bool:
	var dt := _step()
	var from: Transform3D = stale[0]
	var linear: Vector3 = stale[1]
	var angular: Vector3 = stale[2]
	if linear == Vector3.ZERO and angular == Vector3.ZERO:
		return _near(now, from)
	var reach := linear.length() * dt * REPORT_STEPS + REPORT_SLACK + POSE_TOL
	var turn := angular.length() * dt * REPORT_STEPS + REPORT_SLACK
	var q := now.basis.orthonormalized().get_rotation_quaternion() * from.basis.orthonormalized().get_rotation_quaternion().inverse()
	var angle := q.get_angle()
	return now.origin.distance_to(from.origin) <= reach and minf(angle, TAU - angle) <= turn


static func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < POSE_TOL and a.basis.is_equal_approx(b.basis)


func _stop() -> void:
	_targets.clear()
	_free.clear()
	_stale.clear()
	set_physics_process(false)
	set_process(false)
