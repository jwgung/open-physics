## Guided projectile lab (Phase 1 Task 4a; web preset "projectile"): one ball is thrown from a
## launch stand with the speed and direction of the purple velocity arrow, in the chosen field.
## Conditions: gravity (the web's buttons), launch angle (0..90 deg, 15 deg steps like the web
## arrow's snap) and speed (1..9 m/s; the web arrow is capped at 9.09 m/s). The arrow's yellow knob
## can be dragged in the vertical plane of the throw (web step 1, "보라색 화살표를 끌어 방향을
## 정해요"; ArrowSurface), and the ball moved along the launch line and raised with its height
## handle (launch height 0..3 m; the web launches from 0.42 m, the default here is 0.5 m).
## Motion: Jolt + UniformFieldCorrector. Displayed numbers: PhysicsLaws (flight time, range and apex
## to the floor level from landing_time / apex_rise; position and velocity at the formula time).
## The engine gives only the graph's "시뮬레이션" points and the measured landing distance.
extends UniformFieldLab

const LINE := Vector2(-8.0, -3.0)   # x range of the launch point on the floor line
const START_X := -6.0
const START_HEIGHT := 0.5           # launch height (ball bottom above the floor), m
const BOUNCE := 0.6
const KNOB_SIZE := 0.3
const KNOB_LAYER := 2               # the knob is pickable but never hit by the ball (mask 1)
## A ball leaving this box (beyond the island) is stopped and hidden: "섬 밖으로 날아감".
const BOUNDS_X := Vector2(-14.0, 12.5)
const BOUNDS_Y := Vector2(-3.0, 30.0)
const PATH_MAX_S := 12.0            # the formula path is drawn up to the landing, at most this long

var ball: FormulaBody
var knob: StaticBody3D
## Launch point: x, height of the ball's bottom above the floor, z.
var start := Vector3(START_X, START_HEIGHT, 0.0)
var angle_deg := 45.0
var speed := 9.0
var released := false
var out_of_bounds := false
var props := ProjectileProps.new()
var _placed := false
var _out_steps := 0                 # fixed steps counted after the ball was stopped out of bounds
var _measured := PackedVector2Array()
var _graph_revision := 0
var _last_status := ""
var _ball_visual: MeshInstance3D
var _knob_visual: MeshInstance3D
var _shown_start := Vector3.INF     # ball centre the arrow / knob were placed for
var _shown_knob := Vector3.INF      # knob position the arrow preview was made for


func _ready() -> void:
	_build_world()
	for control in definition.get("controls", []):
		set_control(control.id, control.default)


func set_control(id: String, value: Variant) -> void:
	match id:
		"gravity":
			set_gravity(str(value))
		"angle":
			angle_deg = clampf(float(value), ArrowSurface.ANGLE_MIN, ArrowSurface.ANGLE_MAX)
		"speed":
			speed = clampf(float(value), ArrowSurface.SPEED_MIN, ArrowSurface.SPEED_MAX)
	reset_ball()


func control_value(id: String) -> Variant:
	match id:
		"gravity":
			return gravity_id
		"angle":
			return angle_deg
		"speed":
			return speed
	return super(id)


func run_action(id: String) -> void:
	match id:
		"release":
			release()
		"reset":
			reset_ball()


## Launch velocity components (m/s, 64-bit: a Vector3 would round them to 32 bits).
func launch_vx() -> float:
	return speed * cos(deg_to_rad(angle_deg))


func launch_vy() -> float:
	return speed * sin(deg_to_rad(angle_deg))


## Launch velocity for the engine (world, m/s).
func launch_velocity() -> Vector3:
	return Vector3(launch_vx(), launch_vy(), 0.0)


func ball_center() -> Vector3:
	return start + Vector3.UP * BALL_RADIUS


func reset_ball() -> void:
	hold_ball(ball, ball_center())
	apply_field(ball)
	_ball_visual.visible = true
	released = false
	out_of_bounds = false
	_out_steps = 0
	_measured.clear()
	_graph_revision += 1
	_show_launch()
	props.reset()
	_update_status(true)


func release() -> void:
	if released:
		reset_ball()
	apply_field(ball)
	(ball.corrector as UniformFieldCorrector).release(ball, launch_velocity())
	released = true
	_measured.clear()
	_measured.append(Vector2(0.0, start.y))
	_graph_revision += 1
	props.released()
	_knob_visual.visible = false
	_update_status(true)


func corrector() -> UniformFieldCorrector:
	return ball.corrector


# --- formulas (PhysicsLaws only) ------------------------------------------------------------------

## Flight time to the floor level (INF when it never comes down: no field).
func flight_time() -> float:
	return PhysicsLaws.landing_time(launch_vy(), -g, launch_height())


## Horizontal distance to the landing (INF without a landing).
func flight_range() -> float:
	var t := flight_time()
	return PhysicsLaws.constant_acceleration_displacement(launch_vx(), 0.0, t) if is_finite(t) else INF


## Highest point of the ball's bottom above the floor.
func apex_height() -> float:
	return launch_height() + PhysicsLaws.apex_rise(launch_vy(), -g)


func clock() -> float:
	if not released:
		return 0.0
	return (maxi(0, corrector().steps - 1) + _out_steps) * step_dt()


## The formula time shown: the clock, never past the formula landing (and the landing once the
## engine reports it).
func shown_time() -> float:
	if not released:
		return 0.0
	var landing := flight_time()
	return landing if corrector().landed_step >= 0 else minf(clock(), landing)


## Formula offset (x, height of the bottom above the floor) at time t.
## (A Vector2 of 32-bit floats: for drawing. The panel uses formula_x / formula_y.)
func formula_point(t: float) -> Vector2:
	return Vector2(formula_x(t), formula_y(t))


func formula_x(t: float) -> float:
	return PhysicsLaws.constant_acceleration_displacement(launch_vx(), 0.0, t)


func formula_y(t: float) -> float:
	return maxf(0.0, launch_height() + PhysicsLaws.constant_acceleration_displacement(launch_vy(), -g, t))


## Launch height (ball bottom above the floor, m), kept on the 1 mm grid of the handle's steps.
func launch_height() -> float:
	return snappedf(start.y, 0.001)


func status() -> String:
	if not released:
		return "ready"
	if out_of_bounds:
		return "out"
	if corrector().landed_step >= 0:
		return "landed"
	return "floating" if g <= 0.0 else "flying"


func _update_status(quiet := false) -> void:
	_last_status = status()
	if not quiet:
		state_changed.emit()


func _physics_process(_delta: float) -> void:
	if not released:
		return
	if out_of_bounds:
		_out_steps += 1
	else:
		var steps := corrector().steps - 1
		var c := corrector()
		var landed_before := c.landed_step >= 0 and c.landed_step < steps
		if steps > 0 and steps % GRAPH_EVERY_STEPS == 0 and steps < c.samples.size() and not landed_before:
			var t := steps * step_dt()
			if t <= graph_x_max() + 0.001:
				_measured.append(Vector2(t, maxf(0.0, start.y + c.samples[steps])))
				_graph_revision += 1
		_check_bounds()
	if status() != _last_status:
		_update_status()


## Beyond the island the ball is stopped and hidden (the formula values keep their meaning).
func _check_bounds() -> void:
	var p := ball.global_position
	if p.x < BOUNDS_X.x or p.x > BOUNDS_X.y or p.y < BOUNDS_Y.x or p.y > BOUNDS_Y.y:
		out_of_bounds = true
		ball.freeze = true
		ball.linear_velocity = Vector3.ZERO
		_ball_visual.visible = false


func observations() -> Dictionary:
	var t := shown_time()
	var vy := PhysicsLaws.constant_acceleration_velocity(launch_vy(), -g, t)
	var landing := flight_time()
	var apex := apex_height()
	var state_text: String = {
		"ready": "던지기 전",
		"flying": "날아가는 중",
		"landed": "바닥에 닿음",
		"out": "섬 밖으로 날아감",
		"floating": "무중력: 곧게 날아가요",
	}.get(status(), "")
	return {
		"g": g,
		"time": t,
		"state": state_text,
		"launch_height": launch_height(),
		"flight_time": landing if is_finite(landing) else "닿지 않아요",
		"range": flight_range() if is_finite(landing) else "닿지 않아요",
		"apex": apex if is_finite(apex) else "계속 올라가요",
		"x": formula_x(t),
		"y": formula_y(t),
		"vx": PhysicsLaws.constant_acceleration_velocity(launch_vx(), 0.0, t),
		"vy": vy,
		"landing": measured_range(),
	}


## Engine landing distance from the launch point (the "시뮬레이션" readout), or "—".
func measured_range() -> Variant:
	var c := corrector()
	if not released or c.landed_step < 0 or c.landed_step >= c.offsets.size():
		return "—"
	return c.offsets[c.landed_step].x


func graph_series() -> Dictionary:
	var line := PackedVector2Array()
	var x_max := graph_x_max()
	var landing := flight_time()
	for i in 61:
		var t := x_max * i / 60.0
		if t >= landing:
			line.append(Vector2(landing, 0.0))
			break
		line.append(Vector2(t, formula_y(t)))
	return {"formula": line, "measured": _measured.duplicate()}


func graph_revision() -> int:
	return _graph_revision


func follow_point() -> Vector3:
	return ball.global_position if ball else global_position


## Formula path dots from the launch to the landing (or up to PATH_MAX_S / the island's edge) and
## the landing ring.
func formula_path() -> PackedVector3Array:
	var points := PackedVector3Array()
	var landing := flight_time()
	var end := minf(landing, PATH_MAX_S)
	var c := ball_center()
	for i in range(1, ProjectileProps.PATH_DOTS + 1):
		var t := end * i / float(ProjectileProps.PATH_DOTS)
		var q := formula_point(t)
		var point := Vector3(c.x + q.x, q.y + BALL_RADIUS, c.z)
		if point.x > BOUNDS_X.y or point.y > BOUNDS_Y.y:
			break
		points.append(point)
	return points


## Arrow, knob, stand and path for the current start and launch velocity (while waiting).
func _show_launch() -> void:
	_show_preview(start, angle_deg, speed, true)


## Shows a launch from `bottom` with (angle, speed): arrow, stand, formula path and landing ring;
## the knob is put on the arrow tip when `place_knob` (not while a finger holds it).
func _show_preview(bottom: Vector3, angle: float, launch_speed: float, place_knob: bool) -> void:
	var saved := [start, angle_deg, speed]
	start = bottom
	angle_deg = angle
	speed = launch_speed
	var center := ball_center()
	var tip := ArrowSurface.tip(angle_deg, speed)
	if place_knob:
		knob.global_position = center + Vector3(tip.x, -tip.y, 0.0)
		_knob_visual.visible = true
	_shown_start = center
	_shown_knob = knob.global_position
	props.set_arrow(center, angle_deg, speed, tip.length(), KNOB_SIZE * 0.5)
	props.place_stand(start)
	var landing := flight_time()
	var ring: Variant = null
	if is_finite(landing):
		var x := center.x + flight_range()
		if x <= BOUNDS_X.y:
			ring = Vector3(x, 0.0, center.z)
	props.set_path(formula_path(), ring)
	start = saved[0]
	angle_deg = saved[1]
	speed = saved[2]


## While a finger holds the ball or the knob, the launch preview follows it: a dragged ball takes
## its arrow, knob and stand along; a dragged knob turns and stretches the arrow and the formula
## path to the direction and speed it would snap to (the same polar grid as on release).
func _process(_delta: float) -> void:
	if released or not ball.freeze:
		return
	if ball.global_position != _shown_start:
		_show_preview(ball.global_position - Vector3.UP * BALL_RADIUS, angle_deg, speed, true)
	elif knob.global_position != _shown_knob:
		var plane := ArrowSurface.new(ball_center(), KNOB_SIZE * 0.5)
		var q := ArrowSurface.snap_polar(plane.to_plane(knob.global_position))
		_show_preview(start, clampf(q.x, ArrowSurface.ANGLE_MIN, ArrowSurface.ANGLE_MAX), q.y, false)


func _build_world() -> void:
	make_floor(Vector3(30.0, 0.4, 22.0))
	ball = make_ball("Ball", 1.0, BOUNCE)
	# The whole drawn path (PATH_MAX_S) stays in the history: the measured landing distance reads it.
	(ball.corrector as UniformFieldCorrector).history_steps = int(PATH_MAX_S * Engine.physics_ticks_per_second) + 2
	_ball_visual = ArtKit.instance(ball_mesh(ArtPalette.RED))
	_ball_visual.name = "Visual"
	ball.add_child(_ball_visual)
	add_child(ball)
	knob = StaticBody3D.new()
	knob.name = "ArrowKnob"
	knob.collision_layer = 1 << (KNOB_LAYER - 1)
	knob.collision_mask = 0
	_add_box_shape(knob, Vector3.ONE * KNOB_SIZE)
	_knob_visual = ArtKit.instance(props.knob_mesh(KNOB_SIZE))
	_knob_visual.name = "Visual"
	knob.add_child(_knob_visual)
	add_child(knob)
	props.dress(self, ball, _ball_visual, BALL_RADIUS * 2.0)
	props.juice.landed.connect(impact.emit)


# --- manipulation -----------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	match id:
		"ball":
			return ball
		"arrow":
			return null if released else knob   # no arrow while the ball flies
	return null


func manipulation_surface(surface_id: String) -> ManipSurface:
	match surface_id:
		"launch":
			var line := ManipSurface.new(Transform3D.IDENTITY, Vector2(LINE.x, 0.0), Vector2(LINE.y, 0.0))
			line.exclude = [floor_body.get_rid(), knob.get_rid()]
			return line
		"arrow":
			var plane := ArrowSurface.new(ball_center(), KNOB_SIZE * 0.5)
			plane.exclude = [floor_body.get_rid(), ball.get_rid()]
			return plane
	return null


func manipulation_juice(id: String) -> ArtJuice:
	return props.juice if id == "ball" else null


## Picked up (the ball, also while flying or after landing, or the arrow knob): the throw stops
## and the ball waits at its launch point.
func manipulation_started(_id: String) -> void:
	if released:
		reset_ball()
	props.juice.rearm()


func manipulation_placed(id: String, transform: Transform3D) -> void:
	_placed = true
	if id == "ball":
		start = transform.origin - Vector3.UP * BALL_RADIUS
	else:
		var surface := ArrowSurface.new(ball_center(), KNOB_SIZE * 0.5)
		var q := ArrowSurface.snap_polar(surface.to_plane(transform.origin))
		angle_deg = clampf(q.x, ArrowSurface.ANGLE_MIN, ArrowSurface.ANGLE_MAX)
		speed = q.y
	reset_ball()


func manipulation_cancelled(_id: String) -> void:
	reset_ball()


## Launch point and arrow tip once one was moved (kept across a screen rebuild; the angle and speed
## are controls and come back with them).
func placements() -> Dictionary:
	return {"ball": Transform3D(Basis(), ball_center())} if _placed else {}
