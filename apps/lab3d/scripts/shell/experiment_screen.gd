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
## The game's first round (Plan G4): the mission strip (도장), Dugi's prediction question and the
## puppy's celebration when the last stamp comes.
var _mission_strip: HBoxContainer = null
var _stamp_labels: Array = []
var _mission_text: Label = null
var _predict_overlay: Control = null
var _predict_pick: String = ""   # the picked choice ("farther" / "same"); shown on the strip after the run
var _predict_ended: bool = false
var _mission_just_stamped := false   # the last stamp just came (the puppy celebrates)


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
	if _mission_just_stamped:
		_mission_just_stamped = false
		if cast != null and cast.puppy != null:
			cast.puppy.celebrate()
	_run_dialogue()


## Dugi's dialogue opens when he starts explaining and keeps him pointing until it closes (a tap
## past the last page or its read timer; then his arm comes down). It runs along the bottom of the
## view up to the action buttons or Dugi, whichever is nearer. While the sidebar is open there is no
## dialogue (the sidebar's 관찰 포인트 card has the same words): one open closes, and an explanation
## that starts then is pointing only. Dugi stopping (a user change, 처음으로) closes it at once.
func _run_dialogue() -> void:
	if dialogue == null or cast.dugi == null:
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
		dialogue.open()
		dialogue.visible = true
	elif not dugi.speaking():
		_dialogue_started = false


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
		if c.visible:
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


# --- slingshot (Plan G3) ------------------------------------------------------------------------

## The slingshot (the ball's pull sets the launch, Angry Birds style): the experiment must offer
## its own `slingshot_setup()` (object id, launch point, ArrowSurface, and how a pull commits).
## Pulling the ball shows the big angle / speed readout; letting go commits the pull as the
## angle and speed controls (the sliders in "자세히" follow) and throws. The formula path stays
## hidden while a pull is held (no trajectory preview).
func _setup_slingshot() -> void:
	if manipulator == null or not experiment.has_method("slingshot_setup"):
		return
	var spec: Dictionary = experiment.slingshot_setup()
	if spec.is_empty():
		return
	manipulator.set_slingshot(str(spec.object), Vector3(spec.from), spec.surface)
	manipulator.slingshot.connect(_on_slingshot)
	_make_slingshot_hud()
	_slingshot_units = PackedStringArray([str(spec.units.get("angle", "°")), str(spec.units.get("speed", "m/s"))])


## The big readout shown while a pull is held (white with a shadow, over the 3D view):
## "45° · 9.0 m/s".
func _make_slingshot_hud() -> void:
	if _slingshot_hud != null:
		return
	_slingshot_hud = Ui.label("", "HeadingLabel", true)
	_slingshot_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slingshot_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slingshot_hud.add_theme_color_override("font_color", Color("ffffff"))
	# A dark outline so the white numbers read over the island (a Label's shadow, the theme's
	# own shadow constant: font_shadow_color on the label, its offset from the theme).
	var theme := get_theme()
	if theme != null and theme.has_color("font_shadow_color", "Label"):
		_slingshot_hud.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
		_slingshot_hud.add_theme_constant_override("shadow_offset_x", 2)
		_slingshot_hud.add_theme_constant_override("shadow_offset_y", 2)
	view.add_child(_slingshot_hud)
	_slingshot_hud.visible = false


## The pull's readout text: "45° · 9.0 m/s" (whole degrees on the pull's 5 deg grid).
func _slingshot_readout(value: Variant) -> String:
	var v: Vector2 = value
	return "%d%s · %s%s" % [int(roundf(v.x)), _slingshot_units[0], Ui.number(v.y, 1), _slingshot_units[1]]


## The big pull readout under the top buttons, centred (it stays clear of the key cards and the
## action buttons).
func _fit_slingshot_hud() -> void:
	if _slingshot_hud == null:
		return
	_slingshot_hud.position = Vector2((view.size.x - _slingshot_hud.size.x) * 0.5, _top_buttons.position.y + _top_buttons.size.y + 16.0)


## The deferred slingshot throw (see _on_slingshot "release"): runs after the manipulator's
## manipulation_cancelled has restored the cat's grip.
func _slingshot_release() -> void:
	if experiment == null:
		return
	_updating = true
	experiment.change_from_input(experiment.run_action.bind("release"))
	_updating = false
	_refresh()

## The mission tracker (Plan G1), when the experiment has missions: judged on the run's end
## (status + observations), never on the fly.
var _missions: MissionTracker = null


func _make_missions() -> MissionTracker:
	if MissionTracker.missions(definition).is_empty():
		return null
	var tracker := MissionTracker.new()
	tracker.definition = definition
	tracker.progress = _mission_progress
	return tracker


## Manipulator.slingshot handler: the pull moves the big readout and the experiment's arrow
## preview (no formula path or ring); a release commits the pulled angle and speed as the
## controls and throws (the experiment's "release" action).
func _on_slingshot(state: String, value: Variant) -> void:
	match state:
		"pull":
			_slingshot_hud.text = _slingshot_readout(value)
			_slingshot_hud.visible = true
			_fit_slingshot_hud()
			if experiment.has_method("set_slingshot_preview"):
				experiment.set_slingshot_preview(value)
		"release":
			_slingshot_hud.visible = false
			if experiment.has_method("set_slingshot_preview"):
				experiment.set_slingshot_preview(Vector2.INF)
			var v: Vector2 = value
			_updating = true
			experiment.change_from_input(func() -> void:
				experiment.set_control("angle", v.x)
				experiment.set_control("speed", v.y))
			# The cat's grip is restored by the experiment's manipulation_cancelled (the ball's
			# pick-up put the cat in "free"; the pull's end puts it back in "hold").
			_updating = false
			_sync_control("angle")
			_sync_control("speed")
			_update_readouts(true)
			if cast != null:
				cast.user_changed()
			_refresh()
			_missions_judge()
			# The throw runs after the manipulator's manipulation_cancelled restores the cat's grip
			# (the signal emission is synchronous; the cancel comes after this handler returns).
			call_deferred("_slingshot_release")


## The run has reached its end state: the mission stamp, judged on the formula value the panel
## shows (MissionTracker reads the lab and the observations; it never moves anything). Judged once
## per run: while the ball waits (status "ready"), a new run's landing is the next one.
var _missions_end := false


func _missions_judge() -> void:
	if _missions == null or _missions_end:
		return
	var status := experiment.status()
	# The engine's settled report can land between the lab's status changes (the "landed" status
	# is reported once during the flight, then the ball rests): a lab that flags its landing
	# (projectile's _landed_now) is judged on the first settled poll after it.
	if status != MissionTracker.SUCCESS_STATUS and experiment.has_method("landed_now") \
			and (experiment as Node).landed_now():
		status = MissionTracker.SUCCESS_STATUS
	if status == MissionTracker.SUCCESS_STATUS:
		_missions_end = true
		_missions.on_run_ended(status, experiment, experiment.observations())
		_predict_finish()   # the run ended: the prediction's reason (once per screen)
	elif status == "ready":
		_missions_end = false   # the ball is back on the stand: the next run is judged again


# --- game: the mission round (Plan G4) -----------------------------------------------------------

## The experiment has missions: the stamp strip (도장) under the key cards, Dugi's prediction
## question (the two pictures) before the run, and the celebration when the last stamp comes.
## Nothing here moves a body or sets a control (physics stays the formulas').
func _setup_game() -> void:
	if _missions == null:
		return
	_make_mission_strip()
	var stamps := ProgressStore.stamps(ProgressStore.load(), str(definition.get("id", "")))
	_show_stamps(stamps)
	if MissionTracker.predict(definition).is_empty():
		return
	if stamps < 3:
		_show_predict(MissionTracker.predict(definition).get("question", ""))
	else:
		_predict_ended = true   # the round is done: no more question


## The stamp strip: "미션" + one 도장 per stage (filled by the saved count) + the current stage's
## text. Filled when a stage clears, the next stage's text appears.
func _make_mission_strip() -> void:
	_mission_strip = Ui.hbox(10)
	_mission_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_mission_strip)
	var caption := Ui.label("미션", "KeyLabel", true)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_strip.add_child(caption)
	for i in MissionTracker.missions(definition).get("stages", []).size():
		var stamp := Ui.label("도장", "KeyValueLabel", true)
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mission_strip.add_child(stamp)
		_stamp_labels.append(stamp)
	_mission_text = Ui.label("", "KeyValueLabel", true)
	_mission_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_strip.add_child(_mission_text)
	_fit_mission_strip()


func _fit_mission_strip() -> void:
	if _mission_strip == null:
		return
	_mission_strip.size = _mission_strip.get_combined_minimum_size()
	_mission_strip.position = _key_row.position + Vector2(0.0, _key_row.size.y + 8.0)


func _show_stamps(count: int) -> void:
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	for i in _stamp_labels.size():
		(_stamp_labels[i] as Label).add_theme_color_override("font_color",
			Color("4d8f3f") if i < count else Color("c9b892"))
	if _mission_text == null:
		return
	if count >= stages.size():
		_mission_text.text = "모두 완료! (깃발이 섬에 섰어요)"
	else:
		_mission_text.text = str(stages[count].get("text", ""))


## The prediction (predict block): Dugi asks his question, then the two pictures are tappable.
## A tap picks one and shows it until the run ends; after the run Dugi tells the reason. The
## question is Dugi's own (the dialogue box keeps the observe text of the lab).
func _show_predict(question: String) -> void:
	var predict: Dictionary = MissionTracker.predict(definition)
	_predict_overlay = Control.new()
	_predict_overlay.name = "PredictOverlay"
	_predict_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_predict_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	view.add_child(_predict_overlay)
	_predict_overlay.gui_input.connect(_on_predict_input)
	var stack := Ui.vbox(10)
	stack.position = Vector2(40.0, view.size.y * 0.3)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_predict_overlay.add_child(stack)
	var ask := Ui.label(question, "HeadingLabel", true)
	ask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(ask)
	var row := Ui.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(row)
	for choice in predict.get("choices", []):
		var button := Ui.button(str(choice.get("label", "")), "PrimaryButton", 64)
		button.custom_minimum_size.x = 132
		button.pressed.connect(_predict_pick_choice.bind(str(choice.get("id", ""))))
		row.add_child(button)


func _predict_pick_choice(choice_id: String) -> void:
	if _predict_overlay == null:
		return
	_predict_pick = choice_id
	# The picked label (it stays on the strip after the run).
	var picked: String = ""
	for choice in MissionTracker.predict(definition).get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			picked = str(choice.get("label", ""))
	for c: Node in _predict_overlay.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _mission_text != null and picked != "":
		_mission_text.text = "예측: " + picked


func _on_predict_input(_event: InputEvent) -> void:
	# A tap anywhere else closes the question (the run can start without a pick).
	if _predict_overlay != null:
		_predict_overlay.queue_free()
		_predict_overlay = null


## The run ended (judged): the reason behind the prediction (Dugi explains it), then the overlay
## is gone. Runs once per screen when a prediction was shown.
func _predict_finish() -> void:
	if _predict_ended:
		return
	_predict_ended = true
	if _predict_overlay != null:
		_predict_overlay.queue_free()
		_predict_overlay = null
	var reason: String = MissionTracker.predict(definition).get("reason", "")
	if reason == "" or dialogue == null:
		return
	# Dugi explains the reason (the prediction's path, separate from the lab's observe text).
	dialogue.set_words(reason)


## A stamp was saved (MissionTracker, on its own run): the strip fills it in (the next stage's
## text appears) and, when the last one comes, the puppy celebrates for a moment.
func _mission_progress(_id: String, stamps: int) -> void:
	_show_stamps(stamps)
	if _mission_strip != null and _mission_strip.visible and cast != null and cast.puppy != null \
			and MissionTracker.missions(definition).get("stages", []).size() == stamps:
		_mission_just_stamped = true


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
	if _mission_strip != null:
		_fit_mission_strip()
	if _slingshot_hud != null and _slingshot_hud.visible:
		_fit_slingshot_hud()
	if dialogue != null and dialogue.active:
		dialogue.visible = _layout_dialogue()   # follows the view at once (a resize)
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
	experiment.change_from_input(experiment.run_action.bind(id))


func experiment_action(id: String) -> void:
	_drop_held_object()
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
		_missions_judge()   # the end state (landed, out, fence) judges the mission stamp
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
	_missions_judge()   # a run can end between state_changed events (the engine's settled report)


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
