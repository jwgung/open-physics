## Experiment screen: top bar, 3D view (camera modes, "정면으로", gestures) and the 2D panel
## (question, conditions, observations, graph, explanation) built from the experiment's
## definition. Layout: portrait = view on top, panel below; landscape = view left, side panel.
class_name ExperimentScreen
extends Control

signal back_requested
signal settings_requested

const UI_REFRESH_HZ := 10.0
const TOP_BAR_HEIGHT := 84.0
const SIDE_PANEL_WIDTH := 470.0
const TIP_SECONDS := 8.0

## Set by App for the screen it opens from --experiment: then the launch args (--ctl-*, --camera,
## ...) apply to this screen only (a rebuilt screen with a saved state restores that state instead).
var apply_launch_args := false

var definition: Dictionary
var experiment: Experiment
var view: View3D

var _top_bar: PanelContainer
var _panel: PanelContainer
var _scroll: ScrollContainer
var _mode_bar: PanelContainer
var _mode_buttons: Dictionary = {}
var _front_button: Button
var _tip: Label
var _tip_left := TIP_SECONDS
var _observation_labels: Dictionary = {}
var _control_widgets: Dictionary = {}   # id -> {"slider": HSlider, "value": Label} or {"buttons": {}, "note": Label}
var _graph: GraphView
var _sections: Dictionary = {}          # section id -> card (for --scroll-to)
var _refresh_left := 0.0
var _auto_release_every := 0.0
var _auto_release_left := 0.0
var _state: Dictionary = {}             # capture_state() of a screen being rebuilt
var _updating := false                  # a control/action is running: refresh once afterwards
var _graph_revision := -2               # Experiment.graph_revision() of the series on the graph


## `state` (optional): capture_state() of a previous screen of the same experiment (conditions
## and camera are restored instead of the defaults / launch args).
func setup(new_definition: Dictionary, state := {}, launch_args := false) -> void:
	definition = new_definition
	_state = state
	apply_launch_args = launch_args


## Conditions (control values) and camera of this screen, for a rebuild with the same experiment.
func capture_state() -> Dictionary:
	var controls := {}
	for control in definition.controls:
		controls[control.id] = experiment.control_value(control.id)
	return {"controls": controls, "camera": view.rig.get_state()}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_top_bar()
	view = View3D.new()
	add_child(view)
	_build_view_overlays()
	_build_panel()
	experiment = ExperimentRegistry.instantiate(definition)
	experiment.state_changed.connect(_on_state_changed)
	view.set_world(experiment)
	view.rig.follow_source = experiment
	view.rig.configure(definition.camera)
	view.rig.mode_changed.connect(_on_mode_changed)
	view.gesture_used.connect(_hide_tip)
	_on_mode_changed(view.rig.mode)
	resized.connect(_layout)
	_layout()
	if not _state.is_empty():
		_restore_state()
	elif apply_launch_args:
		_apply_launch_args()
	_refresh()
	Bench.reset(definition.get("bench_id", definition.id))


func _restore_state() -> void:
	var controls: Dictionary = _state.get("controls", {})
	_updating = true
	for id in controls:
		experiment.set_control(id, controls[id])
	_updating = false
	view.rig.set_state(_state.get("camera", {}))   # emits mode_changed; setup() refreshes once


## Measurement/screenshot hooks from the launch args (Quality.all_args):
## --camera=<mode>, --ctl-<control>=<value>, --auto-release=<seconds> (re-release periodically),
## --scroll-to=<conditions|observations|graph|explanation> (panel scroll position).
func _apply_launch_args() -> void:
	for control in definition.controls:
		var text := Quality.cmdline_value("ctl-" + control.id)
		if text != "":
			_set_control(control.id, float(text) if control.type == "slider" else text)
	var camera := Quality.cmdline_value("camera")
	if camera != "":
		view.rig.set_mode(camera, true)
	var section := Quality.cmdline_value("scroll-to")
	if _sections.has(section):
		_scroll_to.call_deferred(section)
	var every := Quality.cmdline_value("auto-release")
	if every.is_valid_float():
		_auto_release_every = float(every)
		_auto_release_left = 1.0


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 1.0 / UI_REFRESH_HZ
		_poll()
	if _tip.visible:
		_tip_left -= delta
		if _tip_left <= 0.0:
			_hide_tip()
	if _auto_release_every > 0.0:
		_auto_release_left -= delta
		if _auto_release_left <= 0.0:
			_auto_release_left = _auto_release_every
			experiment.run_action("release")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()


# --- layout ---------------------------------------------------------------------------------

func is_landscape() -> bool:
	return size.x > size.y


func _layout() -> void:
	var w := size.x
	var h := size.y
	_top_bar.position = Vector2.ZERO
	_top_bar.size = Vector2(w, TOP_BAR_HEIGHT)
	var body := h - TOP_BAR_HEIGHT
	if is_landscape():
		var side := minf(SIDE_PANEL_WIDTH, w * 0.45)
		view.position = Vector2(0, TOP_BAR_HEIGHT)
		view.size = Vector2(w - side, body)
		_panel.position = Vector2(w - side, TOP_BAR_HEIGHT)
		_panel.size = Vector2(side, body)
	else:
		var view_height := roundf(clampf(body * 0.46, 300.0, maxf(300.0, body - 380.0)))
		view.position = Vector2(0, TOP_BAR_HEIGHT)
		view.size = Vector2(w, view_height)
		_panel.position = Vector2(0, TOP_BAR_HEIGHT + view_height)
		_panel.size = Vector2(w, body - view_height)


# --- building -------------------------------------------------------------------------------

func _build_top_bar() -> void:
	_top_bar = Ui.panel("TopBar")
	add_child(_top_bar)
	var row := Ui.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_top_bar.add_child(row)
	var back := Ui.button("← 실험 목록", "FlatButton", 60)
	back.pressed.connect(back_requested.emit)
	row.add_child(back)
	var title := Ui.label(definition.title, "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	row.add_child(title)
	var settings := Ui.button("설정", "", 60)
	settings.pressed.connect(settings_requested.emit)
	row.add_child(settings)


func _build_view_overlays() -> void:
	_mode_bar = Ui.panel("ViewOverlay")
	view.add_child(_mode_bar)
	var modes := Ui.hbox(6)
	_mode_bar.add_child(modes)
	var group := ButtonGroup.new()
	for mode in CameraRig.MODES:
		var chip := Ui.button(CameraRig.MODE_LABELS[mode], "ChipButton", 56)
		chip.toggle_mode = true
		chip.button_group = group
		chip.pressed.connect(view.rig.set_mode.bind(mode))
		modes.add_child(chip)
		_mode_buttons[mode] = chip

	_front_button = Ui.button("정면으로", "PrimaryButton", 60)
	view.add_child(_front_button)
	_front_button.pressed.connect(view.rig.set_mode.bind("front"))

	_tip = Ui.label(definition.get("tip", ""), "HintLabel", true)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_tip)
	_tip.visible = _tip.text != ""
	view.resized.connect(_fit_overlays)


func _scroll_to(section: String) -> void:
	# Containers sort over the first frames; the card's offset inside the scrolled content
	# (its parent margin included) is the same measure as scroll_vertical.
	await get_tree().process_frame
	await get_tree().process_frame
	var content: Control = _scroll.get_child(0)
	_scroll.scroll_vertical = int(_sections[section].global_position.y - content.global_position.y)


## Overlays are placed by hand: the mode bar sits bottom-left at its minimum size, "정면으로"
## top-right, the gesture tip top-left in the space left of it.
func _fit_overlays() -> void:
	var margin := 12.0
	_mode_bar.size = _mode_bar.get_combined_minimum_size()
	_mode_bar.position = Vector2(margin, view.size.y - _mode_bar.size.y - margin)
	_front_button.size = _front_button.get_combined_minimum_size()
	_front_button.position = Vector2(view.size.x - _front_button.size.x - margin, margin)
	var tip_width := minf(440.0, view.size.x - _front_button.size.x - margin * 3.0)
	# An autowrap label's minimum height depends on its width: set the width first.
	_tip.size = Vector2(maxf(tip_width, 120.0), 0.0)
	_tip.size.y = _tip.get_minimum_size().y
	_tip.position = Vector2(margin, margin)


func _build_panel() -> void:
	_panel = Ui.panel("SideSheet")
	add_child(_panel)
	_scroll = Ui.scroller()
	_panel.add_child(_scroll)
	var pad := Ui.margin(18)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pad)
	var column := Ui.vbox(16)
	pad.add_child(column)

	var header := Ui.vbox(6)
	header.add_child(Ui.label(definition.category, "EyebrowLabel"))
	header.add_child(Ui.label(definition.question, "MutedLabel", true))
	column.add_child(header)

	_sections = {
		"conditions": _build_conditions(),
		"observations": _build_observations(),
		"graph": _build_graph(),
		"explanation": _build_explanation(),
	}
	for id in _sections:
		column.add_child(_sections[id])


func _section(title: String) -> Array:
	var card := Ui.panel()
	var body := Ui.vbox(12)
	card.add_child(body)
	body.add_child(Ui.label(title, "SectionLabel"))
	return [card, body]


func _build_conditions() -> Control:
	var parts := _section("조건 바꾸기")
	var body: VBoxContainer = parts[1]
	for control in definition.controls:
		var row := Ui.hbox(8)
		var caption := Ui.label(control.label, "")
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		body.add_child(row)
		if control.type == "slider":
			var value := Ui.label("", "ValueLabel")
			row.add_child(value)
			var slider := HSlider.new()
			slider.min_value = control.min
			slider.max_value = control.max
			slider.step = control.step
			slider.custom_minimum_size = Vector2(0, 52)
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.value_changed.connect(func(v: float) -> void: _set_control(control.id, v))
			body.add_child(slider)
			_control_widgets[control.id] = {"slider": slider, "value": value}
		else:
			var chips := HFlowContainer.new()
			chips.add_theme_constant_override("h_separation", 8)
			chips.add_theme_constant_override("v_separation", 8)
			var group := ButtonGroup.new()
			var buttons := {}
			for option in control.options:
				var chip := Ui.button(option.label, "ChipButton", 56)
				chip.toggle_mode = true
				chip.button_group = group
				chip.custom_minimum_size.x = 92
				chip.pressed.connect(_set_control.bind(control.id, option.id))
				chips.add_child(chip)
				buttons[option.id] = chip
			body.add_child(chips)
			var note := Ui.label("", "MutedLabel", true)
			body.add_child(note)
			_control_widgets[control.id] = {"buttons": buttons, "note": note}
	var actions := Ui.hbox(10)
	for action in definition.actions:
		var button := Ui.button(action.label, "PrimaryButton" if action.get("style") == "primary" else "", 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(experiment_action.bind(action.id))
		actions.add_child(button)
	body.add_child(actions)
	return parts[0]


func experiment_action(id: String) -> void:
	_updating = true
	experiment.run_action(id)
	_updating = false
	_refresh()


func _set_control(id: String, value: Variant) -> void:
	_updating = true
	experiment.set_control(id, value)
	_updating = false
	# Only this control's conditions changed: sync it, then redraw the readouts and the series.
	_sync_control(id)
	_update_readouts(true)


## state_changed during our own control/action call is covered by that call's single refresh.
func _on_state_changed() -> void:
	if not _updating:
		_refresh()


func _sync_control(id: String) -> void:
	var widgets: Dictionary = _control_widgets.get(id, {})
	var value: Variant = experiment.control_value(id)
	for control in definition.controls:
		if control.id != id:
			continue
		if control.type == "slider":
			widgets.slider.set_value_no_signal(value)
			widgets.value.text = Ui.number(value, int(control.get("digits", 1))) + control.get("unit", "")
		else:
			for option in control.options:
				widgets.buttons[option.id].set_pressed_no_signal(option.id == value)
				if option.id == value:
					var note: String = control.get("note", "")
					if option.has("mu_s"):
						note = "μs = %.2f · μk = %.2f   %s" % [option.mu_s, option.mu_k, note]
					widgets.note.text = note


func _build_observations() -> Control:
	var parts := _section("관찰")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for observation in definition.observations:
		var tile := Ui.panel("Tile")
		var stack := Ui.vbox(2)
		tile.add_child(stack)
		stack.add_child(Ui.label(observation.label, "MutedLabel", true))
		var value := Ui.label("—", "ValueLabel")
		stack.add_child(value)
		grid.add_child(tile)
		_observation_labels[observation.id] = value
	parts[1].add_child(grid)
	return parts[0]


func _build_graph() -> Control:
	var spec: Dictionary = definition.graph
	var parts := _section(spec.get("title", "그래프"))
	_graph = GraphView.new()
	_graph.spec = spec
	parts[1].add_child(_graph)
	var legend := Ui.hbox(16)
	for entry in spec.series:
		var swatch := ColorRect.new()
		swatch.color = Color(entry.color)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(swatch)
		legend.add_child(Ui.label(entry.label, "MutedLabel"))
	parts[1].add_child(legend)
	var y_spec: Dictionary = spec.get("y", {})
	parts[1].add_child(Ui.label("세로: %s (%s)" % [y_spec.get("label", ""), y_spec.get("unit", "")], "MutedLabel"))
	return parts[0]


func _build_explanation() -> Control:
	var parts := _section("설명")
	var body: VBoxContainer = parts[1]
	body.add_child(Ui.label(definition.title, "HeadingLabel", true))
	var steps := Ui.vbox(10)
	var number := 1
	for step in definition.steps:
		var row := Ui.hbox(10)
		var badge := Ui.label(str(number), "StepNumberLabel")
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(badge)
		row.add_child(Ui.label(step, "", true))
		steps.add_child(row)
		number += 1
	body.add_child(steps)
	var observe := Ui.panel("ObserveCard")
	var observe_body := Ui.vbox(4)
	observe.add_child(observe_body)
	observe_body.add_child(Ui.label("관찰 포인트", "ObserveTitleLabel"))
	observe_body.add_child(Ui.label(definition.observe, "ObserveLabel", true))
	body.add_child(observe)
	var law: Dictionary = definition.law
	var law_card := Ui.panel("SoftCard")
	var law_body := Ui.vbox(6)
	law_card.add_child(law_body)
	law_body.add_child(Ui.label(law.title, "SectionLabel"))
	law_body.add_child(Ui.label(law.description, "MutedLabel", true))
	var equation := Ui.label(law.equation, "EquationLabel", true)
	law_body.add_child(equation)
	body.add_child(law_card)
	for term in definition.get("terms", []):
		var term_box := Ui.vbox(2)
		term_box.add_child(Ui.label(term.name, "SectionLabel"))
		term_box.add_child(Ui.label(term.description, "MutedLabel", true))
		body.add_child(term_box)
	return parts[0]


# --- refresh --------------------------------------------------------------------------------

## Everything: all controls, observations and graph (events, actions, a restored state).
func _refresh() -> void:
	if experiment == null or not experiment.is_inside_tree():
		return
	for control in definition.controls:
		_sync_control(control.id)
	_update_readouts(true)


## The 10 Hz poll: controls only change through _set_control / actions, so only the observations
## follow the running experiment; the graph series is rebuilt when the experiment says it changed.
func _poll() -> void:
	if experiment == null or not experiment.is_inside_tree():
		return
	_update_readouts(false)


func _update_readouts(force_graph: bool) -> void:
	var values := experiment.observations()
	for observation in definition.observations:
		var value: Variant = values.get(observation.id)
		var text := "—"
		if value is float or value is int:
			text = Ui.number(value, int(observation.get("digits", 2)))
			var unit: String = observation.get("unit", "")
			if unit != "":
				text += unit if unit == "°" else " " + unit
		elif value is String:
			text = value
		var label: Label = _observation_labels[observation.id]
		if label.text != text:
			label.text = text
	var revision := experiment.graph_revision()
	if force_graph or revision < 0 or revision != _graph_revision:
		_graph_revision = revision
		_graph.set_data(experiment.graph_series())


func _on_mode_changed(mode: String) -> void:
	for id in _mode_buttons:
		_mode_buttons[id].set_pressed_no_signal(id == mode)


func _hide_tip() -> void:
	_tip.visible = false
