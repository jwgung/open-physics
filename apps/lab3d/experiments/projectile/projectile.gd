## Guided projectile lab (Phase 1 Task 4a; web preset "projectile"): one ball is thrown from a
## launch stand with the speed and direction of the purple velocity arrow, in the chosen field.
## Conditions: gravity (the web's buttons), launch angle (0..90 deg, 15 deg steps like the web
## arrow's snap) and speed (1..9 m/s; the web arrow is capped at 9.09 m/s). The arrow's yellow knob
## can be dragged in the vertical plane of the throw (web step 1, "보라색 화살표를 끌어 방향을
## 정해요"; ArrowSurface), and the ball moved along the launch line and raised with its height
## handle (launch height 0..3 m; the web launches from 0.42 m, the default here is 0.5 m). In the
## game (2026-10-27, one drag per lab) the finger only pulls the slingshot: the launch height is the
## "launch_height" control in "자세히" (the same start as the height handle made), the arrow knob
## and the handle are not picked up (definition: "drag": false, "height": false).
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
## A ball leaving this box (beyond the island) is stopped and hidden: "섬 밖으로 날아감". The
## island's shore is drawn at BOUNDS_X.y (ProjectileProps passes it to ArtKit.add_world: the flat
## sand ends there and drops into the sea), so the ball is hidden as it leaves the land.
const BOUNDS_X := Vector2(-14.0, 12.5)
const BOUNDS_Y := Vector2(-3.0, 30.0)
const PATH_MAX_S := 12.0            # the formula path is drawn up to the landing, at most this long
## No close-up on the throw (2026-10-28 user: the sudden zoom-in is better gone): the
## whole throw, windup to landing, is seen from the still camera the child left.

var ball: FormulaBody
var knob: StaticBody3D
## Launch point: x, height of the ball's bottom above the floor, z.
var start := Vector3(START_X, START_HEIGHT, 0.0)
var angle_deg := 30.0
## The throw's speed (m/s). Fixed in the app since 2026-10-29 (user: "세기는 고정하는거로 하자":
## a stronger throw obviously goes farther; the game is the angle): the slingshot sets only the angle
## and "speed" is no control of the definition any more (set_control still takes it: tests, vectors).
const FIXED_SPEED := 8.0
var speed := FIXED_SPEED
var out_of_bounds := false
var _path := PackedVector3Array()   # reused by _fill_path (the drag preview runs every frame)
var _out_steps := 0                 # fixed steps counted after the ball was stopped out of bounds
var _ball_visual: MeshInstance3D
var _knob_visual: MeshInstance3D
var _shown_start := Vector3.INF     # ball centre the arrow / knob were placed for
var _shown_knob := Vector3.INF      # knob position the arrow preview was made for
## The slingshot game (Plan G3, set by slingshot_setup): no formula path or landing ring before a
## throw; the dots are the last throw's trail, drawn up to the formula time as the ball flies and
## kept until the next throw.
var trail_only := false
var _hit_key: Array = []
var _hit_times: Array = []


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
		"launch_height":
			var h := _clamp_to_control(id, float(value))
			if is_nan(h):
				return
			start.y = snapped_height(h)   # the height handle's own rounding (manipulation_placed)
			reset_run()
		_:
			super(id, value)


func control_value(id: String) -> Variant:
	match id:
		"angle":
			return angle_deg
		"speed":
			return speed
		"launch_height":
			return start.y
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
	if game != null:
		game.run_reset()
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
		# A slingshot pull's release commits the controls (which reset the run and drop the cat's
		# grip) before this runs, so the cat may be in "free" mode: restore the grip so the throw works.
		if projectile_props().cat != null and projectile_props().cat.mode == "free":
			projectile_props().set_cat_grip(true)
		projectile_props().throw(release)


func release() -> void:
	if released:
		reset_run()
	apply_field(ball)
	(ball.corrector as UniformFieldCorrector).release(ball, launch_velocity())
	_knob_visual.visible = false
	if trail_only:   # the new throw's trail: the formula path from its launch, shown as it flies
		projectile_props().set_path(formula_path(), null)
		_show_trail()
	_mark_released(PackedVector2Array([Vector2(0.0, launch_height())]))


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
## before the engine has; the mission's stamp waits for this). A flight that left the island or
## met the fence has ended too.
func settled() -> bool:
	return not released or corrector().landed_step >= 0 or out_of_bounds or hit_fence()


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
		# The piece game (2026-10-29): this throw's formula path touches crate n (1) or not (0).
		"hit_1": 1.0 if is_finite(hit_times()[0]) else 0.0,
		"hit_2": 1.0 if is_finite(hit_times()[1]) else 0.0,
		"hit_3": 1.0 if is_finite(hit_times()[2]) else 0.0,
	}


## The formula times (s) at which this throw's path touches each crate of the piece game
## (ProjectileGame.hit_time: INF = never, before the landing, the fence or PATH_MAX_S). Read only:
## from the launch (start, angle, speed, g), cached until one of them changes.
func hit_times() -> Array:
	var key := [start, angle_deg, speed, g]
	if key != _hit_key:
		_hit_key = key
		var c := ball_center()
		var vx := launch_vx()
		var vy := launch_vy()
		var end := minf(minf(flight_time(), fence_time_for(c.x, vx, vy, launch_height())), PATH_MAX_S)
		_hit_times = []
		for i in ProjectileGame.TARGETS.size():
			_hit_times.append(ProjectileGame.hit_time(i, Vector2(c.x, c.y), vx, vy, g, BALL_RADIUS, end))
	return _hit_times


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
	if trail_only:   # no preview: the last throw's trail stays as it is, no landing ring
		projectile_props().ring.visible = false
		return
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
		if released and trail_only:
			_show_trail()
		if released and game != null and game.stage < ProjectileGame.TARGETS.size():
			var t: float = hit_times()[game.stage]
			if is_finite(t) and clock() >= t:
				(game as ProjectileGame).hit(game.stage, g)   # the formula ball reached the crate: it tips
		if status() == "landed":
			_update_status()   # the rest frame: report the landing once (status "landed")
		return
	# While the slingshot pull holds (Plan G3), the arrow shows the pull's (angle, speed); there is
	# no path or ring (the big on-screen numbers say the rest).
	if _slingshot_preview != Vector2.INF:
		_show_pull(_slingshot_preview)
		return
	if ball.global_position != _shown_start:
		_show_preview(ball.global_position - Vector3.UP * BALL_RADIUS, angle_deg, speed, true)
	elif knob.global_position != _shown_knob:
		var plane := ArrowSurface.new(ball_center(), KNOB_SIZE * 0.5)
		var q := ArrowSurface.snap_polar(plane.to_plane(knob.global_position))
		_show_preview(start, clampf(q.x, ArrowSurface.ANGLE_MIN, ArrowSurface.ANGLE_MAX), q.y, false)


## The slingshot pull's (angle deg, speed m/s) while a finger holds it; INF when no pull. The
## screen sets it from the Manipulator's slingshot signal (the pull's preview and release).
var _slingshot_preview := Vector2.INF


## The screen calls this with the pull's (angle, speed) while a finger holds it (the preview
## hides the formula path and ring), and with INF when the pull ends.
func set_slingshot_preview(value: Variant) -> void:
	_slingshot_preview = Vector2(value.x, speed) if value is Vector2 and value != Vector2.INF else Vector2.INF


## The pull's arrow (the (angle, speed) the release throws); the path stays the last trail.
func _show_pull(value: Vector2) -> void:
	var center := ball_center()
	var tip := ArrowSurface.tip(value.x, value.y)
	knob.global_position = center + Vector3(tip.x, -tip.y, 0.0)
	_knob_visual.visible = true
	_shown_start = center
	_shown_knob = knob.global_position
	projectile_props().set_arrow(center, value.x, tip.length(), KNOB_SIZE * 0.5)
	projectile_props().place_stand(start)
	projectile_props().ring.visible = false


## The trail of the throw in flight: the dots of its formula path up to the formula time shown
## (all of them once it has landed or met the fence).
func _show_trail() -> void:
	var end := minf(minf(flight_time(), fence_time_for(ball_center().x, launch_vx(), launch_vy(), launch_height())), PATH_MAX_S)
	var dots := ProjectileProps.PATH_DOTS
	if end > 0.0:   # the dots sit at end * i / PATH_DOTS (_fill_path)
		dots = clampi(floori(shown_time() / end * ProjectileProps.PATH_DOTS + 1e-6), 0, ProjectileProps.PATH_DOTS)
	projectile_props().show_dots(dots)


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
	game = ProjectileGame.new(self)   # the piece game: the crates and the star piece (visual only)
	add_child(game)
	game.build()
	projectile_props().juice.landed.connect(impact.emit)


# --- manipulation -----------------------------------------------------------------------------

## The slingshot's (Plan G3) own setup: the pull's object (the ball), the launch point now, the
## ArrowSurface the pull's (angle, speed) snap on (the pull's angle step is the definition's
## manipulation.slingshot.angle_step - 5 deg - unlike the 15 deg knob grid; the speed grid and
## range are the speed slider's) and the controls a pull commits ("angle", "speed"; then the
## "release" action throws). The lab turns its preview off (trail_only).
func slingshot_setup() -> Dictionary:
	var manipulation: Dictionary = definition.get("manipulation", {})
	var spec: Dictionary = manipulation.get("slingshot", {})
	if spec.is_empty() or not manipulation_body(str(spec.get("object", ""))):
		return {}
	var surface := ArrowSurface.new(ball_center(), KNOB_SIZE * 0.5)
	surface.angle_step = float(spec.get("angle_step", ArrowSurface.ANGLE_STEP))
	trail_only = true
	projectile_props().show_dots(0)   # nothing thrown yet: no dots
	_show_launch()
	# The pull sets the angle only (the reversed pull's direction on the 5° grid); its length no longer
	# changes the speed (2026-10-29), the manipulator's dead zone still keeps a tap from throwing.
	return {"object": "ball", "surface": surface, "launch": ball_center, "controls": ["angle"],
		"value": func(pull: Vector2) -> Vector2: return Vector2(Manipulator.pull_launch(surface, pull).x, speed),
		"readout": angle_words, "fixed": speed}


## The pull's angle in a child's words (no degrees on the kid screen; the number is in 자세히).
static func angle_words(value: Vector2) -> String:
	if value.x <= 25.0:
		return "낮게"
	if value.x <= 55.0:
		return "비스듬히"
	if value.x <= 75.0:
		return "높이"
	return "아주 높이"


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
		# The launch line's 0.5 m grid (the drag's snap, definition.manipulation); the height
		# handle's finer 0.25 m grid applies to the height alone.
		start.x = snappedf(start.x, 0.5)
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
