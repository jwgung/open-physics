## Guided free-fall lab (Phase 1 Task 4a; web preset "free-fall"): three balls of different mass
## (yellow 0.5 kg, violet "보라" 1 kg, red = the "mass" control, 3 kg by default, like the web's light /
## reference / heavy balls) are dropped together in the chosen field and land at the same time.
## Conditions: gravity (the web's buttons), the drop height of all three (slider) and the red ball's
## mass. A finger drags any ball up or down (2026-10-27, one drag per lab: "drop_<ball>" objects on a
## vertical line through the ball): letting go sets the drop height of all three, the "height"
## control (the "자세히" slider), so the three still start level (web step 1: "세 공의 높이를 맞춰요").
## The per-ball placements (manipulation_placed with a ball id: a restored state, tests) stay; a
## finger no longer moves one ball sideways or raises one alone (definition: "drag": false).
## Motion: Jolt + UniformFieldCorrector (uniform_field_lab.gd). Displayed numbers: PhysicsLaws at the formula time (the landing at landing_time(0, -g, h0)); the engine is
## only the graph's "시뮬레이션" points and the measured landing times.
## Each ball looks as heavy as it is (2026-10-28, look_radius): the red ball grows and shrinks with
## its mass from its body's bottom; the bodies (BALL_RADIUS spheres), their fall and the landings stay.
extends UniformFieldLab

## Left to right. mass: kg (the red one follows the "mass" control).
const BALLS := {
	"yellow": {"x": -1.5, "mass": 0.5, "color": ArtPalette.YELLOW, "name": "노랑"},
	"purple": {"x": 0.0, "mass": 1.0, "color": ArtPalette.VIOLET, "name": "보라"},
	"red": {"x": 1.5, "mass": 3.0, "color": ArtPalette.RED, "name": "빨강"},
}
const ORDER := ["yellow", "purple", "red"]
const LINE_X := 3.0              # the balls move along the floor line x = -3..3 m (z = 0)
const DROP := "drop_"             # the finger's object of a ball: "drop_red" drags the red ball up and down
const BOUNCE := 0.5               # the web's wood balls (restitution 0.5)
const LOOK_MASS := 1.0            # kg: the ball that looks BALL_RADIUS round (the violet one)
const SIGN_AT := Vector3(-5.0, 0.0, -2.2)   # the gravity's signpost (PlanetSign), left of the ruler

var balls: Dictionary = {}        # id -> FormulaBody
## id -> start point of the ball's bottom (x, height above the floor, z).
var starts: Dictionary = {}
## The "height" control (all three balls); a height handle changes one ball only.
var height := 5.0
var mass_id := "heavy"
## The signpost showing which world the gravity is (2026-10-28).
var planet_sign: PlanetSign


func _init() -> void:
	props = FreeFallProps.new()


func set_control(id: String, value: Variant) -> void:
	match id:
		"height":
			set_height(float(value))
		"mass":
			set_red_mass(str(value))
		_:
			super(id, value)
			if id == "gravity":
				planet_sign.show_planet(gravity_id)


func control_value(id: String) -> Variant:
	match id:
		"height":
			return height
		"mass":
			return mass_id
	return super(id)


## All three balls start `h` metres above the floor (their bottoms), limited to the slider's range.
func set_height(h: float) -> void:
	var clamped := _clamp_to_control("height", h)
	if is_nan(clamped):
		return
	height = clamped
	for id in ORDER:
		starts[id].y = height
	reset_run()


func set_red_mass(option_id: String) -> void:
	var option := _find_option("mass", option_id)
	if option.is_empty():
		push_warning("free-fall: unknown mass %s" % option_id)
		return
	balls.red.mass = float(option.kg)
	mass_id = option_id
	fall_props().set_look("red", look_radius("red"))
	reset_run()


func fall_props() -> FreeFallProps:
	return props as FreeFallProps


func mass_of(id: String) -> float:
	return balls[id].mass


## Radius ball `id` looks (m): one stuff, the cube root of its mass against LOOK_MASS.
func look_radius(id: String) -> float:
	return BALL_RADIUS * MassLook.factor(mass_of(id), LOOK_MASS)


func reset_run() -> void:
	for id in ORDER:
		var ball: FormulaBody = balls[id]
		hold_ball(ball, starts[id] + Vector3.UP * BALL_RADIUS)
		apply_field(ball)
		fall_props().place_pad(id, starts[id])
	fall_props().place_cat(starts)
	_mark_reset()


func release() -> void:
	if released:
		reset_run()
	for id in ORDER:
		var ball: FormulaBody = balls[id]
		apply_field(ball)
		(ball.corrector as UniformFieldCorrector).release(ball, Vector3.ZERO)
	var first := PackedVector2Array()
	for id in ORDER:
		first.append(Vector2(0.0, starts[id].y))
	_mark_released(first)


func corrector_of(id: String) -> UniformFieldCorrector:
	return balls[id].corrector


## Formula time (s) of the free fall of ball `id` until `landing_time` (INF without a field).
func landing_time(id: String) -> float:
	return PhysicsLaws.landing_time(0.0, -g, starts[id].y)


## Seconds since the release on the fixed-step clock (the time of the last recorded sample).
func clock() -> float:
	if not released:
		return 0.0
	return maxi(0, corrector_of("red").steps - 1) * step_dt()


## The ball has landed: the clock reached its formula landing time, or the engine reported it
## (has_landed_by).
func has_landed(id: String) -> bool:
	return has_landed_by(corrector_of(id), landing_time(id), clock())


## Formula time of one ball: the clock, but never past its landing (the landing once it landed).
func ball_time(id: String) -> float:
	var landing := landing_time(id)
	return landing if has_landed(id) else minf(clock(), landing)


## Formula height of a ball's bottom above the floor at time t (0 from the landing on).
func formula_height(id: String, t: float) -> float:
	if t >= landing_time(id):
		return 0.0
	return maxf(0.0, starts[id].y + PhysicsLaws.constant_acceleration_displacement(0.0, -g, t))


## The time shown: the clock while a ball is still falling, the last formula landing once all landed
## (without a field no ball lands, also not one on the floor: the clock).
func shown_time() -> float:
	if not released:
		return 0.0
	var last := 0.0
	for id in ORDER:
		if not has_landed(id):
			return clock()
		last = maxf(last, landing_time(id))
	return last


func _status_changed(previous: String, current: String) -> void:
	fall_props().status_changed(previous, current)


func status() -> String:
	if not released:
		return "ready"
	if g <= 0.0:
		return "floating"
	for id in ORDER:
		if not has_landed(id):
			return "falling"
	return "landed"


func _released_step() -> void:
	# samples[k] is the drop after k steps; this runs before the balls' own step (tree order).
	var steps := corrector_of("red").steps - 1
	if _graph_sample_time(steps) < 0.0:
		return
	for id in ORDER:
		_append_sample(corrector_of(id), steps, starts[id].y, landing_time(id))


func observations() -> Dictionary:
	var t_red := ball_time("red") if released else 0.0
	var m := mass_of("red")
	var speed := absf(PhysicsLaws.constant_acceleration_velocity(0.0, -g, t_red))
	var h_red := formula_height("red", t_red)
	var fall: Variant = landing_time("red")
	var state_text: String = {
		"ready": "놓기 전",
		"falling": "떨어지는 중",
		"landed": "모두 바닥에 닿음",
		"floating": "무중력: 떠 있어요",
	}.get(status(), "")
	return {
		"g": g,
		"time": shown_time(),
		"red_time": t_red,   # the red ball's own time (its landing once it landed): the kid card and the stamp
		"state": state_text,
		"height_red": h_red,
		"height_purple": formula_height("purple", ball_time("purple") if released else 0.0),
		"height_yellow": formula_height("yellow", ball_time("yellow") if released else 0.0),
		"fall_time": fall if is_finite(fall) else "닿지 않아요",
		"speed": speed,
		"momentum": PhysicsLaws.momentum(m, speed),
		"kinetic": PhysicsLaws.kinetic_energy(m, speed),
		"potential": PhysicsLaws.gravitational_potential_energy(m, g, h_red),
		"landing": measured_landings(),
	}


## Engine landing times of the three balls (the "시뮬레이션" readout): "노랑 1.02 · 보라 … s"; a
## ball shows "—" until it has a measured landing step (measured_landing_step).
func measured_landings() -> String:
	if not released:
		return "—"
	var parts := PackedStringArray()
	for id in ORDER:
		var step := measured_landing_step(corrector_of(id), landing_time(id), clock())
		parts.append("%s %s" % [BALLS[id].name, "%.2f" % (step * step_dt()) if step >= 0 else "—"])
	return " · ".join(parts) + " s"


func graph_series() -> Dictionary:
	var series := {"measured": _measured.duplicate()}
	for id in ORDER:
		series[id] = _formula_line(func(t: float) -> float: return formula_height(id, t), landing_time(id))
	return series


func follow_point() -> Vector3:
	return balls.red.global_position if balls.has("red") else global_position


func _build_world() -> void:
	make_floor(Vector3(30.0, 0.4, 22.0))
	var visuals := {}
	for id in ORDER:
		var spec: Dictionary = BALLS[id]
		var ball := make_ball(id.capitalize(), spec.mass, BOUNCE)
		var visual := ball_visual(spec.color)
		visual.name = "Visual"
		ball.add_child(visual)
		add_child(ball)
		balls[id] = ball
		visuals[id] = [ball, visual]
		starts[id] = Vector3(spec.x, height, 0.0)
	fall_props().dress(self, visuals, BALL_RADIUS * 2.0)
	planet_sign = PlanetSign.new()
	planet_sign.position = SIGN_AT
	add_child(planet_sign)
	for id in ORDER:
		fall_props().set_look(id, look_radius(id))
	for juice: ArtJuice in fall_props().juices.values():
		juice.landed.connect(impact.emit)


# --- manipulation -----------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return balls.get(id.trim_prefix(DROP))


## "line": the floor line under the balls in front of the ruler (0.5 m grid, the balls' `snap` rule).
## "drop_<ball>": the vertical line of that ball's drop, plane x = the height of the ball's bottom over
## the floor in the height slider's range (its 0.5 m step is the objects' `snap`). The frame stands
## upright (x up, its normal towards the front camera) one radius behind the ball, so a ball lifted
## by its radius off the frame is on its own drop line.
func manipulation_surface(surface_id: String) -> ManipSurface:
	var surface: ManipSurface
	if surface_id == "line":
		surface = ManipSurface.new(Transform3D.IDENTITY, Vector2(-LINE_X, 0.0), Vector2(LINE_X, 0.0))
	elif surface_id.begins_with(DROP) and starts.has(surface_id.trim_prefix(DROP)):
		var control := _find_control("height")
		var x: float = starts[surface_id.trim_prefix(DROP)].x
		var frame := Transform3D(Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT), Vector3(x, BALL_RADIUS, -BALL_RADIUS))
		surface = ManipSurface.new(frame, Vector2(float(control.get("min", 0.5)), 0.0), Vector2(float(control.get("max", 8.0)), 0.0))
	else:
		return null
	surface.exclude = [floor_body.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	return fall_props().juices.get(id.trim_prefix(DROP))


## Picked up (also a falling or landed ball): the run stops and every ball waits at its start, so
## the picked one is lifted from its start height (the handle keeps that height); the bread cat
## stands by while the finger holds its ball.
func manipulation_started(id: String) -> void:
	if released:
		reset_run()
	id = id.trim_prefix(DROP)
	fall_props().juices[id].rearm()
	fall_props().set_finger(id, starts)


## A cancelled pick-up: the balls wait at their starts, the cat holds its ball again.
func manipulation_cancelled(id: String) -> void:
	fall_props().finger = ""
	super(id)


## A ball's drop line is its own: no other ball straight above or below it (the two would collide
## in the air, which the per-ball formula does not describe). Neighbours on the 0.5 m grid (sides
## touching) fall side by side and stay allowed. A drop line keeps its ball where it is.
func placement_allowed(id: String, transform: Transform3D) -> bool:
	if id.begins_with(DROP):
		return true
	for other in ORDER:
		if other != id and absf(transform.origin.x - starts[other].x) < BALL_RADIUS * 2.0 - 0.001:
			return false
	return true


func manipulation_placed(id: String, transform: Transform3D) -> void:
	if id.begins_with(DROP):
		# A ball let go on its drop line: all three start at that height (the "height" control).
		fall_props().finger = ""
		set_height(transform.origin.y - BALL_RADIUS)
		return
	_placed = true
	starts[id] = transform.origin - Vector3.UP * BALL_RADIUS
	starts[id].y = snapped_height(starts[id].y)
	var ball: FormulaBody = balls[id]
	hold_ball(ball, starts[id] + Vector3.UP * BALL_RADIUS)
	apply_field(ball)
	fall_props().place_pad(id, starts[id])
	fall_props().set_finger("", starts)
	_graph_revision += 1
	_update_status(true)


## Every ball's start once one was moved (kept across a screen rebuild).
func placements() -> Dictionary:
	if not _placed:
		return {}
	var result := {}
	for id in ORDER:
		result[id] = Transform3D(Basis(), starts[id] + Vector3.UP * BALL_RADIUS)
	return result
