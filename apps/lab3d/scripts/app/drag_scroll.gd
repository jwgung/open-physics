## Drag-to-scroll for a ScrollContainer full of buttons, check boxes and sliders (2026-10-29 user
## report "설정 스크롤이 왜 안되는 부분이 많지?").
##
## Why a drag often did not scroll: Godot's ScrollContainer scrolls by a finger only from the events
## that reach its own gui_input (and only on a touchscreen). A press on a Button, CheckBox or Slider
## (mouse_filter STOP, the default) is taken by that control: the touch, its emulated click and the
## whole drag go to it and never reach the scroller. The settings page is mostly such controls (the
## three big quality cards are buttons), so most drags did nothing, and a drag that ended on the
## same button pressed it; a press on a slider even changed its value.
##
## This node (a child of the scroller, Ui.scroller adds it) watches the pointer before the GUI
## (_input). A press inside the scroller (the first finger's touch and its emulated click, or the
## desktop's left button) is held back; then
##   - the finger moves more than SLOP and mostly vertically: the list follows the finger (and keeps
##     a little momentum after the lift); the held press is dropped, so no button, check box or
##     slider under the finger reacts;
##   - it moves more than SLOP sideways: the held events go to the GUI, in order, and the drag goes
##     on as usual (a slider drags);
##   - it lifts within SLOP: a tap. The held press and the release go to the GUI: the control under
##     the finger is pressed as before.
## Held events go on right after the input pass that decided (an event pushed from inside _input
## would end the pass of the one being handled). The scroll bar itself and the wheel are left alone.
class_name DragScroll
extends Node

const SLOP := 12.0                   # UI units a press may move and still be a tap
const FLING_MAX := 2400.0            # UI units/s the list may keep after the lift
const FLING_DECAY := 6.0             # 1/s: the momentum fades like exp(-FLING_DECAY t)
const FLING_MIN := 30.0              # UI units/s below which the list stops
const FLING_WINDOW := 0.1            # s of the finger's last moves the momentum is measured over

var scroll: ScrollContainer
## "" (idle), "pending" (pressed, not decided), "scrolling", "flushing" (the held events go on after
## this pass), "passed" (the GUI has the gesture).
var state := ""
var scrolls := 0                     # drags that scrolled (tests)
var _held: Array[InputEvent] = []
var _ended := false                  # the held events end with the lift
var _end_frame := -1                 # the frame a scroll ended (its other release is swallowed too)
var _start := Vector2.ZERO
var _from := 0.0
var _replaying := false
var _samples: Array = []             # [clock s, finger y] of the last moves
var _clock := 0.0                    # s of frames (the process delta: steady in tests)
var _fling := 0.0
var _fling_at := 0.0


## Adds the watcher to `target` (once).
static func attach(target: ScrollContainer) -> DragScroll:
	var node := DragScroll.new()
	node.name = "DragScroll"
	node.scroll = target
	target.add_child(node, false, Node.INTERNAL_MODE_BACK)
	return node


func _exit_tree() -> void:
	state = ""
	_held.clear()
	_fling = 0.0


## "down", "move", "up" for the first finger's touch / drag and the left button's press / move /
## release; "" for anything else (other fingers, other buttons, a hover).
static func pointer_kind(event: InputEvent) -> String:
	if event is InputEventScreenTouch:
		return ("down" if event.pressed else "up") if (event as InputEventScreenTouch).index == 0 else ""
	if event is InputEventScreenDrag:
		return "move" if (event as InputEventScreenDrag).index == 0 else ""
	if event is InputEventMouseButton:
		return ("down" if event.pressed else "up") if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT else ""
	if event is InputEventMouseMotion:
		return "move" if (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT else ""
	return ""


func _input(event: InputEvent) -> void:
	if _replaying or scroll == null:
		return
	var kind := pointer_kind(event)
	if kind == "":
		return
	var at: Vector2 = event.position
	match state:
		"":
			if kind == "down" and _inside(at):
				_fling = 0.0
				state = "pending"
				_held = [event.duplicate()]
				_ended = false
				_start = at
				_from = float(scroll.scroll_vertical)
				_samples = [[_clock, at.y]]
				_consume()
			elif kind == "up" and _end_frame == Engine.get_process_frames():
				_consume()   # a scroll's other release (the touch's and its click's)
		"pending":
			match kind:
				"down":
					_held.append(event.duplicate())   # the touch's emulated click
					_consume()
				"up":   # a tap: the held press, then the release, to the control under the finger
					_held.append(event.duplicate())
					_flush(true)
				"move":
					var moved := at - _start
					if absf(moved.y) > SLOP and absf(moved.y) >= absf(moved.x):
						state = "scrolling"
						scrolls += 1
						_held.clear()
						_follow(at.y)
						_consume()
					elif absf(moved.x) > SLOP:   # sideways: the control's own drag (a slider)
						_held.append(event.duplicate())
						_flush(false)
					else:
						_consume()
		"scrolling":
			match kind:
				"move":
					_follow(at.y)
				"up":
					state = ""
					_end_frame = Engine.get_process_frames()
					_fling = clampf(_release_speed(), -FLING_MAX, FLING_MAX)
					_fling_at = float(scroll.scroll_vertical)
			_consume()
		"flushing":
			_held.append(event.duplicate())   # kept in order behind the held ones
			_ended = _ended or kind == "up"
			_consume()
		"passed":
			if kind == "up":
				state = ""


func _consume() -> void:
	get_viewport().set_input_as_handled()


## The held events go to the GUI right after this input pass (in order, at their own points).
func _flush(ends: bool) -> void:
	state = "flushing"
	_ended = ends
	_consume()
	_push_held.call_deferred()


func _push_held() -> void:
	if not is_inside_tree() or state != "flushing":
		return
	var events := _held.duplicate()
	_held.clear()
	state = "" if _ended else "passed"
	_replaying = true
	for e: InputEvent in events:
		get_viewport().push_input(e, true)
	_replaying = false


## The content follows the finger from where it was at the press.
func _follow(y: float) -> void:
	_samples.append([_clock, y])
	while _samples.size() > 2 and _clock - float(_samples[0][0]) > FLING_WINDOW:
		_samples.pop_front()
	scroll.scroll_vertical = int(round(_from - (y - _start.y)))


## The content's speed at the lift (UI units/s): the finger's way over its last FLING_WINDOW; none
## when it stood still that long before lifting.
func _release_speed() -> float:
	if _samples.size() < 2 or _clock - float(_samples[-1][0]) > FLING_WINDOW:
		return 0.0
	var dt := float(_samples[-1][0]) - float(_samples[0][0])
	if dt < 0.015:
		return 0.0
	return -(float(_samples[-1][1]) - float(_samples[0][1])) / dt


func _process(delta: float) -> void:
	_clock += delta
	if _fling == 0.0 or state != "":
		return
	_fling_at += _fling * delta
	_fling *= exp(-FLING_DECAY * delta)
	var before := scroll.scroll_vertical
	scroll.scroll_vertical = int(round(_fling_at))
	if absf(_fling) < FLING_MIN or (scroll.scroll_vertical == before and int(round(_fling_at)) != before):
		_fling = 0.0   # slow, or at an end


## Inside the visible scroller, not on its scroll bar.
func _inside(at: Vector2) -> bool:
	if not scroll.is_visible_in_tree() or not scroll.get_global_rect().has_point(at):
		return false
	var bar := scroll.get_v_scroll_bar()
	return not (bar != null and bar.is_visible_in_tree() and bar.get_global_rect().has_point(at))
