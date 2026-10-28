## Guided spring lab (Phase 1 Task 4d; web preset "spring", "용수철은 에너지를 어떻게 돌려줄까?"): a ball
## threaded on a horizontal rod is pulled by a spring from a post (the web's AnchoredSpringLaw,
## k = 5 N/m). The finger pulls (or pushes) the ball along the rod (0.1 m grid) and letting go
## releases it from rest; "놓기" releases it again from the same pull. Conditions: the ball's mass
## (the web's mass input; 0.5-5 kg) and the damping (none, energy kept, or the web's b = 0.45 N s/m).
## Motion and every displayed number: SpringModel, the law's exact motion at each fixed step
## (period 2 pi sqrt(m / k), K + U = k x0^2 / 2 without damping). BodyModelDriver poses the engine
## ball on it every step (method "kinematic_model"): the panel has no engine measurement, the ball
## stands where the formula puts it. See docs/formula-correction.md (Task 4d).
## The ball looks as heavy as it is (2026-10-28, look_radius): its mesh grows about its centre; the
## body, its pick sphere (BALL_RADIUS) and the model do not change with the mass.
extends ModelDrivenLab

const ANCHOR_X := -4.5
const REST_LENGTH := 3.0
const ROD_Y := 1.0
const BALL_RADIUS := 0.35
const LOOK_MASS := 1.0            # kg: the ball that looks BALL_RADIUS round
const EXT_MIN := -1.5             # m: the most the ball may be pushed in / pulled out
const EXT_MAX := 2.5
const DEFAULT_PULL := 1.2
const END_X := ANCHOR_X + REST_LENGTH + EXT_MAX + 0.6   # the rod's end stand
const BALL_LAYER := 3             # pickable; the ball touches nothing in the engine (mask 0)
const REST_AMPLITUDE := 0.002     # m: a damped ball within this of the rest length, this slow, is at rest
const REST_SPEED := 0.005         # m/s
## The swing's readout until the ball has been back once (then the formula period, observations).
const SWING_WAIT := "한 번 왕복하면 보여요"

var model := SpringModel.new()
var ball: RigidBody3D
## Conditions (64-bit).
var mass := 1.0
var damping_id := "none"
var pull := DEFAULT_PULL          # extension the ball is released from (m)
var _floor: StaticBody3D


func _init() -> void:
	driver = BodyModelDriver.new()
	props = SpringProps.new()


func set_control(id: String, value: Variant) -> void:
	match id:
		"mass":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			mass = clamped
		"damping":
			if _find_option(id, str(value)).is_empty():
				push_warning("spring: unknown damping %s" % value)
				return
			damping_id = str(value)
		_:
			return
	_restart()


func control_value(id: String) -> Variant:
	match id:
		"mass":
			return mass
		"damping":
			return damping_id
	return super(id)


func run_action(id: String) -> void:
	match id:
		"release":
			release()
		"reset":
			pull = DEFAULT_PULL
			_placed = false
			reset_run()


## b of the damping option (N s / m).
func damping() -> float:
	return float(_find_option("damping", damping_id).get("b", 0.0))


## The model at rest at the pull (not stepped).
func _load_model() -> void:
	model.anchor_x = ANCHOR_X
	model.rest_length = REST_LENGTH
	model.mass = mass
	model.damping = damping()
	model.reset(pull, ROD_Y, 0.0)
	if props.juice != null:
		props.set_look(look_radius())


## Radius the ball looks (m): one stuff, the cube root of its mass against LOOK_MASS.
func look_radius() -> float:
	return BALL_RADIUS * MassLook.factor(mass, LOOK_MASS)


## The ball waits at its pull; the graph is cleared.
func reset_run() -> void:
	if ball == null:
		return
	_clear_run()
	props.reset()
	_show()
	_update_status(true)


func _physics_process(_delta: float) -> void:
	if not released or holding != "":
		return
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	if _graph_due(model.steps, model.time()):
		_add_graph_point()
	if status() != _last_status:
		_update_status()


func _process(_delta: float) -> void:
	if ball != null:
		_show()


## Coil, energy stack and force arrow for the ball where it is now (also a held ball).
func _show() -> void:
	props.stretch_coil(ball.global_position.x)
	if not released or holding != "":
		props.update_cat(ball.global_position, ball.global_position.x - (ANCHOR_X + REST_LENGTH), EXT_MAX)
	else:
		props.update_run(model.time(), model.period())
	if holding != "":
		props.show_energy(0.0, 0.0, 0.0)
		props.show_force(ball.global_position, 0.0)
		return
	props.show_energy(model.kinetic_energy(), model.spring_energy(), PhysicsLaws.spring_potential_energy(model.stiffness, model.x0))
	props.show_force(ball.global_position, model.force())


## (t, kinetic %, spring %) of the model now: the web's energy graph (shares of K + U; 0 / 0 when
## there is (almost) no energy, like the web's 0.0001 J cut).
func _graph_point() -> Vector3:
	var k := model.kinetic_energy()
	var u := model.spring_energy()
	var total := k + u
	if total <= 0.0001:
		return Vector3(model.time(), 0.0, 0.0)
	return Vector3(model.time(), k / total * 100.0, u / total * 100.0)


## ready (waiting at the pull), held, moving (oscillating), rest (at the rest length).
func status() -> String:
	if holding != "":
		return "held"
	if not released:
		return "ready"
	if absf(model.extension) < REST_AMPLITUDE and absf(model.velocity) < REST_SPEED \
			and (model.damping > 0.0 or model.x0 == 0.0):
		return "rest"
	return "moving"


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)


func _notify_released() -> void:
	props.released(pull)


func observations() -> Dictionary:
	var state_text: String = {
		"ready": "놓기 전 · 공을 끌어 당겨요",
		"held": "공을 당기는 중",
		"moving": "왕복하는 중",
		"rest": "제자리에 멈췄어요",
	}.get(status(), "")
	return {
		"state": state_text,
		"extension": model.extension,
		"pull": model.x0,   # the extension it was let go from (the amplitude without damping)
		"speed": absf(model.velocity),
		"force": model.force(),
		"acceleration": model.force() / model.mass,
		"kinetic": model.kinetic_energy(),
		"spring": model.spring_energy(),
		"total": model.total_energy(),
		"natural_period": model.natural_period(),
		"period": model.period(),
		# The mission's swing (2026-10-28): the period once the ball has been back once (the cat's cheer).
		"swing_period": model.period() if released and holding == "" and model.time() >= model.period() else SWING_WAIT,
	}


## Kinetic and spring energy shares (%) over time since the release.
func graph_series() -> Dictionary:
	var k := PackedVector2Array()
	var u := PackedVector2Array()
	for s in _graph:
		k.append(Vector2(s.x, s.y))
		u.append(Vector2(s.x, s.z))
	return {"kinetic": k, "spring": u}


func _main_body() -> RigidBody3D:
	return ball


## Extension (m) of a ball centre at world x on the rod's grid (manipulation snap, whole cells), within EXT_MIN..EXT_MAX.
func extension_at(world_x: float) -> float:
	return _snap_to_grid("ball", world_x - (ANCHOR_X + REST_LENGTH), EXT_MIN, EXT_MAX)


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_floor = _add_floor(null, Vector3(30.0, 0.4, 22.0))
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_RADIUS
	ball = _make_driven_body("Ball", sphere, BALL_LAYER)
	ball.position = Vector3(ANCHOR_X + REST_LENGTH + pull, ROD_Y, 0.0)
	add_child(ball)
	_load_model()
	driver.history_steps = _history_steps()
	driver.bind(model, ball)
	driver.reset()
	props.dress(self, ball, BALL_RADIUS, ANCHOR_X, END_X, ROD_Y, ANCHOR_X + REST_LENGTH)
	props.set_look(look_radius())


# --- manipulation -------------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return ball if id == "ball" else null


## The rod: a line along x at the ball's centre height (the frame sits one radius below it).
func manipulation_surface(surface_id: String) -> ManipSurface:
	if surface_id != "rod":
		return null
	var rest_x := ANCHOR_X + REST_LENGTH
	var surface := ManipSurface.new(Transform3D(Basis(), Vector3(0.0, ROD_Y - BALL_RADIUS, 0.0)),
		Vector2(rest_x + EXT_MIN, 0.0), Vector2(rest_x + EXT_MAX, 0.0), Vector2(_grid_step("ball"), 0.0))
	surface.exclude = [_floor.get_rid(), ball.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	return props.juice if id == "ball" else null


## Put down = let go: the ball is released from rest at the new pull (a restored placement only
## sets the pull).
func manipulation_placed(_id: String, transform: Transform3D) -> void:
	holding = ""
	_placed = true
	pull = extension_at(transform.origin.x)
	_release_or_defer()


func _placement_transforms() -> Dictionary:
	return {"ball": Transform3D(Basis(), Vector3(ANCHOR_X + REST_LENGTH + pull, ROD_Y, 0.0))}
