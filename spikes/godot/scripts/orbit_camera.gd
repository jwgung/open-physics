## Orbit camera: two-finger drag orbits, pinch zooms (touch); right-drag / wheel on desktop.
## Single-finger and left-mouse input are left to the scene (object drag).
class_name OrbitCamera
extends Camera3D

signal single_pointer(event_type: String, screen_position: Vector2)

@export var target := Vector3.ZERO
@export var distance := 16.0
@export var yaw := 0.6
@export var pitch := -0.5
@export var min_distance := 4.0
@export var max_distance := 40.0

var _touches: Dictionary = {}
var _orbiting_with_mouse := false


func _ready() -> void:
	keep_aspect = Camera3D.KEEP_WIDTH
	fov = 60.0
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() <= 1:
			single_pointer.emit("press" if event.pressed else "release", event.position)
		else:
			single_pointer.emit("cancel", event.position)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		if _touches.size() >= 2:
			_two_finger_drag(event.index, event.position)
		else:
			_touches[event.index] = event.position
			single_pointer.emit("move", event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting_with_mouse = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.1)
			MOUSE_BUTTON_LEFT:
				single_pointer.emit("press" if event.pressed else "release", event.position)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _orbiting_with_mouse:
			_orbit(event.relative)
		elif event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			single_pointer.emit("move", event.position)


func _two_finger_drag(index: int, new_position: Vector2) -> void:
	var keys := _touches.keys()
	var other_index: int = keys[0] if keys[0] != index else keys[1]
	var other: Vector2 = _touches[other_index]
	var old_position: Vector2 = _touches[index]
	var old_span := old_position.distance_to(other)
	var new_span := new_position.distance_to(other)
	_touches[index] = new_position
	_orbit((new_position - old_position) * 0.5)
	if old_span > 1.0 and new_span > 1.0:
		_zoom(old_span / new_span)


func _orbit(relative: Vector2) -> void:
	yaw -= relative.x * 0.008
	pitch = clampf(pitch - relative.y * 0.006, -1.45, -0.08)
	_apply()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)
	_apply()


func _apply() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	look_at_from_position(target + offset, target, Vector3.UP)
