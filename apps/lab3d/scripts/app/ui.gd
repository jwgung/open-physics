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
	return node


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
