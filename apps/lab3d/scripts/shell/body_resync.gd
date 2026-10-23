## Puts the bodies an experiment just put back (처음으로, a condition change, an object put down)
## back once more at the start of the next fixed step, before the engine steps (Phase 1 Task 4g bug
## fix, 2026-10-23 user report: 처음으로 did not bring the bodies back; the bug is older, origin/dev 17a9c79 has it).
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
## the step). Recorded: frozen bodies, and free bodies at rest (a box back at its start) with their
## zero velocity; a body let go meanwhile is left alone. Exactly one re-application: it follows the
## engine's order (one sync per step), not a number of steps.
class_name BodyResync
extends Node

var _targets := {}          # RigidBody3D -> Transform3D to put back
var _before := {}           # RigidBody3D -> Transform3D before the change (only bodies it moved are kept)
var _free := {}             # the targets that are free bodies (at rest when recorded)



func _init() -> void:
	name = "BodyResync"
	process_physics_priority = -1000
	set_physics_process(false)


## Records the poses before a change (call, then change the experiment, then hold()).
func mark(root: Node) -> void:
	_before.clear()
	for node in root.find_children("*", "RigidBody3D", true, false):
		_before[node] = (node as Node3D).global_transform


## Records the pose of every frozen rigid body (and every free one at rest) under `root` now that the
## change put somewhere else than before mark() (the bodies the change moved); at the start of the
## next fixed step they are put there again (the stale report carries the pose of the step that was
## under way, the old run's).
func hold(root: Node) -> void:
	_targets.clear()
	_free.clear()
	for node in root.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if not _before.has(body) or _before[body] == body.global_transform:
			continue   # not moved by the change
		if body.freeze:
			_targets[body] = body.global_transform
		elif body.linear_velocity == Vector3.ZERO and body.angular_velocity == Vector3.ZERO:
			_targets[body] = body.global_transform
			_free[body] = true
	set_physics_process(true)


## True until the next fixed step has put the poses back (tests).
func holding() -> bool:
	return is_physics_processing()


func _physics_process(_delta: float) -> void:
	for body: RigidBody3D in _targets:
		if not is_instance_valid(body) or (not body.freeze and not _free.has(body)):
			continue
		body.global_transform = _targets[body]
		if _free.has(body):
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	_targets.clear()
	_free.clear()
	_before.clear()
	set_physics_process(false)
