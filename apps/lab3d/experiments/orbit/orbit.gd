## Guided orbit lab (Phase 1 Task 4d; web preset "orbit", "조금만 다르게 쏘면 궤도를 벗어날까?"): a small
## planet launched around a big star floating over a space stage on the island. Conditions: the
## launch speed and direction (the web's purple arrow: the yellow knob is dragged in the orbit plane,
## 0.1 m/s and 5 deg steps, also sliders) and the start radius (the planet is dragged along the line
## east of the star, 0.5 m grid, 2-5 m). "원 궤도 속력" sets the circular speed sqrt(GM / r).
## Before the launch the panel and the dotted path show the web's prediction (OrbitChallenge: crash,
## orbit or escape, with the circular and escape speeds); "발사" launches.
## Motion and every displayed number: OrbitModel (the web's PointGravityField, GM = 27 m^3/s^2,
## 8 velocity Verlet substeps per fixed step). BodyModelDriver poses the engine planet on it every
## step (method "kinematic_model"): the panel has no engine measurement.
## See docs/formula-correction.md (Task 4d).
extends Experiment

const ORBIT_Y := 2.0
const MU := 27.0                  # G M (m^3/s^2): 3 m/s circular speed at 3 m
const STAR_RADIUS := 0.9
const PLANET_RADIUS := 0.3
const CRASH_RADIUS := STAR_RADIUS + PLANET_RADIUS
const FAR_RADIUS := 12.0
const RADIUS_MIN := 2.0
const RADIUS_MAX := 5.0
const RADIUS_CELLS := 2.0         # grid cells per metre (0.5 m)
const KNOB_SIZE := 0.3
const KNOB_LAYER := 2
const PLANET_LAYER := 3
const GRAPH_EVERY_STEPS := 6

var model := OrbitModel.new()
var driver := BodyModelDriver.new()
var props := OrbitProps.new()
var planet: RigidBody3D
var knob: StaticBody3D
## Conditions (64-bit): start radius (m), launch speed (m/s), direction (deg from outwards,
## counter-clockwise seen from above: 90 = the counter-clockwise tangent).
var start_radius := 3.0
var speed := 3.0
var direction := 90.0
## OrbitChallenge prediction of the launch (PhysicsLaws.orbit_analyze).
var prediction: Dictionary = {}
var released := false
var holding := ""
var reset_count := 0
var crashes := 0
var _batch := 0
var _batch_dirty := false
var _floor: StaticBody3D
var _graph: Array[Vector4] = []   # (t, speed, circular speed, escape speed)
var _graph_revision := 0
var _preview := PackedFloat64Array()   # (direction, speed, radius) the held preview shows


func _ready() -> void:
	_build_world()
	begin_batch()
	for control in definition.get("controls", []):
		set_control(control.id, control.default)
	end_batch()


func begin_batch() -> void:
	_batch += 1


func end_batch() -> void:
	_batch = maxi(0, _batch - 1)
	if _batch == 0 and _batch_dirty:
		_batch_dirty = false
		reset_run()


func _restart() -> void:
	if _batch > 0:
		_batch_dirty = true
	else:
		reset_run()


func set_control(id: String, value: Variant) -> void:
	match id:
		"radius":
			start_radius = _clamp_to_control(id, float(value))
		"speed":
			speed = _clamp_to_control(id, float(value))
		"direction":
			direction = fposmod(float(value), 360.0)
		_:
			return
	_restart()


func control_value(id: String) -> Variant:
	match id:
		"radius":
			return start_radius
		"speed":
			return speed
		"direction":
			return direction
	return super(id)


func run_action(id: String) -> void:
	match id:
		"launch":
			launch()
		"circular":
			speed = PhysicsLaws.circular_orbit_speed(MU, start_radius, 1.0)
			direction = 90.0
			reset_run()
		"reset":
			start_radius = 3.0
			speed = 3.0
			direction = 90.0
			reset_run()


## Launch velocity in the plane (x, z) for (direction deg, speed): the TS angle maths (deg * pi / 180).
static func launch_velocity(direction_deg: float, launch_speed: float) -> PackedFloat64Array:
	var a := direction_deg * PI / 180.0
	return PackedFloat64Array([launch_speed * cos(a), -launch_speed * sin(a)])


func _load_model() -> void:
	model.cx = 0.0
	model.cz = 0.0
	model.plane_y = ORBIT_Y
	model.mu = MU
	model.crash_radius = CRASH_RADIUS
	model.far_radius = FAR_RADIUS
	var v := launch_velocity(direction, speed)
	model.reset(start_radius, v[0], v[1])
	prediction = PhysicsLaws.orbit_analyze(start_radius, 0.0, v[0], v[1], 0.0, 0.0, MU, CRASH_RADIUS)


## The planet waits at its start with the launch arrow; the prediction is shown.
func reset_run() -> void:
	if planet == null:
		return
	reset_count += 1
	released = false
	_load_model()
	driver.reset()
	_graph.clear()
	_graph_revision += 1
	props.set_guide(start_radius)
	props.set_path(prediction.path, prediction.outcome)
	props.reset()
	_preview = PackedFloat64Array()
	_show_waiting()
	_update_status(true)


func launch() -> void:
	if released:
		reset_run()
	else:
		_load_model()
		driver.reset()
	released = true
	_graph.clear()
	_graph.append(_graph_point())
	_graph_revision += 1
	props.launched()
	_update_status(true)


func _physics_process(_delta: float) -> void:
	if not released or holding != "":
		return
	var was := model.outcome
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	if model.outcome == "crash" and was == "":
		crashes += 1
		props.crashed(Vector3(-model.x, 0.0, -model.z))
		impact.emit(0.6)
	if model.steps % GRAPH_EVERY_STEPS == 0 and model.time() <= graph_x_max() + 1e-6 and model.outcome == "":
		_graph.append(_graph_point())
		_graph_revision += 1
	if status() != _last_status:
		_update_status()


func _graph_point() -> Vector4:
	return Vector4(model.time(), model.speed(), model.circular_speed(), model.escape_speed())


func _process(_delta: float) -> void:
	if planet == null:
		return
	if released and holding == "":
		var at := planet.global_position
		props.show_velocity(at, model.vx, model.vz, model.speed() * OrbitArrowSurface.SCALE if model.outcome == "" else 0.0)
		if model.outcome == "":
			props.show_gravity(at, Vector3(0.0, ORBIT_Y, 0.0), PhysicsLaws.point_gravity_acceleration(MU, model.radius(), 1.0))
		else:
			props.hide_gravity()
		return
	_show_waiting()


## Waiting: the knob at the arrow tip of the launch (or where a finger holds it); while a finger holds
## the knob or the planet, the snapped launch from where the planet is now is previewed (arrow and
## the predicted path).
func _show_waiting() -> void:
	var at := planet.global_position
	var chosen := PackedFloat64Array([direction, speed])
	if holding == "arrow":
		chosen = OrbitArrowSurface.launch_of(_arrow_surface().to_plane(knob.global_position))
	else:
		var tip := PolarArrowSurface.tip_point(direction, speed, OrbitArrowSurface.OFFSET, OrbitArrowSurface.SCALE)
		knob.global_position = Vector3(at.x + tip.x, ORBIT_Y, at.z + tip.y)
	var v := launch_velocity(chosen[0], chosen[1])
	props.show_velocity(at, v[0], v[1], OrbitArrowSurface.OFFSET + chosen[1] * OrbitArrowSurface.SCALE - KNOB_SIZE * 0.5)
	if holding == "":
		return
	var key := PackedFloat64Array([chosen[0], chosen[1], radius_at(at.x)])
	if key != _preview:
		_preview = key
		var preview := PhysicsLaws.orbit_analyze(key[2], 0.0, v[0], v[1], 0.0, 0.0, MU, CRASH_RADIUS)
		props.set_guide(key[2])
		props.set_path(preview.path, preview.outcome)


## ready (waiting), held, orbiting (bound, flying), leaving (unbound, flying), crash, far.
func status() -> String:
	if holding != "":
		return "held"
	if not released:
		return "ready"
	if model.outcome != "":
		return model.outcome
	return "orbiting" if model.specific_energy() < 0.0 else "leaving"


func observations() -> Dictionary:
	var state_text: String = {
		"ready": "발사 전 · 예상 길을 먼저 봐요",
		"held": "바꾸는 중",
		"orbiting": "별 둘레를 도는 중",
		"leaving": "별에서 멀어지는 중",
		"crash": "별에 부딪혔어요",
		"far": "멀리 날아가 버렸어요",
	}.get(status(), "")
	var predicted_text: String = {"crash": "충돌", "orbit": "공전", "escape": "이탈"}.get(prediction.get("outcome", ""), "")
	return {
		"state": state_text,
		"predicted": predicted_text,
		"launch_speed": prediction.speed,
		"circular_speed": prediction.circular_speed,
		"escape_speed": prediction.escape_speed,
		"radius": model.radius(),
		"period": model.circular_period(),
		"speed": model.speed(),
		"lap": model.first_lap_time if model.first_lap_time >= 0.0 else "—",
	}


## Speed now and the circular / escape speeds at the radius now, over time since the launch.
func graph_series() -> Dictionary:
	var v := PackedVector2Array()
	var c := PackedVector2Array()
	var e := PackedVector2Array()
	for p in _graph:
		v.append(Vector2(p.x, p.y))
		c.append(Vector2(p.x, p.z))
		e.append(Vector2(p.x, p.w))
	return {"speed": v, "circular": c, "escape": e}


func graph_revision() -> int:
	return _graph_revision


func graph_x_max() -> float:
	return float(definition.get("graph", {}).get("x", {}).get("max", 20.0))


func follow_point() -> Vector3:
	return planet.global_position if planet != null else global_position


## Start radius for a planet centre at world x on the 0.5 m grid (whole cells), RADIUS_MIN..RADIUS_MAX.
static func radius_at(world_x: float) -> float:
	return clampf(roundi(world_x * RADIUS_CELLS) / RADIUS_CELLS, RADIUS_MIN, RADIUS_MAX)


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_floor = _add_floor(null, Vector3(30.0, 0.4, 22.0))
	planet = RigidBody3D.new()
	planet.name = "Planet"
	_setup_free_body(planet)
	planet.gravity_scale = 0.0
	planet.collision_layer = 1 << (PLANET_LAYER - 1)
	planet.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PLANET_RADIUS
	shape.shape = sphere
	planet.add_child(shape)
	planet.position = Vector3(start_radius, ORBIT_Y, 0.0)
	add_child(planet)
	knob = _make_knob("Knob", KNOB_LAYER, KNOB_SIZE)
	props.dress(self, planet, PLANET_RADIUS, knob, ORBIT_Y, STAR_RADIUS)
	_load_model()
	driver.history_steps = int(graph_x_max() * Engine.physics_ticks_per_second) + 2
	driver.bind(model, planet)
	driver.reset()


func _arrow_surface() -> OrbitArrowSurface:
	return OrbitArrowSurface.new(planet.global_position, KNOB_SIZE * 0.5)


# --- manipulation -------------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	match id:
		"planet":
			return planet
		"arrow":
			return null if released else knob
	return null


func manipulation_surface(surface_id: String) -> ManipSurface:
	var surface: ManipSurface
	match surface_id:
		"radius_line":
			surface = ManipSurface.new(Transform3D(Basis(), Vector3(0.0, ORBIT_Y - PLANET_RADIUS, 0.0)),
				Vector2(RADIUS_MIN, 0.0), Vector2(RADIUS_MAX, 0.0), Vector2(1.0 / RADIUS_CELLS, 0.0))
		"arrow":
			surface = _arrow_surface()
		_:
			return null
	surface.exclude = [_floor.get_rid(), planet.get_rid(), knob.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	return props.juice if id == "planet" else null


## Picked up: a flight stops (a planet picked up in flight jumps under the finger onto its start line).
func manipulation_started(id: String) -> void:
	released = false
	props.hide_gravity()
	holding = id
	_update_status(true)


func manipulation_placed(id: String, transform: Transform3D) -> void:
	holding = ""
	match id:
		"planet":
			start_radius = radius_at(transform.origin.x)
		"arrow":
			var chosen := OrbitArrowSurface.launch_of(_arrow_surface().to_plane(transform.origin))
			direction = chosen[0]
			speed = chosen[1]
	_restart()


func manipulation_cancelled(_id: String) -> void:
	holding = ""
	reset_run()
