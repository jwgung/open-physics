## Guided push friction lab (Phase 1 Task 4b; web preset "friction", "얼마나 세게 밀어야 움직일까?"):
## a box on a level floor with friction, pushed towards +x by the bread cat. The child presses and
## holds the box itself (2026-10-28 user decision, no handle): while held the applied force grows
## from 0 at PUSH_RATE N/s up to PUSH_MAX (80 N, the old handle's +-80 N) - HoldRamp - and a gauge
## beside the box fills; letting go sets it back to 0 at once and the box slides on until friction
## stops it (the web's handle let go). The box starts exactly when the ramped force passes
## mu_s m g (PushFrictionLaw). Conditions: material (the web's four, mu_s =
## friction + 0.18, mu_k = friction) and mass (the kid boxes 2 / 5 / 10 kg and the web's 8 kg start
## box; 2026-10-28 user decision "너무 쉽게 밀려": the web's 0.5 / 1 / 3 kg buttons broke loose with
## 10-60 cm of handle on wood, now about 0.4 / 1 / 2 m. The law is the web's: its vectors drive the
## lab with the web's masses through set_box_mass).
## Motion: Jolt + ContactFrictionCorrector (method "contact_force", law "push": PushFrictionLaw
## injected along the floor, engine friction 0). Displayed numbers, the state ("버팀" / "움직임" /
## track end) and the graph come from PushFrictionModel (the same law stepped in 64 bit); the engine
## box is only the "이동 거리 (시뮬레이션)" readout. The box stops at the track ends (a formula
## stop, the bumpers are visual). The box looks as heavy as it is (2026-10-28, look_factor): its
## mesh grows from its body's bottom; the body (a BOX cube), the law and the stops stay.
extends Experiment

const BOX := 0.7
const START_X := -3.0
const LOOK_MASS := 8.0        # kg: the box that looks BOX big (the web's start box)
## Box centres beyond these x stop the box (the yellow track ends at +-TRACK_HALF, bumpers outside).
const TRACK_HALF := 6.0
## The held push (2026-10-28): 25 N/s, at most 80 N. The heaviest box the child can pick (10 kg on
## clay: mu_s m g = 74.6 N) starts after 2.98 s; the 2 kg box on wood (7.85 N) after 0.31 s.
const PUSH_RATE := 25.0       # N per second of holding
const PUSH_MAX := 80.0        # N
const GRAPH_EVERY_STEPS := 6  # 10 Hz graph samples
const END_PADDING := 0.02     # m between a stopped box and the track end
## No close-up on the push (2026-10-28 user: the zoom on picking up the handle felt awkward, as the
## throw's did): the camera stays where the child left it while the box is held and slides.

var mass_id := "start"
var material_id := "wood"
var box: FormulaBody
var corrector := ContactFrictionCorrector.new()
var model := PushFrictionModel.new()
var props := FrictionProps.new()
## Box centre x where the current run started (reset / condition change).
var run_start_x := START_X
## The finger's press on the box: the applied force while it holds (HoldRamp).
var push := HoldRamp.new(PUSH_RATE, PUSH_MAX)
## The box hit a track end and waits (frozen) until the box is pressed again or the lab is reset.
var ended := false

var _floor: StaticBody3D
var _track: Node3D
var _freeze_next := false       # the end was reached this step: freeze the box after its step
var _forced := 0.0              # force set by a test without a hold (set_applied_force)
## Fixed steps since the last reset (every step, also at rest; tests and the bench count with it).
var frames := 0
var _clock_steps := 0           # steps with a force or a moving box since the reset (the graph's time)
var _graph: Array[Vector4] = []  # (t, |F|, max static, |friction|) samples, the last graph window
var _graph_revision := 0
## The push that started the box this run (N, the formula's mu_s m g at the moment it broke loose;
## -1 until it did): the mission's key card (2026-10-28). Read only: nothing reads it back.
var start_force := -1.0


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
	props.set_surface(material_id)
	reset_box()


func set_mass(option_id: String) -> void:
	var option := _find_option("mass", option_id)
	if option.is_empty():
		push_warning("friction: unknown mass %s" % option_id)
		return
	mass_id = option_id
	set_box_mass(float(option.kg))


## A box of `kg` (the mass option's, or any mass: the web-parity tests drive the law with the web's
## 0.5 / 1 / 3 kg boxes): the formula, the body and the look; the box goes back to the start.
func set_box_mass(kg: float) -> void:
	model.mass = kg
	box.mass = model.mass
	props.set_look(look_factor())
	reset_box()


## The box look's size against its body's: one stuff, the cube root of the mass against LOOK_MASS.
func look_factor() -> float:
	return MassLook.factor(model.mass, LOOK_MASS)


## Applied force (N) without a hold: tests and the formula checks drive the lab with it (a hold, when
## the finger is on the box, wins).
func set_applied_force(force: float) -> void:
	_forced = force


## The force the hold (or set_applied_force) gives this step: the held push's ramp.
func applied_force() -> float:
	if push.held:
		return push.force()
	return _forced


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
	start_force = -1.0
	frames = 0
	_clock_steps = 0
	_graph.clear()
	_graph_revision += 1
	if push.held:
		push.start()   # a finger still on the box: the push counts from 0 again, no jump
	props.reset()
	if game != null:
		game.run_reset()
	_update_status(true)


## Lets a box waiting at a track end go: not ended, not frozen (also the freeze still pending for
## the next step), shared by reset_box and a new press on the box.
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
	push.tick()
	if _freeze_next:
		_freeze_next = false
		box.linear_velocity = Vector3.ZERO
		box.freeze = true
		box.global_position.x = formula_x()   # at the bumper (the engine step may have run past it)
	if ended:
		# The bumper holds the box: the push is shown, nothing moves.
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
	if start_force < 0.0 and not model.holding:
		start_force = model.max_static()   # the box broke loose: the push it took (mu_s m g)
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
	props.show_gauge(box.global_position, push.held, push.fraction())
	if game == null or not (game as FrictionGame).cat_busy():   # after the round the cat walks the opened path
		props.update_cat(model.applied, model.max_static(), box.global_position.x, 0.0 if ended else model.velocity)


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
		"start_force": start_force if start_force >= 0.0 else "밀어 보면 보여요",
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
	_track.add_child(props.make_track(TRACK_HALF * 2.0, START_X, material_id))

	box = FormulaBody.new()
	box.name = "Box"
	box.mass = model.mass
	box.physics_material_override = frictionless
	_setup_free_body(box)
	box.lock_rotation = true
	_add_box_shape(box, Vector3.ONE * BOX)
	var box_visual := ArtKit.parcel_box(BOX)   # a parcel box (Task 4g)
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

	props.dress(self, box, box_visual, BOX, TRACK_HALF - BOX * 0.5 - END_PADDING)
	props.set_look(look_factor())
	game = FrictionGame.new(self)   # the piece game: the path the box blocks, its gates, the piece (visual only)
	add_child(game)
	game.build()
	props.juice.landed.connect(impact.emit)


# --- manipulation -----------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return box if id == "box" else null


## Pressed and held (2026-10-28): from the next step the push grows from 0 (PUSH_RATE). A box waiting
## at a track end is let go again.
func hold_started(_id: String) -> void:
	push.start()
	_forced = 0.0
	if ended:
		_release_end()
		corrector.status = "holding"
		_update_status(true)


## Let go (or the hold was cancelled): the push is 0 at once; a moving box slides on.
func hold_ended(_id: String) -> void:
	push.stop()
