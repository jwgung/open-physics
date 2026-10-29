## Settings: quality tier (ported from the spike's "Q" button), sound (효과음 / 배경 음악, SoundBoard),
## the story (이야기 다시 보기, 처음부터 다시 하기) and the performance overlay. The on/off settings are
## big check boxes (2026-10-29 user request: check boxes, not switches; UiTheme "CheckBox", a 64-unit
## row, the box 44 units). A vertical drag anywhere on the page scrolls it (Ui.scroller: DragScroll).
## Switching between low (Compatibility renderer) and medium/high (Mobile renderer) restarts the app.
class_name SettingsScreen
extends Control

signal back_requested
signal fps_toggled(on: bool)
## 이야기 다시 보기: the map opens and the story's prologue plays again.
signal story_requested
## 처음부터 다시 하기, confirmed: every saved progress is gone (ProgressStore.reset_all); the app goes
## back to the start (App: the title, or the map that plays the prologue).
signal restart_requested

const DESCRIPTIONS := {
	"low": "가벼운 기기용이에요. 3D 화면만 낮은 해상도(화면의 45%)로 그리고 가장자리 다듬기(MSAA)는 끄고 60 fps를 지켜요. 글자와 버튼은 선명하게 그대로예요.",
	"medium": "3D 화면을 화면의 60% 해상도로 그리고 가장자리를 다듬어요(MSAA 2x). 중급 기기에 맞춰요.",
	"high": "3D 화면을 원본 해상도로 그려요. 가장자리 다듬기는 보통과 같은 MSAA 2x이고, 성능이 좋은 기기용이에요.",
}

var show_fps := false
## Applies a tier; true when the app is restarting. Quality.set_tier unless a test replaces it.
var set_tier := Callable()
var _selected := ""
var _buttons: Dictionary = {}
var _apply: Button
var _notice: Label
## The sound check boxes (tests press them): effects and music, each mutes its own bus.
var sfx_switch: CheckBox
var music_switch: CheckBox
var fps_check: CheckBox
## 처음부터 다시 하기 and its confirmation (a second step: the question with 다시 하기 / 아니요).
var restart_button: Button
var restart_confirm: Control
var restart_yes: Button
var restart_no: Button
const RESTART_TEXT := "처음부터 다시 하기"
const RESTART_QUESTION := "정말 처음부터 다시 할까요?"
const RESTART_DETAIL := "모은 도장과 별 조각, 이야기가 모두 사라지고 처음부터 시작해요."


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_selected = Quality.tier
	if not set_tier.is_valid():
		set_tier = Quality.set_tier
	var layout := Ui.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var bar := Ui.panel("TopBar")
	layout.add_child(bar)
	var row := Ui.hbox(12)
	bar.add_child(row)
	var back := Ui.button("← 돌아가기", "FlatButton", 60)
	back.pressed.connect(back_requested.emit)
	row.add_child(back)
	row.add_child(Ui.label("설정", "HeadingLabel"))

	var scroll := Ui.scroller()
	layout.add_child(scroll)
	var pad := Ui.margin(24)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var column := Ui.vbox(16)
	pad.add_child(column)

	var quality_card := Ui.panel()
	var quality := Ui.vbox(12)
	quality_card.add_child(quality)
	quality.add_child(Ui.label("그래픽 품질", "SectionLabel"))
	var group := ButtonGroup.new()
	for tier in Quality.TIER_ORDER:
		var option := Ui.button("", "ChipButton", 0)
		option.toggle_mode = true
		option.button_group = group
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var text := Ui.vbox(4)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
		var title := Ui.label(Quality.TIER_LABELS[tier], "HeadingLabel")
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var detail := Ui.label(DESCRIPTIONS[tier], "MutedLabel", true)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(title)
		text.add_child(detail)
		var holder := MarginContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			holder.add_theme_constant_override("margin_" + side, 16)
		holder.add_child(text)
		option.add_child(holder)
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		option.resized.connect(func() -> void: option.custom_minimum_size.y = holder.get_combined_minimum_size().y)
		holder.minimum_size_changed.connect(func() -> void: option.custom_minimum_size.y = holder.get_combined_minimum_size().y)
		option.pressed.connect(_select.bind(tier))
		quality.add_child(option)
		_buttons[tier] = option
	_notice = Ui.label("", "MutedLabel", true)
	quality.add_child(_notice)
	_apply = Ui.button("적용", "PrimaryButton", 64)
	_apply.pressed.connect(_apply_tier)
	quality.add_child(_apply)
	column.add_child(quality_card)
	column.add_child(_build_sound_card())
	column.add_child(_build_story_card())

	var debug_card := Ui.panel()
	var debug := Ui.vbox(8)
	debug_card.add_child(debug)
	debug.add_child(Ui.label("개발자", "SectionLabel"))
	fps_check = check_box("성능 표시 (fps)", show_fps)
	fps_check.name = "FpsCheck"
	fps_check.toggled.connect(fps_toggled.emit)
	debug.add_child(fps_check)
	debug.add_child(Ui.label("현재 렌더러: %s · 품질: %s" % [RenderingServer.get_current_rendering_method(), Quality.label()], "MutedLabel", true))
	column.add_child(debug_card)
	_select(_selected)


## 소리: two switches, both on by default (kept in user://settings.cfg by SoundBoard).
func _build_sound_card() -> Control:
	var card := Ui.panel()
	var box := Ui.vbox(8)
	card.add_child(box)
	box.add_child(Ui.label("소리", "SectionLabel"))
	var board := SoundBoard.instance()
	sfx_switch = check_box("효과음")
	sfx_switch.name = "SfxSwitch"
	music_switch = check_box("배경 음악")
	music_switch.name = "MusicSwitch"
	for entry in [[sfx_switch, "sfx_on", "set_sfx_on"], [music_switch, "music_on", "set_music_on"]]:
		var check: CheckBox = entry[0]
		check.button_pressed = board == null or bool(board.get(entry[1]))
		check.disabled = board == null
		if board != null:
			check.toggled.connect(Callable(board, entry[2]))
		box.add_child(check)
	return card


## 이야기: the story's prologue again (the map plays it; nothing found is lost).
func _build_story_card() -> Control:
	var card := Ui.panel()
	var box := Ui.vbox(8)
	card.add_child(box)
	box.add_child(Ui.label("이야기", "SectionLabel"))
	var replay := Ui.button("이야기 다시 보기", "", 60)
	replay.name = "StoryReplay"
	replay.pressed.connect(story_requested.emit)
	box.add_child(replay)
	restart_button = Ui.button(RESTART_TEXT, "", 60)
	restart_button.name = "RestartButton"
	restart_button.pressed.connect(func() -> void: show_restart_confirm(true))
	box.add_child(restart_button)
	# The confirmation: nothing is erased until 다시 하기 is pressed here.
	var confirm := Ui.panel("SoftCard")
	confirm.name = "RestartConfirm"
	confirm.visible = false
	var ask := Ui.vbox(10)
	confirm.add_child(ask)
	ask.add_child(Ui.label(RESTART_QUESTION, "HeadingLabel", true))
	ask.add_child(Ui.label(RESTART_DETAIL, "MutedLabel", true))
	var row := Ui.hbox(12)
	ask.add_child(row)
	restart_yes = Ui.button("다시 하기", "PrimaryButton", 60)
	restart_yes.name = "RestartYes"
	restart_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart_yes.pressed.connect(restart)
	row.add_child(restart_yes)
	restart_no = Ui.button("아니요", "", 60)
	restart_no.name = "RestartNo"
	restart_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart_no.pressed.connect(func() -> void: show_restart_confirm(false))
	row.add_child(restart_no)
	box.add_child(confirm)
	restart_confirm = confirm
	return card


## A big check box in the island style (UiTheme "CheckBox": the box 44 units, the row 64 units).
static func check_box(text: String, on := false) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = on
	check.custom_minimum_size = Vector2(0, 64)
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Ui.add_press_bounce(check)
	check.toggled.connect(func(_on: bool) -> void: SoundBoard.play(&"tap"))
	return check


## Shows (or hides) the question under 처음부터 다시 하기; while it shows, the button itself hides.
func show_restart_confirm(on: bool) -> void:
	restart_confirm.visible = on
	restart_button.visible = not on


## 다시 하기 (confirmed): the saved progress of the store in use is erased (the bench or test store in
## measurements and tests, never another file), the first-visit tips come back, and the app starts over.
func restart() -> void:
	if not restart_confirm.visible:
		return
	ProgressStore.reset_all()
	ExperimentScreen.reset_tips_shown()
	show_restart_confirm(false)
	restart_requested.emit()


func _select(tier: String) -> void:
	_selected = tier
	for id in _buttons:
		_buttons[id].set_pressed_no_signal(id == tier)
	_apply.disabled = tier == Quality.tier
	if tier == Quality.tier:
		_notice.text = "지금 쓰는 품질이에요."
	elif Quality.needs_restart(tier):
		_notice.text = "적용하면 앱이 한 번 다시 시작돼요."
	else:
		_notice.text = "적용하면 바로 바뀌어요."


func _apply_tier() -> void:
	if set_tier.call(_selected):
		# Restarting: the next launch reopens the settings screen. Written only when Quality
		# really requested the restart, otherwise the marker would outlive this run.
		var marker := FileAccess.open(App.RESUME_PATH, FileAccess.WRITE)
		if marker:
			marker.store_string("settings")
	_select(_selected)
