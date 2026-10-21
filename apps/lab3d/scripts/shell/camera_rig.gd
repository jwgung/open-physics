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
	snap()


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
	pan += (-right * relative.x + up * relative.y) * step
	if pan.length() > pan_radius:
		pan = pan.normalized() * pan_radius
	cur_target = _goal_target()


## Mode and view, to rebuild the camera later (App keeps it across a 3D view rebuild).
func get_state() -> Dictionary:
	return {"mode": mode, "yaw": goal_yaw, "pitch": goal_pitch, "distance": goal_distance, "pan": pan}


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
	if mode == "follow" and follow_source != null and is_instance_valid(follow_source):
		return follow_source.follow_point() + pan
	return base_target + pan


func _process(delta: float) -> void:
	var t := 1.0 - exp(-EASE_RATE * delta)
	cur_yaw = lerp_angle(cur_yaw, goal_yaw, t)
	cur_pitch = lerpf(cur_pitch, goal_pitch, t)
	cur_distance = lerpf(cur_distance, goal_distance, t)
	cur_target = cur_target.lerp(_goal_target(), t)
	_apply()


func _apply() -> void:
	var offset := Vector3(sin(cur_yaw) * cos(cur_pitch), -sin(cur_pitch), cos(cur_yaw) * cos(cur_pitch)) * cur_distance
	var eye := cur_target + offset
	# Straight down: use -z as "up" so the top view keeps the front view's left/right.
	var up := Vector3.UP if absf(cur_pitch) < deg_to_rad(88.5) else Vector3(-sin(cur_yaw), 0.0, -cos(cur_yaw))
	if eye.is_equal_approx(cur_target):
		return
	look_at_from_position(eye, cur_target, up)
