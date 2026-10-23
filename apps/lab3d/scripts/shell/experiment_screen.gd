## Experiment screen (Task 2d, landscape only): the 3D view fills the screen; over it sit the
## back / title / settings / sidebar buttons, the experiment's key observations as small cards
## (definition.key_observations) and its action buttons. Everything else (question, camera modes,
## conditions, all observations, graph, steps, law, terms) is in the right sidebar, which slides
## in and out. When it is open the 3D view shrinks to the area left of it (nothing in the scene is
## hidden behind the sidebar, and the sidebar needs no background: the clear color shows through,
## docs/ui-resolution.md).
class_name ExperimentScreen
extends Control

signal back_requested
signal settings_requested

const UI_REFRESH_HZ := 10.0
const SIDEBAR_WIDTH := 470.0
const SIDEBAR_MAX_FRACTION := 0.42      # of the screen width (tablet 1152 units -> 470, phone 1560 -> 470)
const SIDEBAR_SLIDE_S := 0.22
const OVERLAY_MARGIN := 12.0
const KEY_CARD_WIDTH := 200.0
const TIP_SECONDS := 4.0       # the short gesture hint stays this long (or until the first gesture), then fades
const TIP_FADE_S := 0.3
const TIP_MAX_WIDTH := 340.0
const TIP_MIN_WIDTH := 240.0   # narrower than this beside the actions: the tip goes above them
const DEMO_RELEASE_DELAY_S := 0.4   # --auto-drag: the auto-release waits this long after the demo put its object down

## Set by App for the screen it opens from --experiment: then the launch args (--ctl-*, --camera,
## ...) apply to this screen only (a rebuilt screen with a saved state restores that state instead).
var apply_launch_args := false

var definition: Dictionary
var experiment: Experiment
var view: View3D
## One-finger object manipulation (null when the experiment declares no `manipulation`).
var manipulator: Manipulator

# 3D overlays (children of the view, placed by _fit_overlays).
var _title_bar: PanelContainer
var _back_button: Button
var _title_label: Label
var _top_buttons: HBoxContainer
var _sidebar_button: Button
var _key_row: HBoxContainer
var _key_labels: Dictionary = {}        # observation id -> value Label of its key card
var _action_row: HBoxContainer
var _action_buttons: Dictionary = {}    # action id -> Button
var _tip: Label
var _tip_left := TIP_SECONDS
var _tip_tween: Tween
## Experiments whose short gesture hint was already shown in this app run: it appears the first
## time an experiment opens only (re-entering, rebuilding the screen or changing a condition never
## brings it back). The full text stays in the sidebar's explanation.
static var _tips_shown: Dictionary = {}
# Sidebar.
var _sidebar: PanelContainer
var _sidebar_state := "closed"          # closed, opening, open, closing
var _sidebar_tween: Tween
var _scroll: ScrollContainer
var _mode_buttons: Dictionary = {}
var _observation_labels: Dictionary = {}
var _control_widgets: Dictionary = {}   # id -> {"slider": HSlider, "value": Label} or {"buttons": {}, "note": Label}
var _graph: GraphView
var _sections: Dictionary = {}          # section id -> card (for --scroll-to)
var refresh_count := 0                  # full panel refreshes so far (tests)
var _refresh_left := 0.0
var _auto_release_every := 0.0
var _auto_release_left := 0.0
var _demo_release_left := -1.0          # --auto-drag: seconds until the placed object is released
var _state: Dictionary = {}             # capture_state() of a screen being rebuilt
var _updating := false                  # a control/action is running: refresh once afterwards
var _graph_revision := -2               # Experiment.graph_revision() of the series on the graph


## `state` (optional): capture_state() of a previous screen of the same experiment (conditions
## and camera are restored instead of the defaults / launch args).
func setup(new_definition: Dictionary, state := {}, launch_args := false) -> void:
	definition = new_definition
	_state = state
	apply_launch_args = launch_args


## Conditions (control values), camera and sidebar of this screen, for a rebuild with the same experiment.
func capture_state() -> Dictionary:
	var controls := {}
	for control in definition.controls:
		controls[control.id] = experiment.control_value(control.id)
	return {"controls": controls, "camera": view.rig.get_state(), "placements": experiment.placements(),
		"sidebar": is_sidebar_open()}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view = View3D.new()
	add_child(view)
	_build_view_overlays()
	_build_sidebar()
	experiment = ExperimentRegistry.instantiate(definition)
	experiment.state_changed.connect(_on_state_changed)
	experiment.impact.connect(view.rig.nudge)
	view.set_world(experiment)
	if definition.has("manipulation"):
		manipulator = Manipulator.new()
		manipulator.name = "Manipulator"
		view.viewport.add_child(manipulator)
		manipulator.setup(view, experiment)
		view.single_pointer.connect(manipulator.handle_pointer)
		manipulator.changed.connect(_on_manipulator_changed)
		manipulator.demo_placed.connect(func() -> void:
			if manipulator.demo_action != "":
				_demo_release_left = DEMO_RELEASE_DELAY_S)
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
	experiment.begin_batch()
	for id in controls:
		experiment.set_control(id, controls[id])
	var placements: Dictionary = _state.get("placements", {})
	for id in placements:
		experiment.manipulation_placed(id, placements[id])
	experiment.end_batch()
	_updating = false
	view.rig.set_state(_state.get("camera", {}))   # emits mode_changed; setup() refreshes once
	if _state.get("sidebar", false):
		open_sidebar(false)


## Measurement/screenshot hooks from the launch args (Quality.all_args):
## --camera=<mode>, --ctl-<control>=<value>, --auto-release=<seconds> (re-release periodically),
## --sidebar=open (open the sidebar), --scroll-to=<conditions|observations|graph|explanation>
## (open the sidebar at that section).
func _apply_launch_args() -> void:
	for control in definition.controls:
		var text := Quality.cmdline_value("ctl-" + control.id)
		if text != "":
			_set_control(control.id, float(text) if control.type == "slider" else text)
	var camera := Quality.cmdline_value("camera")
	if camera != "":
		view.rig.set_mode(camera, true)
	var section := Quality.cmdline_value("scroll-to")
	if Quality.cmdline_value("sidebar") == "open" or _sections.has(section):
		open_sidebar(false)
	if _sections.has(section):
		_scroll_to.call_deferred(section)
	var every := Quality.cmdline_value("auto-release")
	if every.is_valid_float():
		_auto_release_every = float(every)
		_auto_release_left = 1.0
	var drag_every := Quality.cmdline_value("auto-drag")
	if drag_every.is_valid_float() and manipulator != null:
		manipulator.start_demo(float(drag_every))


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
			_run_measured_action("release")
	if _demo_release_left >= 0.0:
		_demo_release_left -= delta
		if _demo_release_left < 0.0:
			_run_measured_action(manipulator.demo_action)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not handle_back():
		back_requested.emit()


## The screen's own "← 목록" button goes the same way as Android back / Esc: an open sidebar closes first.
func _on_back_pressed() -> void:
	if not handle_back():
		back_requested.emit()


## Back (Android back, Esc): closes an open sidebar first. Returns true if it did.
func handle_back() -> bool:
	if not is_sidebar_open():
		return false
	close_sidebar()
	return true


# --- layout ---------------------------------------------------------------------------------

func sidebar_width() -> float:
	return roundf(minf(SIDEBAR_WIDTH, size.x * SIDEBAR_MAX_FRACTION))


func is_sidebar_open() -> bool:
	return _sidebar_state == "open" or _sidebar_state == "opening"


## The 3D view is the full screen while the sidebar is closed. Opening shrinks it at once to the
## area left of the sidebar and slides the sidebar into the freed space; closing slides the
## sidebar out first and gives the view the full width when it is gone. The view is resized once
## per open/close, never during the slide (each resize reallocates its SubViewport).
func _layout(snap_slide := true) -> void:
	var w := size.x
	var h := size.y
	var side := sidebar_width()
	var view_width := w if _sidebar_state == "closed" else w - side
	view.position = Vector2.ZERO
	view.size = Vector2(view_width, h)
	_sidebar.size = Vector2(side, h)
	_sidebar.position.y = 0.0
	var sliding := _sidebar_tween != null and _sidebar_tween.is_valid()
	if sliding and snap_slide:
		# A resize in the middle of a slide: stop it and snap to where it was heading, so the
		# sidebar never sits at a target computed for the old window size.
		_sidebar_tween.kill()
		_finish_slide("open" if _sidebar_state == "opening" else "closed")
		return
	if not sliding:
		_sidebar.position.x = w - side if _sidebar_state == "open" else w
	_fit_overlays()


func open_sidebar(animated := true) -> void:
	if is_sidebar_open():
		return
	_sidebar_state = "opening"
	_sidebar.visible = true
	_sidebar_button.visible = false
	_layout(false)   # keeps a running slide: _slide_sidebar restarts it from where it is
	_slide_sidebar(size.x - sidebar_width(), "open", animated)


func close_sidebar(animated := true) -> void:
	if not is_sidebar_open():
		return
	_sidebar_state = "closing"
	_slide_sidebar(size.x, "closed", animated)


func toggle_sidebar() -> void:
	if is_sidebar_open():
		close_sidebar()
	else:
		open_sidebar()


## Tweens only the sidebar's own position (no full-screen layer, art direction "screen change").
func _slide_sidebar(to_x: float, final_state: String, animated: bool) -> void:
	if _sidebar_tween != null and _sidebar_tween.is_valid():
		_sidebar_tween.kill()
	_sidebar_tween = null
	if not animated or not is_inside_tree():
		_sidebar.position.x = to_x
		_finish_slide(final_state)
		return
	_sidebar_tween = _sidebar.create_tween()
	_sidebar_tween.tween_property(_sidebar, "position:x", to_x, SIDEBAR_SLIDE_S) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sidebar_tween.finished.connect(_finish_slide.bind(final_state))


func _finish_slide(final_state: String) -> void:
	_sidebar_tween = null
	_sidebar_state = final_state
	_sidebar.visible = final_state == "open"
	_sidebar_button.visible = final_state == "closed"
	_layout()


# --- building -------------------------------------------------------------------------------

func _build_view_overlays() -> void:
	_title_bar = Ui.panel("ViewOverlay")
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP   # chrome: a touch here never reaches the 3D view
	view.add_child(_title_bar)
	var title_row := Ui.hbox(4)
	_title_bar.add_child(title_row)
	var back := Ui.button("← 목록", "FlatButton", 56)
	back.pressed.connect(_on_back_pressed)
	title_row.add_child(back)
	_back_button = back
	var title := Ui.label(definition.title, "HeadingLabel")
	_title_label = title
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title)

	_top_buttons = Ui.hbox(8)
	_top_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_top_buttons)
	var settings := Ui.button("설정", "", 56)
	settings.pressed.connect(settings_requested.emit)
	_top_buttons.add_child(settings)
	_sidebar_button = Ui.button("설명·조건", "PrimaryButton", 56)
	_sidebar_button.pressed.connect(open_sidebar.bind(true))
	_top_buttons.add_child(_sidebar_button)

	_key_row = Ui.hbox(8)
	_key_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_key_row)
	for id in definition.key_observations:
		var observation := _observation(id)
		var card := Ui.panel("KeyCard")
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card.custom_minimum_size.x = KEY_CARD_WIDTH
		var stack := Ui.vbox(0)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(stack)
		var caption := Ui.label(observation.label, "KeyLabel", true)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(caption)
		var value := Ui.label("—", "KeyValueLabel", true)   # a status text may take two lines
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(value)
		_key_row.add_child(card)
		_key_labels[id] = value

	_action_row = Ui.hbox(10)
	_action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_action_row)
	for action in definition.actions:
		var button := Ui.button(action.label, "PrimaryButton" if action.get("style") == "primary" else "", 64)
		button.custom_minimum_size.x = 140
		button.pressed.connect(experiment_action.bind(action.id))
		_action_row.add_child(button)
		_action_buttons[action.id] = button

	var short_tip: String = definition.get("tip_short", definition.get("tip", ""))
	_tip = Ui.label(short_tip, "HintLabel", true)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_tip)
	_tip.visible = _tip.text != "" and not _tips_shown.has(definition.id)   # recorded in _hide_tip(), once it was seen
	view.resized.connect(_fit_overlays)
	# Wrapped card texts settle their height after the first layout pass (and change with status texts).
	_key_row.minimum_size_changed.connect(_fit_overlays)


func _observation(id: String) -> Dictionary:
	for observation in definition.observations:
		if observation.id == id:
			return observation
	return {}


## Overlays are placed by hand at their minimum sizes: title bar top-left, settings and the
## sidebar button top-right, the key cards under the title bar, the actions bottom-right and the
## gesture tip bottom-left (beside the actions, or above them when the view is too narrow).
func _fit_overlays() -> void:
	if _title_bar == null:
		return
	var m := OVERLAY_MARGIN
	var width := view.size.x
	_top_buttons.size = _top_buttons.get_combined_minimum_size()
	_top_buttons.position = Vector2(width - _top_buttons.size.x - m, m)
	# The title bar takes the room left of the top buttons. When even its minimum does not fit (a very
	# small window), the title text goes first, then the back button's text is clipped, so the bar
	# never reaches under the buttons.
	var room := width - _top_buttons.size.x - m * 3.0
	_title_label.visible = true
	_back_button.clip_text = false
	var title_min := _title_bar.get_combined_minimum_size()
	if title_min.x > room:
		_title_label.visible = false
		title_min = _title_bar.get_combined_minimum_size()
		if title_min.x > room:
			_back_button.clip_text = true
			title_min = _title_bar.get_combined_minimum_size()
	_title_bar.size = Vector2(clampf(room, title_min.x, 560.0), title_min.y)
	_title_bar.position = Vector2(m, m)
	_key_row.size = _key_row.get_combined_minimum_size()
	_key_row.position = Vector2(m, m + maxf(_title_bar.size.y, _top_buttons.size.y) + 8.0)
	_action_row.size = _action_row.get_combined_minimum_size()
	_action_row.position = Vector2(width - _action_row.size.x - m, view.size.y - _action_row.size.y - m)
	# Beside the actions when there is room, otherwise above them (a narrow view with many actions:
	# orbit's three buttons beside the open sidebar on a tablet).
	var beside := width - _action_row.size.x - m * 3.0
	var tip_width := minf(TIP_MAX_WIDTH, beside if beside >= TIP_MIN_WIDTH else width - m * 2.0)
	# An autowrap label's minimum height depends on its width: set the width first.
	_tip.size = Vector2(tip_width, 0.0)
	_tip.size.y = _tip.get_minimum_size().y
	var bottom := view.size.y - m if beside >= TIP_MIN_WIDTH else _action_row.position.y - 8.0
	_tip.position = Vector2(m, bottom - _tip.size.y)


func _scroll_to(section: String) -> void:
	# Containers sort over the first frames; the card's offset inside the scrolled content
	# (its parent margin included) is the same measure as scroll_vertical.
	await get_tree().process_frame
	await get_tree().process_frame
	var content: Control = _scroll.get_child(0)
	_scroll.scroll_vertical = int(_sections[section].global_position.y - content.global_position.y)


func _build_sidebar() -> void:
	_sidebar = Ui.panel("SideSheet")
	_sidebar.visible = false
	add_child(_sidebar)
	_scroll = Ui.scroller()
	_sidebar.add_child(_scroll)
	var pad := Ui.margin(18)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pad)
	var column := Ui.vbox(16)
	pad.add_child(column)

	var header := Ui.hbox(8)
	var heading := Ui.vbox(6)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(Ui.label(definition.category, "EyebrowLabel"))
	heading.add_child(Ui.label(definition.question, "MutedLabel", true))
	header.add_child(heading)
	var close := Ui.button("닫기", "", 56)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_sidebar.bind(true))
	header.add_child(close)
	column.add_child(header)

	_sections = {
		"camera": _build_camera_modes(),
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


## Camera mode chips (Task 2d: in the sidebar, not over the 3D view; the default view is front).
func _build_camera_modes() -> Control:
	var parts := _section("시점")
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for mode in CameraRig.MODES:
		var chip := Ui.button(CameraRig.MODE_LABELS[mode], "ChipButton", 52)
		chip.toggle_mode = true
		chip.button_group = group
		chip.pressed.connect(view.rig.set_mode.bind(mode))
		chips.add_child(chip)
		_mode_buttons[mode] = chip
	parts[1].add_child(chips)
	return parts[0]


func _build_conditions() -> Control:
	var parts := _section("조건 바꾸기")
	var body: VBoxContainer = parts[1]
	for control in definition.controls:
		var row := Ui.hbox(8)
		var caption := Ui.label(control.label, "", true)   # long captions wrap inside the sidebar width
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
	return parts[0]


## An action fired by a measurement hook (--auto-release, --auto-drag): the experiment's own change,
## as in Task 2a, without the UI work of a button press (cancel, full refresh) unless an object is
## held (then it goes back first, as for a button). A selection is still cleared so the height
## handle does not follow a body the action sets moving.
func _run_measured_action(id: String) -> void:
	if manipulator != null and manipulator.mode != "":
		experiment_action(id)
		return
	if manipulator != null and manipulator.selected_id != "":
		manipulator.select("")
	experiment.run_action(id)


func experiment_action(id: String) -> void:
	_drop_held_object()
	_updating = true
	experiment.run_action(id)
	_updating = false
	_refresh()


func _set_control(id: String, value: Variant) -> void:
	_drop_held_object()
	_updating = true
	experiment.set_control(id, value)
	_updating = false
	# Only this control's conditions changed: sync it, then redraw the readouts and the series.
	_sync_control(id)
	_update_readouts(true)


## A control or action changes the experiment under a held object: put it back first. The height
## handle goes away too (a released object may fall or move on, the handle would follow it).
func _drop_held_object() -> void:
	if manipulator != null:
		var was_updating := _updating
		_updating = true   # the caller refreshes once afterwards
		manipulator.cancel()
		manipulator.select("")
		_updating = was_updating


## state_changed during our own control/action call is covered by that call's single refresh; one
## inside a manipulator callback (placed / cancelled) by its `changed`.
func _on_state_changed() -> void:
	if not _updating and not (manipulator != null and manipulator.notifying):
		_refresh()


func _on_manipulator_changed() -> void:
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
					var note: String = option.get("note", control.get("note", ""))   # an option may explain itself (gravity: g)
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
		# Wraps: a long status text must not widen the sidebar past its width (Task 2d).
		var value := Ui.label("—", "ValueLabel", true)
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
	# Wraps when the series do not fit on one line (free fall: three balls + the simulation).
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 16)
	legend.add_theme_constant_override("v_separation", 6)
	for entry in spec.series:
		var swatch := ColorRect.new()
		swatch.color = Color(entry.color)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var item := Ui.hbox(8)
		item.add_child(swatch)
		item.add_child(Ui.label(entry.label, "MutedLabel"))
		legend.add_child(item)
	parts[1].add_child(legend)
	var y_spec: Dictionary = spec.get("y", {})
	parts[1].add_child(Ui.label("세로: %s (%s)" % [y_spec.get("label", ""), y_spec.get("unit", "")], "MutedLabel", true))
	return parts[0]


func _build_explanation() -> Control:
	var parts := _section("설명")
	var body: VBoxContainer = parts[1]
	body.add_child(Ui.label(definition.title, "HeadingLabel", true))
	if definition.get("tip", "") != "":
		var how := Ui.panel("SoftCard")
		var how_body := Ui.vbox(6)
		how.add_child(how_body)
		how_body.add_child(Ui.label("조작 방법", "SectionLabel"))
		how_body.add_child(Ui.label(definition.tip, "MutedLabel", true))
		body.add_child(how)
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
	refresh_count += 1
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


## The displayed text of an observation value (panel tiles and key cards show the same text).
static func format_observation(observation: Dictionary, value: Variant) -> String:
	if value is float or value is int:
		var text := Ui.number(value, int(observation.get("digits", 2)))
		var unit: String = observation.get("unit", "")
		if unit != "":
			text += unit if unit == "°" else " " + unit
		return text
	if value is String:
		return value
	return "—"


func _update_readouts(force_graph: bool) -> void:
	var values := experiment.observations()
	for observation in definition.observations:
		var text := format_observation(observation, values.get(observation.id))
		var label: Label = _observation_labels[observation.id]
		if label.text != text:
			label.text = text
		var key: Label = _key_labels.get(observation.id)
		if key != null and key.text != text:
			key.text = text
	var revision := experiment.graph_revision()
	if force_graph or revision < 0 or revision != _graph_revision:
		_graph_revision = revision
		_graph.set_data(experiment.graph_series())


func _on_mode_changed(mode: String) -> void:
	for id in _mode_buttons:
		_mode_buttons[id].set_pressed_no_signal(id == mode)


## Fades the hint out on its own node (no screen-wide layer), then hides it. This is when the hint
## counts as seen (the timer ran out or the first gesture closed it): a screen rebuilt before that
## (a condition change redraws it from the saved state) shows the hint again.
func _hide_tip() -> void:
	if not _tip.visible or _tip_tween != null:
		return
	_tips_shown[definition.id] = true
	if not is_inside_tree():
		_tip.visible = false
		return
	_tip_tween = _tip.create_tween()
	_tip_tween.tween_property(_tip, "modulate:a", 0.0, TIP_FADE_S)
	_tip_tween.finished.connect(func() -> void: _tip.visible = false)


## For tests: forget which hints were shown, as at a fresh app start.
static func reset_tips_shown() -> void:
	_tips_shown.clear()
