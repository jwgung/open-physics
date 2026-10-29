## Puppy's short result line after an attempt (2026-10-29 user: "after each attempt … a short line in
## a small speech bubble near the game object / the cat for ~2.5 s"): a small white speech bubble with
## one short line (no face: 2026-10-30 user, Puppy is right there behind), its tail pointing at Puppy on
## the island (ExperimentScreen.show_result). A win says what the stamp did ("딩! 종이 울렸어!"), a
## miss what to try next ("종까지 조금 모자라! 더 당겨 봐!"; Puppy gives hints, never science: the
## stage lines are checked against Story.SCIENCE_WORDS). These are not the removed celebration
## captions: one line, gone after SHOW_S, no touch taken (MOUSE_FILTER_IGNORE everywhere).
## Drawing only: one panel, one label and the tail; nothing in the lab changes.
class_name ResultBubble
extends Control

const SHOW_S := 2.5
const POP_S := 0.16
const FADE_S := 0.3
const MAX_TEXT_WIDTH := 330.0
const TAIL := 18.0           # the tail's length below the bubble (UI units)
const TAIL_HALF := 11.0      # its half width where it leaves the bubble
## The look (2026-10-29 user: "말풍선 좀 더 예쁘게"): warm paper tinted by the result, a soft drop
## shadow, a rounded tail drawn over the bubble's edge, a bouncy pop.
const WIN_PAPER := Color("f1fbf3")
const MISS_PAPER := Color("fff6ea")
const WIN_EDGE := Color("39a862")
const MISS_EDGE := Color("e3913f")
const INK := Color("4a2e1f")     # the storybook ink (StarArt.FACE_INK)
const SHADOW := Color(0.18, 0.12, 0.06, 0.22)
## The old names (tests and callers): the paper and edge of this bubble's result.
const PAPER := MISS_PAPER
const EDGE := MISS_EDGE

var text := ""
var face := "happy"
var won := true
## The view point the tail points at (Puppy's head on the view), set by the screen.
var anchor := Vector2.ZERO
## Seconds shown so far.
var age := 0.0
var panel: PanelContainer
var label: Label
var _tail: Control


func _init(words: String, with_face: String, did_win: bool) -> void:
	text = words
	face = with_face
	won = did_win
	name = "ResultBubble"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.name = "Bubble"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = paper()
	box.border_color = edge()
	box.set_border_width_all(3)
	box.set_corner_radius_all(22)
	box.corner_detail = 10
	box.shadow_color = SHADOW
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 4)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	label = Ui.label(text, "KeyValueLabel")
	label.name = "Line"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", INK)
	row.add_child(label)
	# The tail over the bubble's edge (a child after the panel, so it covers the border where it joins).
	_tail = Control.new()
	_tail.name = "Tail"
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.draw.connect(_draw_tail)
	add_child(_tail)


func paper() -> Color:
	return WIN_PAPER if won else MISS_PAPER


func edge() -> Color:
	return WIN_EDGE if won else MISS_EDGE


## The bubble's own size (its panel at the line's width, wrapped past MAX_TEXT_WIDTH).
func bubble_size() -> Vector2:
	if label.get_minimum_size().x > MAX_TEXT_WIDTH:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = MAX_TEXT_WIDTH
	panel.size = panel.get_combined_minimum_size()
	return panel.size


## Puts the bubble at `rect` (view units, its panel's rect) with the tail towards `point`.
func place(rect: Rect2, point: Vector2) -> void:
	position = rect.position
	size = rect.size
	panel.position = Vector2.ZERO
	panel.size = rect.size
	anchor = point
	pivot_offset = Vector2(rect.size.x * 0.5, rect.size.y)
	_tail.position = Vector2.ZERO
	_tail.size = rect.size
	_tail.queue_redraw()


## The panel's rect on the view (tests: inside the view, clear of the other overlays).
func bubble_rect() -> Rect2:
	return Rect2(position, size)


## Pops in, stays, fades out; true once it is over (the screen frees it).
func tick(delta: float) -> bool:
	age += delta
	var k := clampf(age / (POP_S * 1.6), 0.0, 1.0)
	# A springy pop (0.6 → about 1.1 → 1) and a gentle bob while it stays.
	scale = Vector2.ONE * (1.0 - 0.4 * pow(1.0 - k, 2.0) + 0.12 * sin(PI * k) * (1.0 - k * 0.4))
	position.y += sin(age * 4.0) * 0.15
	modulate.a = clampf((SHOW_S - age) / FADE_S, 0.0, 1.0)
	return age >= SHOW_S


## The tail: a rounded wedge from the bubble's edge nearest the anchor towards it (at most TAIL long),
## filled with the paper over the border and outlined on its two sides only, so it joins seamlessly.
func _draw_tail() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var to := anchor - position
	var below := to.y > r.end.y
	var above := to.y < r.position.y
	var base_y := r.end.y - 1.5 if below or not above else r.position.y + 1.5
	var inward := -1.0 if below or not above else 1.0
	var base_x := clampf(to.x, r.position.x + 30.0, r.end.x - 30.0)
	var dir := (to - Vector2(base_x, base_y))
	if dir.length() < 1.0:
		return
	var tip := Vector2(base_x, base_y) + dir.normalized() * minf(TAIL, dir.length())
	var l := Vector2(base_x - TAIL_HALF, base_y)
	var rr := Vector2(base_x + TAIL_HALF, base_y)
	# Slightly curved sides (a quadratic bend toward the tail's middle).
	var side_l := PackedVector2Array()
	var side_r := PackedVector2Array()
	for i in 7:
		var t := i / 6.0
		var mid_l := l.lerp(tip, 0.5) + Vector2(TAIL_HALF * 0.25, 0.0)
		var mid_r := rr.lerp(tip, 0.5) - Vector2(TAIL_HALF * 0.25, 0.0)
		side_l.append(l.lerp(mid_l, t).lerp(mid_l.lerp(tip, t), t))
		side_r.append(rr.lerp(mid_r, t).lerp(mid_r.lerp(tip, t), t))
	# The fill: the curves bend inward, so the wedge under them covers them (a simple triangle never
	# fails to triangulate, unlike the curved outline as a polygon).
	var fill := PackedVector2Array([l + Vector2(0, 3.0 * inward), tip, rr + Vector2(0, 3.0 * inward)])
	_tail.draw_colored_polygon(fill, paper())
	_tail.draw_polyline(side_l, edge(), 3.0, true)
	_tail.draw_polyline(side_r, edge(), 3.0, true)
