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


func _card(definition: Dictionary) -> Control:
	var card := Ui.panel()
	var row := Ui.hbox(16)
	card.add_child(row)
	var badge := Ui.panel("IconBadge")
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var icon := Ui.label(definition.get("icon", "•"), "BadgeLabel")
	icon.custom_minimum_size = Vector2(40, 40)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(icon)
	row.add_child(badge)
	var text := Ui.vbox(8)
	text.add_child(Ui.label(definition.title, "HeadingLabel", true))
	text.add_child(Ui.label(definition.question, "MutedLabel", true))
	var start := Ui.button("실험 시작", "PrimaryButton", 60)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.pressed.connect(experiment_chosen.emit.bind(definition))
	text.add_child(start)
	row.add_child(text)
	return card
