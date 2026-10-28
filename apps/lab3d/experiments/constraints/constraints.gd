## Guided string / rod pendulum lab (Phase 1 Task 4e; web preset "constraints", "줄과 막대는 움직임을
## 어떻게 제한할까?"): a bob on a string and a bob on a rod of the same length hang side by side (the
## web's two pendulums: string 0.62 rad with damping 0.06 /s, rod -0.5 rad with 0.03 /s, 1 kg bobs).
## The finger drags a bob along its circle (5 deg grid, +-75 deg; the anchor-bob distance stays L)
## and letting go releases both from rest at their angles; "놓기" releases them again from the same
## angles. Conditions: gravity (the web's four), the length L of both (the web's is about 4.4 m on a
## large screen; 1-3.5 m here) and the damping (the web's, or none).
## Motion and every displayed number: PendulumLabModel per bob (the web PendulumModel's equation,
## RK4 at the fixed step; tension m g cos + m v^2 / L; the period measured on the model's zero
## crossings) and BodyModelGroupDriver poses the engine bobs on it every step (method
## "kinematic_model"): the panel has no engine measurement, the bobs stand where the formula puts
## them. See docs/formula-correction.md (Task 4e).
extends ModelDrivenLab

const ANCHOR_Y := 4.4
const ANCHOR_X := 1.9            # string at -x, rod at +x
const ANCHOR_Z := 0.35           # string at -z, rod at +z: the bobs pass each other without touching
const BOB_RADIUS := 0.33
const BOB_MASS := 1.0            # kg, the web's bobs
const SIGN_AT := Vector3(-3.5, 0.0, -1.8)   # the gravity's signpost (PlanetSign), behind the string's side
const MAX_DEG := 75.0            # drag range either side of straight down (a string stays taut below 90 deg)
const BOB_LAYER := 3             # pickable; the bobs touch nothing in the engine (mask 0)
const IDS: Array[String] = ["rope", "rod"]
const SURFACES: Array[String] = ["rope_arc", "rod_arc"]
## The web preset's release angles (rad): string, rod.
const WEB_ANGLES: Array[float] = [0.62, -0.5]

var models: Array[PendulumLabModel] = [PendulumLabModel.new(), PendulumLabModel.new()]
var bobs: Array[RigidBody3D] = []
## Conditions (64-bit).
var g := 9.81
var gravity_id := "earth"
## The signpost showing which world the gravity is (2026-10-28).
var planet_sign: PlanetSign
var length := 2.0
var damping_id := "web"
## Release angles (rad) of the string and the rod bob.
var start_angles: Array[float] = WEB_ANGLES.duplicate()
var _floor: StaticBody3D


func _init() -> void:
	driver = BodyModelGroupDriver.new()
	props = ConstraintsProps.new()


func set_control(id: String, value: Variant) -> void:
	match id:
		"gravity":
			var option := _find_option(id, str(value))
			if option.is_empty():
				push_warning("constraints: unknown gravity %s" % value)
				return
			gravity_id = str(value)
			g = float(option.g)
			planet_sign.show_planet(gravity_id)
		"length":
			var clamped := _clamp_to_control(id, float(value))
			if is_nan(clamped):
				return
			length = clamped
		"damping":
			if _find_option(id, str(value)).is_empty():
				push_warning("constraints: unknown damping %s" % value)
				return
			damping_id = str(value)
		_:
			return
	_restart()


func control_value(id: String) -> Variant:
	match id:
		"gravity":
			return gravity_id
		"length":
			return length
		"damping":
			return damping_id
	return super(id)


func run_action(id: String) -> void:
	match id:
		"release":
			release()
		"reset":
			start_angles = WEB_ANGLES.duplicate()
			_placed = false
			reset_run()


## Damping (1/s) of pendulum `i` (0 string, 1 rod) for the damping option.
func damping(i: int) -> float:
	return float(_find_option("damping", damping_id).get("rope_b" if i == 0 else "rod_b", 0.0))


func anchor(i: int) -> Vector3:
	return Vector3(-ANCHOR_X if i == 0 else ANCHOR_X, ANCHOR_Y, -ANCHOR_Z if i == 0 else ANCHOR_Z)


## Both models at rest at their release angles (not stepped).
func _load_model() -> void:
	for i in 2:
		_load_one(i, start_angles[i])


func _load_one(i: int, angle: float) -> void:
	var m := models[i]
	var a := anchor(i)
	m.anchor_x = a.x
	m.anchor_y = a.y
	m.anchor_z = a.z
	m.length = length
	m.g = g
	m.damping = damping(i)
	m.mass = BOB_MASS
	m.reset(angle)


## The bobs wait at their release angles; the graph is cleared.
func reset_run() -> void:
	if bobs.is_empty():
		return
	_clear_run()
	props.reset()
	props.place_cat(models[0].position())
	props.show_paths(length, MAX_DEG)
	_show()
	_update_status(true)


func _physics_process(_delta: float) -> void:
	if not released or holding != "":
		return
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	if _graph_due(models[0].steps, models[0].time()):
		_add_graph_point()
	if status() != _last_status:
		_update_status()


func _process(_delta: float) -> void:
	if bobs.is_empty():
		return
	var held := IDS.find(holding)
	if held >= 0:
		# The held bob's model follows the finger (at rest at the bob's angle): the panel shows it.
		_load_one(held, angle_at(held, bobs[held].global_position))
	_show()
	if released:
		props.update_cat(models[0].half_swing_period)   # with the stamp (half a swing), not a full measured period


## The string and the rod from their anchors to the bobs where they are now.
func _show() -> void:
	for i in 2:
		props.stretch_link(i, bobs[i].global_position)


## (t, string angle deg, rod angle deg) of the models now: the web's graph "두 진자의 각도".
func _graph_point() -> Vector3:
	return Vector3(models[0].time(), rad_to_deg(models[0].angle), rad_to_deg(models[1].angle))


## ready (waiting at the angles), held, swinging, or weightless (released without gravity: the bobs
## stay where they were let go).
func status() -> String:
	if holding != "":
		return "held"
	if not released:
		return "ready"
	return "swinging" if g > 0.0 else "weightless"


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)


func _notify_released() -> void:
	props.released(models[0].position())


func observations() -> Dictionary:
	var state_text: String = {
		"ready": "놓기 전 · 추를 끌어 각도를 정해요",
		"held": "추를 옮기는 중 · 고정점에서 거리는 그대로예요",
		"swinging": "흔들리는 중",
		"weightless": "무중력 · 놓은 자리에 그대로 있어요",
	}.get(status(), "")
	var values := {
		"state": state_text,
		"length": length,
		"small_period": models[0].small_angle_period() if g > 0.0 else "무중력에서는 흔들리지 않아요",
	}
	for i in 2:
		var m := models[i]
		var id := IDS[i]
		values[id + "_distance"] = m.distance()
		values[id + "_angle"] = rad_to_deg(m.angle)
		values[id + "_period"] = m.period if m.period > 0.0 else "한 번 왕복하면 보여요"
		values[id + "_tension"] = m.tension()
	# The mission's period (2026-10-28): known at the first turning point on the other side.
	values["rope_half_swing"] = models[0].half_swing_period if models[0].half_swing_period > 0.0 else "한 번 왕복하면 보여요"
	return values


## The two angles (deg) over time since the release.
func graph_series() -> Dictionary:
	var rope := PackedVector2Array()
	var rod := PackedVector2Array()
	for s in _graph:
		rope.append(Vector2(s.x, s.y))
		rod.append(Vector2(s.x, s.z))
	return {"rope": rope, "rod": rod}


func _main_body() -> RigidBody3D:
	return bobs[0] if not bobs.is_empty() else null


## Angle (rad, from straight down, + towards +x) of a bob centre at `world` around anchor `i`, on
## the drag grid (whole steps of the rule's degrees) within +-MAX_DEG.
func angle_at(i: int, world: Vector3) -> float:
	var d := world - anchor(i)
	var deg := rad_to_deg(atan2(d.x, -d.y))
	deg = PendulumArcSurface.snap_deg(deg, _grid_step(IDS[i]))
	return deg_to_rad(clampf(deg, -MAX_DEG, MAX_DEG))


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_floor = _add_floor(null, Vector3(30.0, 0.4, 22.0))
	var colors: Array[Color] = [ArtPalette.BLUE, ArtPalette.ORANGE]
	var anchors: Array[Vector3] = [anchor(0), anchor(1)]
	_load_model()
	var history := _history_steps()
	for i in 2:
		var sphere := SphereShape3D.new()
		sphere.radius = BOB_RADIUS
		var bob := _make_driven_body("StringBob" if i == 0 else "RodBob", sphere, BOB_LAYER)
		bob.position = models[i].position()
		add_child(bob)
		bobs.append(bob)
		(driver as BodyModelGroupDriver).add(models[i], bob, history)
	driver.reset()
	props.dress(self, bobs, anchors, colors, BOB_RADIUS)
	props.show_paths(length, MAX_DEG)
	planet_sign = PlanetSign.new()
	planet_sign.position = SIGN_AT
	add_child(planet_sign)


# --- manipulation -------------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	var i := IDS.find(id)
	return bobs[i] if i >= 0 and not bobs.is_empty() else null


## The bob's circle around its anchor (radius L) in its swing plane.
func manipulation_surface(surface_id: String) -> ManipSurface:
	var i := SURFACES.find(surface_id)
	if i < 0:
		return null
	var surface := PendulumArcSurface.new(anchor(i), length, _grid_step(IDS[i]), MAX_DEG, BOB_RADIUS)
	surface.exclude = [_floor.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	var i := IDS.find(id)
	return props.juices[i] if i >= 0 and i < props.juices.size() else null


## Picked up: the run stops; the other bob waits at its release angle, the graph starts again.
func manipulation_started(id: String) -> void:
	super(id)
	var held := IDS.find(id)
	for i in 2:
		if i != held:
			_load_one(i, start_angles[i])
			(driver as BodyModelGroupDriver).members[i].reset()
	_graph.clear()
	_graph_revision += 1
	props.place_cat(models[0].position(), held != 0)   # a finger holds the string bob: the cat stands by


## Put down = let go: both bobs are released from rest at their angles (a restored placement only
## sets the angle).
func manipulation_placed(id: String, transform: Transform3D) -> void:
	var i := IDS.find(id)
	holding = ""
	if i < 0:
		return
	_placed = true
	start_angles[i] = angle_at(i, transform.origin)
	_release_or_defer()


func _placement_transforms() -> Dictionary:
	var result := {}
	for i in 2:
		var offset := PhysicsLaws.pendulum_offset(length, start_angles[i])
		result[IDS[i]] = Transform3D(Basis(), anchor(i) + Vector3(offset[0], -offset[1], 0.0))
	return result
