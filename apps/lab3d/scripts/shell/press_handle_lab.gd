## Base of the labs the finger presses and holds (Phase 1 Task 4e: the lever and the pulley lab; a
## red handle pressed along a grid line until 2026-10-28, now a press and hold on the object itself).
## It owns what both share: the hand's force ramp while held (`hand`, HoldRamp: the lab sets its rate
## and cap), the gauge beside the pressed place (ForceGauge), the graph clock that runs only while
## the object is held (fixed steps, so frame rate does not matter), the rolling graph of the hand's
## force and the required force, and the panel hooks. A lab says when it is held, where the gauge
## stands and what the hand's force does.
class_name PressHandleLab
extends Experiment

const GRAPH_EVERY_STEPS := 6       # 10 Hz graph samples
const PICK_LAYER := 2              # pickable press bodies (mask 0)
const GRAPH_WINDOW := 10.0         # s of the rolling graph

var graph := RollingGraph.new(["applied", "required"] as Array[String], GRAPH_WINDOW)
var load_body: RigidBody3D
## The hand's press: its force while held (the lab sets rate and cap in _init()).
var hand := HoldRamp.new()
var gauge: ForceGauge
## Fixed steps with the object held (the graph's clock).
var clock_steps := 0


# --- the lab fills these in -----------------------------------------------------------------

## The finger holds the object.
func _handle_held() -> bool:
	return hand.held


## Where the gauge stands (its foot, world).
func _gauge_at() -> Vector3:
	return Vector3.ZERO


## The graph's values in the order of its series: the hand's force and the required force.
func _graph_values() -> Array:
	return [0.0, 0.0]


# --- shared ---------------------------------------------------------------------------------

func clock_time() -> float:
	return clock_steps / float(Engine.physics_ticks_per_second)


## One fixed step of the hand and the clock: both run while the object is held, a graph sample every
## 6th step.
func _tick_clock() -> void:
	hand.tick()
	if not _handle_held():
		return
	clock_steps += 1
	if clock_steps % GRAPH_EVERY_STEPS == 0:
		_add_graph_point()


func _add_graph_point() -> void:
	graph.add(clock_time(), _graph_values())


## The clock and the graph start again (a new run).
func _restart_clock() -> void:
	clock_steps = 0
	graph.clear()


## A pickable static body of `size` (the pulley's rope end, the lever's stand; mask 0).
func _static_pickable(body_name: String, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1 << (PICK_LAYER - 1)
	body.collision_mask = 0
	_add_box_shape(body, size)
	add_child(body)
	return body


## The gauge (built once, the lab adds it) shown while held, filled to the hand's share of its cap.
func _show_gauge() -> void:
	if gauge == null:
		gauge = ForceGauge.new()
		add_child(gauge)
	gauge.visible = hand.held
	if hand.held:
		gauge.set_fraction(hand.fraction())
		gauge.global_position = _gauge_at()


func graph_series() -> Dictionary:
	return graph.series()


func graph_revision() -> int:
	return graph.revision


func follow_point() -> Vector3:
	return load_body.global_position if load_body else global_position
