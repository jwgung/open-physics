## Guided pulley lab (Phase 1 Task 4e; web preset "pulley", "도르래 줄이 많으면 얼마나 쉬워질까?"): an
## orange load (the web's 20 kg) hangs from n = 1, 2 or 4 supporting strands under a gantry. The red
## grip on the pull strand is pulled down by one finger in strokes (5 cm grid); the load rises the
## pulled length / n. Letting go keeps the rope (a ratchet) and the grip goes back up the rope for the
## next stroke (hand over hand), so the same height can be reached with any n. Conditions: the
## number of strands (the web's 1 / 2 / 4 buttons) and the load mass (the web's mass input, 1-20 kg).
## Motion and every displayed number: PulleyLabModel (PulleyAdvantageChallenge: F = m g / n, lift =
## pull / n, pull for 1 m = n m; work F d_pull = m g d_lift); PulleyLabDriver poses the engine load on
## it every step (method "kinematic_model"). See docs/formula-correction.md (Task 4e).
## The graph is the web's "줄 수에 따른 필요한 힘": the hand's pull and the required force over the
## last 10 s with the grip held (a changed condition adds a point).
extends Experiment

const LOAD_X := -1.0
const LOAD_SIZE := 0.8
const MAX_LIFT := 2.4
const TOP_Y := 4.4                 # bottom of the fixed block's wheels: the strands start here
const BEAM_Y := 4.95               # the gantry's top beam
const HOOK_UP := 0.62              # the moving block's hook above the load centre
const GUIDE := Vector3(1.2, 4.6, 0.0)   # the guide wheel over the pull side
const HANDLE_SIZE := Vector3(0.5, 0.3, 0.4)
const HANDLE_TOP := 3.4            # the grip's centre at the start of a stroke
const STROKE := 2.6                # m: the longest stroke (down to 0.8 m)
const HANDLE_LAYER := 2
const GRAPH_EVERY_STEPS := 6

var model := PulleyLabModel.new()
var driver := PulleyLabDriver.new()
var props := PulleyProps.new()
var graph := RollingGraph.new(["applied", "required"] as Array[String], 10.0)
var strands_id := "one"
var load_body: RigidBody3D
var handle: StaticBody3D
## The finger holds the grip.
var holding := false
## Fixed steps with the grip held (the graph's clock).
var clock_steps := 0
var _press: PressLineSurface
var _press_step := 0.05


func _ready() -> void:
	model.g = engine_g   # the weight m g uses the engine's gravity (the project setting, the web's 9.81)
	model.max_lift = MAX_LIFT
	_build_world()
	for control in definition.get("controls", []):
		set_control(control.id, control.default)


func set_control(id: String, value: Variant) -> void:
	match id:
		"strands":
			var option := _find_option(id, str(value))
			if option.is_empty():
				push_warning("pulley: unknown strands %s" % value)
				return
			strands_id = str(value)
			model.strands = int(option.n)
			model.reset()          # the web starts the pull again when the strands change
			props.reset()
		"mass":
			model.mass = _clamp_to_control(id, float(value))
		_:
			return
	_changed()


func control_value(id: String) -> Variant:
	match id:
		"strands":
			return strands_id
		"mass":
			return model.mass
	return super(id)


func run_action(id: String) -> void:
	if id == "reset":
		model.reset()
		clock_steps = 0
		graph.clear()
		props.reset()
		_changed()


func _changed() -> void:
	if load_body == null:
		return
	driver.pose()
	props.show_strands(model.strands)
	graph.add(clock_time(), [model.applied(), model.required()])
	_show()
	_update_status(true)


func clock_time() -> float:
	return clock_steps / float(Engine.physics_ticks_per_second)


## Grid cells the grip is below the top of its stroke (0..the stroke's limit) while held.
func handle_cells() -> int:
	if not holding or _press == null:
		return 0
	return mini(model.stroke_limit(), roundi(clampf(_press.depth_of(handle.global_position), 0.0, STROKE) / _press_step))


## A stroke of `cells` without the grip (tests); `held` = the hand holds it.
func set_stroke(cells: int, held := true) -> void:
	model.stroke_cells = mini(cells, model.stroke_limit())
	model.holding = held


## The stroke ends without the grip (tests): the ratchet keeps the rope.
func let_go() -> void:
	model.let_go()


func _physics_process(_delta: float) -> void:
	if holding:
		model.stroke_cells = handle_cells()
		clock_steps += 1
		if clock_steps % GRAPH_EVERY_STEPS == 0:
			graph.add(clock_time(), [model.applied(), model.required()])
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	if status() != _last_status:
		_update_status()


func _process(_delta: float) -> void:
	if load_body == null:
		return
	if not holding:
		_place_handle()
	_show()


func _show() -> void:
	var grip_top := handle.global_position + Vector3(0.0, HANDLE_SIZE.y * 0.5, 0.0)
	props.show_rope(TOP_Y, load_body.global_position.y + HOOK_UP, GUIDE, grip_top,
		model.cells_before / float(PulleyLabModel.CELLS_PER_M), load_body.global_position, LOAD_SIZE * 0.5, model.weight(), model.applied())


## ground (on the floor), pulling (the hand holds it up), held (the ratchet holds it), top (at the
## highest place).
func status() -> String:
	if model.lift() <= 0.0:
		return "pulling" if holding else "ground"
	if model.lift() >= MAX_LIFT:
		return "top"
	return "pulling" if holding else "held"


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)


func observations() -> Dictionary:
	var state_text: String = {
		"ground": "빨간 손잡이를 아래로 당겨 짐을 올려요",
		"pulling": "당기는 중 · 손이 짐을 받치고 있어요",
		"held": "멈추개가 짐을 잡고 있어요 · 손잡이를 다시 당겨요",
		"top": "맨 위까지 올라갔어요",
	}.get(status(), "")
	return {
		"state": state_text,
		"strands": model.strands,
		"weight": model.weight(),
		"required": model.required(),
		"applied": model.applied(),
		"pulled": model.pulled(),
		"lift": model.lift(),
		"per_metre": model.pull_per_metre(),
		"work_in": model.work_in(),
		"work_out": model.work_out(),
	}


func graph_series() -> Dictionary:
	return graph.series()


func graph_revision() -> int:
	return graph.revision


func follow_point() -> Vector3:
	return load_body.global_position if load_body else global_position


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_add_floor(null, Vector3(30.0, 0.4, 22.0))
	load_body = RigidBody3D.new()
	load_body.name = "Load"
	_setup_free_body(load_body)
	load_body.gravity_scale = 0.0
	load_body.collision_layer = 1 << 2   # layer 3: nothing picks or stands on it
	load_body.collision_mask = 0
	_add_box_shape(load_body, Vector3.ONE * LOAD_SIZE)
	add_child(load_body)
	driver.history_steps = 600
	driver.attach(model, load_body, Vector3(LOAD_X, LOAD_SIZE * 0.5, 0.0))
	handle = StaticBody3D.new()
	handle.name = "Handle"
	handle.collision_layer = 1 << (HANDLE_LAYER - 1)
	handle.collision_mask = 0
	_add_box_shape(handle, HANDLE_SIZE)
	add_child(handle)
	_place_handle()
	props.dress(self, load_body, handle, {
		"left": LOAD_X - 1.4, "right": GUIDE.x + 1.0, "beam_y": BEAM_Y, "guide": GUIDE, "load_x": LOAD_X,
		"top_y": TOP_Y, "hook_up": HOOK_UP, "load_size": LOAD_SIZE, "handle": HANDLE_SIZE,
	})


## The grip's place at the start of a stroke: under the guide wheel's right side.
func handle_top() -> Vector3:
	return Vector3(GUIDE.x + PulleyProps.WHEEL_RADIUS, HANDLE_TOP, 0.0)


func _place_handle() -> void:
	var rest := handle_top()
	if handle.global_position != rest:
		handle.global_position = rest


# --- manipulation -------------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return handle if id == "handle" else null


## The grip's line down from the top of a stroke, as long as the rope left to pull allows.
func manipulation_surface(surface_id: String) -> ManipSurface:
	if surface_id != "pull":
		return null
	var reach := minf(STROKE, model.stroke_limit() / float(PulleyLabModel.CELLS_PER_M))
	var surface := PressLineSurface.new(handle_top(), reach, _grid_step("handle"), HANDLE_SIZE.y * 0.5)
	surface.exclude = [load_body.get_rid()]
	return surface


func manipulation_started(_id: String) -> void:
	holding = true
	model.holding = true
	_press = manipulation_surface("pull") as PressLineSurface
	_press_step = _grid_step("handle")
	_update_status(true)


## Let go where the grip was put down: that stroke counts, the ratchet keeps the rope pulled so far
## and the grip goes back up for the next stroke.
func manipulation_placed(_id: String, transform: Transform3D) -> void:
	if _press != null:
		model.stroke_cells = mini(model.stroke_limit(), roundi(clampf(_press.depth_of(transform.origin), 0.0, STROKE) / _press_step))
	_let_go()


## A cancelled pull (second finger, system cancel): the grip went back, the stroke does not count.
func manipulation_cancelled(_id: String) -> void:
	model.stroke_cells = 0
	_let_go()


func _let_go() -> void:
	holding = false
	_press = null
	model.let_go()
	_place_handle()
	_changed()
