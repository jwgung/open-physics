## Shell camera: six modes with smooth transitions, limited orbit, zoom and pan.
## Modes: front (정면), three_quarter (3/4), top (위), side (옆), follow (따라가기, tracks
## follow_source.follow_point()), orbit (제한 회전: wherever the user turned it, within the
## experiment's yaw/pitch limits). Preset views and limits come from the experiment's
## definition.camera. Gestures change the view directly (no lag); mode switches ease over
## ~0.4 s. Angles: yaw 0 looks along -z (camera on +z), pitch < 0 is above the target.
class_name CameraRig
extends Camera3D

signal mode_changed(mode: String)

const MODES := ["front", "three_quarter", "top", "side", "follow", "orbit"]
const MODE_LABELS := {
	"front": "정면", "three_quarter": "3/4", "top": "위", "side": "옆",
	"follow": "따라가기", "orbit": "제한 회전",
}
const EASE_RATE := 8.0          # 1/s; ~95% of a transition in 0.37 s
const ORBIT_RAD_PER_UNIT := 0.006
const PAN_PER_UNIT := 0.0016    # world units per UI unit per metre of distance
## Landing dip (nudge): a damped spring on a vertical offset of the drawn view only, so it never
## changes the mode, the goal or the limits. Full strength dips ~5 cm and settles in ~0.2 s.
const NUDGE_SPEED := 2.4        # m/s downward kick at strength 1
const NUDGE_K := 300.0
const NUDGE_DAMP := 20.0

var mode := "front"
var follow_source: Object       # any object with follow_point() -> Vector3 (the experiment)

var base_target := Vector3.ZERO
var default_distance := 10.0
var distance_range := Vector2(3.0, 30.0)
var yaw_range := Vector2(-PI, PI)
var pitch_range := Vector2(deg_to_rad(-89.0), deg_to_rad(-2.0))
var pan_radius := 5.0
var views: Dictionary = {}

# goal_* is where the camera is heading; cur_* is what is drawn.
var goal_yaw := 0.0
var goal_pitch := -0.2
var goal_distance := 10.0
var pan := Vector3.ZERO
var cur_yaw := 0.0
var cur_pitch := -0.2
var cur_distance := 10.0
var cur_target := Vector3.ZERO
var shake := 0.0                # vertical offset of the drawn view (m), see nudge()
var _shake_v := 0.0
## Manipulation assist (begin_assist): the goal view before the correction, and the follow
## target held still while an object is dragged.
var _assist_saved: Dictionary = {}
var _assist_active := false
var _held_target := Vector3.ZERO


## Reads definition.camera (see content/experiments/*.json) and jumps to the default mode.
func configure(camera: Dictionary) -> void:
	var t: Array = camera.get("target", [0, 0, 0])
	base_target = Vector3(t[0], t[1], t[2])
	default_distance = camera.get("distance", 10.0)
	var d: Array = camera.get("distance_range", [3.0, 30.0])
	distance_range = Vector2(d[0], d[1])
	var y: Array = camera.get("yaw_range_deg", [-180.0, 180.0])
	yaw_range = Vector2(deg_to_rad(y[0]), deg_to_rad(y[1]))
	var p: Array = camera.get("pitch_range_deg", [-89.0, -2.0])
	pitch_range = Vector2(deg_to_rad(p[0]), deg_to_rad(p[1]))
	pan_radius = camera.get("pan_radius", 5.0)
	views = camera.get("views", {})
	set_mode(camera.get("default_mode", "front"), true)


func _ready() -> void:
	fov = 50.0
	_apply()


## Portrait views keep the horizontal field of view so the apparatus stays in frame.
func fit_aspect(view_size: Vector2) -> void:
	keep_aspect = Camera3D.KEEP_WIDTH if view_size.x < view_size.y else Camera3D.KEEP_HEIGHT


## Switches mode. Preset modes reset pan and zoom to the preset ("정면으로" is set_mode("front")).
## `instant` skips the transition.
func set_mode(new_mode: String, instant := false) -> void:
	if new_mode not in MODES:
		push_warning("CameraRig: unknown mode %s" % new_mode)
		return
	if new_mode != "orbit":
		var view: Dictionary = views.get(new_mode, {})
		goal_yaw = clampf(deg_to_rad(view.get("yaw_deg", 0.0)), yaw_range.x, yaw_range.y)
		goal_pitch = clampf(deg_to_rad(view.get("pitch_deg", -10.0)), pitch_range.x, pitch_range.y)
		goal_distance = clampf(view.get("distance", default_distance), distance_range.x, distance_range.y)
		pan = Vector3.ZERO
	_assist_saved = {}   # the new mode wins: end_assist() must not turn the view back to the old one
	var changed := new_mode != mode
	mode = new_mode   # before snap(): follow targets depend on the mode
	if instant:
		snap()
	if changed:
		mode_changed.emit(mode)


## Two-finger drag / right-mouse drag (UI units). Turning leaves a preset view for "orbit"
## (follow keeps following).
func orbit(relative: Vector2) -> void:
	# The drawn view moves by the same delta as the goal, so a gesture during a mode transition
	# neither jumps to the goal nor drops the rest of the transition.
	var yaw := clampf(goal_yaw - relative.x * ORBIT_RAD_PER_UNIT, yaw_range.x, yaw_range.y)
	var pitch := clampf(goal_pitch - relative.y * ORBIT_RAD_PER_UNIT, pitch_range.x, pitch_range.y)
	cur_yaw += yaw - goal_yaw
	cur_pitch += pitch - goal_pitch
	_assist_saved = {}   # the user's own view wins: end_assist() must not turn it back
	goal_yaw = yaw
	goal_pitch = pitch
	if mode != "orbit" and mode != "follow":
		mode = "orbit"
		mode_changed.emit(mode)


## Twist (radians, counter-clockwise on screen) turns the view around the vertical axis.
func twist(radians: float) -> void:
	orbit(Vector2(radians / ORBIT_RAD_PER_UNIT, 0.0))


## factor < 1 zooms in.
func zoom(factor: float) -> void:
	var distance := clampf(goal_distance * factor, distance_range.x, distance_range.y)
	cur_distance += distance - goal_distance
	goal_distance = distance


## Moves the look-at point in the screen plane (UI units), keeping it within pan_radius.
func pan_by(relative: Vector2) -> void:
	var basis_now := global_transform.basis
	var right := basis_now.x
	var up := basis_now.y
	var step := PAN_PER_UNIT * cur_distance
	var before := pan
	pan += (-right * relative.x + up * relative.y) * step
	if pan.length() > pan_radius:
		pan = pan.normalized() * pan_radius
	cur_target += pan - before  # same delta as the goal, like orbit()


## Small camera dip when something lands (strength 0..1). Visual only.
func nudge(strength: float) -> void:
	_shake_v -= NUDGE_SPEED * clampf(strength, 0.0, 1.0)


## Manipulation assist (Task 2b, apps/lab3d/README.md "보조 시점"): while an object is dragged the
## view must show the surface it moves on. If the current goal view looks at the plane with
## `plane_normal` at less than ASSIST_PLANE_DEG, or along `line_axis` (a line the object moves on,
## or the height handle's vertical) within ASSIST_LINE_DEG, the goal turns to the nearest yaw/pitch
## inside the experiment's limits that satisfies both (pass Vector3.ZERO to skip one). A view that
## already satisfies them is left alone. The follow target is held still until end_assist(), so
## the camera does not chase the object under the finger. Returns true if the view was turned.
const ASSIST_PLANE_DEG := 25.0
const ASSIST_LINE_DEG := 35.0
const ASSIST_STEP_DEG := 5.0
## Number of assist_ok() evaluations so far (tests: the search must stay small).
static var assist_checks := 0
const ASSIST_REFINE_STEPS := 5   # bisection steps pulling the found view back toward the goal


func begin_assist(plane_normal: Vector3, line_axis: Vector3) -> bool:
	_held_target = _goal_target()
	_assist_active = true
	_assist_saved = {}
	if assist_ok(goal_yaw, goal_pitch, plane_normal, line_axis):
		return false
	var found := _nearest_assist_view(plane_normal, line_axis)
	if found.is_empty():
		return false
	_assist_saved = {"yaw": goal_yaw, "pitch": goal_pitch}
	goal_yaw = found.yaw
	goal_pitch = found.pitch
	return true


## The satisfying view nearest to the goal view (cost = yaw change + pitch change), inside the
## limits, or {} if there is none. Searches outward in ASSIST_STEP_DEG steps around the goal view and
## stops once no closer view is possible (a typical turn needs a few dozen checks, not the whole
## range), then pulls the best view back toward the goal along each axis as far as it still
## satisfies (so the turn is no bigger than needed).
func _nearest_assist_view(plane_normal: Vector3, line_axis: Vector3) -> Dictionary:
	var step := deg_to_rad(ASSIST_STEP_DEG)
	var full_circle := yaw_range.y - yaw_range.x >= TAU - 0.001
	var yaw_reach := PI if full_circle else yaw_range.y - yaw_range.x
	var best_cost := INF
	var best_yaw := 0.0
	var best_pitch := 0.0
	var k := 0
	while k * step <= yaw_reach + 0.0001 and k * step < best_cost:
		var d := k * step
		for side in ([1.0] if k == 0 else [1.0, -1.0]):
			var yaw: float = goal_yaw + side * d
			if full_circle:
				yaw = wrapf(yaw, yaw_range.x, yaw_range.x + TAU)
			elif yaw < yaw_range.x - 0.0001 or yaw > yaw_range.y + 0.0001:
				continue
			var j := 0
			while d + j * step < best_cost and j * step <= pitch_range.y - pitch_range.x + 0.0001:
				var hit := false
				for pitch_side in ([1.0] if j == 0 else [1.0, -1.0]):
					var pitch: float = goal_pitch + pitch_side * j * step
					if pitch < pitch_range.x - 0.0001 or pitch > pitch_range.y + 0.0001:
						continue
					if assist_ok(yaw, pitch, plane_normal, line_axis):
						best_cost = d + j * step
						best_yaw = yaw
						best_pitch = pitch
						hit = true
						break
				if hit:
					break
				j += 1
		k += 1
	if best_cost == INF:
		return {}
	# Refine: bisect the pitch, then the yaw, back toward the goal (the grid overshoots the limit
	# of the satisfying region by up to a step).
	var pitch_back := best_pitch - goal_pitch
	var lo := 0.0
	var hi := 1.0
	for i in ASSIST_REFINE_STEPS:
		var mid := (lo + hi) * 0.5
		if assist_ok(best_yaw, goal_pitch + pitch_back * mid, plane_normal, line_axis):
			hi = mid
		else:
			lo = mid
	best_pitch = goal_pitch + pitch_back * hi
	var yaw_back := angle_difference(goal_yaw, best_yaw)
	lo = 0.0
	hi = 1.0
	for i in ASSIST_REFINE_STEPS:
		var mid := (lo + hi) * 0.5
		if assist_ok(goal_yaw + yaw_back * mid, best_pitch, plane_normal, line_axis):
			hi = mid
		else:
			lo = mid
	var yaw_goal := goal_yaw + yaw_back * hi
	if full_circle:
		yaw_goal = wrapf(yaw_goal, yaw_range.x, yaw_range.x + TAU)
	return {"yaw": yaw_goal, "pitch": best_pitch}


## Ends the assist: a turned view eases back to where it was (unless the user turned the view
## meanwhile, see orbit()), the follow target moves again.
func end_assist() -> void:
	if not _assist_saved.is_empty():
		goal_yaw = _assist_saved.yaw
		goal_pitch = _assist_saved.pitch
	_assist_saved = {}
	_assist_active = false


func is_assisting() -> bool:
	return _assist_active


## Whether a view at (yaw, pitch) sees the plane / line well enough (see begin_assist).
static func assist_ok(yaw: float, pitch: float, plane_normal: Vector3, line_axis: Vector3) -> bool:
	assist_checks += 1
	var look := view_direction(yaw, pitch)
	if plane_normal != Vector3.ZERO and absf(look.dot(plane_normal.normalized())) < sin(deg_to_rad(ASSIST_PLANE_DEG)):
		return false
	if line_axis != Vector3.ZERO and absf(look.dot(line_axis.normalized())) > cos(deg_to_rad(ASSIST_LINE_DEG)):
		return false
	return true


## Unit direction the camera looks in at (yaw, pitch) (from the eye to the target).
static func view_direction(yaw: float, pitch: float) -> Vector3:
	return -Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))


## Mode and view, to rebuild the camera later (App keeps it across a 3D view rebuild). During an
## assist this is the view the user had before it (the one end_assist() returns to), or the
## current goal view when the user turned it meanwhile.
func get_state() -> Dictionary:
	var yaw: float = _assist_saved.get("yaw", goal_yaw)
	var pitch: float = _assist_saved.get("pitch", goal_pitch)
	return {"mode": mode, "yaw": yaw, "pitch": pitch, "distance": goal_distance, "pan": pan}


func set_state(state: Dictionary) -> void:
	var saved: String = state.get("mode", mode)
	if saved not in MODES:
		return
	goal_yaw = state.get("yaw", goal_yaw)
	goal_pitch = state.get("pitch", goal_pitch)
	goal_distance = state.get("distance", goal_distance)
	pan = state.get("pan", pan)
	var changed := saved != mode
	mode = saved
	snap()
	if changed:
		mode_changed.emit(mode)


func snap() -> void:
	cur_yaw = goal_yaw
	cur_pitch = goal_pitch
	cur_distance = goal_distance
	cur_target = _goal_target()
	_apply()


func is_settled(epsilon := 0.001) -> bool:
	return absf(angle_difference(cur_yaw, goal_yaw)) < epsilon and absf(cur_pitch - goal_pitch) < epsilon \
		and absf(cur_distance - goal_distance) < epsilon * 10.0 and cur_target.distance_to(_goal_target()) < epsilon * 10.0


func _goal_target() -> Vector3:
	if _assist_active:
		return _held_target
	if mode == "follow" and follow_source != null and is_instance_valid(follow_source):
		return follow_source.follow_point() + pan
	return base_target + pan


func _process(delta: float) -> void:
	var t := 1.0 - exp(-EASE_RATE * delta)
	cur_yaw = lerp_angle(cur_yaw, goal_yaw, t)
	cur_pitch = lerpf(cur_pitch, goal_pitch, t)
	cur_distance = lerpf(cur_distance, goal_distance, t)
	cur_target = cur_target.lerp(_goal_target(), t)
	if shake != 0.0 or _shake_v != 0.0:
		var dt := minf(delta, 1.0 / 30.0)
		_shake_v += (-NUDGE_K * shake - NUDGE_DAMP * _shake_v) * dt
		shake += _shake_v * dt
		if absf(shake) < 0.0001 and absf(_shake_v) < 0.001:
			shake = 0.0
			_shake_v = 0.0
	_apply()


func _apply() -> void:
	var offset := Vector3(sin(cur_yaw) * cos(cur_pitch), -sin(cur_pitch), cos(cur_yaw) * cos(cur_pitch)) * cur_distance
	var target := cur_target + Vector3(0.0, shake, 0.0)
	var eye := target + offset
	# Straight down: use -z as "up" so the top view keeps the front view's left/right.
	var up := Vector3.UP if absf(cur_pitch) < deg_to_rad(88.5) else Vector3(-sin(cur_yaw), 0.0, -cos(cur_yaw))
	if eye.is_equal_approx(target):
		return
	look_at_from_position(eye, target, up)
