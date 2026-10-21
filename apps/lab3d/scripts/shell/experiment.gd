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

## Parsed content JSON (see ExperimentRegistry). Read-only for the experiment.
var definition: Dictionary = {}


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


## Runs an action declared in definition.actions (buttons).
func run_action(_id: String) -> void:
	pass


## Values for definition.observations: id -> float (formatted with unit/digits) or String.
func observations() -> Dictionary:
	return {}


## Graph data for definition.graph.series: series id -> PackedVector2Array of (x, y) points.
func graph_series() -> Dictionary:
	return {}


## World position the "따라가기" camera mode follows.
func follow_point() -> Vector3:
	return global_position
