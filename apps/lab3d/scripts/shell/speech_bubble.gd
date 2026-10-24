## Dugi's speech bubble over the 3D view (Phase 1 Task 4h): a small card with his name and the
## lab's observe text (the sidebar's 관찰 포인트, the same words), and a tail towards him. The screen
## places it every frame from where Dugi is on the view (place()): above his ears when that is clear
## of the title, key cards and top buttons, else beside him; always inside the view and clear of the
## actions. UI only (no full-screen layer), it never takes input.
class_name SpeechBubble
extends Control

const MAX_WIDTH := 360.0
const MIN_WIDTH := 240.0
const GAP := 10.0                   # between the bubble and Dugi
const TAIL := 12.0                  # tail length
const TAIL_HALF := 9.0

var card: PanelContainer
var name_label: Label
var label: Label
## Where the tail points (local), set by place().
var _tail_to := Vector2.ZERO
var _tail_side := "bottom"          # bottom / left / right
var _tail: Control
var _last := -1                     # index of the spot used last frame (-1: none)


func _init(text: String) -> void:
	name = "SpeechBubble"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	card = Ui.panel("SpeechBubble")
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var stack := Ui.vbox(2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stack)
	name_label = Ui.label("두기두기", "SpeechNameLabel")
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(name_label)
	label = Ui.label(text, "SpeechLabel", true)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	_tail = Control.new()
	_tail.name = "Tail"
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tail)
	_tail.draw.connect(_draw_tail)


## Lays the bubble out for Dugi's on-view rect `who` inside `view` (local units), away from the
## `avoid` rects (overlays) and the `keep` points (what he points at). Tries above him (centred,
## then reaching out to either side), then beside him (the roomier side first). Returns false when
## no clear spot exists (then the caller hides it).
func place(who: Rect2, view: Rect2, avoid: Array[Rect2], margin: float, keep: Array[Vector2] = []) -> bool:
	var width := clampf(view.size.x * 0.34, MIN_WIDTH, MAX_WIDTH)
	# An autowrap label's minimum height depends on its width: set the width first (as the tip).
	var box := card.get_theme_stylebox("panel").get_minimum_size()
	var inner := width - box.x
	label.custom_minimum_size.x = inner
	label.size = Vector2(inner, 0.0)
	var s := Vector2(width, box.y + name_label.get_minimum_size().y + 2.0 + label.get_minimum_size().y)
	card.size = s
	var room := view.grow(-margin)
	var top_center := Vector2(who.get_center().x, who.position.y)
	var above := who.position.y - GAP - TAIL - s.y
	var side_y := who.position.y + who.size.y * 0.25 - s.y * 0.5
	var to_right := Vector2(who.end.x + GAP + TAIL, side_y)
	var to_left := Vector2(who.position.x - GAP - TAIL - s.x, side_y)
	var right_first := who.get_center().x < view.get_center().x
	var tries := [
		["bottom", Vector2(top_center.x - s.x * 0.5, above)],
		["bottom", Vector2(top_center.x - s.x + 30.0, above)],
		["bottom", Vector2(top_center.x - 30.0, above)],
		["left", to_right] if right_first else ["right", to_left],
		["right", to_left] if right_first else ["left", to_right],
	]
	# The spot of the last frame first while it stays clear: the bubble does not jump between spots
	# as Dugi bobs or the target moves.
	var order := range(tries.size())
	if _last >= 0:
		order.erase(_last)
		order.push_front(_last)
	for i in order:
		var t: Array = tries[i]
		var p: Vector2 = t[1]
		p.x = clampf(p.x, room.position.x, room.end.x - s.x)
		p.y = clampf(p.y, room.position.y, room.end.y - s.y)
		var r := Rect2(p, s)
		if r.intersects(who) or avoid.any(func(a: Rect2) -> bool: return a.intersects(r)) \
				or keep.any(func(k: Vector2) -> bool: return r.grow(8.0).has_point(k)):
			continue
		_last = i
		position = p
		size = s
		card.position = Vector2.ZERO
		_tail_side = t[0]
		match _tail_side:
			"bottom":
				_tail_to = Vector2(clampf(top_center.x - p.x, 24.0, s.x - 24.0), s.y + TAIL)
			"left":
				_tail_to = Vector2(-TAIL, clampf(who.position.y + who.size.y * 0.25 - p.y, 20.0, s.y - 20.0))
			_:
				_tail_to = Vector2(s.x + TAIL, clampf(who.position.y + who.size.y * 0.25 - p.y, 20.0, s.y - 20.0))
		_tail.size = s
		_tail.queue_redraw()
		return true
	_last = -1
	return false


## A new explanation starts from the preferred spot again.
func reset_spot() -> void:
	_last = -1


## The bubble's rect in its parent (tests).
func rect() -> Rect2:
	return Rect2(position, size)


func _draw_tail() -> void:
	var a: Vector2
	var b: Vector2
	match _tail_side:
		"bottom":
			a = Vector2(_tail_to.x - TAIL_HALF, size.y - 3.0)
			b = Vector2(_tail_to.x + TAIL_HALF, size.y - 3.0)
		"left":
			a = Vector2(3.0, _tail_to.y - TAIL_HALF)
			b = Vector2(3.0, _tail_to.y + TAIL_HALF)
		_:
			a = Vector2(size.x - 3.0, _tail_to.y - TAIL_HALF)
			b = Vector2(size.x - 3.0, _tail_to.y + TAIL_HALF)
	# Over the card's border (drawn after the card), so the tail opens into the bubble.
	_tail.draw_colored_polygon(PackedVector2Array([a, _tail_to, b]), UiTheme.WHITE)
	_tail.draw_polyline(PackedVector2Array([a, _tail_to, b]), UiTheme.SPEECH_LINE, 2.0, true)
