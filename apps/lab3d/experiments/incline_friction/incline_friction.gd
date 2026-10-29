## Guided incline friction experiment (port of spike S3 with the web app's surface materials).
## 1 kg box on an adjustable incline, g = 9.81. Box and incline share one material whose static /
## kinetic coefficients come from the content JSON (TS MATERIALS: mu_s = friction + 0.18,
## mu_k = friction; checked by tools/incline-vectors.test.ts).
## Every displayed number comes from PhysicsLaws (formula port); the motion is Jolt + the formula
## correction layer (friction_corrector.gd), and only "이동 거리 (시뮬레이션)" / the graph's
## measured points are engine measurements.
## Task 2b: the box can be dragged along the incline to a new start position (manipulation rule
## "box" on surface "incline", content JSON). The run length (start to the incline's lower end)
## then caps the displayed distance and the formula curve.
extends Experiment

const G := 9.81
const MASS := 1.0
const BOX := 0.4
const INCLINE_LENGTH := 8.0
const START_X := 3.5          # default release point along the incline (pivot local x), uphill end is +x
const MIN_RUN := 1.0          # shortest run (m) the box can be placed at (start to the lower end)
const PIVOT_HEIGHT := 3.2
const STAND_HEIGHT := PIVOT_HEIGHT - 0.15   # full height of the support post mesh
const GRAPH_EVERY_STEPS := 6  # graph sample every 6 fixed steps (10 Hz)
const FLOOR_DAMP := 4.0       # 1/s braking of a box lying on the floor after leaving the incline
const FALL_LIMIT_Y := -3.0    # below this the box is stopped (it left the floor)


var angle_deg := 20.0
var material_id := "wood"
var mu_s := 0.4
var mu_k := 0.22
var released := false
## Release point along the incline (pivot local x of the box centre); set by dragging the box.
var start_x := START_X
var box: InclineBox
var corrector := InclineFrictionCorrector.new()
## Grass island meshes, shadows and the box reactions (visual only, never the bodies).
var props := InclineProps.new()
var _stand: MeshInstance3D
var _post: MeshInstance3D

var _pivot: Node3D
var _incline_body: StaticBody3D
var _mark: MeshInstance3D
var _placed := false          # the user dragged the box to start_x (kept across a screen rebuild)
var _graph_points := PackedVector2Array()
var _graph_revision := 0


func _ready() -> void:
	_build_world()
	for control in definition.get("controls", []):
		set_control(control.id, control.default)


func set_control(id: String, value: Variant) -> void:
	match id:
		"angle":
			set_angle(float(value))
		"material":
			set_material(str(value))


func control_value(id: String) -> Variant:
	match id:
		"angle":
			return angle_deg
		"material":
			return material_id
	return super(id)


func run_action(id: String) -> void:
	match id:
		"release":
			release()
		"reset":
			reset_box()


func set_angle(degrees: float) -> void:
	angle_deg = clampf(degrees, 0.0, 45.0)
	_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(angle_deg))
	props.angle_changed(angle_deg)
	_fit_stand()
	reset_box()


## Selects a material option from the "material" control (unknown ids are ignored).
func set_material(option_id: String) -> void:
	var option := _find_option("material", option_id)
	if option.is_empty():
		push_warning("incline: unknown material %s" % option_id)
		return
	set_coefficients(float(option.mu_s), float(option.mu_k))
	material_id = option_id
	props.set_surface(material_id)
	reset_box()


func set_coefficients(static_mu: float, kinetic_mu: float) -> void:
	mu_s = static_mu
	mu_k = kinetic_mu
	corrector.mu_s = mu_s
	corrector.mu_k = mu_k
	_graph_revision += 1


## Distance from the release point to the incline's lower end (the box leaves the incline after it).
func run_length() -> float:
	return start_x + INCLINE_LENGTH * 0.5


## Moves the release point (run length in m, kept inside the incline) and puts the box there.
func set_run_length(run: float) -> void:
	start_x = clampf(run, MIN_RUN, START_X + INCLINE_LENGTH * 0.5) - INCLINE_LENGTH * 0.5
	if _mark != null:
		_mark.position.x = start_x - BOX * 0.5
	_graph_revision += 1
	reset_box()


## Places the box at rest on the incline (frozen) at start_x.
func reset_box() -> void:
	box.freeze = true
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	var local := Transform3D(Basis(), Vector3(start_x, BOX * 0.5, 0.0))
	box.global_transform = _pivot.global_transform * local
	_stop_run()
	props.place_cat(_pivot.global_transform, start_x, BOX, angle_deg, true)
	if game != null:
		game.run_reset()
	_update_status()


## Ends the run at the box's current place: not released, no floor brake, history and graph cleared.
func _stop_run() -> void:
	released = false
	box.linear_damp = 0.0
	corrector.reset(box.global_position)
	_graph_points.clear()
	_graph_revision += 1


func release() -> void:
	if released:
		reset_box()
	corrector.reset(box.global_position)
	_graph_points.clear()
	_graph_points.append(Vector2.ZERO)
	_graph_revision += 1
	released = true
	box.freeze = false
	box.sleeping = false
	props.cat_let_go(_pivot.global_transform.basis * Vector3.LEFT)
	_update_status()


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)
	if current == "left" and game != null:
		(game as InclineGame).arrive()   # the formula box reached the slide's end: the dominoes' row reacts


func formula_acceleration() -> float:
	return PhysicsLaws.incline_acceleration(G, deg_to_rad(angle_deg), mu_s, mu_k)


## The box's formula speed at the slide's lower end (the piece game, 2026-10-29): from rest over the
## run d with the formula acceleration a, v² = 2 a d (0 when it holds). Read only.
func bottom_speed() -> float:
	return sqrt(2.0 * formula_acceleration() * run_length())


func status() -> String:
	if not released:
		return "ready"
	if corrector.past_end:
		return "left"
	return corrector.status


func _physics_process(_delta: float) -> void:
	if not released:
		return
	# samples[k] is the displacement after k steps; this runs before the box's step (tree order).
	var steps := corrector.steps - 1
	if steps > 0 and steps % GRAPH_EVERY_STEPS == 0 and steps < corrector.samples.size():
		var max_t: float = definition.get("graph", {}).get("x", {}).get("max", 3.0)
		var t := steps / float(Engine.physics_ticks_per_second)
		if t <= max_t + 0.001 and t > _graph_points[-1].x and status() != "left":
			_graph_points.append(Vector2(t, corrector.samples[steps]))
			_graph_revision += 1
	if status() != _last_status:
		_update_status()
	_settle_off_incline()


## The floor is frictionless like the incline (so the formula layer owns all friction), but a box
## that has left the incline must not run off the end of the finite floor: it brakes once it lies
## on the floor and is stopped if it ever drops far below it. Does not touch the displayed numbers.
func _settle_off_incline() -> void:
	if box.freeze:
		return
	var y := box.global_position.y
	if y < FALL_LIMIT_Y:
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.freeze = true
	elif status() == "left" and y < BOX * 0.5 + 0.05:
		box.linear_damp = FLOOR_DAMP


func observations() -> Dictionary:
	var theta := deg_to_rad(angle_deg)
	var normal := PhysicsLaws.incline_normal_load(MASS, G, theta)
	var state_text: String = {
		"ready": "놓기 전",
		"holding": "버티는 중 (정지)",
		"sliding": "미끄러지는 중",
		"left": "빗면을 벗어남",
	}.get(status(), "")
	return {
		"critical_angle": rad_to_deg(PhysicsLaws.critical_angle(mu_s)),
		"state": state_text,
		"tangential": PhysicsLaws.incline_tangential_gravity(MASS, G, theta),
		"max_static": PhysicsLaws.max_static_friction(mu_s, normal),
		"acceleration": formula_acceleration(),
		# Distance along the incline; after the box runs off the end it stays at the run length.
		"distance": minf(corrector.last_sample, run_length()) if released else 0.0,
		"run": run_length(),
		"bottom_speed": bottom_speed(),
	}


func graph_series() -> Dictionary:
	var max_t: float = definition.get("graph", {}).get("x", {}).get("max", 3.0)
	var a := formula_acceleration()
	var limit := run_length()  # the box leaves the incline after this distance
	var formula := PackedVector2Array()
	for i in 31:
		var t := max_t * i / 30.0
		var s := PhysicsLaws.constant_acceleration_displacement(0.0, a, t)
		if s > limit:
			break
		formula.append(Vector2(t, s))
	return {"formula": formula, "measured": _graph_points.duplicate()}


func graph_revision() -> int:
	return _graph_revision


func follow_point() -> Vector3:
	return box.global_position if box else global_position


func _build_world() -> void:
	var frictionless := _frictionless_material()
	_add_floor(frictionless)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, PIVOT_HEIGHT, 0.0)
	add_child(_pivot)
	var incline_size := Vector3(INCLINE_LENGTH, 0.3, 2.0)
	var incline := StaticBody3D.new()
	_incline_body = incline
	incline.physics_material_override = frictionless
	_add_box_shape(incline, incline_size)
	incline.add_child(props.make_incline(incline_size, material_id))
	incline.position = Vector3(0.0, -0.15, 0.0)
	_pivot.add_child(incline)
	# Start line where the box is released (visual only).
	_mark = ArtKit.instance(props.start_line_mesh(incline_size.z))
	_mark.position = Vector3(start_x - BOX * 0.5, 0.0, 0.0)
	_pivot.add_child(_mark)
	# Scale ticks on the start-position grid (the box's `snap` rule; no rule, no ticks), visual only.
	var snap := _start_snap()
	if snap > 0.0:
		_pivot.add_child(ArtKit.instance(props.ticks_mesh(INCLINE_LENGTH, incline_size.z, snap)))

	# Support post under the pivot (visual only, no collision).
	_stand = ArtKit.instance(props.foot_mesh())
	_stand.name = "Stand"
	_post = ArtKit.instance(props.post_mesh(STAND_HEIGHT))
	_post.name = "Post"
	_stand.add_child(_post)
	_stand.position = Vector3(0.0, 0.0, InclineProps.STAND_Z)
	add_child(_stand)
	_fit_stand()

	box = InclineBox.new()
	box.mass = MASS
	box.physics_material_override = frictionless
	_setup_free_body(box)
	box.freeze = true
	_add_box_shape(box, Vector3.ONE * BOX)
	var box_visual := ArtKit.parcel_box(BOX)   # a parcel box (Task 4g)
	box_visual.name = "Visual"
	box.add_child(box_visual)
	add_child(box)

	corrector.incline = _pivot
	corrector.half_length = INCLINE_LENGTH * 0.5
	corrector.half_extent = BOX * 0.5
	# The graph window (+ the sample at its end) is all the app reads from the history.
	corrector.history_steps = int(definition.get("graph", {}).get("x", {}).get("max", 3.0) * Engine.physics_ticks_per_second) + 2
	set_coefficients(mu_s, mu_k)
	box.corrector = corrector

	props.dress(self, _stand.position, box, box_visual, BOX)
	game = InclineGame.new(self)   # the piece game: the dominoes past the slide's end (visual only)
	add_child(game)
	game.build()
	props.juice.landed.connect(impact.emit)


## The post leans and shortens with the incline so its top stays inside the hinge axle's circle.
func _fit_stand() -> void:
	if _post != null:
		var pose := InclineProps.post_pose(PIVOT_HEIGHT, angle_deg)
		_post.rotation.z = pose.x
		_post.scale.y = pose.y / STAND_HEIGHT


# --- manipulation (Task 2b) -------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return box if id == "box" else null


## The incline's top face as a line: the box centre moves along pivot x between MIN_RUN and
## START_X (its default, 0.3 m short of the upper end). The grid step is the box's `snap` rule in
## the experiment JSON (the shell sets it on this surface), counted from the pivot (x = 0), which
## is also where the scale ticks are.
func manipulation_surface(surface_id: String) -> ManipSurface:
	if surface_id != "incline":
		return null
	var surface := ManipSurface.new(_pivot.global_transform,
		Vector2(MIN_RUN - INCLINE_LENGTH * 0.5, 0.0), Vector2(START_X, 0.0))
	surface.exclude = [_incline_body.get_rid()]
	return surface


## The box's grid step (m) from its manipulation rule as the manipulator reads it (0 = none), also
## the tick spacing on the incline.
func _start_snap() -> float:
	return Manipulator.parse_rules(definition).get("box", {}).get("snap", 0.0)


func manipulation_juice(_id: String) -> ArtJuice:
	return props.juice


## Picked up (also while sliding or lying on the floor): the run stops and the box waits, frozen.
func manipulation_started(_id: String) -> void:
	_stop_run()
	props.place_cat(_pivot.global_transform, start_x, BOX, angle_deg, false)
	props.juice.rearm()   # the next landing reacts again (squash, dust, impact)
	_update_status(true)  # no "placed" pop: the hand reaction comes from the manipulator


func manipulation_placed(_id: String, transform: Transform3D) -> void:
	_placed = true
	set_run_length((_pivot.global_transform.affine_inverse() * transform.origin).x + INCLINE_LENGTH * 0.5)


func manipulation_cancelled(_id: String) -> void:
	reset_box()


func placements() -> Dictionary:
	return {"box": _pivot.global_transform * Transform3D(Basis(), Vector3(start_x, BOX * 0.5, 0.0))} if _placed else {}
