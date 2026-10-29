## Guided orbit lab (Phase 1 Task 4d; web preset "orbit", "조금만 다르게 쏘면 궤도를 벗어날까?"): a small
## planet launched around a big star floating over a space stage on the island. Conditions: the
## launch speed and direction (0.1 m/s and 5 deg steps, also sliders) and the start radius (picture
## buttons and a slider, 0.5 m grid, 2-5 m). The child pulls the planet itself like a slingshot
## (2026-10-28 user decision, no handles): in the orbit plane, the launch is the reversed pull
## (direction on the 5 deg grid, speed = pull length / PULL_SCALE on the 0.1 m/s grid, 0-6 m/s) and
## letting go launches (the same run as "발사"). "원 궤도 속력" sets the circular speed sqrt(GM / r).
## Before the launch the panel and the dotted path show the web's prediction (OrbitChallenge: crash,
## orbit or escape, with the circular and escape speeds); "발사" launches. In a game round
## (answer_preview false) the path and the dashed circle appear only once the planet is launched:
## the path's colour would answer Dugi's question ("더 세게 쏘면 별을 떠날까?") before the run.
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
const PLANET_LAYER := 3
const PULL_SCALE := 0.6           # m of slingshot pull per m/s of launch speed
const ANGLE_STEP := 5.0           # deg: the direction slider's grid
const SPEED_STEP := 0.1           # m/s: the speed slider's grid
const SPEED_MAX := 6.0
## The velocity arrow: ARROW_OFFSET + speed * ARROW_SCALE m from the planet centre (the old knob's
## arrow, up to its near face).
const ARROW_OFFSET := 0.3
const ARROW_SCALE := 0.4

var model := OrbitModel.new()
var planet: RigidBody3D
## Conditions (64-bit): start radius (m), launch speed (m/s), direction (deg from outwards,
## counter-clockwise seen from above: 90 = the counter-clockwise tangent).
var start_radius := DEFAULT_RADIUS
var speed := DEFAULT_SPEED
var direction := DEFAULT_DIRECTION
## OrbitChallenge prediction of the launch (PhysicsLaws.orbit_analyze).
var prediction: Dictionary = {}
var crashes := 0
var _floor: StaticBody3D
var _analyzed_key := PackedFloat64Array()   # (radius, vx, vz) of _analyzed
var _analyzed: Dictionary = {}
## The slingshot pull's (direction, speed) while a finger holds the planet; INF when no pull (the
## screen sets it from the Manipulator's slingshot signal).
var _slingshot_preview := Vector2.INF


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
		"rearm":   # the slingshot's next shot after a run: the run waits again, the conditions stay
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


## The planet waits at its start with the launch arrow; the prediction is shown (not in a game
## round: it shows at the launch).
func reset_run() -> void:
	if planet == null:
		return
	_clear_run()
	if answer_preview:
		_show_prediction(start_radius, prediction)
	else:
		props.hide_prediction()
	props.reset()
	if game != null:
		game.run_reset()
	_show_waiting()
	_update_status(true)


func _notify_released() -> void:
	if not answer_preview:
		_show_prediction(start_radius, prediction)
	var v := launch_velocity(direction, speed)
	props.launched(Vector3(v[0], 0.0, v[1]))


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)


## The dashed circular-orbit guide at `radius` and the predicted path of `analysis`.
func _show_prediction(radius: float, analysis: Dictionary) -> void:
	props.set_guide(radius)
	props.set_path(analysis.path, analysis.outcome)


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
		props.update_cat(model.first_lap_time)
		var at := planet.global_position
		props.show_velocity(at, model.vx, model.vz, _arrow_length(model.speed()) if model.outcome == "" else 0.0)
		if model.outcome == "":
			props.show_gravity(at, Vector3(0.0, ORBIT_Y, 0.0), PhysicsLaws.point_gravity_acceleration(MU, model.radius(), 1.0))
		else:
			props.hide_gravity()
		return
	_show_waiting()


## Waiting: the velocity arrow of the launch; while a finger pulls the planet, the arrow of the
## pull's launch and the pull dots back to the pulled point (no path preview).
func _show_waiting() -> void:
	var at := planet.global_position
	props.place_cat(at, holding != "planet")
	var pulling := _slingshot_preview != Vector2.INF
	var shown_direction := _slingshot_preview.x if pulling else direction
	var shown_speed := _slingshot_preview.y if pulling else speed
	var v := launch_velocity(shown_direction, shown_speed)
	props.show_velocity(at, v[0], v[1], _arrow_length(shown_speed))
	var pull := Vector3.INF
	if pulling and shown_speed > 0.0:
		pull = at - Vector3(v[0], 0.0, v[1]) / shown_speed * (shown_speed * PULL_SCALE)
	props.show_pull(at, pull)


## The pull's (direction, speed) while a finger holds the planet (INF when the pull ends).
func set_slingshot_preview(value: Variant) -> void:
	_slingshot_preview = value if value is Vector2 else Vector2.INF
	if planet != null and not released:
		_show_waiting()


## The launch (direction deg, speed m/s) of a slingshot pull `pull` (orbit-plane coordinates: x, z;
## from the press to the finger): the reversed pull, its direction on the 5 deg grid (0..355,
## counter-clockwise from +x seen from above, as the "direction" slider), its length / PULL_SCALE on
## the 0.1 m/s grid within 0..SPEED_MAX.
static func pull_launch(pull: Vector2) -> Vector2:
	var launch := -pull
	var angle := fposmod(roundf(rad_to_deg(atan2(-launch.y, launch.x)) / ANGLE_STEP) * ANGLE_STEP, 360.0)
	var launch_speed := clampf(roundf(launch.length() / PULL_SCALE / SPEED_STEP) * SPEED_STEP, 0.0, SPEED_MAX)
	return Vector2(angle, launch_speed)


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
		"ready": "발사 전",
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
		"laps": absf(model.swept) / TAU,   # turns round the star since the launch (either way)
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
	props.dress(self, planet, PLANET_RADIUS, ORBIT_Y, STAR_RADIUS)
	_load_model()
	driver.history_steps = _history_steps()
	driver.bind(model, planet)
	driver.reset()
	game = OrbitGame.new(self)   # the piece game: the piece far out in space, the lap sparkles (visual only)
	(game as OrbitGame).plane_y = ORBIT_Y
	add_child(game)
	game.build()


## Length of the velocity arrow of launch speed `launch_speed` (m), the same before the launch and
## in flight; 0 for a planet at rest.
static func _arrow_length(launch_speed: float) -> float:
	if launch_speed == 0.0:
		return 0.0
	return ARROW_OFFSET + launch_speed * ARROW_SCALE


# --- manipulation -------------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	match id:
		"planet":
			return planet
	return null


func manipulation_surface(surface_id: String) -> ManipSurface:
	var surface: ManipSurface
	match surface_id:
		"radius_line":
			surface = ManipSurface.new(Transform3D(Basis(), Vector3(0.0, ORBIT_Y - PLANET_RADIUS, 0.0)),
				Vector2(RADIUS_MIN, 0.0), Vector2(RADIUS_MAX, 0.0), Vector2(_grid_step("planet"), 0.0))
		"pull":
			# The slingshot's pull: the level orbit plane through the planet's start.
			surface = ManipSurface.new(Transform3D(Basis(), Vector3(start_radius, ORBIT_Y, 0.0)), Vector2(-30.0, -30.0), Vector2(30.0, 30.0))
		_:
			return null
	surface.exclude = [_floor.get_rid(), planet.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	return props.juice if id == "planet" else null


## The slingshot (2026-10-28): the planet is pulled in the orbit plane; a release sets "direction"
## and "speed" (pull_launch) and runs "launch" ("발사"); the next shot after a run is "rearm" (the
## run waits, the radius and the launch stay). The readout says the speed only, in a child's words.
func slingshot_setup() -> Dictionary:
	var spec: Dictionary = definition.get("manipulation", {}).get("slingshot", {})
	if spec.is_empty() or manipulation_body(str(spec.get("object", ""))) == null:
		return {}
	return {"object": str(spec.object), "surface": manipulation_surface("pull"), "launch": launch_point,
		"controls": ["direction", "speed"], "value": pull_launch, "action": "launch", "rearm": "rearm",
		"readout": func(value: Vector2) -> String: return ExperimentScreen.kid_value("m/s", value.y, 1),
		"demo": [Vector2(0.0, 45.0), Vector2(-20.0, 70.0)]}


## The planet's start (the slingshot's launch point: a press there after a run pulls the next shot).
func launch_point() -> Vector3:
	return Vector3(start_radius, ORBIT_Y, 0.0)


## Picked up: a flight stops (a planet picked up in flight jumps under the finger onto its start line).
func manipulation_started(id: String) -> void:
	props.picked_up()
	super(id)


func manipulation_placed(id: String, transform: Transform3D) -> void:
	holding = ""
	match id:
		"planet":
			start_radius = radius_at(transform.origin.x)
	_restart()

