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
## Fences at both ends of the throw line (Task 4f; 2026-10-23 user decision): boards FENCE_THICKNESS
## thick with faces towards the throw at x = FENCE_X (the ball meets it moving +x) and FENCE_LEFT_X,
## FENCE_HEIGHT tall. The formula ball model (RollingContact) bounces any ball that meets one, on its
## face, top or top corner, with the ball's restitution and Coulomb friction along the surface; the
## engine has no fence body. A landed ball stops on the island by rolling resistance. A flight that
## meets a fence (the moon's long low throws, and low throws in zero gravity) is the formula's up to
## the contact, then the model's ("울타리에 맞음"); one that clears the top flies on as before
## (docs/formula-correction.md "Task 4f"). The launch preview's dots end at the contact.
## Both stand wholly on the island top (inside its 14-sided top, ArtKit.ISLAND_RADIUS around
## ProjectileProps.ISLAND_CENTER; tests/ball_spin_checks.gd checks every fence vertex), so the right
## one is at 9.5 m and narrower on the left. 1.8 m: at these faces the lowest of the heights scanned
## (1.2-2.0 m, 0.1 m steps) at which no earth / jupiter ball bounces over after landing (1.5 m: 6 of
## 4641 earth throws do, 1.7 m: 1).
const FENCE_X := 9.5
const FENCE_LEFT_X := -9.3
const FENCE_HEIGHT := 1.8
const FENCE_WIDTH := 6.0
const FENCE_LEFT_WIDTH := 4.4
const FENCE_THICKNESS := 0.15
## A ball leaving this box (beyond the island) is stopped and hidden: "섬 밖으로 날아감".
const BOUNDS_X := Vector2(-14.0, 12.5)
const BOUNDS_Y := Vector2(-3.0, 30.0)
const PATH_MAX_S := 12.0            # the formula path is drawn up to the landing, at most this long
## Close-up of the throw (CameraRig.focus, apps/lab3d/README.md, close-up): "공 놓기" eases the view
## in on the cat and the ball (CLOSE_UP_FILL of the view height, their centre at CLOSE_UP_ANCHOR:
## left of the middle) over CLOSE_UP_IN_S, holds CLOSE_UP_HOLD_S and eases back over CLOSE_UP_OUT_S,
## so the camera is at rest on the whole lab before the ball leaves the paw (CatActor.WINDUP_S +
## SWING_S = 0.48 s; 2026-10-24 user decision: the flight is seen from a still camera). The release
## cuts whatever is left (a slow frame), so the flight never sees a moving camera. The release frame
## and the run are the same as without it.
const CLOSE_UP_FILL := 0.3
const CLOSE_UP_ANCHOR := Vector2(0.36, 0.58)
const CLOSE_UP_IN_S := 0.15
const CLOSE_UP_HOLD_S := 0.12
const CLOSE_UP_OUT_S := 0.17

var ball: FormulaBody
var knob: StaticBody3D
## Launch point: x, height of the ball's bottom above the floor, z.
var start := Vector3(START_X, START_HEIGHT, 0.0)
var angle_deg := 45.0
var speed := 9.0
var out_of_bounds := false
var _path := PackedVector3Array()   # reused by _fill_path (the drag preview runs every frame)
var _out_steps := 0                 # fixed steps counted after the ball was stopped out of bounds
var _ball_visual: MeshInstance3D
var _knob_visual: MeshInstance3D
var _shown_start := Vector3.INF     # ball centre the arrow / knob were placed for
var _shown_knob := Vector3.INF      # knob position the arrow preview was made for


func _init() -> void:
	props = ProjectileProps.new()


func set_control(id: String, value: Variant) -> void:
	match id:
		"angle":
			angle_deg = clampf(float(value), ArrowSurface.ANGLE_MIN, ArrowSurface.ANGLE_MAX)
			reset_run()
		"speed":
			speed = clampf(float(value), ArrowSurface.SPEED_MIN, ArrowSurface.SPEED_MAX)
			reset_run()
		_:
			super(id, value)


func control_value(id: String) -> Variant:
	match id:
		"angle":
			return angle_deg
		"speed":
			return speed
	return super(id)


## Launch velocity components (m/s, 64-bit: a Vector3 would round them to 32 bits).
func launch_vx() -> float:
	return vx_of(angle_deg, speed)


func launch_vy() -> float:
	return vy_of(angle_deg, speed)


static func vx_of(angle: float, launch_speed: float) -> float:
	return launch_speed * cos(deg_to_rad(angle))


static func vy_of(angle: float, launch_speed: float) -> float:
	return launch_speed * sin(deg_to_rad(angle))


## Launch velocity for the engine (world, m/s).
func launch_velocity() -> Vector3:
	return Vector3(launch_vx(), launch_vy(), 0.0)


func ball_center() -> Vector3:
	return start + Vector3.UP * BALL_RADIUS


func reset_run() -> void:
	close_up_ended.emit(0.0)   # a throw in progress stops: no close-up either
	hold_ball(ball, ball_center())
	apply_field(ball)
	_ball_visual.visible = true
	out_of_bounds = false
	_out_steps = 0
	_show_launch()
	_mark_reset()


## "공 놓기" (the action button): the bread cat throws the ball (ProjectileProps.throw); release()
## runs on the frame the ball leaves its paw at the launch point, so the run (the formula clock, the
## engine ball, the panel) is the same as a direct release from then on. Pressed again during the
## throw it does nothing; "처음으로", a condition change or picking something up stops the throw.
func run_action(id: String) -> void:
	if id != "release":
		super(id)
		return
	if released:
		reset_run()
	if not projectile_props().throwing():
		projectile_props().throw(release)
		if projectile_props().throwing():
			close_up.emit(close_up_spec())


## What the throw's close-up frames: the cat and the ball in its paw.
func close_up_spec() -> Dictionary:
	var box := projectile_props().cat.bounds().merge(AABB(ball_center() - Vector3.ONE * BALL_RADIUS, Vector3.ONE * BALL_RADIUS * 2.0))
	return {"box": box, "fill": CLOSE_UP_FILL, "anchor": CLOSE_UP_ANCHOR,
		"in_s": CLOSE_UP_IN_S, "hold_s": CLOSE_UP_HOLD_S, "out_s": CLOSE_UP_OUT_S}


func release() -> void:
	if released:
		reset_run()
	apply_field(ball)
	(ball.corrector as UniformFieldCorrector).release(ball, launch_velocity())
	_knob_visual.visible = false
	_mark_released(PackedVector2Array([Vector2(0.0, launch_height())]))
	close_up_cut.emit()   # normally already over: the camera is still from the release on


func projectile_props() -> ProjectileProps:
	return props as ProjectileProps


func corrector() -> UniformFieldCorrector:
	return ball.corrector


# --- formulas (PhysicsLaws only) ------------------------------------------------------------------

## Flight time to the floor level (INF when it never comes down: no field).
func flight_time() -> float:
	return flight_time_for(launch_vy(), launch_height())


## The same for a launch with vertical speed `vy` from `height` (no state read: the preview).
func flight_time_for(vy: float, height: float) -> float:
	return PhysicsLaws.landing_time(vy, -g, height)


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
## engine reports it); a flight that met the fence stops at the fence time (its x, y there).
func shown_time() -> float:
	if not released:
		return 0.0
	if hit_fence():
		return corrector().rolling.fence_time   # the formula flight ends at the fence
	var landing := flight_time()
	return landing if has_landed() else minf(clock(), landing)


## The clock reached the formula flight time, or the engine reported the landing (has_landed_by;
## a level throw from the floor has flight time 0: it slides, it does not fly).
func has_landed() -> bool:
	return has_landed_by(corrector(), flight_time(), clock())


## Formula offset (x, height of the bottom above the floor) at time t.
## (A Vector2 of 32-bit floats: for drawing. The panel uses formula_x / formula_y.)
func formula_point(t: float) -> Vector2:
	return Vector2(formula_x(t), formula_y(t))


func formula_x(t: float) -> float:
	return PhysicsLaws.constant_acceleration_displacement(launch_vx(), 0.0, t)


func formula_y(t: float) -> float:
	return maxf(0.0, launch_height() + PhysicsLaws.constant_acceleration_displacement(launch_vy(), -g, t))


## Launch height (ball bottom above the floor, m): start.y, kept on the 1 mm grid (snapped_height)
## where it is set, so the engine start, the graph points and the formulas use the same value.
func launch_height() -> float:
	return start.y


func status() -> String:
	if not released:
		return "ready"
	if out_of_bounds:
		return "out"
	if hit_fence():
		return "fence"
	if has_landed():
		return "landed"
	return "floating" if g <= 0.0 else "flying"


## The engine ball has landed: the corrector's own report (the first sample at or after the
## formula touch), not has_landed_by's clock slack (the status can say "landed" a few steps
## before the bounce and roll are done; the mission's stamp waits for this).
func settled() -> bool:
	return not released or corrector().landed_step >= 0 or out_of_bounds


## The flight met the fence below its top (2026-10-23 user decision) and the clock has reached that
## formula time: the ball bounced back from it (RollingContact) and stays on the island.
func hit_fence() -> bool:
	var contact := corrector().rolling
	return released and contact.hit_fence_in_flight() and clock() >= contact.fence_time - LANDING_SLACK


func _released_step() -> void:
	if out_of_bounds:
		_out_steps += 1
		return
	var steps := corrector().steps - 1
	if _graph_sample_time(steps) >= 0.0:
		# Engine heights of the free flight only: to the floor landing, or to the fence.
		_append_sample(corrector(), steps, launch_height(), minf(flight_time(), corrector().rolling.fence_time))
	_check_bounds()


## Beyond the island the ball is stopped and hidden (the formula values keep their meaning). Only
## a ball still in flight counts as "섬 밖으로 날아감"; one that landed and rolled off keeps "landed".
func _check_bounds() -> void:
	if ball.freeze:
		return
	var p := ball.global_position
	if p.x < BOUNDS_X.x or p.x > BOUNDS_X.y or p.y < BOUNDS_Y.x or p.y > BOUNDS_Y.y:
		out_of_bounds = not has_landed()
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
		"fence": "울타리에 맞음",
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


## Engine landing distance from the launch point (the "시뮬레이션" readout): the engine x at the
## measured landing step (measured_landing_step: since Task 4f the first sample at or after the
## formula touch), or "—" before it.
func measured_range() -> Variant:
	var c := corrector()
	if c.rolling.hit_fence_in_flight():
		return "—"   # it never landed where the formula lands
	var step := measured_landing_step(c, flight_time(), clock()) if released else -1
	if step < 0 or step >= c.offsets.size():
		return "—"
	return c.offsets[step].x


func graph_series() -> Dictionary:
	return {"formula": _formula_line(formula_y, flight_time()), "measured": _measured.duplicate()}


func follow_point() -> Vector3:
	return ball.global_position if ball else global_position


## Dugi points at where the formula flight ends (Task 4h): the landing point (the ball's centre when
## it touches the floor) or the fence contact, the end of the formula path; a flight without one
## (zero gravity past the island) points at the ball.
func explain_point() -> Vector3:
	var c := ball_center()
	var t := minf(flight_time_for(launch_vy(), launch_height()), fence_time_for(c.x, launch_vx(), launch_vy(), launch_height()))
	if not is_finite(t) or t > PATH_MAX_S:
		return follow_point()
	return Vector3(c.x + formula_x(t), formula_y(t) + BALL_RADIUS, c.z)


## Formula path dots from the launch to the landing or the fence contact (or up to PATH_MAX_S /
## the island's edge).
func formula_path() -> PackedVector3Array:
	var vx := launch_vx()
	var vy := launch_vy()
	var height := launch_height()
	var center := ball_center()
	return _fill_path(center, vx, vy, height, minf(flight_time_for(vy, height), fence_time_for(center.x, vx, vy, height)))


## Formula time at which a launch from the ball centre x `x` with (vx, vy) from `height` meets a
## fence in flight (INF: it lands first or clears the top; RollingContact.flight_fence_time).
func fence_time_for(x: float, vx: float, vy: float, height: float) -> float:
	return corrector().rolling.flight_fence_time(x, height, vx, vy, g)


## Fills (and returns) the reused path buffer: PATH_DOTS points of the flight from the ball centre
## `c`, launched with (vx, vy) from `height`, until `landing` (the floor or a fence). A copy already handed out keeps its
## points (copy on write), so the buffer only allocates when the dot count grows.
func _fill_path(c: Vector3, vx: float, vy: float, height: float, landing: float) -> PackedVector3Array:
	_path.clear()
	var end := minf(landing, PATH_MAX_S)
	for i in range(1, ProjectileProps.PATH_DOTS + 1):
		var t := end * i / float(ProjectileProps.PATH_DOTS)
		var q_x := PhysicsLaws.constant_acceleration_displacement(vx, 0.0, t)
		var q_y := maxf(0.0, height + PhysicsLaws.constant_acceleration_displacement(vy, -g, t))
		var point := Vector3(c.x + q_x, q_y + BALL_RADIUS, c.z)
		if point.x > BOUNDS_X.y or point.y > BOUNDS_Y.y:
			break
		_path.append(point)
	return _path


## Arrow, knob, stand and path for the current start and launch velocity (while waiting).
func _show_launch() -> void:
	_show_preview(start, angle_deg, speed, true)


## Shows a launch from `bottom` with (angle, speed): arrow, stand, formula path and landing ring;
## the knob is put on the arrow tip when `place_knob` (not while a finger holds it). Reads only
## its arguments (the lab's start / angle / speed stay as they are).
func _show_preview(bottom: Vector3, angle: float, launch_speed: float, place_knob: bool) -> void:
	var center := bottom + Vector3.UP * BALL_RADIUS
	var tip := ArrowSurface.tip(angle, launch_speed)
	if place_knob:
		knob.global_position = center + Vector3(tip.x, -tip.y, 0.0)
		_knob_visual.visible = true
	_shown_start = center
	_shown_knob = knob.global_position
	projectile_props().set_arrow(center, angle, tip.length(), KNOB_SIZE * 0.5)
	projectile_props().place_stand(bottom)
	var vx := vx_of(angle, launch_speed)
	var vy := vy_of(angle, launch_speed)
	var height := snapped_height(bottom.y)
	var landing := flight_time_for(vy, height)
	var fence := fence_time_for(center.x, vx, vy, height)
	# The dots end where the flight meets a fence; the ring marks the formula landing only when the
	# ball gets there (no fence first) and it lies between the fences (a throw over the top lands
	# behind the board).
	var ring: Variant = null
	if is_finite(landing) and not is_finite(fence):
		var x := center.x + PhysicsLaws.constant_acceleration_displacement(vx, 0.0, landing)
		if x < FENCE_X and x > FENCE_LEFT_X:
			ring = Vector3(x, 0.0, center.z)
	projectile_props().set_path(_fill_path(center, vx, vy, height, minf(landing, fence)), ring)


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
	var contact := (ball.corrector as UniformFieldCorrector).rolling
	contact.wall_x = FENCE_X
	contact.wall_left_x = FENCE_LEFT_X
	contact.wall_top = FENCE_HEIGHT
	contact.wall_restitution = BOUNCE   # the web's wall rule: the ball's own restitution
	contact.wall_thickness = FENCE_THICKNESS   # its top and back are boards too
	# The whole drawn path (PATH_MAX_S) stays in the history: the measured landing distance reads it.
	(ball.corrector as UniformFieldCorrector).history_steps = int(PATH_MAX_S * Engine.physics_ticks_per_second) + 2
	_ball_visual = ball_visual(ArtPalette.RED)
	_ball_visual.name = "Visual"
	ball.add_child(_ball_visual)
	add_child(ball)
	knob = _make_knob("ArrowKnob", KNOB_LAYER, KNOB_SIZE)
	_knob_visual = knob.get_node("Visual")
	projectile_props().dress(self, ball, _ball_visual, BALL_RADIUS * 2.0)
	projectile_props().juice.landed.connect(impact.emit)


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
	return projectile_props().juice if id == "ball" else null


## Picked up (the ball, also while flying or after landing, or the arrow knob): the throw stops
## and the ball waits at its launch point.
func manipulation_started(id: String) -> void:
	if released or projectile_props().throwing():
		reset_run()   # a throw in progress stops (no late release)
	if id == "ball":
		projectile_props().set_cat_grip(false)   # the finger holds the ball now
	projectile_props().juice.rearm()


func manipulation_cancelled(id: String) -> void:
	projectile_props().cat_grip = true
	super(id)


func _status_changed(previous: String, current: String) -> void:
	projectile_props().status_changed(previous, current)


func manipulation_placed(id: String, transform: Transform3D) -> void:
	_placed = true
	projectile_props().cat_grip = true
	if id == "ball":
		start = transform.origin - Vector3.UP * BALL_RADIUS
		start.y = snapped_height(start.y)
	else:
		var surface := ArrowSurface.new(ball_center(), KNOB_SIZE * 0.5)
		var q := ArrowSurface.snap_polar(surface.to_plane(transform.origin))
		angle_deg = clampf(q.x, ArrowSurface.ANGLE_MIN, ArrowSurface.ANGLE_MAX)
		speed = q.y
	reset_run()


## Launch point and arrow tip once one was moved (kept across a screen rebuild; the angle and speed
## are controls and come back with them).
func placements() -> Dictionary:
	return {"ball": Transform3D(Basis(), ball_center())} if _placed else {}
