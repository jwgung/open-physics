## Experiment list: one card per registered experiment, grouped by category (web "실험 선택"),
## under the island banner (art direction).
class_name ListScreen
extends Control

signal experiment_chosen(definition: Dictionary)
signal settings_requested

var definitions: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := Ui.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var bar := Ui.panel("TopBar")
	layout.add_child(bar)
	var row := Ui.hbox(12)
	bar.add_child(row)
	var brand := Ui.vbox(0)
	brand.add_child(Ui.label("Open Physics 3D", "HeadingLabel"))
	brand.add_child(Ui.label("역학 실험실", "EyebrowLabel"))
	row.add_child(brand)
	var settings := Ui.button("설정", "", 60)
	settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings.pressed.connect(settings_requested.emit)
	row.add_child(settings)

	var scroll := Ui.scroller()
	layout.add_child(scroll)
	var pad := Ui.margin(24)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var column := Ui.vbox(18)
	pad.add_child(column)
	column.add_child(IslandBanner.new())
	column.add_child(Ui.label("실험 선택", "TitleLabel"))
	column.add_child(Ui.label("질문을 고르고, 조건을 바꾸며 무슨 일이 일어나는지 관찰해요.", "MutedLabel", true))

	var category := ""
	for definition in definitions:
		if definition.category != category:
			category = definition.category
			column.add_child(Ui.label(category, "SectionLabel"))
		column.add_child(_card(definition))


## One card in one line (2026-10-23 user request): [icon] [title / question] ...... [실험 시작], the icon and
## the button centred on the text block's height, the text taking the width left (a long question
## wraps; the button stays at the right). A tap anywhere on the card starts the experiment too (a
## drag to scroll does not).
func _card(definition: Dictionary) -> Control:
	var card := Ui.panel()
	card.name = "Card_%s" % definition.id
	var row := Ui.hbox(16)
	card.add_child(row)
	var badge := Ui.panel("IconBadge")
	badge.name = "Badge"
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := Ui.label(definition.get("icon", "•"), "BadgeLabel")
	icon.custom_minimum_size = Vector2(40, 40)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(icon)
	row.add_child(badge)
	var text := Ui.vbox(8)
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_child(Ui.label(definition.title, "HeadingLabel", true))
	text.add_child(Ui.label(definition.question, "MutedLabel", true))
	row.add_child(text)
	var start := Ui.button("실험 시작", "PrimaryButton", 60)
	start.name = "Start"
	start.size_flags_horizontal = Control.SIZE_SHRINK_END
	start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(experiment_chosen.emit.bind(definition))
	row.add_child(start)
	_tap_to_start(card, definition)
	return card


const TAP_SLOP := 12.0   # UI units a press may move and still count as a tap on the card


## A press and release on the card within TAP_SLOP (not a scroll drag) starts the experiment.
func _tap_to_start(card: Control, definition: Dictionary) -> void:
	var down := [Vector2.INF]
	card.mouse_filter = Control.MOUSE_FILTER_PASS   # the scroller still gets the drag
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				down[0] = event.position
			elif down[0] != Vector2.INF and event.position.distance_to(down[0]) <= TAP_SLOP:
				down[0] = Vector2.INF
				experiment_chosen.emit(definition)
			else:
				down[0] = Vector2.INF)
