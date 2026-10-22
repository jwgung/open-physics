## Base class for a 3D experiment scene. The shell (experiment_screen.gd) owns the camera, the
## gestures and every 2D panel; an experiment only owns its 3D world and physics and answers the
## questions below. Its content (texts, controls, observations, graph, camera views) is data in
## content/experiments/<id>.json, passed in as `definition` before the node enters the tree.
## How to add an experiment: apps/lab3d/README.md ("실험 추가").
class_name Experiment
extends Node3D

## Emitted when a value shown in the panels changes outside a control (e.g. the box starts to
## slide). The screen also polls observations() at UI_REFRESH_HZ, so this is only a hint.
signal state_changed
## Something visibly hit the ground (strength 0..1). Visual only: the screen gives the camera a
## small dip (CameraRig.nudge). Experiments emit it from their ArtJuice.landed.
signal impact(strength: float)

## Parsed content JSON (see ExperimentRegistry). Read-only for the experiment.
var definition: Dictionary = {}
## The project's engine gravity (m/s^2): labs whose formulas use g read it here, never a copy.
var engine_g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.81)
## status() as of the last _update_status().
var _last_status := ""


## Adds a box collision shape of `size` to a body (floors, blocks, boxes of the experiments).
func _add_box_shape(body: CollisionObject3D, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)


## A physics material without friction or bounce: the labs' bodies slide on it and the formula
## correction supplies the friction.
func _frictionless_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	return material


## The collision floor: the island's top surface at y = 0 (the island mesh is ArtKit's, no
## collision), named "Floor". `material` null = frictionless.
func _add_floor(material: PhysicsMaterial = null, size := Vector3(30.0, 0.4, 12.0)) -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.physics_material_override = material if material != null else _frictionless_material()
	_add_box_shape(floor_body, size)
	floor_body.position = Vector3(0.0, -size.y * 0.5, 0.0)
	add_child(floor_body)
	return floor_body


## The settings of a formula-corrected body: never sleeps, no damping (the corrector and the
## formulas own the motion), frozen bodies stay static.
func _setup_free_body(body: RigidBody3D) -> void:
	body.can_sleep = false
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


## The state that decides the panels' texts (changes emit state_changed through _update_status).
func status() -> String:
	return ""


## Records status(), tells the UI and calls _status_changed when it changed (`quiet`: the change was
## made by the user's hand, no reaction).
func _update_status(quiet := false) -> void:
	var previous := _last_status
	_last_status = status()
	state_changed.emit()
	if _last_status != previous and not quiet:
		_status_changed(previous, _last_status)


## Reaction to a status change (props); the labs override it.
func _status_changed(_previous: String, _current: String) -> void:
	pass


## A pickable handle: a StaticBody3D on `layer` (never hit: mask 0) with a box shape and the yellow
## knob mesh as its "Visual" child, added to this experiment (the velocity arrows' knobs of the
## projectile and collision labs).
func _make_knob(knob_name: String, layer: int, size: float) -> StaticBody3D:
	var knob := StaticBody3D.new()
	knob.name = knob_name
	knob.collision_layer = 1 << (layer - 1)
	knob.collision_mask = 0
	_add_box_shape(knob, Vector3.ONE * size)
	var visual := ArtKit.instance(VelocityArrow.knob_mesh(size))
	visual.name = "Visual"
	knob.add_child(visual)
	add_child(knob)
	return knob


## The screen restores a saved state (controls, then placements) between begin_batch() and
## end_batch(): an experiment whose every change restarts the run restarts it once, in end_batch().
func begin_batch() -> void:
	pass


func end_batch() -> void:
	pass


## Sets a control declared in definition.controls. `value` is a float for sliders and the option
## id (String) for choices. Called once per control with its default before the first frame.
func set_control(_id: String, _value: Variant) -> void:
	pass


## Current value of a control (the screen syncs sliders/chips from it after actions).
func control_value(id: String) -> Variant:
	for control in definition.get("controls", []):
		if control.id == id:
			return control.get("default")
	return null


## The option `option_id` of the choice control `control_id` in definition.controls ({} when the
## control or the option does not exist).
func _find_option(control_id: String, option_id: String) -> Dictionary:
	for control in definition.get("controls", []):
		if control.id != control_id:
			continue
		for option in control.get("options", []):
			if option.id == option_id:
				return option
	return {}


## `value` limited to the min / max of the slider control `id` in definition.controls (a bound
## the control does not declare stays open).
func _clamp_to_control(id: String, value: float) -> float:
	for control in definition.get("controls", []):
		if control.id == id:
			return clampf(value, float(control.get("min", -INF)), float(control.get("max", INF)))
	return value


## Runs an action declared in definition.actions (buttons).
func run_action(_id: String) -> void:
	pass


## Values for definition.observations: id -> float (formatted with unit/digits) or String.
func observations() -> Dictionary:
	return {}


## Graph data for definition.graph.series: series id -> PackedVector2Array of (x, y) points.
func graph_series() -> Dictionary:
	return {}


## Changes whenever graph_series() would return different data (e.g. a point was added). The
## screen polls this and only rebuilds the series when it changed; -1 = unknown (rebuild each poll).
func graph_revision() -> int:
	return -1


## World position the "따라가기" camera mode follows.
func follow_point() -> Vector3:
	return global_position


# --- manipulation (Task 2b) ---------------------------------------------------------------------
# definition.manipulation.objects lists the objects a finger may pick up and the rules (surface id,
# grid step, height handle); the shell's Manipulator does the picking, dragging, snapping and the
# preview, and asks the experiment for the geometry and tells it the outcome. While an object is
# held it is frozen; the experiment decides what a placed object does next (README "조작").

## The physics body of a manipulable object (null = not available right now).
func manipulation_body(_id: String) -> PhysicsBody3D:
	return null


## The surface `surface_id` (from the object's rule) as it is now, e.g. at the current incline angle.
func manipulation_surface(_surface_id: String) -> ManipSurface:
	return null


## Visual reactions of the object (hold lift, settle, wobble), or null.
func manipulation_juice(_id: String) -> ArtJuice:
	return null


## A finger picked the object up. The shell has frozen the body; stop whatever it was doing.
func manipulation_started(_id: String) -> void:
	pass


## Extra placement rule of the experiment (the shell already checks the region and overlaps).
func placement_allowed(_id: String, _transform: Transform3D) -> bool:
	return true


## The object was put down at `transform` (already snapped and checked). Also used to restore a
## saved placement (placements()) when the screen is rebuilt.
func manipulation_placed(_id: String, _transform: Transform3D) -> void:
	pass


## The pick-up was cancelled (second finger, system cancel, or let go where it cannot be placed).
## The shell has put the body back where it was picked up.
func manipulation_cancelled(_id: String) -> void:
	pass


## id -> Transform3D of the objects the user placed (kept across a screen rebuild).
func placements() -> Dictionary:
	return {}
