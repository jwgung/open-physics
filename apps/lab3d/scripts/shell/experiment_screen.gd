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
const CHOICE_SIZE := Vector2(210.0, 170.0)    # a prediction picture button (UI units)

## Set by App for the screen it opens from --experiment: then the launch args (--ctl-*, --camera,
## ...) apply to this screen only (a rebuilt screen with a saved state restores that state instead).
var apply_launch_args := false

var definition: Dictionary
var experiment: Experiment
var view: View3D
## One-finger object manipulation (null when the experiment declares no `manipulation`).
var manipulator: Manipulator
## Dugi and Puppy on the island (Task 4h, null when the definition has no `cast`), next to the lab
## under the 3D view; Dugi's dialogue box over the view.
var cast: IslandCast
var dialogue: DialogueBox
## Tests: false opens the same screen without the cast (the lab must run the same).
var show_cast := true
var _dialogue_started := false          # the dialogue of the current explanation was opened

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
var _camera_home: Dictionary = {}       # the experiment's opening view (kept across a rebuild): 처음으로 snaps back to it
var _updating := false                  # a control/action is running: refresh once afterwards
var _graph_revision := -2               # Experiment.graph_revision() of the series on the graph
var _slingshot_hud: Label = null        # the big pull readout (Plan G3)
var _slingshot_units: PackedStringArray = PackedStringArray(["°", "m/s"])
var _slingshot_controls: PackedStringArray = PackedStringArray()   # the two controls a pull sets
## The game's first round (Plan G4): the mission strip (도장), Dugi's prediction question and the
## reason he tells once after the first throw.
var _missions: MissionTracker = null
var _judged_run := false              # this attempt earned its stamp (cleared by the next attempt)
var _mission_strip: HBoxContainer = null
var _stamp_labels: Array = []
var _mission_text: Label = null
var _asking := false                  # Dugi's question is open (his box held, the picture buttons)
var _question := ""
var _choices: HBoxContainer = null    # the two picture buttons while asking
var _predict_pick: String = ""        # the picked choice ("farther" / "same")
var _predict_ended: bool = false      # the first throw has ended (or there is no question)
var _reason_pending := ""             # the prediction's reason, told at Dugi's next explanation


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
	return {"controls": controls, "camera": view.rig.get_state(), "camera_home": _camera_home,
		"placements": experiment.placements(), "sidebar": is_sidebar_open()}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if apply_launch_args and (Quality.cmdline_value("auto-drag") != "" or Quality.cmdline_value("auto-release") != ""):
		ProgressStore.path = ProgressStore.BENCH_PATH   # a measurement's throws never earn the child's stamps
	view = View3D.new()
	add_child(view)
	_build_view_overlays()
	_build_sidebar()
	experiment = ExperimentRegistry.instantiate(definition)
	experiment.state_changed.connect(_on_state_changed)
	experiment.impact.connect(view.rig.nudge)
	experiment.close_up.connect(func(spec: Dictionary) -> void: view.rig.focus(spec))
	experiment.close_up_ended.connect(view.rig.end_focus)
	experiment.close_up_cut.connect(view.rig.cut_focus)
	view.set_world(experiment)
	if show_cast:
		cast = IslandCast.create(definition, experiment)
	if cast != null:
		view.viewport.add_child(cast)
	if cast != null and cast.dugi != null:
		dialogue = DialogueBox.new(cast.text)
		view.add_child(dialogue)
		dialogue.closed.connect(func() -> void: cast.dugi.stop())
	if definition.has("manipulation"):
		manipulator = Manipulator.new()
		manipulator.name = "Manipulator"
		view.viewport.add_child(manipulator)
		manipulator.setup(view, experiment)
		view.single_pointer.connect(manipulator.handle_pointer)
		manipulator.changed.connect(_on_manipulator_changed)
		if cast != null:
			manipulator.changed.connect(cast.rearm)
		manipulator.demo_placed.connect(func() -> void:
			if manipulator.demo_action != "":
				_demo_release_left = DEMO_RELEASE_DELAY_S)
	_missions = _make_missions()
	view.rig.follow_source = experiment
	view.rig.configure(definition.camera)
	view.rig.mode_changed.connect(_on_mode_changed)
	view.gesture_used.connect(_hide_tip)
	_on_mode_changed(view.rig.mode)
	resized.connect(_layout)
	_layout()
	_camera_home = view.rig.get_state()   # the definition's view (before a restored, user-turned one)
	if not _state.is_empty():
		_camera_home = _state.get("camera_home", _camera_home)
		_restore_state()
	elif apply_launch_args:
		_apply_launch_args()
		_camera_home = view.rig.get_state()   # a measurement's --camera is the view it opens with
	_refresh()
	_setup_slingshot()   # after the state: a restored launch point is the pull's origin
	_setup_game()        # after the state: the stamp count and the question belong to the saved run
	Bench.reset(definition.get("bench_id", definition.id))


func _restore_state() -> void:
	var controls: Dictionary = _state.get("controls", {})
	_updating = true
	var placements: Dictionary = _state.get("placements", {})
	experiment.change_from_input(func() -> void:
		experiment.begin_batch()
		for id in controls:
			experiment.set_control(id, controls[id])
		for id in placements:
			experiment.manipulation_placed(id, placements[id])
		experiment.end_batch())
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
	if _tip != null and _tip.visible:
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
	_run_dialogue()


## Dugi's dialogue opens when he starts explaining and keeps him pointing until it closes (a tap
## past the last page or its read timer; then his arm comes down). It runs along the bottom of the
## view up to the action buttons or Dugi, whichever is nearer. While the sidebar is open there is no
## dialogue (the sidebar's 관찰 포인트 card has the same words): one open closes, and an explanation
## that starts then is pointing only. Dugi stopping (a user change, 처음으로) closes it at once.
func _run_dialogue() -> void:
	if dialogue == null or cast.dugi == null:
		return
	if _asking:
		_run_question()
		return
	var dugi := cast.dugi
	if dialogue.active:
		if not dugi.speaking() or is_sidebar_open():
			_close_dialogue()
			return
		dugi.hold_on()
		dialogue.visible = _layout_dialogue()
		return
	if dugi.speaking() and dugi.state == "raise" and not _dialogue_started and not is_sidebar_open() and _layout_dialogue():
		_dialogue_started = true
		_hide_tip()
		# Dugi explains only after a throw has ended (cast explain_on): the first explanation tells the
		# prediction's reason once, whether or not the stamp was judged yet.
		dialogue.open(_reason_pending)
		_reason_pending = ""
		dialogue.visible = true
	elif not dugi.speaking():
		_dialogue_started = false


## Dugi's question (Plan G4): his box holds the question with the picture buttons over it. It
## yields to the sidebar (hidden while it is open) and comes back when it closes.
func _run_question() -> void:
	if not dialogue.active and not is_sidebar_open() and _layout_dialogue():
		_hide_tip()
		dialogue.open(_question)
	var shown := dialogue.active and not is_sidebar_open() and _layout_dialogue()
	dialogue.visible = shown
	if _choices != null:
		_choices.visible = shown
		if shown:
			_fit_choices()


## Closes an open dialogue now; Dugi lowers his arm.
func _close_dialogue() -> void:
	if dialogue != null and dialogue.active:
		dialogue.close(true)
		if cast.dugi.speaking():
			cast.dugi.stop()


## Places the dialogue box: right end at the action buttons or Dugi's left edge (when he stands in
## the box's height band), whichever is nearer. False when there is no room.
func _layout_dialogue() -> bool:
	var view_rect := Rect2(Vector2.ZERO, view.size)
	var right := _action_row.position.x - OVERLAY_MARGIN
	var who := dugi_rect()
	if who.size.x > 0.0 and who.end.y > view.size.y - OVERLAY_MARGIN - DialogueBox.PORTRAIT_SIZE:
		right = minf(right, who.position.x - OVERLAY_MARGIN)
	return dialogue.layout(view_rect, right, OVERLAY_MARGIN)


## The overlays Dugi, Puppy and the dialogue must not cover (view space): title, top buttons, key cards,
## actions and the gesture tip while it shows.
func overlay_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c: Control in [_title_bar, _top_buttons, _key_row, _action_row, _tip]:
		if c != null and c.visible:
			out.append(c.get_rect().grow(4.0))
	return out


## A world point on the view (UI units of the view).
func view_point(world: Vector3) -> Vector2:
	return view.rig.unproject_position(world) / (Vector2(view.viewport.size) / view.size)


## The view rect of a world AABB (its 8 corners; empty when a corner is behind the camera).
func view_rect_of(box: AABB) -> Rect2:
	var r := Rect2()
	for i in 8:
		var p := box.get_endpoint(i)
		if view.rig.is_position_behind(p):
			return Rect2()
		r = Rect2(view_point(p), Vector2.ZERO) if i == 0 else r.expand(view_point(p))
	return r


## Dugi on the view (empty without him).
func dugi_rect() -> Rect2:
	if cast == null or cast.dugi == null:
		return Rect2()
	return view_rect_of(cast.dugi.bounds())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not handle_back():
		back_requested.emit()


## The screen's own "← 지도" button goes the same way as Android back / Esc: an open sidebar closes first.
func _on_back_pressed() -> void:
	if not handle_back():
		back_requested.emit()


## Back (Android back, Esc): closes an open sidebar first. Returns true if it did.
func handle_back() -> bool:
	if not is_sidebar_open():
		return false
	close_sidebar()
	return true


# --- slingshot (Plan G3) ------------------------------------------------------------------------

## The slingshot (Angry Birds): the experiment offers its own `slingshot_setup()` (the object, the
## surface the pull snaps on, the launch point, the two controls a pull sets). Pressing the ball
## and pulling it back shows the big readout and the arrow of the (angle, speed) the release will
## throw (the reversed pull); letting go after a real pull commits them as the controls (the
## sliders in "자세히" follow) and throws with the "release" action, the same run as setting the
## controls and pressing "공 놓기". A tap or a cancel throws nothing and changes nothing. After a
## run the next press resets it first (처음으로's reset): the next shot is ready.
func _setup_slingshot() -> void:
	if manipulator == null or not experiment.has_method("slingshot_setup"):
		return
	var spec: Dictionary = experiment.slingshot_setup()
	if spec.is_empty():
		return
	_slingshot_controls = PackedStringArray(spec.controls)
	manipulator.set_slingshot(str(spec.object), spec.surface, spec.launch, func() -> Vector2:
		return Vector2(experiment.control_value(_slingshot_controls[0]), experiment.control_value(_slingshot_controls[1])))
	manipulator.slingshot.connect(_on_slingshot)
	_make_slingshot_hud()
	_slingshot_units = PackedStringArray([str(spec.units.get("angle", "°")), str(spec.units.get("speed", "m/s"))])


## The big readout shown while a pull is held (white with a dark shadow, over the 3D view):
## "45° · 9.0 m/s".
func _make_slingshot_hud() -> void:
	if _slingshot_hud != null:
		return
	_slingshot_hud = Ui.label("", "HeadingLabel")   # one line (a wrapping label would have no width)
	_slingshot_hud.name = "SlingshotReadout"
	_slingshot_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slingshot_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slingshot_hud.add_theme_color_override("font_color", Color("ffffff"))
	_slingshot_hud.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_slingshot_hud.add_theme_constant_override("shadow_offset_x", 2)
	_slingshot_hud.add_theme_constant_override("shadow_offset_y", 2)
	_slingshot_hud.add_theme_font_size_override("font_size", 44)
	view.add_child(_slingshot_hud)
	_slingshot_hud.visible = false


## The pull's readout text: "45° · 9.0 m/s" (the values the release throws, already on the grids).
func slingshot_readout(value: Vector2) -> String:
	return "%d%s · %s %s" % [int(roundf(value.x)), _slingshot_units[0], Ui.number(value.y, 1), _slingshot_units[1]]


## The big pull readout centred under the key cards and the mission strip (clear of both).
func _fit_slingshot_hud() -> void:
	if _slingshot_hud == null:
		return
	_slingshot_hud.size = _slingshot_hud.get_combined_minimum_size()
	var top := _key_row.position.y + _key_row.size.y
	if _mission_strip != null:
		top = maxf(top, maxf(_mission_strip.get_rect().end.y, _mission_text.get_rect().end.y))
	_slingshot_hud.position = Vector2((view.size.x - _slingshot_hud.size.x) * 0.5, top + 16.0)


## Manipulator.slingshot: "rearm" resets a finished run (the next shot), "pull" moves the readout
## and the arrow, "release" commits the pull and throws, "cancel" puts everything back as it was.
func _on_slingshot(state: String, value: Variant) -> void:
	match state:
		"rearm":
			_new_attempt()
			_updating = true
			experiment.change_from_input(experiment.run_action.bind("reset"))
			_updating = false
			if cast != null:
				cast.reset()
			_refresh()
		"pull":
			if _asking:
				_end_question()   # the child went for the ball: the question goes, unanswered
			_slingshot_hud.text = slingshot_readout(value)
			_slingshot_hud.visible = true
			_fit_slingshot_hud()
			experiment.set_slingshot_preview(value)
		"cancel":
			_slingshot_hud.visible = false
			experiment.set_slingshot_preview(Vector2.INF)
		"release":
			_slingshot_hud.visible = false
			experiment.set_slingshot_preview(Vector2.INF)
			var v: Vector2 = value
			_new_attempt()
			_updating = true
			experiment.change_from_input(func() -> void:
				experiment.set_control(_slingshot_controls[0], v.x)
				experiment.set_control(_slingshot_controls[1], v.y))
			experiment.change_from_input(experiment.run_action.bind("release"))
			_updating = false
			if cast != null:
				cast.user_changed()
			_refresh()


# --- game: the mission round (Plan G4) -----------------------------------------------------------

## The mission tracker (Plan G1), when the experiment has missions; it starts from the saved stamps.
func _make_missions() -> MissionTracker:
	if MissionTracker.missions(definition).is_empty():
		return null
	var tracker := MissionTracker.new()
	tracker.definition = definition
	tracker.progress = _mission_progress
	tracker.start()
	return tracker


## The mission judges the current attempt (MissionTracker's header) while the lab's status is one
## of the missions' judge_on states and the lab is settled (the engine has finished the landing,
## not merely reached the formula landing within the slack): the stamp from the formula values the
## panel shows and the lab's control values (MissionTracker only reads). Nothing is latched before
## a stamp; an attempt that earned one is done until the next attempt (_new_attempt, or the lab
## back at "ready"). Once the run has its result (reveal_on) the prediction's question is over.
func _missions_judge() -> void:
	if _missions == null:
		return
	var status := experiment.status()
	if status == "ready":
		_judged_run = false
		return
	var judging := not _judged_run and _missions.stage() >= 0 and status in MissionTracker.judge_on(definition)
	if not (judging or (not _predict_ended and status in MissionTracker.reveal_on(definition))) or not experiment.settled():
		return
	var values := experiment.observations()
	if judging and _missions.on_run_ended(status, experiment, values):
		_judged_run = true
	if MissionTracker.result_in(definition, status, values):
		_predict_finish()


## The child acted on the lab (an action, a condition, an object put down or back, a slingshot
## throw): a new attempt, which may earn its own stamp.
func _new_attempt() -> void:
	_judged_run = false


## The experiment has missions: the stamp strip (도장) under the key cards, and Dugi's prediction
## question (his dialogue box, two picture buttons) before the first throw while stages are left.
## Nothing here moves a body or sets a control (physics stays the formulas').
func _setup_game() -> void:
	if _missions == null:
		return
	_make_mission_strip()
	_show_stamps(_missions.stamps)
	var predict := MissionTracker.predict(definition)
	if predict.is_empty() or _missions.stage() < 0 or dialogue == null:
		_predict_ended = true   # the round is done (or no Dugi to ask): no question
		return
	_reason_pending = str(predict.get("reason", ""))
	_ask(str(predict.get("question", "")), predict.get("choices", []))


## The stamp strip: one 도장 per stage (filled by the saved count) and the current stage's text.
func _make_mission_strip() -> void:
	_mission_strip = Ui.hbox(8)
	_mission_strip.name = "MissionStrip"
	_mission_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_mission_strip)
	for i in MissionTracker.missions(definition).get("stages", []).size():
		var stamp := Ui.label("○", "KeyValueLabel")   # no wrap: a wrapping label has no width in the row
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mission_strip.add_child(stamp)
		_stamp_labels.append(stamp)
	_mission_text = Ui.label("", "KeyValueLabel", true)
	_mission_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.add_child(_mission_text)
	_fit_mission_strip()


func _fit_mission_strip() -> void:
	if _mission_strip == null:
		return
	var m := OVERLAY_MARGIN
	var key_bottom := _key_row.position.y + maxf(_key_row.size.y, 80.0)
	var y := key_bottom + 8.0
	_mission_strip.size = _mission_strip.get_combined_minimum_size()
	_mission_strip.position = Vector2(m, y)
	if _mission_text != null:
		var max_w := view.size.x - m * 2.0 - _mission_strip.size.x - 8.0
		_mission_text.custom_minimum_size.x = maxf(120.0, max_w)
		_mission_text.size = Vector2(_mission_text.custom_minimum_size.x, 0.0)
		_mission_text.size.y = _mission_text.get_minimum_size().y
		_mission_text.position = Vector2(m + _mission_strip.size.x + 8.0, y)


func _show_stamps(count: int) -> void:
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	for i in _stamp_labels.size():
		var stamp := _stamp_labels[i] as Label
		stamp.text = "●" if i < count else "○"
		stamp.add_theme_color_override("font_color",
			Color("4d8f3f") if i < count else Color("c9b892"))
	if _mission_text == null:
		return
	if count >= stages.size():
		_mission_text.text = "모두 완료! (깃발이 섬에 섰어요)"
	else:
		_mission_text.text = str(stages[count].get("text", ""))


## Dugi asks (Plan G4): his dialogue box with the question (portrait and name tag, held open until
## an answer) and the two picture buttons above it. Only the buttons take touches; the 3D view
## under them works as before (a pull on the ball ends the question unanswered).
func _ask(question: String, choices: Array) -> void:
	_asking = true
	dialogue.hold = true
	_choices = Ui.hbox(16)
	_choices.name = "PredictChoices"
	_choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_choices)
	for choice in choices:
		_choices.add_child(_choice_button(choice))
	_question = question
	_choices.visible = false   # _run_dialogue lays the box out, then shows both


## A big picture button: its drawing (PredictPictures) over its label.
func _choice_button(choice: Dictionary) -> Button:
	var button := Ui.button("", "", 0)
	button.name = "Choice_%s" % str(choice.get("id", ""))
	button.custom_minimum_size = CHOICE_SIZE
	var stack := Ui.vbox(4)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	button.add_child(stack)
	var picture := Control.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.custom_minimum_size = Vector2(CHOICE_SIZE.x - 20.0, CHOICE_SIZE.y - 70.0)
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var kind := str(choice.get("picture", ""))
	picture.draw.connect(func() -> void: PredictPictures.draw(picture, kind))
	stack.add_child(picture)
	var caption := Ui.label(str(choice.get("label", "")), "HeadingLabel")
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption)
	button.pressed.connect(_predict_pick_choice.bind(str(choice.get("id", ""))))
	return button


## The picture buttons over the dialogue box, at its right end (the ball and the cat stand on
## the left: they stay in sight while Dugi asks).
func _fit_choices() -> void:
	if _choices == null:
		return
	_choices.size = _choices.get_combined_minimum_size()
	var box: Rect2 = dialogue.rects()[0]
	var left := maxf(box.position.x + DialogueBox.PORTRAIT_SIZE, box.end.x - _choices.size.x)
	_choices.position = Vector2(left, box.position.y - DialogueBox.NAME_LIFT - _choices.size.y - 12.0)


## A picture is tapped: the pick is kept (the strip shows it until the run ends) and the question
## goes at once (nothing of it stays to catch the next touch).
func _predict_pick_choice(choice_id: String) -> void:
	if not _asking:
		return
	_predict_pick = choice_id
	var picked := ""
	for choice in MissionTracker.predict(definition).get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			picked = str(choice.get("label", ""))
	_end_question()
	if _mission_text != null and picked != "":
		_mission_text.text = "예측: " + picked


## The question ends (an answer or a pull): the box closes and the buttons go.
func _end_question() -> void:
	if not _asking:
		return
	_asking = false
	dialogue.hold = false
	dialogue.close(true)
	if _choices != null:
		_choices.queue_free()
		_choices = null


## The first throw has ended (judged): the question is over and the strip shows the stage again.
## Dugi tells the reason the next time he explains (once: _reason_pending).
func _predict_finish() -> void:
	if _predict_ended:
		return
	_predict_ended = true
	_end_question()
	_show_stamps(_missions.stamps)


## A stamp was saved (MissionTracker, more than was stored): the strip fills it in (the next
## stage's text appears) and, on the last one, the puppy celebrates.
func _mission_progress(_id: String, stamps: int) -> void:
	_show_stamps(stamps)
	if cast != null and cast.puppy != null and MissionTracker.missions(definition).get("stages", []).size() == stamps:
		cast.puppy.celebrate()


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
	_close_dialogue()   # at once: a tap in this frame must reach the controls, not a stale box
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
	var back := Ui.button("← 지도", "FlatButton", 56)
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
	# Settings live on the island map (Plan G2). The game's labs keep their sliders behind "자세히".
	var game := not MissionTracker.missions(definition).is_empty()
	_sidebar_button = Ui.button("자세히" if game else "설명·조건", "PrimaryButton", 56)
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
	if _mission_strip != null:
		_fit_mission_strip()
	if _asking and dialogue != null and dialogue.active:
		dialogue.visible = _layout_dialogue()
		_fit_choices()
	if _slingshot_hud != null and _slingshot_hud.visible:
		_fit_slingshot_hud()
	if dialogue != null and dialogue.active:
		dialogue.visible = _layout_dialogue()   # follows the view at once (a resize)
	# Beside the actions when there is room, otherwise above them (a narrow view with many actions:
	# orbit's three buttons beside the open sidebar on a tablet).
	var beside := width - _action_row.size.x - m * 3.0
	var tip_width := minf(TIP_MAX_WIDTH, beside if beside >= TIP_MIN_WIDTH else width - m * 2.0)
	if _tip != null:
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
	experiment.change_from_input(experiment.run_action.bind(id))


func experiment_action(id: String) -> void:
	_drop_held_object()
	_new_attempt()
	_updating = true
	experiment.change_from_input(experiment.run_action.bind(id))
	_updating = false
	if cast != null:
		if id == "reset":
			cast.reset()
		else:
			cast.user_changed()
	if id == "reset":
		_snap_camera_home()
	_refresh()


## 처음으로: the camera back to the view the screen opened with, at once (no easing).
func _snap_camera_home() -> void:
	if not _camera_home.is_empty():
		view.rig.set_state(_camera_home)


func _set_control(id: String, value: Variant) -> void:
	_drop_held_object()
	_new_attempt()
	_updating = true
	experiment.change_from_input(experiment.set_control.bind(id, value))
	_updating = false
	if cast != null:
		cast.user_changed()
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
		_missions_judge()   # a result state (the missions' judge_on) judges the mission stamp
		_refresh()


func _on_manipulator_changed() -> void:
	_new_attempt()   # an object put down or put back (a let-go handle, a placed ball)
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
	_missions_judge()   # a run can end between state_changed events (the engine's settled report)


## The displayed text of an observation value (panel tiles and key cards show the same text).
## A mission's answer before the throw has ended (missions.hidden_until_end): "?" and the unit.
static func hidden_observation(observation: Dictionary) -> String:
	var unit: String = observation.get("unit", "")
	if unit == "":
		return "?"
	return "?" + unit if unit == "°" else "? " + unit


## The observation ids a mission round hides now: its hidden_until_end ones until the run has its
## result (MissionTracker.result_in: the throw landed, went out or hit the fence; the box slides; the
## pendulum's first period is measured); `values` are the observations shown now.
func _hidden_answers(values: Dictionary) -> Array:
	if _missions == null or MissionTracker.result_in(definition, experiment.status(), values):
		return []
	return MissionTracker.missions(definition).get("hidden_until_end", [])


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
	var hidden := _hidden_answers(values)
	for observation in definition.observations:
		var text := format_observation(observation, values.get(observation.id))
		if hidden.has(observation.id):
			text = hidden_observation(observation)
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
	if _tip == null or not _tip.visible or _tip_tween != null:
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
