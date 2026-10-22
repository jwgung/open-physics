## Base of the labs with one red handle the finger presses or pulls along a grid line (Phase 1
## Task 4e: the lever and the pulley lab). It owns what both share: the handle body, its press line
## (PressLineSurface) and the grid cells read from it, the graph clock that runs only while the handle
## is held (fixed steps, so frame rate does not matter), the rolling graph of the hand's force and the
## required force, and the panel hooks. A lab names the handle's rest place, reach and cell limit and
## says when it is held.
class_name PressHandleLab
extends Experiment

const GRAPH_EVERY_STEPS := 6       # 10 Hz graph samples
const HANDLE_LAYER := 2            # pickable handle (mask 0)
const GRAPH_WINDOW := 10.0         # s of the rolling graph

var graph := RollingGraph.new(["applied", "required"] as Array[String], GRAPH_WINDOW)
var handle: StaticBody3D
var load_body: RigidBody3D
## Fixed steps with the handle held (the graph's clock).
var clock_steps := 0
var _press: PressLineSurface      # the held handle's line (origin = its rest point when picked up)
var _press_step := 0.02           # its grid step (m per cell)
var _line: PressLineSurface       # the last press line built (reused while its top, reach, step and lift are the same)
var _line_key := []


# --- the lab fills these in -----------------------------------------------------------------

## The finger holds the handle.
func _handle_held() -> bool:
	return false


## The handle's place when it is not held.
func _handle_rest() -> Vector3:
	return Vector3.ZERO


## The press line's length (m).
func _handle_reach() -> float:
	return 1.0


## The most grid cells the handle may count now.
func _handle_cell_limit() -> int:
	return 1 << 30


## The graph's values in the order of its series: the hand's force and the required force.
func _graph_values() -> Array:
	return [0.0, 0.0]


# --- shared ---------------------------------------------------------------------------------

func clock_time() -> float:
	return clock_steps / float(Engine.physics_ticks_per_second)


## Grid cells the handle is along its press line (0..limit) while held.
func handle_cells() -> int:
	if not _handle_held() or _press == null:
		return 0
	return mini(_handle_cell_limit(), roundi(clampf(_press.depth_of(handle.global_position), 0.0, _handle_reach()) / _press_step))


## One fixed step of the clock: it runs while the handle is held, a graph sample every 6th step.
func _tick_clock() -> void:
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


## The press line down from `top` (the manipulator asks for it at every pick-up and the lab again to
## count the cells): built once per top / reach / step / lift and reused.
func _press_line(top: Vector3, reach: float, step: float, lift: float) -> PressLineSurface:
	var key := [top, reach, step, lift]
	if _line == null or _line_key != key:
		_line = PressLineSurface.new(top, reach, step, lift)
		_line_key = key
	return _line


## The handle's press line starts at the surface `surface`, counted in the handle rule's grid.
func _begin_press(surface: ManipSurface) -> void:
	_press = surface as PressLineSurface
	_press_step = _grid_step("handle")


func _end_press() -> void:
	_press = null


## A pickable static body of `size` (the handle, the lever's stand; mask 0).
func _static_pickable(body_name: String, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1 << (HANDLE_LAYER - 1)
	body.collision_mask = 0
	_add_box_shape(body, size)
	add_child(body)
	return body


func _place_handle() -> void:
	var rest := _handle_rest()
	if handle.global_position != rest:
		handle.global_position = rest


func graph_series() -> Dictionary:
	return graph.series()


func graph_revision() -> int:
	return graph.revision


func follow_point() -> Vector3:
	return load_body.global_position if load_body else global_position
