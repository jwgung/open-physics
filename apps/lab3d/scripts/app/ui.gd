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


## Press feedback (art direction "button"): the face shrinks by PRESS_SHRINK per side while held and
## springs back with a small overshoot on release. A Container resets its children's scale on every
## layout pass, so this does not touch scale: a short Tween moves the expand margins of the button's
## own StyleBoxFlat copies (drawing only, layout and hit area stay put).
const PRESS_SHRINK := 0.03          # of the button's width / height, on each side (about 0.94x)
const PRESS_IN_S := 0.06
const PRESS_OUT_S := 0.22
const PRESS_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled"]

static func add_press_bounce(node: Control) -> void:
	node.gui_input.connect(func(event: InputEvent) -> void:
		var pressed: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch
		if not pressed:
			return
		if event.pressed:
			if not (node is BaseButton and node.disabled):
				_bounce(node, 1.0, PRESS_IN_S)
		else:
			_bounce(node, 0.0, PRESS_OUT_S))   # always back to full size, even if disabled while held
	node.mouse_exited.connect(func() -> void: if press_amount(node) != 0.0: _bounce(node, 0.0, PRESS_OUT_S))


## 0 = not pressed, 1 = fully shrunk (briefly below 0 while it springs back).
static func press_amount(node: Control) -> float:
	return node.get_meta("press_amount", 0.0)


static func _bounce(node: Control, to: float, seconds: float) -> void:
	if not node.is_inside_tree():
		return
	if not node.has_meta("press_boxes"):
		_own_boxes(node)
	var old: Tween = node.get_meta("press_tween") if node.has_meta("press_tween") else null
	if old and old.is_valid():
		old.kill()
	var tween := node.create_tween()
	tween.tween_method(_set_press.bind(node), press_amount(node), to, seconds) \
		.set_trans(Tween.TRANS_BACK if to <= 0.0 else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	node.set_meta("press_tween", tween)


## Per-button copies of the theme's flat boxes (the theme's own are shared), with their base expand margins.
static func _own_boxes(node: Control) -> void:
	var boxes := []
	for state in PRESS_STATES:
		var theme_box := node.get_theme_stylebox(state)
		if theme_box is StyleBoxFlat:
			var box: StyleBoxFlat = theme_box.duplicate()
			node.add_theme_stylebox_override(state, box)
			boxes.append([box, Vector4(box.expand_margin_left, box.expand_margin_top, box.expand_margin_right, box.expand_margin_bottom)])
	node.set_meta("press_boxes", boxes)


static func _set_press(amount: float, node: Control) -> void:
	node.set_meta("press_amount", amount)
	var inset := Vector2(node.size.x, node.size.y) * PRESS_SHRINK * amount
	for entry in node.get_meta("press_boxes"):
		var box: StyleBoxFlat = entry[0]
		var base: Vector4 = entry[1]
		box.expand_margin_left = base.x - inset.x
		box.expand_margin_right = base.z - inset.x
		box.expand_margin_top = base.y - inset.y
		box.expand_margin_bottom = base.w - inset.y
	node.queue_redraw()


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
