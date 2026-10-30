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
## The slide's lower end (the middle of its top face's lower edge, world x/y) stays here at every
## angle (2026-10-29 user: "더 기울이면 더 빨리, 더 멀리"): only the top rises as the slide tilts,
## so a steeper slide starts the box higher and it leaves the end faster. Before, the slide turned
## about its middle 3.2 m up and a steeper slide lowered its end (the box landed nearer). END_Y is
## the top face's height there: the slide's 0.5 m thick body reaches the ground, and the box drops
## the last 0.3 m onto the floor (lower, its corner catches the floor's edge and the engine box runs
## up to 9 cm off the formula; from 0.2 m on it stays within 1 cm).
const END_X := -2.6
const END_Y := 0.3
const STAND_X := END_X + INCLINE_LENGTH * 0.5  # the support post's foot (world x): under the flat slide's middle; it leans to the hinge
const STAND_HEIGHT := 3.3     # full height of the support post mesh (scaled to the hinge)
const GRAPH_EVERY_STEPS := 6  # graph sample every 6 fixed steps (10 Hz)
## The floor's kinetic friction on the box past the slide's end (2026-10-29, with the fixed lower end):
## from the formula landing the box's floor speed drops by μ g each second (Coulomb friction, the
## same law as on the slide), so it stops after v²/(2μg): a faster box goes clearly farther. Before,
## a 4/s velocity damp stopped it after about v/4, too little apart between the slopes.
const FLOOR_MU := 0.6
const EDGE_SLIDE := 0.25      # of BOX: the run over the slide's frictionless edge (arrival())
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
var _brake_step := -1         # the step (corrector.steps) of the formula landing: the floor brake starts
var _braking := false         # the floor's friction slows the box (from _brake_step on)
var _landing_speed := 0.0     # the formula's floor speed v cos θ at the landing (arrival().vx)
var _graph_points := PackedVector2Array()
var _graph_revision := 0
var _reach_key := []
var _reach := []


func _ready() -> void:
	_build_world()
	for control in definition.controls():
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
	_place_slide()
	props.angle_changed(angle_deg, _pivot.position.x)
	_fit_stand()
	reset_box()   # the dominoes follow (InclineGame.place through run_reset)


## Selects a material option from the "material" control (unknown ids are ignored).
func set_material(option_id: String) -> void:
	var option := definition.option("material", option_id)
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
	_braking = false
	_brake_step = -1
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
	var way := arrival()
	_brake_step = int(way.brake_step) if way.has("brake_step") else -1
	_landing_speed = float(way.get("vx", 0.0))
	box.freeze = false
	box.sleeping = false
	props.cat_let_go(_pivot.global_transform.basis * Vector3.LEFT)
	_update_status()


func _status_changed(previous: String, current: String) -> void:
	props.status_changed(previous, current)


## The run is settled once the box past the end has run into the stage's dominoes or stopped on the
## floor (InclineGame watches it): the stamp and Puppy's line come when the row falls or wobbles.
func settled() -> bool:
	if not released or status() != "left" or game == null:
		return true
	var dominoes := game as InclineGame
	return dominoes.touched() or dominoes.stopped()


## The middle of the slide's lower end on its top face (world): where the formula run ends.
func lower_end() -> Vector3:
	return _pivot.global_transform * Vector3(-INCLINE_LENGTH * 0.5, 0.0, 0.0)


func formula_acceleration() -> float:
	return PhysicsLaws.incline_acceleration(G, deg_to_rad(angle_deg), mu_s, mu_k)


## The box's formula speed at the slide's lower end (the piece game, 2026-10-29): from rest over the
## run d with the formula acceleration a, v² = 2 a d (0 when it holds). Read only.
func bottom_speed() -> float:
	return sqrt(2.0 * formula_acceleration() * run_length())


## The box's way past the slide's end (2026-10-29 user: "착지 지점과 도미노의 위치가 안맞다"), from the
## formula only, for the dominoes (read only, nothing here moves the box):
## - it leaves the end at t_L = √(2d/a) with v = a t_L along the slope (d = run_length());
## - its centre flies on g from the end (the box's centre BOX/2 above the top face) and lands when it
##   is BOX/2 above the floor (t_f, x_land): the projectile p = p₀ + v t − ½ g t² ŷ;
## - the landing keeps its horizontal speed v cos θ; the floor's friction (FLOOR_MU) starts at the
##   formula landing's step (brake_step) and takes μ g Δt off that speed each step until it stops
##   (brake_steps later, rest_x): about (v cos θ)²/(2 μ g) further on.
## The lower end stays at (END_X, END_Y) for every slope, so the steeper slide leaves the box faster
## at the same place: from the top, steeper goes farther (every material, the picks 20°/30°/40°).
## {} when the box holds (a ≤ 0). World x (downhill is −x).
func arrival() -> Dictionary:
	var a := formula_acceleration()
	if a <= 0.0:
		return {}
	var theta := deg_to_rad(angle_deg)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t_left := sqrt(2.0 * run_length() / a)
	# Past the end the formula's friction stops and the box tips over the frictionless edge: about
	# a quarter of its size more on g sin θ alone (measured on the engine box, every material/angle).
	var v := sqrt(a * a * t_left * t_left + 2.0 * G * sin(theta) * BOX * EDGE_SLIDE)
	var from := _pivot.global_transform * Vector3(-INCLINE_LENGTH * 0.5, BOX * 0.5, 0.0)
	var vx := v * cos(theta)
	var vy := -v * sin(theta)
	var drop := maxf(from.y - BOX * 0.5, 0.0)
	var t_fly := (vy + sqrt(vy * vy + 2.0 * G * drop)) / G
	var brake_step := ceili((t_left + t_fly) / dt - 1e-6)
	var at_brake := from.x - vx * (brake_step * dt - t_left)
	var slow := floor_brake() * dt
	var steps := floori(vx / slow)   # steps with speed left after their slowing
	return {
		"t_left": t_left, "t_land": t_left + t_fly, "x_land": from.x - vx * t_fly, "from_x": from.x,
		"from_y": from.y, "vx": vx, "vy": vy, "brake_step": brake_step, "brake_steps": steps,
		"rest_x": at_brake - _floor_run(vx, slow, steps),
	}


## The floor friction's slowing (m/s²): μ g.
static func floor_brake() -> float:
	return FLOOR_MU * G


## How far a box at speed `speed` runs in `n` steps on the floor slowing by `slow` (m/s) each step
## (the slowing comes before each step's move; the speed stays at 0 once it is used up).
static func _floor_run(speed: float, slow: float, n: int) -> float:
	var k := mini(n, floori(speed / slow))
	return (k * speed - slow * k * (k + 1) * 0.5) / Engine.physics_ticks_per_second


## The box centre's x (world) after `step` steps from the release on arrival()'s way past the end
## (the flight, then the braked floor run). Only past the end (step ≥ t_left); NAN when it holds.
static func arrival_x(way: Dictionary, step: int) -> float:
	if way.is_empty():
		return NAN
	var dt := 1.0 / Engine.physics_ticks_per_second
	var brake: int = way.brake_step
	var x: float = way.from_x - way.vx * (mini(step, brake) * dt - way.t_left)
	if step > brake:
		x -= _floor_run(float(way.vx), floor_brake() * dt, step - brake)
	return x


## The box centre's height (world y) after `step` steps on arrival()'s way past the end: the flight
## p = p₀ + v t − ½ g t² from the slide's end until the formula landing, then BOX/2 on the floor.
static func arrival_y(way: Dictionary, step: int) -> float:
	if way.is_empty():
		return NAN
	var t := step / float(Engine.physics_ticks_per_second)
	if t >= float(way.t_land):
		return BOX * 0.5
	var s: float = t - float(way.t_left)
	return maxf(float(way.from_y) + float(way.vy) * s - 0.5 * G * s * s, BOX * 0.5)


## The first step (from the release) at which the formula's box (arrival(): its flight from the
## slide's end, then the braked floor run; the box's square of side BOX about its centre) overlaps a
## domino of the piece game's row r standing in the lane (InclineGame.LANE_FACE); -1 when it
## stops short, flies over the row or holds.
static func contact_step(way: Dictionary, row: int) -> int:
	if way.is_empty() or row < 0 or row >= InclineGame.ROWS.size():
		return -1
	var dt := 1.0 / Engine.physics_ticks_per_second
	var half := BOX * 0.5
	var pivots: Array = []
	for k in (InclineGame.ROWS[row][0] as Array).size():
		pivots.append(InclineGame.lane_x(row, k))
	var nearest: float = pivots[0] + (InclineGame.ROWS[row][1] as Vector3).x
	var step := ceili(float(way.t_left) / dt - 1e-6)
	var last := -INF
	while step <= int(way.brake_step) + int(way.brake_steps) + 1:
		var x := arrival_x(way, step)
		var y := arrival_y(way, step)
		if x - half <= nearest:
			for p: float in pivots:
				if InclineGame.overlaps(row, p, x - half, x + half, y - half):
					return step
		if step > int(way.brake_step) + int(way.brake_steps):
			return -1   # at rest
		last = x
		step += 1
	return -1


## Per stage: 1 when the formula's way past the end meets that stage's fixed domino row
## (contact_step), else 0 (the stamp's judge, reach_1–3; read only). Kept for a setting.
func reaches() -> Array:
	var key := [angle_deg, mu_s, mu_k, start_x]
	if key != _reach_key:
		_reach_key = key
		var way := arrival()
		_reach = []
		for r in InclineGame.LANE_FACE.size():
			_reach.append(1.0 if contact_step(way, r) >= 0 else 0.0)
	return _reach


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
		var max_t: float = definition.graph_x_max()
		var t := steps / float(Engine.physics_ticks_per_second)
		if t <= max_t + 0.001 and t > _graph_points[-1].x and status() != "left":
			_graph_points.append(Vector2(t, corrector.samples[steps]))
			_graph_revision += 1
	if status() != _last_status:
		_update_status()
	_settle_off_incline()


## The floor is frictionless like the incline (so the formula layer owns all friction): the floor's
## friction FLOOR_MU acts from the formula landing's step (arrival(); 2026-10-29: before, from when
## its centre dropped below BOX/2 + 0.05 m, which the landing's tumbles and hops moved by up to 1.7 m
## of rest point) on the box's floor speed, and a box that drops far below the floor is stopped.
## Does not touch the displayed numbers.
func _settle_off_incline() -> void:
	if box.freeze:
		return
	var y := box.global_position.y
	if y < FALL_LIMIT_Y:
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.freeze = true
	elif status() == "left" and _brake_step >= 0 and corrector.steps >= _brake_step:
		# The formula landing (arrival()): from this step on the floor's friction slows the box (a
		# fixed step, not the box's own hops after it lands, so its rest point is the formula's).
		var v := box.linear_velocity
		var floor_speed := Vector2(v.x, v.z).length()
		if not _braking:
			# The landing keeps the formula's floor speed v cos θ (the engine's tumbling landing is off by
			# up to 0.5 %, which the friction's v²/(2μg) run would stretch to centimetres).
			floor_speed = _landing_speed
			v = Vector3(-_landing_speed, v.y, 0.0)
		_braking = true
		var left := maxf(floor_speed - floor_brake() / Engine.physics_ticks_per_second, 0.0)
		var keep := left / floor_speed if floor_speed > 0.0 else 0.0
		box.linear_velocity = Vector3(v.x * keep, v.y, v.z * keep)


## The floor's friction is slowing the box (past the formula landing; InclineGame's stop watch).
func braking() -> bool:
	return _braking


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
		"reach_1": reaches()[0],
		"reach_2": reaches()[1],
		"reach_3": reaches()[2],
	}


func graph_series() -> Dictionary:
	var max_t: float = definition.graph_x_max()
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
	add_child(_pivot)
	_place_slide()
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
	_stand.position = Vector3(STAND_X, 0.0, InclineProps.STAND_Z)
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
	corrector.history_steps = int(definition.graph_x_max() * Engine.physics_ticks_per_second) + 2
	set_coefficients(mu_s, mu_k)
	box.corrector = corrector

	props.dress(self, _stand.position, box, box_visual, BOX)
	game = InclineGame.new(self)   # the piece game: the dominoes past the slide's end (visual only)
	add_child(game)
	game.build()
	props.juice.landed.connect(impact.emit)


## The slide at angle_deg with its lower end at (END_X, END_Y): the pivot (the middle of its top
## face, the frame every along-the-slide position is in) half the length up the slope from the end.
func _place_slide() -> void:
	var theta := deg_to_rad(angle_deg)
	_pivot.rotation = Vector3(0.0, 0.0, theta)
	_pivot.position = Vector3(END_X, END_Y, 0.0) + INCLINE_LENGTH * 0.5 * Vector3(cos(theta), sin(theta), 0.0)


## The post leans from its foot (STAND_X) and stretches with the incline so its top stays inside the
## hinge axle's circle; on a slope so gentle that the hinge is near the ground there is no post.
func _fit_stand() -> void:
	if _post != null:
		var pose := InclineProps.post_pose(_pivot.position - _stand.position, angle_deg)
		_post.rotation.z = pose.x
		_post.scale.y = maxf(pose.y, 0.01) / STAND_HEIGHT
		_post.visible = pose.y >= InclineProps.POST_MIN


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
	return definition.grid_step("box")


func manipulation_juice(_id: String) -> ArtJuice:
	return props.juice


## Picked up (also while sliding or lying on the floor): the run stops and the box waits, frozen.
func manipulation_started(_id: String) -> void:
	_stop_run()
	props.place_cat(_pivot.global_transform, start_x, BOX, angle_deg, false)
	props.juice.rearm()   # the next landing reacts again (squash, dust, impact)
	_update_status(true)  # no "placed" pop: the hand reaction comes from the manipulator


## Put down on the slide = let go (2026-10-29 user: no "상자 놓기" button): the box starts from rest
## there. A restored placement (the screen's batch) only places it.
func manipulation_placed(_id: String, transform: Transform3D) -> void:
	_placed = true
	set_run_length((_pivot.global_transform.affine_inverse() * transform.origin).x + INCLINE_LENGTH * 0.5)
	if _batch == 0:
		release()


func manipulation_cancelled(_id: String) -> void:
	reset_box()


func placements() -> Dictionary:
	return {"box": _pivot.global_transform * Transform3D(Basis(), Vector3(start_x, BOX * 0.5, 0.0))} if _placed else {}
