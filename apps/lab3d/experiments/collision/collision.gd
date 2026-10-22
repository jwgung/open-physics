## Guided collision lab (Phase 1 Task 4c; web preset "collision", "충돌하면 움직임은 어디로 갈까?"):
## two balls on a straight rail roll towards each other and collide. Conditions (the web's): each
## ball's mass (the web's mass input, 0.5-10 kg here), material (the web's four MATERIALS: the
## restitution e; the pair uses min(eA, eB), 0 below 1 m/s) and velocity (the web's purple velocity
## arrows: the yellow knob above each ball is dragged along the rail, 0.5 m/s grid, +-9 m/s like the
## web arrow's cap; the sliders take 0.1 m/s steps for the web's start 3.4 / -1.7 m/s). The balls'
## start positions are dragged along their half of the rail (0.5 m grid).
## Motion and every displayed number: CollisionModel (the web's collision preset on the TS world:
## explicit Euler, world.ts collision with push-out, the preset's damping 0.15/s and stop below
## 2 px/s, wall bounces with the ball's e), stepped in 64 bit. CollisionRailDriver poses the engine
## balls on it every step (method "kinematic_model"), so the panel has no engine measurement: the
## balls stand where the formula puts them. See docs/formula-correction.md (Task 4c).
extends ModelDrivenLab

const RADIUS_A := 0.4
const RADIUS_B := 0.5
const WALL := 7.0                       # bumper faces at x = +-WALL (the formula walls)
const START_A := -4.0
const START_B := 4.0
const LANE_A := Vector2(-6.5, -0.5)     # where each ball's centre may start (its half of the rail)
const LANE_B := Vector2(0.5, 6.5)
const KNOB_SIZE := 0.3
const KNOB_HALF := KNOB_SIZE * 0.5
const ARROW_SCALE := 0.4                # m of arrow per m/s (the knob sits v * ARROW_SCALE beside the ball)
const ARROW_STEP := 0.5                 # m/s grid of the knob (the web arrow has none; 0.5 like the projectile's)
const SPEED_MAX := 9.0                  # m/s (the web arrow: 96 px / 0.22 = 9.09 m/s)
const BALL_LAYER := 3                   # pickable; the balls touch nothing in the engine (mask 0)
const KNOB_LAYER := 2
const HIT_CLOSING_MAX := 8.0            # m/s closing speed that gives the full hit strength
const HIT_STRENGTH_MIN := 0.25          # weakest hit reaction
const HIT_CLOSING_MIN := 0.3            # m/s: a contact that closes more slowly than this gets no reaction
const IMPACT_STEPS := 30                # "충돌!" is shown this many steps after a hit (the web's 0.4 s flash)

var model := CollisionModel.new()
var ball_a: RigidBody3D
var ball_b: RigidBody3D
var knob_a: StaticBody3D
var knob_b: StaticBody3D
## Conditions (64-bit; velocities + = to the right).
var mass_a := 1.0
var mass_b := 2.0
var material_a := "rubber"
var material_b := "rubber"
var velocity_a := 3.4
var velocity_b := -1.7
var start_a := START_A
var start_b := START_B
## Test-only restitutions (>= 0 replaces the materials' e: the ideal elastic e = 1 of the checks).
var restitution_override := Vector2(-1.0, -1.0)
## Reactions shown (hits at or above HIT_CLOSING_MIN) since the screen opened (tests).
var hit_reactions := 0
var _floor: StaticBody3D
var _shown := Vector4.INF                # (ball A x, ball B x, knob A x, knob B x) the arrows were placed for


func _init() -> void:
	driver = CollisionRailDriver.new()
	props = CollisionProps.new()


func set_control(id: String, value: Variant) -> void:
	match id:
		"mass_a":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			mass_a = clamped
		"mass_b":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			mass_b = clamped
		"velocity_a":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			velocity_a = clamped
		"velocity_b":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			velocity_b = clamped
		"material_a", "material_b":
			if _find_option(id, str(value)).is_empty():
				push_warning("collision: unknown material %s" % value)
				return
			if id == "material_a":
				material_a = str(value)
			else:
				material_b = str(value)
		_:
			return
	_restart()


func control_value(id: String) -> Variant:
	match id:
		"mass_a":
			return mass_a
		"mass_b":
			return mass_b
		"material_a":
			return material_a
		"material_b":
			return material_b
		"velocity_a":
			return velocity_a
		"velocity_b":
			return velocity_b
	return super(id)


func run_action(id: String) -> void:
	match id:
		"release":
			release()
		"reset":
			reset_run()


## The model set to the conditions and the start positions, at rest at the start (not stepped).
func _load_model() -> void:
	model.mass_a = mass_a
	model.mass_b = mass_b
	model.radius_a = RADIUS_A
	model.radius_b = RADIUS_B
	model.restitution_a = float(_find_option("material_a", material_a).get("e", 1.0))
	model.restitution_b = float(_find_option("material_b", material_b).get("e", 1.0))
	if restitution_override.x >= 0.0:
		model.restitution_a = restitution_override.x
		model.restitution_b = restitution_override.y
	model.wall = WALL
	model.reset(start_a, start_b, velocity_a, velocity_b)


## Both balls back at their starts, waiting; the graph is cleared.
func reset_run() -> void:
	if ball_a == null:
		return
	_clear_run()
	_shown = Vector4.INF
	props.reset()
	_show_arrows()
	_update_status(true)


## (t, pA, pB).
func _graph_point() -> Vector3:
	return Vector3(_clock(), model.momentum_a(), model.momentum_b())


func _physics_process(_delta: float) -> void:
	if not released or holding != "":
		return
	var collisions := model.collisions
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	if model.collisions != collisions:
		_hit()
	if _graph_due(model.steps, _clock()):
		_add_graph_point()
	if status() != _last_status:
		_update_status()


## Seconds since the release (the model's fixed steps).
func _clock() -> float:
	return model.steps / float(Engine.physics_ticks_per_second)


## The model's balls just hit: visual reactions along the normal and the camera nudge (not for a
## contact slower than HIT_CLOSING_MIN).
func _hit() -> void:
	# The closing speed of this very step (a re-contact after a rebound is far slower than the first
	# hit); a tiny one only presses the balls together: no squash, dust or camera nudge.
	var closing := model.last_closing
	if closing < HIT_CLOSING_MIN:
		return
	hit_reactions += 1
	var strength := clampf(closing / HIT_CLOSING_MAX, HIT_STRENGTH_MIN, 1.0)
	props.hit(model.xa + RADIUS_A if model.xa < model.xb else model.xa - RADIUS_A, strength)
	impact.emit(strength)


## ready (waiting at the starts), moving, impact (just hit), collided (after the first hit), rest.
func status() -> String:
	if not released:
		return "ready"
	if model.last_collision_step >= 0 and model.steps - model.last_collision_step < IMPACT_STEPS:
		return "impact"
	if model.at_rest():
		return "rest"
	return "collided" if model.collided else "moving"


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)


func observations() -> Dictionary:
	var state_text: String = {
		"ready": "출발 전 · 화살표로 속도를 정해요",
		"moving": "굴러가는 중",
		"impact": "충돌! 충격량이 전달됐어요",
		"collided": "충돌 뒤 · 운동량을 비교해 보세요",
		"rest": "멈췄어요",
	}.get(status(), "")
	# Before the first collision "충돌 전" follows the balls (the start values while waiting).
	var ua := model.before[0] if model.collided else model.va
	var ub := model.before[1] if model.collided else model.vb
	var result := {
		"state": state_text,
		"before_a": ua,
		"before_b": ub,
		"p_before": model.momentum_of(ua, ub),
		"k_before": model.kinetic_of(ua, ub),
		"after_a": "—",
		"after_b": "—",
		"p_after": "—",
		"k_after": "—",
		"impulse_a": "—",
		"impulse_b": "—",
		"restitution": "—",
		}
	if model.collided:
		result.after_a = model.after[0]
		result.after_b = model.after[1]
		result.p_after = model.momentum_of(model.after[0], model.after[1])
		result.k_after = model.kinetic_of(model.after[0], model.after[1])
		result.impulse_a = model.impulse_a()
		result.impulse_b = model.impulse_b()
		result.restitution = model.restitution_used
	return result


## Momentum of A and B (kg m/s, + = to the right) over time since the release.
func graph_series() -> Dictionary:
	var pa := PackedVector2Array()
	var pb := PackedVector2Array()
	for s in _graph:
		pa.append(Vector2(s.x, s.y))
		pb.append(Vector2(s.x, s.z))
	return {"momentum_a": pa, "momentum_b": pb}


func follow_point() -> Vector3:
	if ball_a == null:
		return global_position
	return (ball_a.global_position + ball_b.global_position) * 0.5


# --- arrows -------------------------------------------------------------------------------------

## Velocity (m/s) of a knob `offset` m beside its ball: on the ARROW_STEP grid (counted in whole grid
## steps, 64-bit), within +-SPEED_MAX.
static func knob_velocity(offset: float) -> float:
	var cells := roundi(offset / (ARROW_STEP * ARROW_SCALE))
	return clampf(cells * ARROW_STEP, -SPEED_MAX, SPEED_MAX)


func _process(_delta: float) -> void:
	if ball_a == null:
		return
	props.spin(ball_a.global_position.x - start_a, ball_b.global_position.x - start_b)
	if released:
		props.show_momentum(ball_a.global_position, RADIUS_A, model.momentum_a(), ball_b.global_position, RADIUS_B, model.momentum_b())
		return
	_show_arrows()


## Waiting: the knobs and velocity arrows follow the balls (also dragged ones) and a dragged knob's
## grid value; only when something moved.
func _show_arrows() -> void:
	var va := velocity_a
	var vb := velocity_b
	if holding == "arrow_a":
		va = knob_velocity(knob_a.global_position.x - ball_a.global_position.x)
	elif holding == "arrow_b":
		vb = knob_velocity(knob_b.global_position.x - ball_b.global_position.x)
	var key := Vector4(ball_a.global_position.x, ball_b.global_position.x, knob_a.global_position.x, knob_b.global_position.x)
	if key == _shown and holding == "":
		return
	if holding != "arrow_a":
		knob_a.global_position = Vector3(ball_a.global_position.x + va * ARROW_SCALE, CollisionProps.arrow_height(RADIUS_A), 0.0)
	if holding != "arrow_b":
		knob_b.global_position = Vector3(ball_b.global_position.x + vb * ARROW_SCALE, CollisionProps.arrow_height(RADIUS_B), 0.0)
	props.show_velocity(ball_a.global_position, RADIUS_A, _arrow_length(va), ball_b.global_position, RADIUS_B, _arrow_length(vb))
	_shown = Vector4(ball_a.global_position.x, ball_b.global_position.x, knob_a.global_position.x, knob_b.global_position.x)


## Signed length of the velocity arrow of `velocity` (m): up to the knob's near face, never reversed
## (a slow ball's knob sits within KNOB_HALF of the ball: the shortest length, the arrow draws it at
## its minimum); 0 for a ball at rest.
static func _arrow_length(velocity: float) -> float:
	if velocity == 0.0:
		return 0.0
	return signf(velocity) * maxf(absf(velocity) * ARROW_SCALE - KNOB_HALF, CollisionProps.LENGTH_STEP)


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_floor = _add_floor(null, Vector3(30.0, 0.4, 22.0))
	ball_a = _make_ball("BallA", RADIUS_A, START_A)
	ball_b = _make_ball("BallB", RADIUS_B, START_B)
	knob_a = _make_knob("KnobA", KNOB_LAYER, KNOB_SIZE)
	knob_b = _make_knob("KnobB", KNOB_LAYER, KNOB_SIZE)
	_load_model()
	driver.history_steps = _history_steps()
	driver.attach(model, ball_a, ball_b)
	driver.reset()
	props.dress(self, ball_a, RADIUS_A, ball_b, RADIUS_B, knob_a, knob_b, WALL)


## A ball on the rail: a sphere the manipulator can pick (its own layer) that touches nothing.
func _make_ball(ball_name: String, radius: float, x: float) -> RigidBody3D:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var ball := _make_driven_body(ball_name, sphere, BALL_LAYER)
	ball.physics_material_override = _frictionless_material()
	ball.position = Vector3(x, radius, 0.0)
	add_child(ball)
	return ball


# --- manipulation -----------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	match id:
		"ball_a":
			return ball_a
		"ball_b":
			return ball_b
		"arrow_a":
			return null if released else knob_a
		"arrow_b":
			return null if released else knob_b
	return null


func manipulation_surface(surface_id: String) -> ManipSurface:
	var surface: ManipSurface
	match surface_id:
		"lane_a":
			surface = ManipSurface.new(Transform3D.IDENTITY, Vector2(LANE_A.x, 0.0), Vector2(LANE_A.y, 0.0))
		"lane_b":
			surface = ManipSurface.new(Transform3D.IDENTITY, Vector2(LANE_B.x, 0.0), Vector2(LANE_B.y, 0.0))
		"arrow_a", "arrow_b":
			var a := surface_id == "arrow_a"
			var ball := ball_a if a else ball_b
			var height := CollisionProps.arrow_height(RADIUS_A if a else RADIUS_B) - KNOB_HALF
			var reach := SPEED_MAX * ARROW_SCALE
			surface = ManipSurface.new(Transform3D(Basis(), Vector3(ball.global_position.x, height, 0.0)),
				Vector2(-reach, 0.0), Vector2(reach, 0.0), Vector2(ARROW_STEP * ARROW_SCALE, 0.0))
		_:
			return null
	surface.exclude = [_floor.get_rid(), ball_a.get_rid(), ball_b.get_rid(), knob_a.get_rid(), knob_b.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	match id:
		"ball_a":
			return props.juice_a
		"ball_b":
			return props.juice_b
	return null


## Picked up: a run stops and both balls wait at their starts.
func manipulation_started(id: String) -> void:
	if released:
		reset_run()
	holding = id


func manipulation_placed(id: String, transform: Transform3D) -> void:
	holding = ""
	_placed = true
	match id:
		"ball_a":
			start_a = snappedf(transform.origin.x, 0.001)
		"ball_b":
			start_b = snappedf(transform.origin.x, 0.001)
		"arrow_a":
			velocity_a = knob_velocity(transform.origin.x - ball_a.global_position.x)
		"arrow_b":
			velocity_b = knob_velocity(transform.origin.x - ball_b.global_position.x)
	_restart()


## The start positions once a ball was moved (kept across a screen rebuild; the velocities are
## controls and come back with them).
func _placement_transforms() -> Dictionary:
	return {"ball_a": Transform3D(Basis(), Vector3(start_a, RADIUS_A, 0.0)), "ball_b": Transform3D(Basis(), Vector3(start_b, RADIUS_B, 0.0))}
