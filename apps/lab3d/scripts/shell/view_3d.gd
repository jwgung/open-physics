## The 3D view of the experiment screen: a SubViewport rendered at the quality tier's resolution
## (Quality.view_pixels_per_unit) and drawn into this rect, plus the camera gestures.
## The UI around it stays at screen resolution (docs/ui-resolution.md).
##
## Gestures (touch): two fingers moving together turn the view (orbit), spreading/pinching zooms
## and moves the view with the fingers (pan), twisting turns it around the vertical axis.
## The gesture is classified once per two-finger touch after GESTURE_SLOP units.
## A single finger on the view is NOT used by the camera: it is reported through
## `single_pointer` for object manipulation (Task 2b).
## Desktop: right drag orbits, middle drag or Shift + right drag pans, wheel zooms; left drag is
## reserved like a single finger. Trackpad pinch/pan gestures zoom/pan.
class_name View3D
extends Control

signal single_pointer(event_type: String, position: Vector2)
signal gesture_used

const GESTURE_SLOP := 14.0

var rig: CameraRig
var viewport: SubViewport

var _display: TextureRect
var _touches: Dictionary = {}      # touch index -> position (local UI units)
var _gesture := ""                 # "", "pending", "orbit", "pinch", "ended" (one finger left)
var _gesture_start_mid := Vector2.ZERO
var _gesture_start_span := 0.0
var _gesture_pair: Array = []      # touch indices of the two fingers the gesture is measured on
var _mouse_mode := ""              # "", "orbit", "pan"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	viewport.size = Vector2i(64, 64)
	add_child(viewport)
	rig = CameraRig.new()
	viewport.add_child(rig)
	rig.current = true
	_display = TextureRect.new()
	_display.texture = viewport.get_texture()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_display)


func _ready() -> void:
	Quality.configure_view(viewport)
	resized.connect(update_resolution)
	get_tree().root.size_changed.connect(update_resolution)
	update_resolution()


## Adds the experiment's 3D world under the SubViewport (it shares the root World3D; the root
## viewport has no camera, so only this view renders it).
func set_world(world: Node3D) -> void:
	viewport.add_child(world)


func update_resolution() -> void:
	if not is_inside_tree() or size.x < 1.0 or size.y < 1.0:
		return
	var pixels := (size * Quality.view_pixels_per_unit()).round()
	viewport.size = Vector2i(maxi(1, int(pixels.x)), maxi(1, int(pixels.y)))
	rig.fit_aspect(size)


## Render target size in pixels (for the UI-resolution measurement log).
func render_size() -> Vector2i:
	return viewport.size


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
		accept_event()
	elif event is InputEventScreenDrag:
		_on_drag(event)
		accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event)
		accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		rig.zoom(1.0 / maxf(event.factor, 0.01))
		gesture_used.emit()
	elif event is InputEventPanGesture:
		rig.pan_by(-event.delta * 8.0)
		gesture_used.emit()


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	match _touches.size():
		0:
			if _gesture == "" and not event.pressed:
				single_pointer.emit("release", event.position)
			_gesture = ""
		1:
			if _gesture != "":
				_gesture = "ended"  # lifting one of two fingers ends the gesture; the other never becomes a drag
			elif event.pressed:
				single_pointer.emit("press", event.position)
		2:
			if event.pressed:
				single_pointer.emit("cancel", event.position)
				_gesture = "pending"
				_gesture_pair = []
	# A third finger landing or one of the first two lifting changes which two fingers count:
	# measure from the new pair so the next drag is not compared with the old one.
	if _touches.size() >= 2 and _gesture != "" and _gesture != "ended":
		var keys := _touches.keys()
		keys.sort()
		if _gesture_pair != [keys[0], keys[1]]:
			_gesture_pair = [keys[0], keys[1]]
			var pair := _pair()
			_gesture_start_mid = (pair[0] + pair[1]) * 0.5
			_gesture_start_span = pair[0].distance_to(pair[1])


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	if _touches.size() == 1:
		_touches[event.index] = event.position
		if _gesture == "":
			single_pointer.emit("move", event.position)
		return
	var before := _pair()
	_touches[event.index] = event.position
	var after := _pair()
	var mid_before := (before[0] + before[1]) * 0.5
	var mid_after := (after[0] + after[1]) * 0.5
	var span_before := before[0].distance_to(before[1])
	var span_after := after[0].distance_to(after[1])
	if _gesture == "pending":
		# Android reports one drag event per finger for each touch frame; classify only once the
		# frame's last finger has moved, never on the half-updated pair in between.
		var keys := _touches.keys()
		keys.sort()
		if event.index != keys[1]:
			return
		var moved := mid_after.distance_to(_gesture_start_mid)
		var spread := absf(span_after - _gesture_start_span)
		if maxf(moved, spread) < GESTURE_SLOP:
			return
		_gesture = "orbit" if moved > spread else "pinch"
		gesture_used.emit()
	match _gesture:
		"orbit":
			rig.orbit(mid_after - mid_before)
		"pinch":
			if span_before > 1.0 and span_after > 1.0:
				rig.zoom(span_before / span_after)
			rig.pan_by(mid_after - mid_before)
			var turn := angle_difference((before[1] - before[0]).angle(), (after[1] - after[0]).angle())
			if absf(turn) > 0.002:
				rig.twist(-turn)


## The two lowest touch indices (extra fingers are ignored).
func _pair() -> Array[Vector2]:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			_mouse_mode = ("pan" if event.shift_pressed else "orbit") if event.pressed else ""
		MOUSE_BUTTON_MIDDLE:
			_mouse_mode = "pan" if event.pressed else ""
		MOUSE_BUTTON_WHEEL_UP:
			rig.zoom(0.9)
			gesture_used.emit()
		MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom(1.1)
			gesture_used.emit()
		MOUSE_BUTTON_LEFT:
			single_pointer.emit("press" if event.pressed else "release", event.position)


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	match _mouse_mode:
		"orbit":
			rig.orbit(event.relative)
			gesture_used.emit()
		"pan":
			rig.pan_by(event.relative)
			gesture_used.emit()
		_:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				single_pointer.emit("move", event.position)
