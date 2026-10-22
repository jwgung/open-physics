## Shared base of the uniform-field guided labs (Phase 1 Task 4a: free fall and projectile). Both
## drop or throw balls in the field chosen by the "gravity" control (the web's gravity buttons:
## 0, moon 1.62, earth 9.81, jupiter 24.79 m/s^2) and use the uniform-field formula correction
## (UniformFieldCorrector, docs/formula-correction.md section 4): Jolt integrates the field, the
## first released step gets the leapfrog half force, and the engine contact report ends the free
## flight. Every displayed number comes from PhysicsLaws; engine positions are only the graph's
## "시뮬레이션" points and the measured landing values.
## The base also owns what both labs do the same way: the run state (released), the graph's
## "시뮬레이션" points and revision, the status change hint, the controls' defaults, and the
## release / reset actions. A lab fills in _build_world, release, reset_run, status, _released_step.
## The field is the project gravity (physics/3d/default_gravity) times each ball's gravity_scale, so
## the corrector reads it from the engine on release; its 64-bit g is set to the chosen value first.
class_name UniformFieldLab
extends Experiment

const BALL_RADIUS := 0.25     # m (0.5 m balls, about the web's 24 px radius at 48 px = 1 m)
const GRAPH_EVERY_STEPS := 6  # graph sample every 6 fixed steps (10 Hz), like the incline
## The balls' own collision layer; their mask is the world's layer 1 only, so balls never touch each
## other (each falls as its own formula says; a neighbour's contact also delayed the engine's floor
## report by a step). Picking and the free-place query still see them (all layers).
const BALL_LAYER := 3

## Field the balls feel (m/s^2, downwards) and the selected gravity option id.
var g := 9.81
var gravity_id := "earth"
## The project's engine gravity; gravity_scale = g / engine_g.
var engine_g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.81)
var floor_body: StaticBody3D
## True from the release until the next reset (the balls are in the field, not held).
var released := false
## Island / pad / reaction props; the lab assigns its own PadProps subclass in _init.
var props: PadProps
## Set once the user moved something (placements() then keeps it across a screen rebuild).
var _placed := false
## Engine samples for the graph: (time, height of the ball's bottom above the floor).
var _measured := PackedVector2Array()
var _graph_revision := 0
var _last_status := ""


func _ready() -> void:
	_build_world()
	for control in definition.get("controls", []):
		set_control(control.id, control.default)


## Builds the lab's bodies and props (once, before the controls' defaults are applied).
func _build_world() -> void:
	pass


## The gravity control; the lab's own controls call super for the others.
func set_control(id: String, value: Variant) -> void:
	if id == "gravity":
		set_gravity(str(value))
		reset_run()


func control_value(id: String) -> Variant:
	if id == "gravity":
		return gravity_id
	return super(id)


func run_action(id: String) -> void:
	match id:
		"release":
			release()
		"reset":
			reset_run()


## Lets the balls go (a run in progress is reset first).
func release() -> void:
	pass


## Every ball back at its start, frozen, in the current field; graph points cleared.
func reset_run() -> void:
	pass


## "ready" / ... : the state that decides the panels' texts; a change emits state_changed.
func status() -> String:
	return "ready"


## Per fixed step while released (before the balls' own step: tree order).
func _released_step() -> void:
	pass


func _physics_process(_delta: float) -> void:
	if not released:
		return
	_released_step()
	if status() != _last_status:
		_update_status()


func _update_status(quiet := false) -> void:
	_last_status = status()
	if not quiet:
		state_changed.emit()


func graph_revision() -> int:
	return _graph_revision


func manipulation_cancelled(_id: String) -> void:
	reset_run()


## The run starts: `first_points` are the graph's first measured points (the release height).
func _mark_released(first_points: PackedVector2Array) -> void:
	released = true
	_measured = first_points
	_graph_revision += 1
	props.released()
	_update_status(true)


## The balls are back at their start.
func _mark_reset() -> void:
	released = false
	_measured.clear()
	_graph_revision += 1
	props.reset()
	_update_status(true)


## Time (s) of this fixed step when it is a graph sample step inside the graph window, else -1.
## `steps` = fixed steps since the release (the corrector's samples index).
func _graph_sample_time(steps: int) -> float:
	if steps <= 0 or steps % GRAPH_EVERY_STEPS != 0:
		return -1.0
	var t := steps * step_dt()
	return t if t <= graph_x_max() + 0.001 else -1.0


## Appends the engine's height of one ball at `steps` to the graph points and moves the graph
## revision on, unless the ball landed earlier or at the release (formula `landing` 0; true when a
## point was added).
func _append_sample(c: UniformFieldCorrector, steps: int, start_y: float, landing: float) -> bool:
	var landed_before := c.landed_step >= 0 and c.landed_step < steps
	if landing <= 0.0 or steps >= c.samples.size() or landed_before:
		return false
	_measured.append(Vector2(steps * step_dt(), maxf(0.0, start_y + c.samples[steps])))
	_graph_revision += 1
	return true


## The formula line of one ball for the graph: (t, height(t)) at 61 points over the graph window,
## ending with (landing, 0) at the formula `landing` (INF: no landing, the whole window).
func _formula_line(height: Callable, landing: float) -> PackedVector2Array:
	var line := PackedVector2Array()
	var x_max := graph_x_max()
	for i in 61:
		var t := x_max * i / 60.0
		if t >= landing:
			line.append(Vector2(landing, 0.0))
			break
		line.append(Vector2(t, height.call(t)))
	return line


## A ball has landed: the engine reported its landing, or its formula landing time is 0 (let go on
## the floor in a field and not thrown upwards: nothing to fall). Without a field a ball on the
## floor never lands (landing INF).
## A landing within the first step (a release a few mm above the floor) touches the floor inside the
## step that seeds the start contacts, so the engine never reports it: the formula time decides.
static func has_landed_by(c: UniformFieldCorrector, landing: float) -> bool:
	return c.landed_step >= 0 or landing <= c.dt


## Start height (ball bottom above the floor, m) kept on the 1 mm grid of the handles' steps, so the
## engine start, the graph points and the formulas use one value.
static func snapped_height(bottom_y: float) -> float:
	return snappedf(bottom_y, 0.001)


## Selects a gravity option ({id, g} in the "gravity" control). False for an unknown id.
func set_gravity(option_id: String) -> bool:
	var option := _find_option("gravity", option_id)
	if not option.is_empty():
		g = float(option.g)
		gravity_id = option_id
		return true
	push_warning("%s: unknown gravity %s" % [definition.get("id", "?"), option_id])
	return false


## Puts the chosen field on a ball: engine gravity scale and the corrector's 64-bit strength.
func apply_field(ball: FormulaBody) -> void:
	ball.gravity_scale = g / engine_g
	(ball.corrector as UniformFieldCorrector).g = g


## Fixed-step length (s).
func step_dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## Graph window (s) from the definition.
func graph_x_max() -> float:
	return float(definition.get("graph", {}).get("x", {}).get("max", 3.0))


## Collision floor: the island's top surface at y = 0 (the island mesh is ArtKit's, no collision).
func make_floor(size: Vector3) -> StaticBody3D:
	floor_body = StaticBody3D.new()
	floor_body.name = "Floor"
	var material := PhysicsMaterial.new()
	material.friction = 0.6
	material.bounce = 0.0
	floor_body.physics_material_override = material
	_add_box_shape(floor_body, Vector3(size.x, 0.4, size.z))
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	add_child(floor_body)
	return floor_body


## A ball for the uniform-field correction: sphere of BALL_RADIUS, no damping, no rotation (a toy
## ball that slides after landing; the free flight has no rotation anyway, and ArtJuice squashes
## along the surface normal), frozen until released, contact reports on (landing: on the floor made
## by make_floor before, which a lab can add its own surfaces to).
func make_ball(ball_name: String, mass: float, bounce: float) -> FormulaBody:
	var ball := FormulaBody.new()
	ball.name = ball_name
	ball.mass = mass
	ball.can_sleep = false
	ball.lock_rotation = true
	ball.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.linear_damp = 0.0
	ball.angular_damp = 0.0
	ball.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	ball.freeze = true
	ball.contact_monitor = true
	ball.max_contacts_reported = 4
	ball.collision_layer = 1 << (BALL_LAYER - 1)
	ball.collision_mask = 1   # the world (floor); other balls and handles are on other layers
	var material := PhysicsMaterial.new()
	material.friction = 0.6
	material.bounce = bounce
	ball.physics_material_override = material
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_RADIUS
	shape.shape = sphere
	ball.add_child(shape)
	var corrector := UniformFieldCorrector.new()
	if floor_body:
		corrector.surfaces.assign([floor_body])   # landing on the ground only, not on another ball
	# The graph window (+ a sample at its end) is all the lab reads from the history.
	corrector.history_steps = int(graph_x_max() * Engine.physics_ticks_per_second) + 2
	ball.corrector = corrector
	return ball


## Stops a ball where it is (frozen, no velocity) with a fresh corrector history: not released.
static func hold_ball(ball: FormulaBody, at: Vector3) -> void:
	ball.freeze = true
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = at
	var corrector := ball.corrector as UniformFieldCorrector
	corrector.reset_history()
	corrector.offsets.clear()
	corrector.in_flight = false
	corrector.landed_step = -1
	corrector.origin = at
	corrector.initial_velocity = Vector3.ZERO


## Low-poly ball mesh (art-direction section 3: a sphere with 4 rings x 7 sides, one colour).
static func ball_mesh(color: Color) -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = BALL_RADIUS * 1.2
	b.add_sphere(Transform3D.IDENTITY, BALL_RADIUS, 4, 7, color)
	return b.commit()
