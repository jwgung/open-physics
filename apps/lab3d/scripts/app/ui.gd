## Small widget factory so screens read as layout, not property noise.
class_name Ui
extends RefCounted


static func label(text: String, variation := "", wrap := false) -> Label:
	var node := Label.new()
	node.text = text
	if variation != "":
		node.theme_type_variation = variation
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func vbox(separation: int) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func hbox(separation: int) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func panel(variation := "") -> PanelContainer:
	var node := PanelContainer.new()
	node.mouse_filter = Control.MOUSE_FILTER_PASS  # let drags reach the ScrollContainer
	if variation != "":
		node.theme_type_variation = variation
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func button(text: String, variation := "", min_height := 64.0) -> Button:
	var node := Button.new()
	node.text = text
	if variation != "":
		node.theme_type_variation = variation
	node.custom_minimum_size = Vector2(0, min_height)
	add_press_bounce(node)
	return node


## Press feedback (art direction "button"): shrinks to PRESS_SCALE while held and springs back with
## a small overshoot on release. One short Tween on the button's own scale (no extra layer).
const PRESS_SCALE := 0.94
const PRESS_IN_S := 0.06
const PRESS_OUT_S := 0.22

static func add_press_bounce(node: Control) -> void:
	node.resized.connect(func() -> void: node.pivot_offset = node.size * 0.5)
	node.gui_input.connect(func(event: InputEvent) -> void:
		var pressed: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch
		if pressed and not (node is BaseButton and node.disabled):
			_bounce(node, PRESS_SCALE if event.pressed else 1.0, PRESS_IN_S if event.pressed else PRESS_OUT_S))
	node.mouse_exited.connect(func() -> void: if node.scale != Vector2.ONE: _bounce(node, 1.0, PRESS_OUT_S))


static func _bounce(node: Control, to: float, seconds: float) -> void:
	if not node.is_inside_tree():
		return
	var old: Tween = node.get_meta("press_tween", null)
	if old and old.is_valid():
		old.kill()
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2.ONE * to, seconds) \
		.set_trans(Tween.TRANS_BACK if to >= 1.0 else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	node.set_meta("press_tween", tween)


static func margin(all: int) -> MarginContainer:
	var node := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		node.add_theme_constant_override("margin_" + side, all)
	return node


## Vertical scroller whose content always fits the width (labels wrap instead of scrolling).
static func scroller() -> ScrollContainer:
	var node := ScrollContainer.new()
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node


## "%.Nf" formatting with N from content (String.num drops trailing zeros).
static func number(value: float, digits: int) -> String:
	return ("%." + str(clampi(digits, 0, 4)) + "f") % value
