## Guided lever lab (Phase 1 Task 4e; web preset "rotation", "지렛대로 무거운 짐을 들 수 있을까?"): a
## 6 m beam on a fulcrum with an orange load (the web's 20 kg) on its left side. The red handle above
## the chosen effort point (the web's three points 가까이 / 중간 / 멀리) is pressed down by one finger:
## a spring scale, force_step newtons per 2 cm (5 N; the scale steps up to 10 / 20 / 50 N when the
## full press of REACH would not lift the load, so every condition can be lifted). When the force reaches F = m g r_load / r_effort the
## beam turns to the web's lift angle (load side up); letting go puts it back level. The fulcrum and
## the load can be dragged along the beam (0.25 m grid; the web's lever has them fixed). Conditions:
## the load mass (the web's mass input, 1-20 kg) and the effort point.
## Motion and every displayed number: LeverLabModel (LeverChallenge: required force, capped force on
## the beam, lifting, torques); LeverLabDriver poses the engine beam and load on it every step
## (method "kinematic_model"). See docs/formula-correction.md (Task 4e).
## The graph is the web's "지렛대에 필요한 힘": the force on the beam and the required force over the
## last 10 s of pressing (the clock runs while the handle is held; a changed condition adds a point).
extends PressHandleLab

const BEAM_HALF := 3.0
const BEAM_THICK := 0.22
const BEAM_DEPTH := 0.6
const PIVOT_Y := 1.25              # the beam's axis (world y)
const LOAD_SIZE := 0.7
const PIVOT_MIN := -1.5            # fulcrum range (world x)
const PIVOT_MAX := 1.5
const LOAD_MIN := -2.75            # leftmost load centre
const LOAD_GAP := 0.5              # the load stays this far left of the fulcrum (or more)
const DEFAULT_PIVOT := -0.5
const DEFAULT_LOAD := -2.5
const REST_X := -2.75              # the rest block under the beam's left end
const HANDLE_SIZE := Vector3(0.6, 0.3, 0.5)
const HANDLE_REST := 1.6           # m above the beam's axis (the grip's centre, not pressed)
const REACH := 1.0                 # m of press: 50 cells (REACH / the handle's 2 cm grid)
const MAX_CELLS := 50
const LOAD_LAYER := 3              # the pickable load (the handle and the stand are on HANDLE_LAYER)
const IDS: Array[String] = ["handle", "load", "fulcrum"]

var model := LeverLabModel.new()
var driver := LeverLabDriver.new()
var props := RotationProps.new()
var effort_id := "mid"
## false = the scale stays where a test set it (model.force_step).
var auto_force_step := true
var beam: RigidBody3D
var stand: StaticBody3D
## The finger holds this object ("" = none).
var holding := ""
var _floor: StaticBody3D
var _was_lifted := false
var _placed := {}                 # ids put down by hand (kept across a screen rebuild)


func _ready() -> void:
	model.g = engine_g   # the weight m g uses the engine's gravity (the project setting, the web's 9.81)
	_build_world()
	for control in definition.get("controls", []):
		set_control(control.id, control.default)


func set_control(id: String, value: Variant) -> void:
	match id:
		"mass":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			model.mass = clamped
		"effort":
			var option := _find_option(id, str(value))
			if option.is_empty():
				push_warning("rotation: unknown effort point %s" % value)
				return
			effort_id = str(value)
			model.fraction = float(option.fraction)
		_:
			return
	_changed()


func control_value(id: String) -> Variant:
	match id:
		"mass":
			return model.mass
		"effort":
			return effort_id
	return super(id)


func run_action(id: String) -> void:
	if id == "reset":
		model.pivot_x = DEFAULT_PIVOT
		model.load_x = DEFAULT_LOAD
		model.cells = 0
		_placed.clear()
		_restart_clock()
		_was_lifted = false   # the pop below is the reaction; no lowering on top of it
		props.reset()
		_changed()


## The conditions or the lever changed: pose the bodies, add a graph point at the current time.
func _changed() -> void:
	if beam == null:
		return
	if auto_force_step:
		model.fit_force_step(MAX_CELLS)
	driver.pose(true)
	_place_stand()
	_add_graph_point()
	_show_markers()
	_show()
	_track_lift()
	_update_status(true)


# --- PressHandleLab ---------------------------------------------------------------------------

func _handle_held() -> bool:
	return holding == "handle"


func _handle_rest() -> Vector3:
	return handle_rest()


func _handle_reach() -> float:
	return REACH


func _graph_values() -> Array:
	return [model.applied(), model.required()]


## Pressed cells without the handle (tests): the force of `cells` grid steps.
func set_cells(cells: int) -> void:
	model.cells = cells


## Fulcrum and load positions (world x) without dragging (tests): a condition change.
func set_layout(pivot: float, load_at: float) -> void:
	model.pivot_x = pivot
	model.load_x = load_at
	_changed()


func _physics_process(_delta: float) -> void:
	if holding == "handle":
		model.cells = handle_cells()
		_tick_clock()
	driver.hand_holds = holding == "load"
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	_track_lift()
	if status() != _last_status:
		_update_status()


func _process(_delta: float) -> void:
	if beam == null:
		return
	if holding != "handle":
		_place_handle()
	_show()


func _show() -> void:
	var effort := Vector3(model.beam_x(model.effort_x(), BEAM_THICK * 0.5), model.beam_y(model.effort_x(), BEAM_THICK * 0.5), 0.0)
	props.show_forces(handle.global_position - Vector3(0.0, HANDLE_SIZE.y * 0.5, 0.0), effort, model.applied(),
		load_body.global_position, LOAD_SIZE * 0.5, model.weight())
	props.update_cat(model, beam, BEAM_THICK, clampf(model.applied() / model.required(), 0.0, 1.0) if model.required() > 0.0 else 0.0)


## The three effort points on the beam (beam-local x = world x of the level beam), the chosen one red.
func _show_markers() -> void:
	var points: Array[float] = []
	var chosen := 0
	for option in _find_control("effort").get("options", []):
		if option.id == effort_id:
			chosen = points.size()
		points.append(model.effort_x_at(float(option.fraction)))
	props.show_markers(points, chosen, BEAM_THICK, BEAM_DEPTH)


## ready (no force), pressing (held, not enough), lifted, moving (the load or the fulcrum is held).
func status() -> String:
	if model.lifting():
		return "lifted"
	if holding == "handle":
		return "pressing" if model.cells > 0 else "holding"
	if holding != "":
		return "moving"
	return "ready"


## The lift and lowering reactions follow the beam's state itself, not status() changes: a change made
## by the hand (a released handle, a moved load, a new condition) updates the status quietly but
## still lifts or sets the beam down.
func _track_lift() -> void:
	var up := model.lifting()
	if up != _was_lifted:
		_was_lifted = up
		if up:
			props.lifted()
		else:
			props.lowered()


func observations() -> Dictionary:
	var state_text: String = {
		"ready": "힘점을 골라 빨간 손잡이를 아래로 눌러 보세요",
		"holding": "손잡이를 아래로 눌러요",
		"pressing": "누르는 중 · 아직 힘이 모자라요",
		"lifted": "들렸다! 힘이 충분해요",
		"moving": "받침점·짐 위치를 옮기는 중",
	}.get(status(), "")
	return {
		"state": state_text,
		"weight": model.weight(),
		"load_arm": model.load_arm(),
		"effort_arm": model.effort_arm(),
		"required": model.required(),
		"applied": model.applied(),
		"force_step": model.force_step,
		"advantage": model.advantage(),
		"load_torque": absf(model.load_torque()),
		"effort_torque": absf(model.effort_torque()),
		"net_torque": model.load_torque() + model.effort_torque(),
	}


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_floor = _add_floor(null, Vector3(30.0, 0.4, 22.0))
	model.beam_half = BEAM_HALF
	model.pivot_y = PIVOT_Y
	model.pivot_x = DEFAULT_PIVOT
	model.load_x = DEFAULT_LOAD
	model.load_up = BEAM_THICK * 0.5 + LOAD_SIZE * 0.5
	beam = RigidBody3D.new()
	beam.name = "Beam"
	_setup_free_body(beam)
	beam.gravity_scale = 0.0
	beam.collision_mask = 0              # layer 1: the load's shadow lands on it; it touches nothing
	_add_box_shape(beam, Vector3(BEAM_HALF * 2.0, BEAM_THICK, BEAM_DEPTH))
	add_child(beam)
	load_body = RigidBody3D.new()
	load_body.name = "Load"
	_setup_free_body(load_body)
	load_body.gravity_scale = 0.0
	load_body.collision_layer = 1 << (LOAD_LAYER - 1)
	load_body.collision_mask = 0
	_add_box_shape(load_body, Vector3.ONE * LOAD_SIZE)
	add_child(load_body)
	driver.history_steps = 600
	driver.attach(model, beam, load_body)
	stand = _static_pickable("Fulcrum", Vector3(0.9, stand_height(), BEAM_DEPTH))
	handle = _static_pickable("Handle", HANDLE_SIZE)
	_place_stand()
	_place_handle()
	props.dress(self, {"beam": beam, "load": load_body, "stand": stand, "handle": handle}, {
		"beam_half": BEAM_HALF, "beam_thick": BEAM_THICK, "beam_depth": BEAM_DEPTH, "rest_x": REST_X,
		"rest_top": PIVOT_Y - BEAM_THICK * 0.5, "stand_height": stand_height(), "load_size": LOAD_SIZE, "handle": HANDLE_SIZE,
	})


## The stand reaches from the floor to just under the beam.
func stand_height() -> float:
	return PIVOT_Y - BEAM_THICK * 0.5 - 0.01


func _place_stand() -> void:
	if holding != "fulcrum":
		stand.global_position = Vector3(model.pivot_x, stand_height() * 0.5, 0.0)


## The grip's rest point: HANDLE_REST above the effort point of the level beam.
func handle_rest() -> Vector3:
	return Vector3(model.effort_x(), PIVOT_Y + HANDLE_REST, 0.0)


# --- manipulation -------------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	match id:
		"handle":
			return handle
		"load":
			return load_body
		"fulcrum":
			return stand
	return null


func manipulation_surface(surface_id: String) -> ManipSurface:
	var surface: ManipSurface
	match surface_id:
		"press":
			surface = _press_line(handle_rest(), REACH, _grid_step("handle"), HANDLE_SIZE.y * 0.5)
		"beam_top":
			surface = ManipSurface.new(Transform3D(Basis(), Vector3(0.0, PIVOT_Y + BEAM_THICK * 0.5, 0.0)),
				Vector2(LOAD_MIN, 0.0), Vector2(model.pivot_x - LOAD_GAP, 0.0), Vector2(_grid_step("load"), 0.0))
		"floor_line":
			surface = ManipSurface.new(Transform3D.IDENTITY, Vector2(PIVOT_MIN, 0.0), Vector2(PIVOT_MAX, 0.0), Vector2(_grid_step("fulcrum"), 0.0))
		_:
			return null
	surface.exclude = [_floor.get_rid(), beam.get_rid(), load_body.get_rid(), stand.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	return props.juice if id == "load" else null


## The fulcrum stays LOAD_GAP right of the load (the load left of the fulcrum).
func placement_allowed(id: String, transform: Transform3D) -> bool:
	match id:
		"fulcrum":
			return transform.origin.x >= model.load_x + LOAD_GAP - 1e-6
		"load":
			return transform.origin.x <= model.pivot_x - LOAD_GAP + 1e-6
	return true


func manipulation_started(id: String) -> void:
	holding = id
	model.cells = 0
	if id == "handle":
		_begin_press(manipulation_surface("press"))
	_update_status(true)


## Put down: the handle lets go (no force, the beam back level); the load or the fulcrum takes its
## new place (a condition change).
func manipulation_placed(id: String, transform: Transform3D) -> void:
	holding = ""
	_end_press()
	model.cells = 0
	match id:
		"load":
			model.load_x = _snap_to_grid("load", transform.origin.x, LOAD_MIN, model.pivot_x - LOAD_GAP)
			_placed[id] = true
		"fulcrum":
			model.pivot_x = _snap_to_grid("fulcrum", transform.origin.x, PIVOT_MIN, PIVOT_MAX)
			_placed[id] = true
	_changed()


func manipulation_cancelled(_id: String) -> void:
	holding = ""
	_end_press()
	model.cells = 0
	_changed()


func placements() -> Dictionary:
	# The fulcrum first: restoring the load limits it to LOAD_GAP left of the fulcrum, so the fulcrum
	# must already be where it was (the screen restores in this order).
	var result := {}
	if _placed.has("fulcrum"):
		result["fulcrum"] = Transform3D(Basis(), Vector3(model.pivot_x, stand_height() * 0.5, 0.0))
	if _placed.has("load"):
		result["load"] = Transform3D(Basis(), Vector3(model.load_x, PIVOT_Y + model.load_up, 0.0))
	return result
