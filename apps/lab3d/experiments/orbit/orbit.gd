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
extends ModelDrivenLab

const ORBIT_Y := OrbitModel.DEFAULT_PLANE_Y
const MU := OrbitModel.DEFAULT_MU
const STAR_RADIUS := OrbitModel.STAR_RADIUS
const PLANET_RADIUS := OrbitModel.PLANET_RADIUS
const CRASH_RADIUS := OrbitModel.DEFAULT_CRASH_RADIUS
const FAR_RADIUS := OrbitModel.DEFAULT_FAR_RADIUS
const DEFAULT_RADIUS := 3.0       # the TS circular case: 3 m from the star at 3 m/s, counter-clockwise
const DEFAULT_SPEED := 3.0
const DEFAULT_DIRECTION := 90.0
const RADIUS_MIN := 2.0
const RADIUS_MAX := 5.0
const KNOB_SIZE := 0.3
const KNOB_LAYER := 2
const PLANET_LAYER := 3

var model := OrbitModel.new()
var planet: RigidBody3D
var knob: StaticBody3D
## Conditions (64-bit): start radius (m), launch speed (m/s), direction (deg from outwards,
## counter-clockwise seen from above: 90 = the counter-clockwise tangent).
var start_radius := DEFAULT_RADIUS
var speed := DEFAULT_SPEED
var direction := DEFAULT_DIRECTION
## OrbitChallenge prediction of the launch (PhysicsLaws.orbit_analyze).
var prediction: Dictionary = {}
var crashes := 0
var _floor: StaticBody3D
var _preview := PackedFloat64Array()   # (direction, speed, radius) the held preview shows
var _chosen := PackedFloat64Array([0.0, 0.0])   # (direction, speed) the waiting arrow shows (reused every frame)
var _surface: OrbitArrowSurface
var _analyzed_key := PackedFloat64Array()   # (radius, vx, vz) of _analyzed
var _analyzed: Dictionary = {}
var _surface_at := Vector3.INF         # planet position the cached surface was built for


func _init() -> void:
	driver = BodyModelDriver.new()
	props = OrbitProps.new()


func set_control(id: String, value: Variant) -> void:
	match id:
		"radius":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			start_radius = clamped
		"speed":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			speed = clamped
		"direction":
			if not is_finite(float(value)):
				return
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
			release()
		"circular":
			speed = PhysicsLaws.circular_orbit_speed(MU, start_radius, 1.0)
			direction = DEFAULT_DIRECTION
			reset_run()
		"reset":
			start_radius = DEFAULT_RADIUS
			speed = DEFAULT_SPEED
			direction = DEFAULT_DIRECTION
			reset_run()


## Launch velocity in the plane (x, z) for (direction deg, speed): the TS angle maths (deg * pi / 180).
static func launch_velocity(direction_deg: float, launch_speed: float) -> PackedFloat64Array:
	var a := direction_deg * PI / 180.0
	return PackedFloat64Array([launch_speed * cos(a), -launch_speed * sin(a)])


func _load_model() -> void:
	model.cx = 0.0
	model.cz = 0.0
	var v := launch_velocity(direction, speed)
	model.reset(start_radius, v[0], v[1])
	prediction = analyze(start_radius, v[0], v[1])


## The planet waits at its start with the launch arrow; the prediction is shown.
func reset_run() -> void:
	if planet == null:
		return
	_clear_run()
	props.set_guide(start_radius)
	props.set_path(prediction.path, prediction.outcome)
	props.reset()
	_preview.clear()
	_show_waiting()
	_update_status(true)


func _notify_released() -> void:
	props.launched()


func _physics_process(_delta: float) -> void:
	if not released or holding != "":
		return
	var was := model.outcome
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	if model.outcome == "crash" and was == "":
		crashes += 1
		props.crashed(Vector3(model.cx - model.x, 0.0, model.cz - model.z))
		impact.emit(0.6)
	if model.outcome == "" and _graph_due(model.steps, model.time()):
		_add_graph_point()
	if status() != _last_status:
		_update_status()


## (t, speed, circular speed, escape speed).
func _graph_point() -> Vector4:
	return Vector4(model.time(), model.speed(), model.circular_speed(), model.escape_speed())


func _process(_delta: float) -> void:
	if planet == null:
		return
	if released and holding == "":
		var at := planet.global_position
		props.show_velocity(at, model.vx, model.vz, _arrow_length(model.speed()) if model.outcome == "" else 0.0)
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
	var chosen := _chosen
	chosen[0] = direction
	chosen[1] = speed
	if holding == "arrow":
		OrbitArrowSurface.launch_into(_arrow_surface().to_plane(knob.global_position), chosen)
	else:
		var tip := PolarArrowSurface.tip_point(direction, speed, OrbitArrowSurface.OFFSET, OrbitArrowSurface.SCALE)
		knob.global_position = Vector3(at.x + tip.x, ORBIT_Y, at.z + tip.y)
	var v := launch_velocity(chosen[0], chosen[1])
	props.show_velocity(at, v[0], v[1], _arrow_length(chosen[1]))
	if holding == "":
		return
	var radius := radius_at(at.x)
	if _preview.size() == 3 and _preview[0] == chosen[0] and _preview[1] == chosen[1] and _preview[2] == radius:
		return
	_preview.resize(3)
	_preview[0] = chosen[0]
	_preview[1] = chosen[1]
	_preview[2] = radius
	var preview := analyze(radius, v[0], v[1])
	props.set_guide(radius)
	props.set_path(preview.path, preview.outcome)


## PhysicsLaws.orbit_analyze of a launch from (radius, 0) with (vx, vz), the last one remembered: the
## held preview, the put-down and the launch ask for the same launch one after another (SM-P200: up
## to 5 ms each). The result is shared (read it, never change it).
func analyze(radius: float, vx: float, vz: float) -> Dictionary:
	if _analyzed_key.size() == 3 and _analyzed_key[0] == radius and _analyzed_key[1] == vx and _analyzed_key[2] == vz:
		return _analyzed
	_analyzed_key = PackedFloat64Array([radius, vx, vz])
	_analyzed = PhysicsLaws.orbit_analyze(radius, 0.0, vx, vz, 0.0, 0.0, MU, CRASH_RADIUS)
	return _analyzed


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


func _main_body() -> RigidBody3D:
	return planet


## Start radius for a planet centre at world x on the planet's grid (manipulation snap, whole cells), RADIUS_MIN..RADIUS_MAX.
func radius_at(world_x: float) -> float:
	return _snap_to_grid("planet", world_x, RADIUS_MIN, RADIUS_MAX)


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_floor = _add_floor(null, Vector3(30.0, 0.4, 22.0))
	var sphere := SphereShape3D.new()
	sphere.radius = PLANET_RADIUS
	planet = _make_driven_body("Planet", sphere, PLANET_LAYER)
	planet.position = Vector3(start_radius, ORBIT_Y, 0.0)
	add_child(planet)
	knob = _make_knob("Knob", KNOB_LAYER, KNOB_SIZE)
	props.dress(self, planet, PLANET_RADIUS, knob, ORBIT_Y, STAR_RADIUS)
	_load_model()
	driver.history_steps = _history_steps()
	driver.bind(model, planet)
	driver.reset()


## The knob's surface through the planet (rebuilt only when the planet stands elsewhere).
func _arrow_surface() -> OrbitArrowSurface:
	if _surface == null or _surface_at != planet.global_position:
		_surface_at = planet.global_position
		_surface = OrbitArrowSurface.new(_surface_at, KNOB_SIZE * 0.5)
	return _surface


## Length of the velocity arrow of launch speed `launch_speed` (m): from the planet centre up to
## the knob's near face (the knob sits OFFSET + speed * SCALE out), the same before the launch and
## in flight so the arrow does not jump when the knob goes; 0 for a planet at rest.
static func _arrow_length(launch_speed: float) -> float:
	if launch_speed == 0.0:
		return 0.0
	return OrbitArrowSurface.OFFSET + launch_speed * OrbitArrowSurface.SCALE - KNOB_SIZE * 0.5


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
				Vector2(RADIUS_MIN, 0.0), Vector2(RADIUS_MAX, 0.0), Vector2(_grid_step("planet"), 0.0))
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
	props.picked_up()
	super(id)


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

