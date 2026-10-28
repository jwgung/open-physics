## A key card's bar (2026-10-28 "어려운 말들은 세부 쪽으로"): a quantity with no kid unit (the push
## that started the box) as a horizontal bar that grows with it, full at the definition's kid.bars
## value. No number and no unit: the value is in "자세히". Drawing only (it takes no touch).
class_name KidBar
extends Control

const SIZE := Vector2(176.0, 26.0)
const TRACK := Color("e3ecf6")
const FILL := Color("e8553d")
const FILL_EDGE := Color("b8392a")
const MIN_SHOWN := 0.04   # a tiny push still shows a sliver

## 0..1 of the full bar (clamped when set).
var fraction := 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if clamped != fraction:
			fraction = clamped
			queue_redraw()


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := minf(size.y * 0.5, 13.0)
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK
	track.set_corner_radius_all(int(r))
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	if fraction <= 0.0:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = FILL
	fill.border_color = FILL_EDGE
	fill.border_width_bottom = 3
	fill.set_corner_radius_all(int(r))
	draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(maxf(size.x * maxf(fraction, MIN_SHOWN), size.y), size.y)))
