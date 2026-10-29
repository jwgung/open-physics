## Puppy's short result line after an attempt (2026-10-29 user: "after each attempt … a short line in
## a small speech bubble near the game object / the cat for ~2.5 s"): a small white speech bubble with
## Puppy's round face (the line's face, Story.FACES) and one short line, its tail pointing at Puppy on
## the island (ExperimentScreen.show_result). A win says what the stamp did ("딩! 종이 울렸어!"), a
## miss what to try next ("종까지 조금 모자라! 더 당겨 봐!"; Puppy gives hints, never science: the
## stage lines are checked against Story.SCIENCE_WORDS). These are not the removed celebration
## captions: one line, gone after SHOW_S, no touch taken (MOUSE_FILTER_IGNORE everywhere).
## Drawing only: one panel, one label, one portrait and the tail; nothing in the lab changes.
class_name ResultBubble
extends Control

const SHOW_S := 2.5
const POP_S := 0.16
const FADE_S := 0.3
const FACE_SIZE := 52.0
const MAX_TEXT_WIDTH := 330.0
const TAIL := 18.0           # the tail's length below the bubble (UI units)
const TAIL_HALF := 11.0      # its half width where it leaves the bubble
const PAPER := Color("ffffff")
const EDGE := Color("6e4630")  # the characters' brown outline (art direction 11)
const WIN_EDGE := Color("23753a")

var text := ""
var face := "happy"
var won := true
## The view point the tail points at (Puppy's head on the view), set by the screen.
var anchor := Vector2.ZERO
## Seconds shown so far.
var age := 0.0
var panel: PanelContainer
var label: Label
var portrait: TextureRect


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
	box.bg_color = PAPER
	box.border_color = WIN_EDGE if won else EDGE
	box.set_border_width_all(3)
	box.set_corner_radius_all(20)
	box.content_margin_left = 10
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	portrait = TextureRect.new()
	portrait.name = "Face"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(FACE_SIZE, FACE_SIZE)
	portrait.texture = DialogueBox.portrait_texture("puppy", face)
	row.add_child(portrait)
	label = Ui.label(text, "KeyValueLabel")
	label.name = "Line"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)


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
	queue_redraw()


## The panel's rect on the view (tests: inside the view, clear of the other overlays).
func bubble_rect() -> Rect2:
	return Rect2(position, size)


## Pops in, stays, fades out; true once it is over (the screen frees it).
func tick(delta: float) -> bool:
	age += delta
	var k := clampf(age / POP_S, 0.0, 1.0)
	scale = Vector2.ONE * (0.8 + 0.2 * k + 0.08 * sin(PI * k))
	modulate.a = clampf((SHOW_S - age) / FADE_S, 0.0, 1.0)
	return age >= SHOW_S


## The tail: a small triangle from the bubble's edge nearest the anchor towards it (at most TAIL long).
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var to := anchor - position
	var below := to.y > r.end.y
	var above := to.y < r.position.y
	var base_y := r.end.y - 2.0 if below or not above else r.position.y + 2.0
	var base_x := clampf(to.x, r.position.x + 24.0, r.end.x - 24.0)
	var dir := (to - Vector2(base_x, base_y))
	if dir.length() < 1.0:
		return
	var tip := Vector2(base_x, base_y) + dir.normalized() * minf(TAIL, dir.length())
	var points := PackedVector2Array([Vector2(base_x - TAIL_HALF, base_y), tip, Vector2(base_x + TAIL_HALF, base_y)])
	draw_colored_polygon(points, PAPER)
	draw_polyline(points, (panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color, 3.0, true)
