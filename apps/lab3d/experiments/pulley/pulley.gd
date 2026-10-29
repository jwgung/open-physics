## Guided pulley lab (Phase 1 Task 4e; web preset "pulley", "도르래 줄이 많으면 얼마나 쉬워질까?"): an
## orange load (the web's 20 kg) hangs from n = 1, 2 or 4 supporting strands under a gantry. The
## child presses and holds the end of the pull strand (2026-10-28 user decision: the red grip went):
## the hand's force grows from 0 at PULL_RATE N/s up to PULL_MAX (HoldRamp) and a gauge beside it
## fills; once it reaches F = m g / n the rope comes down ROPE_SPEED m/s (a steady pull at F, on the
## 5 cm grid, at most STROKE per hold) and the load rises the pulled length / n. Letting go keeps the
## rope (a ratchet) and the rope end goes back up for the next stroke (hand over hand), so the same
## height can be reached with any n. Conditions: the number of strands (the web's 1 / 2 / 4 buttons)
## and the load mass (the web's mass input, 1-20 kg).
## Motion and every displayed number: PulleyLabModel (PulleyAdvantageChallenge: F = m g / n, lift =
## pull / n, pull for 1 m = n m; work F d_pull = m g d_lift); PulleyLabDriver poses the engine load on
## it every step (method "kinematic_model"). See docs/formula-correction.md (Task 4e).
## The graph is the web's "줄 수에 따른 필요한 힘": the hand's pull and the required force over the
## last 10 s with the rope held (a changed condition adds a point).
## The load looks as heavy as it is (2026-10-28, look_factor): its mesh grows from its bottom and the
## moving block rides on its top; its body (a LOAD_SIZE cube), its lift and the model stay.
extends PressHandleLab

const LOAD_X := -1.0
const LOAD_SIZE := 0.8
const LOOK_MASS := 20.0            # kg: the load that looks LOAD_SIZE big (the web's 20 kg)
const MAX_LIFT := 2.4
const TOP_Y := 4.4                 # bottom of the fixed block's wheels: the strands start here
const BEAM_Y := 4.95               # the gantry's top beam
const HOOK_UP := 0.62              # the moving block's hook above the load centre
const GUIDE := Vector3(1.2, 4.6, 0.0)   # the guide wheel over the pull side
const END_SIZE := Vector3(0.5, 0.5, 0.4)   # the rope end's pick box (the knot and around it)
const END_TOP := 3.4               # the rope end's centre at the start of a stroke
const STROKE := 2.6                # m: the longest stroke (down to 0.8 m)
## The held pull (2026-10-28): 65 N/s, at most 250 N; the rope then comes down 1 m/s. One strand
## with 20 kg (F = 196.2 N) moves after 3.02 s, two strands (98.1 N) after 1.51 s, four (49.05 N)
## after 0.75 s; 1 kg on four strands (2.45 N) after 0.04 s.
const PULL_RATE := 65.0            # N per second of holding
const PULL_MAX := 250.0            # N
const ROPE_SPEED := 1.0            # m of rope per second once the hand's force reaches F
const GAUGE_RIGHT := 0.7           # m right of the rope end

var model := PulleyLabModel.new()
var driver := PulleyLabDriver.new()
var props := PulleyProps.new()
var strands_id := "one"
## The finger holds the rope end.
var holding := false
## The rope end (pickable; its knot mesh from the props).
var rope_end: StaticBody3D
var _lifted := false
var _moving_steps := 0             # fixed steps of this hold with the hand at F (the rope coming down)


func _ready() -> void:
	model.g = engine_g   # the weight m g uses the engine's gravity (the project setting, the web's 9.81)
	model.max_lift = MAX_LIFT
	hand = HoldRamp.new(PULL_RATE, PULL_MAX)
	var snap := _grid_step("rope")   # the one source of the cell size: the definition's rope grid
	if snap > 0.0:
		model.cells_per_m = roundi(1.0 / snap)
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
			_restart()             # the web starts the pull again when the strands change (reset_run, once per batch)
			return
		"mass":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			model.mass = clamped
			props.set_look(look_factor())
		_:
			return
	_changed()


## The load look's size against its body's: one stuff, the cube root of the mass against LOOK_MASS.
func look_factor() -> float:
	return MassLook.factor(model.mass, LOOK_MASS)


func control_value(id: String) -> Variant:
	match id:
		"strands":
			return strands_id
		"mass":
			return model.mass
	return super(id)


func run_action(id: String) -> void:
	if id == "reset":
		_restart()


## A new pull: the rope, the clock and the graph start again, the props too. A grip the finger still
## holds is let go first (its stroke does not count): the load must not jump to the old stroke under
## the new strand count, and the clock must not go on with the old run.
func _new_pull() -> void:
	if holding:
		holding = false
		hand.stop()
		model.hand = INF
		_moving_steps = 0
		model.stroke_cells = 0
		_place_end()
		props.cat_let_go(end_top(), false)
	model.reset()
	model.holding = false
	_restart_clock()
	_lifted = false   # the pop below is the reaction
	props.reset()
	if game != null:
		game.run_reset()


## The screen's batch calls this once at its end (Experiment._restart): the new pull, then the posed
## bodies, props and graph point.
func reset_run() -> void:
	_new_pull()
	_changed()


func _changed() -> void:
	if load_body == null:
		return
	driver.pose()
	props.show_strands(model.strands)
	_add_graph_point()
	_show()
	_track_lift()
	_update_status(true)


# --- PressHandleLab ---------------------------------------------------------------------------

func _handle_held() -> bool:
	return holding


func _gauge_at() -> Vector3:
	return Vector3(end_top().x + GAUGE_RIGHT, END_TOP - ForceGauge.HEIGHT, 0.2)


## The cells this hold has pulled: ROPE_SPEED for the steps with the hand at F, on the 5 cm grid,
## at most a STROKE and the rest of the rope up to the top.
func stroke_cells_now() -> int:
	var metres := _moving_steps / float(Engine.physics_ticks_per_second) * ROPE_SPEED
	return mini(mini(floori(metres * model.cells_per_m + 1e-9), roundi(STROKE * model.cells_per_m)), model.stroke_limit())


func _graph_values() -> Array:
	return [model.applied(), model.required()]


## A stroke of `cells` without the grip (tests); `held` = the hand holds it.
func set_stroke(cells: int, held := true) -> void:
	model.stroke_cells = mini(cells, model.stroke_limit())
	model.holding = held


## The stroke ends without the grip (tests): the ratchet keeps the rope.
func let_go() -> void:
	model.let_go()


func _physics_process(_delta: float) -> void:
	if holding:
		_tick_clock()
		model.hand = hand.force()
		if model.hand >= model.required():
			_moving_steps += 1
		model.stroke_cells = stroke_cells_now()
		_place_end()
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	_track_lift()
	if status() != _last_status:
		_update_status()


func _process(_delta: float) -> void:
	if load_body == null:
		return
	_place_end()
	if holding:
		props.update_cat(rope_end.global_position, END_SIZE)
	_show_gauge()
	_show()


func _show() -> void:
	var grip_top := rope_end.global_position + Vector3(0.0, PulleyProps.KNOT_RADIUS, 0.0)
	props.show_rope(TOP_Y, load_body.global_position.y + props.hook_up, GUIDE, grip_top,
		model.pulled(), props.look_centre(load_body), LOAD_SIZE * 0.5 * props.look, model.weight(), model.applied())


## ground (on the floor), pulling (the hand holds it up), held (the ratchet holds it), top (at the
## highest place).
func status() -> String:
	if model.lift() <= 0.0:
		return "pulling" if holding else "ground"
	if model.lift() >= MAX_LIFT:
		return "top"
	return "pulling" if holding else "held"


## The lift-off reaction follows the load itself, not status() changes: grabbing the grip updates
## the status quietly (ground -> pulling), which must not swallow the load leaving the ground.
func _track_lift() -> void:
	var up := model.lift() > 0.0
	if up and not _lifted:
		props.lifted_off()
	_lifted = up


func observations() -> Dictionary:
	var state_text: String = {
		"ground": "줄 끝을 꾹 눌러 짐을 올려요",
		"pulling": "당기는 중 · 손이 짐을 받치고 있어요",
		"held": "멈추개가 짐을 잡고 있어요 · 줄 끝을 다시 눌러요",
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


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_add_floor(null, Vector3(30.0, 0.4, 22.0))
	load_body = RigidBody3D.new()
	load_body.name = "Load"
	_setup_free_body(load_body)
	load_body.gravity_scale = 0.0
	load_body.collision_layer = 0        # nothing picks, hits or stands on it (the juice's shadow ray excludes it)
	load_body.collision_mask = 0
	_add_box_shape(load_body, Vector3.ONE * LOAD_SIZE)
	add_child(load_body)
	driver.history_steps = 600
	driver.attach(model, load_body, Vector3(LOAD_X, LOAD_SIZE * 0.5, 0.0))
	rope_end = _static_pickable("RopeEnd", END_SIZE)
	_place_end()
	props.dress(self, load_body, rope_end, {
		"left": LOAD_X - 1.4, "right": GUIDE.x + 1.0, "beam_y": BEAM_Y, "guide": GUIDE, "load_x": LOAD_X,
		"top_y": TOP_Y, "hook_up": HOOK_UP, "load_size": LOAD_SIZE,
	})
	game = PulleyGame.new(self)   # the piece game: the chest load, the shelf at the top (visual only)
	(game as PulleyGame).shelf_y = MAX_LIFT
	add_child(game)
	game.build()


## The rope end's place at the start of a stroke: under the guide wheel's right side.
func end_top() -> Vector3:
	return Vector3(GUIDE.x + PulleyProps.WHEEL_RADIUS, END_TOP, 0.0)


## The rope end follows the stroke: down by the rope this hold has pulled (back up when let go).
func _place_end() -> void:
	var at := end_top() - Vector3(0.0, model.stroke_cells / float(model.cells_per_m), 0.0)
	if rope_end.global_position != at:
		rope_end.global_position = at


# --- manipulation -------------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return rope_end if id == "rope" else null


## Pressed and held: the hand's force grows from 0 from the next step; the rope moves once it is F.
func hold_started(_id: String) -> void:
	holding = true
	model.holding = true
	model.stroke_cells = 0
	_moving_steps = 0
	hand.start()
	model.hand = 0.0
	_update_status(true)


## Let go (or cancelled): the stroke pulled so far counts, the ratchet keeps the rope and the rope end
## goes back up for the next stroke.
func hold_ended(_id: String) -> void:
	holding = false
	hand.stop()
	model.hand = INF
	_moving_steps = 0
	model.let_go()
	_place_end()
	props.cat_let_go(end_top(), model.lift() > 0.0)
	_changed()
