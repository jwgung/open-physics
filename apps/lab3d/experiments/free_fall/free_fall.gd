## Guided free-fall lab (Phase 1 Task 4a; web preset "free-fall"): three balls of different mass
## (pink 0.5 kg, orange 1 kg, red = the "mass" control, 3 kg by default, like the web's light /
## reference / heavy balls) are dropped together in the chosen field and land at the same time.
## Conditions: gravity (the web's buttons), the drop height of all three (slider) and the red ball's
## mass. Each ball can be dragged sideways along the floor line under it and raised with its height
## handle (web step 1: "세 공의 높이를 맞춰요"). A line, not the floor plane: a ball held 5 m up is
## level with the camera, where a horizontal drag plane at its height would be seen edge-on.
## Motion: Jolt + UniformFieldCorrector (uniform_field_lab.gd). Displayed numbers: PhysicsLaws at the formula time (the landing at landing_time(0, -g, h0)); the engine is
## only the graph's "시뮬레이션" points and the measured landing times.
extends UniformFieldLab

## Left to right. mass: kg (the red one follows the "mass" control).
const BALLS := {
	"pink": {"x": -1.5, "mass": 0.5, "color": ArtPalette.PINK, "name": "분홍"},
	"orange": {"x": 0.0, "mass": 1.0, "color": ArtPalette.ORANGE, "name": "주황"},
	"red": {"x": 1.5, "mass": 3.0, "color": ArtPalette.RED, "name": "빨강"},
}
const ORDER := ["pink", "orange", "red"]
const LINE_X := 3.0              # the balls move along the floor line x = -3..3 m (z = 0)
const BOUNCE := 0.5               # the web's wood balls (restitution 0.5)

var balls: Dictionary = {}        # id -> FormulaBody
## id -> start point of the ball's bottom (x, height above the floor, z).
var starts: Dictionary = {}
## The "height" control (all three balls); a height handle changes one ball only.
var height := 5.0
var mass_id := "heavy"


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


func control_value(id: String) -> Variant:
	match id:
		"height":
			return height
		"mass":
			return mass_id
	return super(id)


## All three balls start `h` metres above the floor (their bottoms), where they stand on the floor.
func set_height(h: float) -> void:
	height = h
	for id in ORDER:
		starts[id].y = h
	reset_run()


func set_red_mass(option_id: String) -> void:
	var option := _find_option("mass", option_id)
	if option.is_empty():
		push_warning("free-fall: unknown mass %s" % option_id)
		return
	balls.red.mass = float(option.kg)
	mass_id = option_id
	reset_run()


func fall_props() -> FreeFallProps:
	return props as FreeFallProps


func mass_of(id: String) -> float:
	return balls[id].mass


func reset_run() -> void:
	for id in ORDER:
		var ball: FormulaBody = balls[id]
		hold_ball(ball, starts[id] + Vector3.UP * BALL_RADIUS)
		apply_field(ball)
		fall_props().place_pad(id, starts[id])
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


## The engine reported the ball's landing (a ball standing on the floor has nothing to fall).
func has_landed(id: String) -> bool:
	return corrector_of(id).landed_step >= 0 or starts[id].y <= 1e-6


## Formula time of one ball: the clock, but never past its landing.
func ball_time(id: String) -> float:
	return minf(clock(), landing_time(id))


## Formula height of a ball's bottom above the floor at time t (0 from the landing on).
func formula_height(id: String, t: float) -> float:
	if t >= landing_time(id):
		return 0.0
	return maxf(0.0, starts[id].y + PhysicsLaws.constant_acceleration_displacement(0.0, -g, t))


## The time shown: the clock while a ball is still falling, the last formula landing once all landed.
func shown_time() -> float:
	if not released:
		return 0.0
	var last := 0.0
	for id in ORDER:
		if not has_landed(id):
			return clock()
		last = maxf(last, landing_time(id))
	return last


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
		if starts[id].y > 1e-6:
			_append_sample(corrector_of(id), steps, starts[id].y)
	_graph_revision += 1


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
		"state": state_text,
		"height_red": h_red,
		"height_orange": formula_height("orange", ball_time("orange") if released else 0.0),
		"height_pink": formula_height("pink", ball_time("pink") if released else 0.0),
		"fall_time": fall if is_finite(fall) else "닿지 않아요",
		"speed": speed,
		"momentum": PhysicsLaws.momentum(m, speed),
		"kinetic": PhysicsLaws.kinetic_energy(m, speed),
		"potential": PhysicsLaws.gravitational_potential_energy(m, g, h_red),
		"landing": measured_landings(),
	}


## Engine landing times of the three balls (the "시뮬레이션" readout): "분홍 1.02 · 주황 … s".
func measured_landings() -> String:
	if not released:
		return "—"
	var parts := PackedStringArray()
	for id in ORDER:
		var step := corrector_of(id).landed_step
		parts.append("%s %s" % [BALLS[id].name, "%.2f" % (step * step_dt()) if step >= 0 else "—"])
	return " · ".join(parts) + " s"


func graph_series() -> Dictionary:
	var series := {"measured": _measured.duplicate()}
	var x_max := graph_x_max()
	for id in ORDER:
		var line := PackedVector2Array()
		var land := landing_time(id)
		for i in 61:
			var t := x_max * i / 60.0
			if t >= land:
				line.append(Vector2(land, 0.0))
				break
			line.append(Vector2(t, formula_height(id, t)))
		series[id] = line
	return series


func follow_point() -> Vector3:
	return balls.red.global_position if balls.has("red") else global_position


func _build_world() -> void:
	make_floor(Vector3(30.0, 0.4, 22.0))
	var visuals := {}
	for id in ORDER:
		var spec: Dictionary = BALLS[id]
		var ball := make_ball(id.capitalize(), spec.mass, BOUNCE)
		var visual := ArtKit.instance(ball_mesh(spec.color))
		visual.name = "Visual"
		ball.add_child(visual)
		add_child(ball)
		balls[id] = ball
		visuals[id] = [ball, visual]
		starts[id] = Vector3(spec.x, height, 0.0)
	fall_props().dress(self, visuals, BALL_RADIUS * 2.0)
	for juice: ArtJuice in fall_props().juices.values():
		juice.landed.connect(impact.emit)


# --- manipulation -----------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return balls.get(id)


## The floor line under the balls in front of the ruler (0.5 m grid, the balls' `snap` rule).
func manipulation_surface(surface_id: String) -> ManipSurface:
	if surface_id != "line":
		return null
	var surface := ManipSurface.new(Transform3D.IDENTITY, Vector2(-LINE_X, 0.0), Vector2(LINE_X, 0.0))
	surface.exclude = [floor_body.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	return fall_props().juices.get(id)


## Picked up (also a falling or landed ball): the run stops and every ball waits at its start, so
## the picked one is lifted from its start height (the handle keeps that height).
func manipulation_started(id: String) -> void:
	if released:
		reset_run()
	fall_props().juices[id].rearm()


func manipulation_placed(id: String, transform: Transform3D) -> void:
	_placed = true
	starts[id] = transform.origin - Vector3.UP * BALL_RADIUS
	var ball: FormulaBody = balls[id]
	hold_ball(ball, transform.origin)
	apply_field(ball)
	fall_props().place_pad(id, starts[id])
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
