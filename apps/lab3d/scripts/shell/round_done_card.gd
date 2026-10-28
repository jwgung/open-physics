## The round-done card (2026-10-28): when the child finishes a spot's last stage in this visit, a
## card in the middle of the view shows the round's stamps, big, and two big buttons: [지도로] (back
## to the map, like ← 지도) and [더 해 보기] (the card goes, the lab stays). Pictures only (2026-10-28
## user decision: no headline or caption). While it is up nothing behind it takes a touch: a dim
## over the whole view stops every press (the QuestionShield pattern), and it lets go of input in the
## frame it closes (MOUSE_FILTER_IGNORE before queue_free).
class_name RoundDoneCard
extends Control

signal to_map
signal stay

const DIM := Color(0.08, 0.12, 0.2, 0.38)   # ExperimentScreen.QUESTION_DIM
const DIM_FADE := 0.2
const STAMP_R := 46.0
const STAMP_GAP := 22.0
const POP_S := 0.35

var stamps := 3
## The story: the round's star piece is drawn after the stamps (the piece the child just found).
var piece := false
var dim: ColorRect
var card: PanelContainer
var stamp_row: Control
var map_button: Button
var stay_button: Button
var closed := false


func _init(stamp_count: int, with_piece := false) -> void:
	name = "RoundDoneCard"
	stamps = stamp_count
	piece = with_piece
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.modulate.a = 0.0
	add_child(dim)
	card = Ui.panel("DialogueBox")
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(card)
	var stack := Ui.vbox(22)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := Ui.margin(22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(stack)
	card.add_child(margin)
	stamp_row = Control.new()
	stamp_row.name = "Stamps"
	stamp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slots := stamps + (1 if piece else 0)
	stamp_row.custom_minimum_size = Vector2(slots * STAMP_R * 2.0 + (slots - 1) * STAMP_GAP, STAMP_R * 2.0 + 8.0)
	stamp_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stamp_row.draw.connect(_draw_stamps)
	stack.add_child(stamp_row)
	var buttons := Ui.hbox(16)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(buttons)
	map_button = Ui.button("지도로", "ChoiceButton", 84)
	map_button.name = "ToMap"
	map_button.custom_minimum_size.x = 190
	map_button.pressed.connect(func() -> void: _close(to_map))
	buttons.add_child(map_button)
	stay_button = Ui.button("더 해 보기", "ChoiceButton", 84)
	stay_button.name = "Stay"
	stay_button.custom_minimum_size.x = 190
	stay_button.pressed.connect(func() -> void: _close(stay))
	buttons.add_child(stay_button)
	for b: Button in [map_button, stay_button]:
		b.add_theme_font_size_override("font_size", 26)


func _ready() -> void:
	create_tween().tween_property(dim, "modulate:a", 1.0, DIM_FADE)
	resized.connect(_fit)
	_fit()
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE * 0.75
	create_tween().tween_property(card, "scale", Vector2.ONE, POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The card in the middle of the view.
func _fit() -> void:
	card.size = card.get_combined_minimum_size()
	card.position = ((size - card.size) * 0.5).round()
	card.pivot_offset = card.size * 0.5


func _draw_stamps() -> void:
	for i in stamps:
		var c := Vector2(STAMP_R + i * (STAMP_R * 2.0 + STAMP_GAP), STAMP_R + 4.0)
		StampSlam.draw_stamp(stamp_row, c, STAMP_R, true)
	if piece:   # the found star piece: a yellow star with the brown outline
		var c := Vector2(STAMP_R + stamps * (STAMP_R * 2.0 + STAMP_GAP), STAMP_R + 4.0)
		stamp_row.draw_colored_polygon(StarEmblem.star_points(c, STAMP_R + 4.0), ArtPalette.OUTLINE)
		stamp_row.draw_colored_polygon(StarEmblem.star_points(c, STAMP_R - 1.0), StarEmblem.FILL)
		stamp_row.draw_colored_polygon(StarEmblem.star_points(c + Vector2(-4.0, -5.0), STAMP_R * 0.45), StarEmblem.FILL_LIGHT)


## Closes now: the touch of this same frame already reaches what is behind (IGNORE before the free).
func close() -> void:
	_close(Signal())


func _close(then: Signal) -> void:
	if closed:
		return
	closed = true
	for c: Control in [self, dim, card, map_button, stay_button]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	queue_free()
	if not then.is_null():
		then.emit()
