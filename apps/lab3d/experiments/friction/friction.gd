## Guided push friction lab (Phase 1 Task 4b; web preset "friction", "얼마나 세게 밀어야 움직일까?"):
## a box on a level floor with friction, pulled (or pushed) through a red handle on a rod. Holding
## the handle and moving it along the floor sets the applied force: FORCE_PER_M newtons per metre
## from where it was picked up (the web: 0.9 N per px from the grab point), on the 1 N grid of the
## handle's `snap` rule, up to +-REACH m (+-80 N); letting go sets it back to 0 and the box slides
## on until friction stops it (the web's handle). Conditions: material (the web's four, mu_s =
## friction + 0.18, mu_k = friction) and mass (the web's mass buttons and its 8 kg start box).
## Motion: Jolt + ContactFrictionCorrector (method "contact_force", law "push": PushFrictionLaw
## injected along the floor, engine friction 0). Displayed numbers, the state ("버팀" / "움직임" /
## track end) and the graph come from PushFrictionModel (the same law stepped in 64 bit); the engine
## box is only the "이동 거리 (시뮬레이션)" readout. The box stops at the track ends (a formula
## stop, the bumpers are visual).
extends Experiment

const BOX := 0.7
const START_X := -3.0
## Box centres beyond these x stop the box (the yellow track ends at +-TRACK_HALF, bumpers outside).
const TRACK_HALF := 6.0
const FORCE_PER_M := 20.0     # N per metre of handle travel (1 N per 5 cm grid step)
const REACH := 4.0            # m either way: +-80 N
const HANDLE_GAP := 0.9       # m from the box's right face to the handle centre
const HANDLE_SIZE := Vector3(0.4, BOX, 0.4)   # the handle's pick box, standing on the floor
const HANDLE_LAYER := 2       # pickable, never touched by the box (mask 0)
const GRAPH_EVERY_STEPS := 6  # 10 Hz graph samples
const END_PADDING := 0.02     # m between a stopped box and the track end

var mass_id := "start"
var material_id := "wood"
var box: FormulaBody
var handle: StaticBody3D
var corrector := ContactFrictionCorrector.new()
var model := PushFrictionModel.new()
var props := FrictionProps.new()
## Box centre x where the current run started (reset / condition change).
var run_start_x := START_X
## The handle is held by a finger (the force follows it).
var holding_handle := false
## The box hit a track end and waits (frozen) until the handle is picked up or the lab is reset.
var ended := false

var _floor: StaticBody3D
var _track: Node3D
var _pull: ManipSurface         # the held handle's line (frame origin = where it was picked up)
var _pull_snap := 0.0           # its grid step (m, 64-bit: the surface keeps a 32-bit Vector2)
var _freeze_next := false       # the end was reached this step: freeze the box after its step
var _forced := 0.0              # force set by a test / demo without the handle (set_applied_force)
## Fixed steps since the last reset (every step, also at rest; tests and the bench count with it).
var frames := 0
var _clock_steps := 0           # steps with a force or a moving box since the reset (the graph's time)
var _graph: Array[Vector4] = []  # (t, |F|, max static, |friction|) samples, the last graph window
var _graph_revision := 0


func _ready() -> void:
	model.g = engine_g   # the formulas use the engine's gravity (the project setting)
	_build_world()
	for control in definition.get("controls", []):
		set_control(control.id, control.default)


func set_control(id: String, value: Variant) -> void:
	match id:
		"material":
			set_material(str(value))
		"mass":
			set_mass(str(value))


func control_value(id: String) -> Variant:
	match id:
		"material":
			return material_id
		"mass":
			return mass_id
	return super(id)


func run_action(id: String) -> void:
	if id == "reset":
		reset_box()


func set_material(option_id: String) -> void:
	var option := _find_option("material", option_id)
	if option.is_empty():
		push_warning("friction: unknown material %s" % option_id)
		return
	material_id = option_id
	model.mu_s = float(option.mu_s)
	model.mu_k = float(option.mu_k)
	corrector.mu_s = model.mu_s
	corrector.mu_k = model.mu_k
	reset_box()


func set_mass(option_id: String) -> void:
	var option := _find_option("mass", option_id)
	if option.is_empty():
		push_warning("friction: unknown mass %s" % option_id)
		return
	mass_id = option_id
	model.mass = float(option.kg)
	box.mass = model.mass
	reset_box()


## Applied force (N) without the handle: tests and the formula checks drive the lab with it (the
## handle, when held, wins).
func set_applied_force(force: float) -> void:
	_forced = force


## The force the handle (or set_applied_force) gives this step: FORCE_PER_M per metre of the held
## handle's grid point from where it was picked up.
func applied_force() -> float:
	if holding_handle and _pull != null:
		return handle_force(_pull.nearest_inside(_pull.to_plane(handle.global_position)).x, _pull_snap)
	return _forced


## Force (N) of a handle `offset` m from where it was picked up, on the grid of `snap` m (counted in
## whole grid steps, so a grid point gives a whole number of newtons exactly).
static func handle_force(offset: float, snap: float) -> float:
	if snap <= 0.0:
		return offset * FORCE_PER_M
	return roundi(offset / snap) * (snap * FORCE_PER_M)


## Box back at the start, at rest; the run, the heat and the graph start again.
func reset_box() -> void:
	_release_end()
	_forced = 0.0
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	box.global_position = Vector3(START_X, BOX * 0.5, 0.0)
	run_start_x = START_X
	corrector.reset(box.global_position)
	model.reset()
	frames = 0
	_clock_steps = 0
	_graph.clear()
	_graph_revision += 1
	if holding_handle:
		# The finger keeps the handle where it is: the force counts from here again (0 N), no jump.
		_pull = _pull_line(handle.global_position.x)
		_pull.snap = Vector2.ONE * _pull_snap
	else:
		_place_handle()
	props.reset()
	_update_status(true)


## Lets a box waiting at a track end go: not ended, not frozen (also the freeze still pending for
## the next step), shared by reset_box and picking up the handle.
func _release_end() -> void:
	if _freeze_next:
		# The freeze did not happen yet: stop the engine box at the bumper like it would have.
		box.linear_velocity = Vector3.ZERO
		box.global_position.x = formula_x()
	ended = false
	_freeze_next = false
	box.freeze = false


## "holding" (the law holds the box, also with no force), "sliding", or "end" (stopped at a track end).
func status() -> String:
	if ended:
		return "end"
	return "holding" if model.holding else "sliding"


## Box centre x by the formula.
func formula_x() -> float:
	return run_start_x + model.displacement


## The engine box's displacement from the run start (m): the "시뮬레이션" readout.
func engine_displacement() -> float:
	return box.global_position.x - run_start_x


func _physics_process(_delta: float) -> void:
	# Runs before the box's own step (tree order): the corrector and the model use the same force.
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	frames += 1
	if _freeze_next:
		_freeze_next = false
		box.linear_velocity = Vector3.ZERO
		box.freeze = true
		box.global_position.x = formula_x()   # at the bumper (the engine step may have run past it)
	if ended:
		# The bumper holds the box: the handle's force is shown, nothing moves.
		corrector.applied_force = 0.0
		model.applied = applied_force()
		model.friction = 0.0
		return
	var force := applied_force()
	corrector.applied_force = force
	if force == 0.0 and model.holding:
		model.applied = 0.0
		model.friction = 0.0
		return   # at rest with no force: nothing changes, the graph waits
	model.step(force, dt)
	_clock_steps += 1
	var x := formula_x()
	var low := -TRACK_HALF + BOX * 0.5 + END_PADDING
	var high := TRACK_HALF - BOX * 0.5 - END_PADDING
	if (x >= high and model.velocity > 0.0) or (x <= low and model.velocity < 0.0):
		# The bumper stops the box at the end (also a fast box that would pass it within this step).
		model.stop()
		model.displacement = clampf(x, low, high) - run_start_x
		ended = true
		_freeze_next = true
		props.hit_end()
		impact.emit(0.35)
	if _clock_steps % GRAPH_EVERY_STEPS == 0:
		_add_graph_sample()
	if status() != _last_status:
		_update_status()


func _process(_delta: float) -> void:
	if not holding_handle:
		_place_handle()
	props.update_rod(box.global_position, handle.global_position, model.holding and not ended)


## The handle waits HANDLE_GAP beside the box's right face, on the floor.
func _place_handle() -> void:
	if handle == null:
		return
	var rest := handle_rest()
	if handle.global_position != rest:
		handle.global_position = rest


func handle_rest() -> Vector3:
	return Vector3(box.global_position.x + BOX * 0.5 + HANDLE_GAP, HANDLE_SIZE.y * 0.5, 0.0)


func _add_graph_sample() -> void:
	var window := graph_x_max()
	var t := _clock_steps / float(Engine.physics_ticks_per_second)
	_graph.append(Vector4(t, absf(model.applied), model.max_static(), absf(model.friction)))
	while not _graph.is_empty() and _graph[0].x < t - window - 1e-6:
		_graph.pop_front()
	_graph_revision += 1


func graph_x_max() -> float:
	return float(definition.get("graph", {}).get("x", {}).get("max", 10.0))


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)


func observations() -> Dictionary:
	var state_text := ""
	match status():
		"end":
			state_text = "바닥 끝에 닿았어요"
		"holding":
			state_text = "멈춰 있어요" if model.applied == 0.0 else "버티는 중 · 마찰이 막고 있어요"
		"sliding":
			state_text = "움직여요 · 주는 힘이 마찰을 이겼어요" if model.applied != 0.0 else "미끄러지다 멈추는 중"
	return {
		"state": state_text,
		"applied": absf(model.applied),
		"max_static": model.max_static(),
		"friction": absf(model.friction),
		"kinetic": model.kinetic_friction(),
		"speed": absf(model.velocity),
		"heat": model.heat,
		"distance": absf(model.displacement),
		"measured": absf(engine_displacement()),
	}


## Applied force, maximum static friction and friction (magnitudes) over the last graph window: x is
## the time since the window's start (the time counts only steps with a force or a moving box).
func graph_series() -> Dictionary:
	var applied := PackedVector2Array()
	var limit := PackedVector2Array()
	var friction := PackedVector2Array()
	if not _graph.is_empty():
		var offset := maxf(0.0, _graph[-1].x - graph_x_max())
		for s in _graph:
			applied.append(Vector2(s.x - offset, s.y))
			limit.append(Vector2(s.x - offset, s.z))
			friction.append(Vector2(s.x - offset, s.w))
	return {"applied": applied, "max_static": limit, "friction": friction}


func graph_revision() -> int:
	return _graph_revision


func follow_point() -> Vector3:
	return box.global_position if box else global_position


func _build_world() -> void:
	var frictionless := _frictionless_material()
	_floor = _add_floor(frictionless)
	# The surface frame of the corrector: the floor's top face (y = 0), +x along the track.
	_track = Node3D.new()
	_track.name = "Track"
	add_child(_track)
	var track_visual := ArtKit.instance(props.track_mesh(TRACK_HALF * 2.0, START_X))
	track_visual.name = "TrackVisual"
	_track.add_child(track_visual)

	box = FormulaBody.new()
	box.name = "Box"
	box.mass = model.mass
	box.physics_material_override = frictionless
	_setup_free_body(box)
	box.lock_rotation = true
	_add_box_shape(box, Vector3.ONE * BOX)
	var box_visual := ArtKit.instance(props.box_mesh(BOX))
	box_visual.name = "Visual"
	box.add_child(box_visual)
	box.position = Vector3(START_X, BOX * 0.5, 0.0)
	add_child(box)

	corrector.law = "push"
	corrector.surface = _track
	corrector.tangent_axis = Vector3.RIGHT
	corrector.half_length = TRACK_HALF + 1.0
	corrector.half_extent = BOX * 0.5
	corrector.history_steps = 2
	box.corrector = corrector

	handle = StaticBody3D.new()
	handle.name = "Handle"
	handle.collision_layer = 1 << (HANDLE_LAYER - 1)
	handle.collision_mask = 0
	_add_box_shape(handle, HANDLE_SIZE)
	var handle_visual := ArtKit.instance(props.handle_mesh(HANDLE_SIZE.y))
	handle_visual.name = "Visual"
	handle.add_child(handle_visual)
	add_child(handle)
	_place_handle()

	props.dress(self, box, box_visual, BOX, handle_visual)
	props.juice.landed.connect(impact.emit)


# --- manipulation -----------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return handle if id == "handle" else null


## The handle's line along the floor through where it waits now (the grid counts from there, so
## the grid point under the finger is a whole number of newtons).
func manipulation_surface(surface_id: String) -> ManipSurface:
	if surface_id != "pull":
		return null
	return _pull_line(handle_rest().x)


## The pull line along the floor with its origin (zero force) at `origin_x`.
func _pull_line(origin_x: float) -> ManipSurface:
	var line := ManipSurface.new(Transform3D(Basis(), Vector3(origin_x, 0.0, 0.0)),
		Vector2(-REACH, 0.0), Vector2(REACH, 0.0))
	line.exclude = [_floor.get_rid(), box.get_rid()]
	return line


## Picked up: from now on the force follows the handle. A box waiting at a track end is let go again.
func manipulation_started(_id: String) -> void:
	_pull = manipulation_surface("pull")
	_pull_snap = float(Manipulator.parse_rules(definition).get("handle", {}).get("snap", 0.0))
	_pull.snap = Vector2.ONE * _pull_snap
	holding_handle = true
	_forced = 0.0
	if ended:
		_release_end()
		corrector.status = "holding"
		_update_status(true)
	props.grab(true)


## Let go (also when the shell puts it back): the force is 0 again, the handle returns to the box.
func manipulation_placed(_id: String, _transform: Transform3D) -> void:
	_let_go()


func manipulation_cancelled(_id: String) -> void:
	_let_go()


func _let_go() -> void:
	holding_handle = false
	_pull = null
	_place_handle()
	props.grab(false)
