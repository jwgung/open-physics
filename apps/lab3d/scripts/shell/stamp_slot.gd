## One slot of the mission strip: the text "●" (stamped) or "○" (empty) still says which, but the
## slot draws the same paw stamp the StampSlam flies in (a green paw stamp, or the pale ring), so
## the stamp keeps its shape once it has landed. The glyph itself is not drawn (clear font colour);
## it only gives the slot its width.
class_name StampSlot
extends Label

const GLYPH_CLEAR := Color(1.0, 1.0, 1.0, 0.0)
const SIDE := 48.0            # the slot's own size (view units): a stamp a child can read at a glance


func _init() -> void:
	text = "○"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = "KeyValueLabel"
	add_theme_color_override("font_color", GLYPH_CLEAR)
	custom_minimum_size = Vector2(SIDE, SIDE)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## The stamp drawn here has this radius; the flying stamp shrinks to it.
func stamp_radius() -> float:
	return maxf(8.0, minf(size.x, size.y) * 0.47)


func is_filled() -> bool:
	return text == "●"


func set_filled(filled: bool) -> void:
	text = "●" if filled else "○"
	queue_redraw()


func _draw() -> void:
	StampSlam.draw_stamp(self, size * 0.5, stamp_radius(), is_filled())
