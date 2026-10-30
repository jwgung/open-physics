## Base of the guided labs whose bodies follow a formula model stepped at the fixed step and posed by
## a driver (Phase 1 Task 4d: spring, buoyancy, orbit; collision, Task 4c). What they share: the run
## state (released, holding, reset_count), the graph bookkeeping, the controls' defaults at start,
## the release of the run, the free body the driver poses, and the default manipulation hooks (a
## pick-up stops the run, a cancelled one restarts it, a put-down is the lab's own). A lab sets
## `driver` and `props` in _init() and implements _build_world(), _load_model(), _graph_point(),
## _main_body(), reset_run() and its own conditions (set_control, run_action, status, observations,
## manipulation_placed / _placement_transforms); it overrides _notify_released() or
## manipulation_started() only where it differs.
class_name ModelDrivenLab
extends Experiment

const GRAPH_EVERY_STEPS := 6      # 10 Hz graph samples
const GRAPH_X_DEFAULT := 10.0     # s: the graph's x range when the content does not give one

## True from the release (launch) until the next reset.
var released := false
## A finger holds the lab's body (or knob): the run waits.
var holding := ""
## Run resets (tests).
var reset_count := 0
## The lab's driver (set in _init(); BodyModelDriver, CollisionRailDriver): poses its bodies on the
## model each fixed step and has reset().
var driver: FormulaCorrector
## The lab's props (set in _init()): meshes and reactions; they need reset() and released().
var props: RefCounted
## A body was put down by hand (or restored): placements() keeps it across a screen rebuild.
var _placed := false
## The graph's points; the lab's _graph_point() decides what one is.
var _graph: Array = []
var _graph_revision := 0


func _ready() -> void:
	_build_world()
	begin_batch()   # the defaults restart the run once, not once per control
	for control in definition.controls():
		set_control(control.id, control.default)
	end_batch()


## The lab's 3D world, its model and its driver (before the controls' defaults are set).
func _build_world() -> void:
	pass


## The model set to the conditions, at rest at the start (not stepped).
func _load_model() -> void:
	pass


## A new driver run from the model's current state.
func _reset_driver() -> void:
	driver.reset()


## The graph point of the model now.
func _graph_point() -> Variant:
	return null


## The lab's props react to the release (stretch, splash ...).
func _notify_released() -> void:
	props.released()


## The body the "따라가기" camera follows (null = not built yet).
func _main_body() -> RigidBody3D:
	return null


## The state of a run that waits: counted as a reset, the model and driver back at the start, the
## graph cleared (the lab's reset_run() does the rest).
func _clear_run() -> void:
	reset_count += 1
	released = false
	_load_model()
	_reset_driver()
	_graph.clear()
	_graph_revision += 1


## Starts the run from the conditions (a running one starts again from there).
func release() -> void:
	if released:
		reset_run()
	else:
		_load_model()
		_reset_driver()
	released = true
	_graph.clear()
	_add_graph_point()
	_notify_released()
	_update_status(true)


## Put down = let go: release from rest now, or, while the screen restores a saved state (a batch),
## only mark the run for the one restart in end_batch().
func _release_or_defer() -> void:
	if _batch > 0:
		_batch_dirty = true
		return
	release()


## Picked up: a run stops (the body follows the finger).
func manipulation_started(id: String) -> void:
	released = false
	holding = id
	_update_status(true)


## A pick-up that is cancelled: the run waits at its conditions again.
func manipulation_cancelled(_id: String) -> void:
	holding = ""
	reset_run()


## Where the bodies were put down, kept across a screen rebuild (empty until one was).
func placements() -> Dictionary:
	return _placement_transforms() if _placed else {}


## The put-down bodies' transforms (id -> Transform3D), for placements().
func _placement_transforms() -> Dictionary:
	return {}


## Appends the graph point of the model now.
func _add_graph_point() -> void:
	_graph.append(_graph_point())
	_graph_revision += 1


## True on the fixed steps that sample the graph, until the graph's x range ends.
func _graph_due(step_count: int, time: float) -> bool:
	return step_count % GRAPH_EVERY_STEPS == 0 and time <= graph_x_max() + 1e-6


## Positions kept by the driver: the graph's window of fixed steps (and two).
func _history_steps() -> int:
	return int(graph_x_max() * Engine.physics_ticks_per_second) + 2


func graph_revision() -> int:
	return _graph_revision


func graph_x_max() -> float:
	return float(definition.graph_x_max(GRAPH_X_DEFAULT))


func follow_point() -> Vector3:
	var body := _main_body()
	return body.global_position if body != null else global_position


## A body the driver poses: a frozen free body that touches nothing in the engine (mask 0) and is
## pickable on `layer`. The caller positions it and adds it to the lab.
func _make_driven_body(body_name: String, shape: Shape3D, layer: int) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = body_name
	_setup_free_body(body)
	body.gravity_scale = 0.0
	body.collision_layer = 1 << (layer - 1)
	body.collision_mask = 0
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	body.add_child(collision_shape)
	return body
