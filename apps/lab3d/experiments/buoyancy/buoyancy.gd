## Guided buoyancy lab (Phase 1 Task 4d; web preset "buoyancy", "물체는 언제 물에 뜰까?"): an upright drum
## in a water tank (water 1000 kg/m^3). The finger drags the drum up into the air or down into the
## water (0.05 m grid) and letting go releases it from rest there; "놓기" releases it again from the
## same place. Conditions: the drum's mass (the web's mass input; 5-150 kg) and its volume (100 L or
## 50 L: the same density floats at the same share of its height).
## Motion and every displayed number: BuoyancyModel (the web's BuoyancyRegionLaw and gravity, 4
## semi-implicit Euler substeps per fixed step, the web's floor rule). BodyModelDriver poses the
## engine drum on it every step (method "kinematic_model"): the panel has no engine measurement. The
## floating depth and the judgement (floats / stays / sinks) come from the densities.
## See docs/formula-correction.md (Task 4d).
extends ModelDrivenLab

const WATERLINE := 1.5
const FLOOR_Y := 0.2
const TANK_TOP := 2.1
const HOLD_ABOVE := 1.0           # m: the drum's bottom may be held this far above the water
const GRID_CELLS := 20.0          # grid cells per metre (0.05 m), counted in whole cells (64-bit)
const START_ABOVE := 0.3          # m: the drum's bottom above the water at the start
const WATER_DENSITY := 1000.0     # kg/m^3
const DRUM_LAYER := 3             # pickable; the drum touches nothing in the engine (mask 0)
const SETTLED_SPEED := 0.002      # m/s: slower than this (and where the formula puts it) = settled
const SETTLED_DEPTH := 0.002      # m from the floating depth
const SPLASH_SPEED := 0.5         # m/s: a slower entry into the water gets no splash
const FLOOR_HIT_SPEED := 0.3      # m/s: a slower floor contact gets no bump

var model := BuoyancyModel.new()
var driver := BodyModelDriver.new()
var props := BuoyancyProps.new()
var drum: RigidBody3D
## Conditions (64-bit).
var mass := 70.0
var volume_id := "big"
var start_bottom := WATERLINE + START_ABOVE   # height of the drum's bottom it is released from (m)
var splashes := 0
var _placed := false
var _floor: StaticBody3D
var _tank_floor: StaticBody3D
var _shape: CylinderShape3D


func set_control(id: String, value: Variant) -> void:
	match id:
		"mass":
			mass = _clamp_to_control(id, float(value))
		"volume":
			if _find_option(id, str(value)).is_empty():
				push_warning("buoyancy: unknown volume %s" % value)
				return
			volume_id = str(value)
			_resize()
		_:
			return
	_restart()


func control_value(id: String) -> Variant:
	match id:
		"mass":
			return mass
		"volume":
			return volume_id
	return super(id)


func run_action(id: String) -> void:
	match id:
		"release":
			release()
		"reset":
			start_bottom = WATERLINE + START_ABOVE
			_placed = false
			reset_run()


## Volume (m^3) and height (m) of the chosen drum; its radius from V = pi r^2 h.
func volume() -> float:
	return float(_find_option("volume", volume_id).get("volume", 0.1))


func drum_height() -> float:
	return float(_find_option("volume", volume_id).get("height", 0.5))


func drum_radius() -> float:
	return sqrt(volume() / (PI * drum_height()))


## The drum's collision shape and props for the chosen volume.
func _resize() -> void:
	if _shape == null:
		return
	_shape.radius = drum_radius()
	_shape.height = drum_height()
	props.set_drum(drum_radius(), drum_height())


func _load_model() -> void:
	model.mass = mass
	model.displaced_mass = WATER_DENSITY * volume()
	model.height = drum_height()
	model.waterline = WATERLINE
	model.floor_y = FLOOR_Y
	model.g = engine_g
	model.reset(start_bottom + drum_height() * 0.5, 0.0, 0.0)


func reset_run() -> void:
	if drum == null:
		return
	_clear_run()
	props.reset()
	_update_status(true)


func _reset_driver() -> void:
	driver.reset()


func _notify_released() -> void:
	props.released()


## (t, submerged depth).
func _graph_point() -> Vector2:
	return Vector2(model.time(), model.depth())


func _physics_process(_delta: float) -> void:
	if not released or holding != "":
		return
	driver.step(1.0 / float(Engine.physics_ticks_per_second))
	if model.entered and model.entry_speed >= SPLASH_SPEED:
		splashes += 1
		props.splash(model.entry_speed)
		impact.emit(clampf(model.entry_speed / 6.0, 0.15, 0.6))
	if model.hit_floor and model.hit_speed >= FLOOR_HIT_SPEED:
		props.hit_floor(model.hit_speed)
		impact.emit(clampf(model.hit_speed / 6.0, 0.15, 0.6))
	if _graph_due(model.steps, model.time()):
		_add_graph_point()
	if status() != _last_status:
		_update_status()


func _process(_delta: float) -> void:
	if drum == null:
		return
	if holding != "":
		props.hide_forces()
		return
	props.show_forces(drum.global_position, model.weight(), model.buoyant_force(), model.displaced_mass * model.g)


## ready (waiting), held, moving, floating (settled at the floating depth), staying (neutral, at
## rest under water), sunk (at rest on the tank floor).
func status() -> String:
	if holding != "":
		return "held"
	if not released:
		return "ready"
	if absf(model.vy) >= SETTLED_SPEED:
		return "moving"
	if model.bottom() <= FLOOR_Y + 1e-9 and model.net_force() <= 0.0:
		return "sunk"
	match model.judgement():
		"floats":
			if absf(model.depth() - model.floating_depth()) < SETTLED_DEPTH:
				return "floating"
		"neutral":
			if model.fraction() == 1.0:
				return "staying"
	return "moving"


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)


func observations() -> Dictionary:
	var state_text: String = {
		"ready": "놓기 전 · 통을 끌어 물에 넣어요",
		"held": "통을 옮기는 중",
		"moving": "움직이는 중",
		"floating": "떠 있어요 · 부력 = 무게",
		"staying": "물속에 그대로 머물러요",
		"sunk": "바닥에 가라앉았어요",
	}.get(status(), "")
	var judgement_text: String = {
		"floats": "뜸 (물보다 가벼움)",
		"neutral": "물속에 머묾 (물과 같음)",
		"sinks": "가라앉음 (물보다 무거움)",
	}.get(model.judgement(), "")
	return {
		"state": state_text,
		"judgement": judgement_text,
		"density": PhysicsLaws.density(model.mass, volume()),
		"floating_depth": model.floating_depth(),
		"depth": model.depth(),
		"buoyant": model.buoyant_force(),
		"weight": model.weight(),
		"net": model.net_force(),
		"speed": absf(model.vy),
	}


## Submerged depth over time since the release, and the floating depth of the formula (a level line).
func graph_series() -> Dictionary:
	var depth := PackedVector2Array()
	for p in _graph:
		depth.append(p)
	var level := model.floating_depth()
	return {"depth": depth, "floating": PackedVector2Array([Vector2(0.0, level), Vector2(graph_x_max(), level)])}


func _main_body() -> RigidBody3D:
	return drum


## Height of the drum's bottom for a centre at world y on the 0.05 m grid (whole cells, 64-bit),
## between the tank floor and HOLD_ABOVE over the water.
func bottom_at(centre_y: float) -> float:
	var cells := roundi((centre_y - drum_height() * 0.5) * GRID_CELLS)
	return clampf(cells / GRID_CELLS, FLOOR_Y, WATERLINE + HOLD_ABOVE)


# --- world --------------------------------------------------------------------------------------

func _build_world() -> void:
	_floor = _add_floor(null, Vector3(30.0, 0.4, 22.0))
	# The tank floor (the drum's shadow lands on it; the drum itself touches nothing).
	_tank_floor = StaticBody3D.new()
	_tank_floor.name = "TankFloor"
	_add_box_shape(_tank_floor, Vector3(BuoyancyProps.HALF_X * 2.0, FLOOR_Y, BuoyancyProps.HALF_Z * 2.0))
	_tank_floor.position = Vector3(0.0, FLOOR_Y * 0.5, 0.0)
	add_child(_tank_floor)
	_shape = CylinderShape3D.new()
	drum = _make_driven_body("Drum", _shape, DRUM_LAYER)
	drum.position = Vector3(0.0, start_bottom + 0.25, 0.0)
	add_child(drum)
	props.dress(self, drum, drum_radius(), drum_height(), FLOOR_Y, WATERLINE, TANK_TOP)
	_resize()
	_load_model()
	driver.history_steps = _history_steps()
	driver.bind(model, drum)
	driver.reset()


# --- manipulation -------------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return drum if id == "drum" else null


## A vertical line through the tank's middle: the drum's centre from resting on the tank floor to
## HOLD_ABOVE over the water.
func manipulation_surface(surface_id: String) -> ManipSurface:
	if surface_id != "tank":
		return null
	var half := drum_height() * 0.5
	var surface := UprightLineSurface.new(Vector3.ZERO, FLOOR_Y + half, WATERLINE + HOLD_ABOVE + half, 1.0 / GRID_CELLS, half)
	surface.exclude = [_floor.get_rid(), _tank_floor.get_rid(), drum.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	return props.juice if id == "drum" else null


func manipulation_started(id: String) -> void:
	released = false
	holding = id
	_update_status(true)


## Put down = let go: released from rest there (a restored placement only sets the height).
func manipulation_placed(_id: String, transform: Transform3D) -> void:
	holding = ""
	_placed = true
	start_bottom = bottom_at(transform.origin.y)
	if _batch > 0:
		_batch_dirty = true
		return
	release()


func manipulation_cancelled(_id: String) -> void:
	holding = ""
	reset_run()


func placements() -> Dictionary:
	if not _placed:
		return {}
	return {"drum": Transform3D(Basis(), Vector3(0.0, start_bottom + drum_height() * 0.5, 0.0))}
