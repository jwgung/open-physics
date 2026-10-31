## The hand guide (2026-10-30 user request: young children need a guide to the controls): a soft white hand
## over the 3D view shows the gesture the child should make on the real object, so no reading is
## needed. It is a picture only: it never presses, moves a body or changes a control.
##
## Gestures (play()):
## - "drag": the finger presses on `from`, carries it to `to` and lifts (끌었다 놓기),
## - "pull": the same, then a short arrow from `from` away from the pull shows where it flies (the slingshot),
## - "hold": the finger presses on `from` and stays while a ring fills (꾹 누르기),
## - "tap": the finger taps `from` (지도의 장소 누르기).
## `from` and `to` are callables returning view points (UI units), read every frame, so the hand stays
## on the object while the camera eases. One play shows the gesture `cycles` times, then the hand goes.
class_name HandGuide
extends Control

const KINDS := ["drag", "pull", "hold", "tap"]
const FADE_S := 0.25
const PRESS_S := 0.2
const MOVE_S := 1.0
const HOLD_S := 1.4
const LIFT_S := 0.25
const REST_S := 0.35
const SIZE := 1.0             # drawing scale (UI units per unit of the shapes below)
const PRESS_SCALE := 0.88     # the hand a little smaller while pressing (it "goes into" the glass)
const RING_RADIUS := 26.0
const ARROW_LENGTH := 70.0
const SKIN := Color(1.0, 1.0, 1.0, 0.95)
const LINE := Color(0.18, 0.2, 0.3, 0.9)
const RING := Color(1.0, 0.85, 0.3, 0.95)
const TRAIL := Color(1.0, 1.0, 1.0, 0.55)

## The gesture shown now ("" when none).
var kind := ""
## The fingertip on the view now (UI units; tests).
var tip := Vector2.ZERO
## Gestures shown so far (tests).
var plays := 0
var _from := Callable()
var _to := Callable()
var _cycles := 0
var _t := 0.0


func _init() -> void:
	name = "HandGuide"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Shows `gesture` (KINDS) `cycles` times. `to` is needed for "drag" and "pull".
func play(gesture: String, from: Callable, to := Callable(), cycles := 2) -> void:
	if gesture not in KINDS or not from.is_valid() or (gesture in ["drag", "pull"] and not to.is_valid()):
		return
	kind = gesture
	_from = from
	_to = to
	_cycles = maxi(1, cycles)
	_t = 0.0
	plays += 1
	visible = true
	_place()


## The hand goes at once (a touch, a question, the sidebar).
func stop() -> void:
	kind = ""
	visible = false
	queue_redraw()


func playing() -> bool:
	return kind != ""


## One cycle's length (s).
func cycle_s() -> float:
	match kind:
		"drag", "pull":
			return FADE_S + PRESS_S + MOVE_S + LIFT_S + FADE_S + REST_S
		"hold":
			return FADE_S + PRESS_S + HOLD_S + LIFT_S + FADE_S + REST_S
	return FADE_S + PRESS_S + LIFT_S + FADE_S + REST_S


func _process(delta: float) -> void:
	step(delta)


## Advances the gesture (tests call it directly).
func step(delta: float) -> void:
	if kind == "":
		return
	_t += delta
	if _t >= cycle_s() * _cycles:
		stop()
		return
	_place()


## Where the hand is in its cycle: [fingertip, alpha, pressed 0..1, progress of the hold or move 0..1].
func _pose() -> Array:
	var c := fmod(_t, cycle_s())
	var start: Vector2 = _from.call()
	var goal: Vector2 = _to.call() if _to.is_valid() else start
	var moves := kind in ["drag", "pull"]
	var middle := MOVE_S if moves else (HOLD_S if kind == "hold" else 0.0)
	var marks: Array[float] = [FADE_S, FADE_S + PRESS_S, FADE_S + PRESS_S + middle, FADE_S + PRESS_S + middle + LIFT_S,
		FADE_S + PRESS_S + middle + LIFT_S + FADE_S]
	if c < marks[0]:
		return [start + Vector2(0.0, 10.0 * (1.0 - c / FADE_S)), c / FADE_S, 0.0, 0.0]
	if c < marks[1]:
		return [start, 1.0, (c - marks[0]) / PRESS_S, 0.0]
	if c < marks[2]:
		var k: float = (c - marks[1]) / middle
		var eased := k * k * (3.0 - 2.0 * k)
		return [start.lerp(goal, eased) if moves else start, 1.0, 1.0, k]
	var end := goal if moves else start
	if c < marks[3]:
		return [end, 1.0, 1.0 - (c - marks[2]) / LIFT_S, 1.0]
	if c < marks[4]:
		return [end + Vector2(0.0, 10.0 * (c - marks[3]) / FADE_S), 1.0 - (c - marks[3]) / FADE_S, 0.0, 1.0]
	return [end, 0.0, 0.0, 1.0]


func _place() -> void:
	var pose := _pose()
	tip = pose[0]
	modulate.a = clampf(pose[1], 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if kind == "":
		return
	var pose := _pose()
	var start: Vector2 = _from.call()
	var pressed: float = pose[2]
	var progress: float = pose[3]
	if kind in ["drag", "pull"] and _to.is_valid():
		var goal: Vector2 = _to.call()
		_dotted(start, goal, TRAIL)
		if kind == "pull" and progress >= 1.0:
			# Where the throw goes: away from the pull.
			var away := (start - goal).normalized() * ARROW_LENGTH
			_arrow(start, start + away)
	if kind == "hold" and pressed > 0.0:
		draw_arc(start, RING_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * progress, 32, RING, 6.0, true)
	if pressed > 0.0 and kind != "hold":
		draw_arc(pose[0], RING_RADIUS * (0.6 + 0.4 * pressed), 0.0, TAU, 32, Color(RING, 0.6 * pressed), 3.0, true)
	_hand(pose[0], lerpf(1.0, PRESS_SCALE, pressed))


## A pointing hand with its index fingertip at `at` (the touch point), drawn with an outline.
func _hand(at: Vector2, scale_k: float) -> void:
	var s := SIZE * scale_k
	draw_set_transform(at, 0.0, Vector2.ONE * s)
	for pass_i in 2:
		var grow := 3.0 if pass_i == 0 else 0.0
		var color := LINE if pass_i == 0 else SKIN
		_capsule(Vector2(0.0, 2.0), Vector2(0.0, 30.0), 7.5 + grow, color)       # index finger
		_capsule(Vector2(12.0, 26.0), Vector2(12.0, 40.0), 6.5 + grow, color)    # middle finger (folded)
		_capsule(Vector2(22.0, 30.0), Vector2(22.0, 42.0), 6.0 + grow, color)    # ring finger
		_capsule(Vector2(-11.0, 40.0), Vector2(-4.0, 52.0), 6.5 + grow, color)   # thumb
		draw_rect(Rect2(Vector2(-8.0 - grow, 30.0 - grow), Vector2(36.0 + grow * 2.0, 30.0 + grow * 2.0)), color)
		draw_circle(Vector2(10.0, 60.0), 18.0 + grow, color)                     # palm
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _capsule(a: Vector2, b: Vector2, radius: float, color: Color) -> void:
	draw_line(a, b, color, radius * 2.0)
	draw_circle(a, radius, color)
	draw_circle(b, radius, color)


func _dotted(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var n := int(length / 14.0)
	for i in n + 1:
		draw_circle(a.lerp(b, float(i) / maxf(1.0, float(n))), 3.0, color)


func _arrow(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, RING, 6.0, true)
	var d := (b - a).normalized()
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([b + d * 12.0, b - d * 6.0 + side * 10.0, b - d * 6.0 - side * 10.0]), RING)
