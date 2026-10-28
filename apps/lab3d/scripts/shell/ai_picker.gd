## The AI app picker (2026-10-29 user decision): "AI에게 더 물어보기" opens a small card in the
## middle of the screen with one button per AI app (names only, no brand logos; ScienceNote.ai_apps),
## a small "다른 앱으로 보내기" (the share sheet) and "닫기". When the device can tell which apps are
## there (`installed` is an Array) only those show, and none shows "이 기기에는 AI 앱이 없어요";
## when it cannot (null) every app shows, and a tap on one that is not there shows "이 기기에는 ○○
## 앱이 없어요" and the card stays. While it is up nothing behind it takes a touch: a dim over the
## whole screen stops every press (the QuestionShield pattern), and it lets go of input in the frame
## it closes (MOUSE_FILTER_IGNORE before queue_free).
class_name AiPicker
extends Control

## The hand-off's result (ScienceNote.send_to): "sent", "share" or "clipboard" (the card has closed).
signal handed(result: String)

const TITLE := "어느 AI에게 물어볼까요?"
const NONE := "이 기기에는 AI 앱이 없어요"
const MISSING := "이 기기에는 %s 앱이 없어요"
const OTHER := "다른 앱으로 보내기"
const CLOSE := "닫기"
const DIM := Color(0.08, 0.12, 0.2, 0.38)   # ExperimentScreen.QUESTION_DIM
const DIM_FADE := 0.2
const COLUMNS := 3
const APP_SIZE := Vector2(200.0, 64.0)

## (package: String) -> String: hands the question to `package` ("" = the share sheet).
var send: Callable
var dim: ColorRect
var card: PanelContainer
var app_buttons: Array[Button] = []
var status: Label
var other_button: Button
var close_button: Button
var closed := false


## `apps`: {name, package} in order; `installed`: the packages that are there, or null when unknown.
func _init(apps: Array, installed: Variant, send_fn: Callable) -> void:
	name = "AiPicker"
	send = send_fn
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.modulate.a = 0.0
	add_child(dim)
	card = Ui.panel()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	var stack := Ui.vbox(16)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stack)
	var title := Ui.label(TITLE, "HeadingLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var grid := GridContainer.new()
	grid.name = "Apps"
	grid.columns = COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(grid)
	for app in apps:
		if installed is Array and not installed.has(app.package):
			continue
		var button := Ui.button(str(app.name), "", APP_SIZE.y)
		button.name = "App_" + str(app.package)
		button.custom_minimum_size.x = APP_SIZE.x
		button.set_meta("package", str(app.package))
		button.pressed.connect(_pick.bind(str(app.package), str(app.name)))
		grid.add_child(button)
		app_buttons.append(button)
	grid.visible = not app_buttons.is_empty()
	status = Ui.label(NONE, "MutedLabel")
	status.name = "Status"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.visible = app_buttons.is_empty()
	stack.add_child(status)
	var row := Ui.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(row)
	other_button = Ui.button(OTHER, "ChipButton", 52)
	other_button.name = "Other"
	other_button.pressed.connect(_pick.bind("", OTHER))
	row.add_child(other_button)
	close_button = Ui.button(CLOSE, "ChipButton", 52)
	close_button.name = "Close"
	close_button.custom_minimum_size.x = 120
	close_button.pressed.connect(close)
	row.add_child(close_button)


func _ready() -> void:
	create_tween().tween_property(dim, "modulate:a", 1.0, DIM_FADE)
	resized.connect(_fit)
	card.minimum_size_changed.connect(_fit)
	_fit()


## The card in the middle of the screen.
func _fit() -> void:
	card.size = card.get_combined_minimum_size()
	card.position = ((size - card.size) * 0.5).round()


## An app (or "" for the share sheet) is tapped: the question goes to it once. A missing app shows
## its line and the card stays; anything else closes the card.
func _pick(package: String, app_name: String) -> void:
	if closed:
		return
	var result := str(send.call(package))
	if result == "missing":
		status.text = MISSING % app_name
		status.visible = true
		return
	close()
	handed.emit(result)


## Closes now: the touch of this same frame already reaches what is behind (IGNORE before the free).
func close() -> void:
	if closed:
		return
	closed = true
	var controls: Array[Control] = [self, dim, card, other_button, close_button]
	controls.append_array(app_buttons)
	for c in controls:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	queue_free()
