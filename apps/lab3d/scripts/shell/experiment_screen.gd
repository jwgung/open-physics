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
## A game lab's reset button: a short word on a small button (the lab's own label stays in the JSON).
const RESET_SHORT := "다시"
const TIP_MIN_WIDTH := 240.0   # narrower than this beside the actions: the tip goes above them
const DEMO_RELEASE_DELAY_S := 0.4   # --auto-drag: the auto-release waits this long after the demo put its object down
const CHOICE_SIZE := Vector2(210.0, 170.0)    # a prediction picture button (UI units)
const QUESTION_DIM := Color(0.08, 0.12, 0.2, 0.38)   # the scrim behind Dugi's question
const QUESTION_DIM_FADE := 0.2
const CHOICE_HOP := 7.0          # the picture buttons' hop while Dugi asks (UI units, upwards)
const CHOICE_HOP_SPEED := 3.0    # rad/s of the hop's sine (a hop every ~1 s)
## The strip's words for a 7-year-old: all stages done, and the picked prediction before the run.
## (2026-10-28 user decision: no celebration words; a finished round shows its stamps only.)
const DONE_TEXT := ""
const PICK_PREFIX := "내 생각: "
const PICK_SIZE := Vector2(132.0, 112.0)    # a condition picture button (UI units, at least)
const PICK_GAP := 10.0                      # between the buttons of one condition
const PICK_GROUP_GAP := 22.0                # between two conditions' buttons
const MORE_CLOSED := "더 보기"              # the science note's collapsed rest (_build_sidebar)
const MORE_OPEN := "접기"
const ASK_TEXT := "AI에게 더 물어보기"
const ASK_CAPTION := "이 실험의 조건과 숫자로 질문을 만들어, 고른 AI 앱에 보내요."

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
## The lab's sounds (SoundBoard): reads its status and impacts only, beside the lab like the cast.
var sounds: LabSounds
var _dialogue_started := false          # the dialogue of the current explanation was opened

# 3D overlays (children of the view, placed by _fit_overlays).
var _title_bar: PanelContainer
var _back_button: Button
var _title_label: Label
var _top_buttons: HBoxContainer
var _sidebar_button: Button
var _key_row: HBoxContainer
var _key_labels: Dictionary = {}        # observation id -> value Label of its key card
var _key_bars: Dictionary = {}          # observation id -> KidBar of its key card (kid.bars)
var _key_ids: Array = [null]            # the cards built (ExperimentRegistry.shown_cards; [null]: none yet)
var _action_row: HBoxContainer
var _action_buttons: Dictionary = {}    # action id -> Button
var _extra_actions: Array[Button] = []  # a game lab's secondary actions, shown under the conditions in the sidebar
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
var _observation_labels: Dictionary = {}
var _control_widgets: Dictionary = {}   # id -> {"slider": HSlider, "value": Label} or {"buttons": {}, "note": Label}
var _graph: GraphView
var _sections: Dictionary = {}          # section id -> card (for --scroll-to)
var _more: VBoxContainer                # 더 보기's contents (collapsed when the screen opens)
var _more_button: Button
## "AI에게 더 물어보기" (ScienceNote, 2026-10-28; the system chooser with the AI apps only since
## 2026-10-29): a tap hands this run's question and the AI apps' packages (content/ai_apps.json) to
## this handler ((packages, text) -> "chooser" | "clipboard"); tests put a recorder here. The
## default is ScienceNote.send_to_ai.
var ask_handler: Callable = func(packages: Array, text: String) -> String: return ScienceNote.send_to_ai(packages, text)
## A measurement or a device check (Story.measurement_run): the note has no ask button, unless the
## device check of the button itself asks for it (--ask=show, with --progress=bench,--sound=0).
var measurement := Story.measurement_run(Quality.all_args()) and Quality.cmdline_value("ask") != "show"
var _ask_button: Button = null
var _ask_status: Label = null           # "질문을 복사했어요..." when the text went to the clipboard
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
var _slingshot_controls: PackedStringArray = PackedStringArray()   # the controls a pull sets (one or two)
var _slingshot_spec: Dictionary = {}    # the lab's slingshot_setup() (its readout, action, rearm)
## The game's first round (Plan G4): the mission strip (도장), Dugi's prediction question and the
## reason he tells once after the first throw.
var _missions: MissionTracker = null
var _judged_run := false              # this attempt earned its stamp (cleared by the next attempt)
var _mission_strip: HBoxContainer = null
var _mission_pill: PanelContainer = null   # the strip's soft paper background (readable over the scene)
var _stamp_labels: Array = []
var _mission_text: Label = null
var _series_hidden := false           # the graph's hidden_series_until_end lines were left out last time
var _asking := false                  # Dugi's question is open (his box held, the picture buttons)
var _question_shield: ColorRect         # while asking: dims and catches everything but the box and the buttons
var _dialogue_index := -1               # the box's place among the overlays before the question lifted it
var _question := ""
var _choices: HBoxContainer = null    # the two picture buttons while asking
var _choices_popped := false          # the buttons' pop-in has run
var _dialogue_right := NAN              # the open box's right end so far (_layout_dialogue)
var _dialogue_right_for := Vector2.ZERO  # the view size it was found for
var _predict_pick: String = ""        # the picked choice ("farther" / "same")
var _predict_ended: bool = false      # the first throw has ended (or there is no question)
var _reason_pending := ""             # the prediction's reason, told at Dugi's next explanation
## The current stage's condition picture buttons (ConditionPicks, 2026-10-27): a row at the bottom
## of the view, lifted over Dugi's box while he talks, hidden while he asks or when it has no room.
var _picks_row: HBoxContainer = null
var _picks: Array = []                # [{"control": id, "preset": kid.picks entry, "button": Button}]
var _picks_stage := -2                # the stage the row was built for
var _picks_for := Vector4(NAN, 0, 0, 0)   # view width, height, talking, asking the row was laid out for (_fit_picks)
var _picks_box := Rect2()             # Dugi's box it was laid out over
## The celebrations (2026-10-28): the stamp flying into its slot (StampSlam), the strip's filled
## stamps so far (a stamp in flight fills its slot when it lands), the whole-round confetti and the
## card that follows it (RoundDoneCard), the bread cat of the lab (it hops on a stamp).
var _slam: StampSlam = null
var _stamps_landed := 0
var _confetti: Confetti = null
var _done_card: RoundDoneCard = null
var _card_left := -1.0                 # s until the round-done card shows (after the confetti starts)
var _cat: CatActor = null
var _demo_left := -1.0                 # --demo-celebrate: s until the next demo stamp
var _demo_stamps := 0
const CARD_DELAY_S := 0.8
## The story (2026-10-28 "별 조각 찾기"): Puppy's clue on the first visit (before Dugi's question) and,
## when the round is completed, the star piece the bread cat lifts before the card comes.
var _clue := ""                        # Puppy's clue still to tell ("" when none)
var _clue_open := false                # it is in the box now
var _piece: Node3D = null              # the found piece over the bread cat
var _piece_t := 0.0
const PIECE_HOLD_S := 1.4              # the card waits this much longer: the piece is seen first
const PIECE_POP_S := 0.4
const DEMO_STAMP_EVERY_S := 1.6


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
	if apply_launch_args and (Quality.cmdline_value("auto-drag") != "" or Quality.cmdline_value("auto-release") != ""
			or Quality.cmdline_value("demo-celebrate") != ""):
		ProgressStore.path = ProgressStore.BENCH_PATH   # a measurement's throws never earn the child's stamps
	view = View3D.new()
	add_child(view)
	_build_view_overlays()
	_build_sidebar()
	experiment = ExperimentRegistry.instantiate(definition)
	# A game round draws no answer preview before the run (Experiment.answer_preview: visual only).
	experiment.answer_preview = MissionTracker.missions(definition).is_empty()
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
	sounds = LabSounds.create(experiment)
	add_child(sounds)
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
		manipulator.demo_blocked.connect(func() -> void:
			if _action_buttons.has("reset"):
				_run_measured_action("reset"))
	_missions = _make_missions()
	view.rig.follow_source = experiment
	view.rig.configure(definition.camera)
	view.gesture_used.connect(_hide_tip)
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
	view.rig.set_state(_state.get("camera", {}))
	if _state.get("sidebar", false):
		open_sidebar(false)


## Measurement/screenshot hooks from the launch args (Quality.all_args):
## --camera=<mode>, --ctl-<control>=<value>, --auto-release=<seconds> (re-release periodically),
## --sidebar=open (open the sidebar), --scroll-to=<law|numbers|conditions|graph|more|...> (open the
## sidebar at that section; "observations" = numbers, "explanation" = more, opened).
func _apply_launch_args() -> void:
	for control in definition.controls:
		var text := Quality.cmdline_value("ctl-" + control.id)
		if text != "":
			_set_control(control.id, float(text) if control.type == "slider" else text)
	var camera := Quality.cmdline_value("camera")
	if camera != "":
		view.rig.set_mode(camera, true)
	var section := Quality.cmdline_value("scroll-to")
	section = SECTION_ALIASES.get(section, section)
	if Quality.cmdline_value("sidebar") == "open" or _sections.has(section):
		open_sidebar(false)
	if _sections.has(section):
		_scroll_to.call_deferred(section)
	var every := Quality.cmdline_value("auto-release")
	if every.is_valid_float():
		_auto_release_every = float(every)
		_auto_release_left = 1.0
	var demo := Quality.cmdline_value("demo-celebrate")
	if Quality.cmdline_value("demo-story").begins_with("found:"):
		demo = "2.5"   # the story's screenshots: the clue is told, then the stamps and the piece
	if demo.is_valid_float() and _missions != null:
		_demo_left = float(demo)   # screenshots: the stamps and the round's end play (bench store only, nothing judged)
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
	_run_celebration(delta)


## Dugi's dialogue opens when he starts explaining and keeps him pointing until it closes (a tap
## past the last page or its read timer; then his arm comes down). It runs along the bottom of the
## view up to the action buttons or Dugi, whichever is nearer. While the sidebar is open there is no
## dialogue (the sidebar's 관찰 포인트 card has the same words): one open closes, and an explanation
## that starts then is pointing only. Dugi stopping (a user change, 처음으로) closes it at once.
func _run_dialogue() -> void:
	_fit_picks()   # follows the dialogue (opened, closed) and the question
	if dialogue == null or cast.dugi == null:
		return
	if _done_card != null:
		_close_dialogue()   # the round-done card is up: nothing talks behind it
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
	if _clue != "":
		if _clue_open and not dialogue.active:   # the clue was read: Dugi asks
			_clue = ""
			_clue_open = false
			dialogue.set_speaker("dugi")
			dialogue.hold = true
			if _question == "":
				_end_question()
				return
		elif not _clue_open and not dialogue.active and not is_sidebar_open() and _layout_dialogue():
			_hide_tip()
			dialogue.set_speaker("puppy")
			dialogue.hold = false   # a tap or the read timer closes it
			dialogue.open(_clue)
			_clue_open = true
			ProgressStore.set_mark(ProgressStore.CLUES, str(definition.id), true)   # told once
	if _clue == "" and not dialogue.active and not is_sidebar_open() and _layout_dialogue():
		_hide_tip()
		dialogue.open(_question)
	var shown := dialogue.active and not is_sidebar_open() and _layout_dialogue()
	dialogue.visible = shown
	if _choices != null:
		_choices.visible = shown and _clue == ""
		if _choices.visible:
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
	# While the box is open its right end only moves left: Dugi's raised and lowered arm (his drawn
	# bounds) made it grow and shrink every frame (2026-10-27 user report). A new box or a resized
	# view starts over.
	if dialogue.active and view.size == _dialogue_right_for and not is_nan(_dialogue_right):
		right = minf(right, _dialogue_right)
	_dialogue_right = right if dialogue.active else NAN
	_dialogue_right_for = view.size
	return dialogue.layout(view_rect, right, OVERLAY_MARGIN)


## The overlays Dugi, Puppy and the dialogue must not cover (view space): title, top buttons, key cards,
## actions and the gesture tip while it shows.
func overlay_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c: Control in [_title_bar, _top_buttons, _key_row, _action_row, _tip, _picks_row]:
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
	if _done_card != null:
		_done_card.close()   # back closes the round-done card first (the lab stays, like 더 해 보기)
		_done_card = null
		return true
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
## The collision and orbit labs (2026-10-28) pull their ball / planet the same way: the spec may give
## the pull's own value (`value`: pull -> Vector2), its readout (`readout`: value -> text), the
## action that launches (`action`, default "release"), the one that readies the next shot (`rearm`,
## default "reset") and the demo's pulls (`demo`). One control: the value's x.
func _setup_slingshot() -> void:
	if manipulator == null or not experiment.has_method("slingshot_setup"):
		return
	var spec: Dictionary = experiment.slingshot_setup()
	if spec.is_empty():
		return
	_slingshot_spec = spec
	_slingshot_controls = PackedStringArray(spec.controls)
	manipulator.set_slingshot(str(spec.object), spec.surface, spec.launch, func() -> Vector2:
		return Vector2(experiment.control_value(_slingshot_controls[0]),
			experiment.control_value(_slingshot_controls[1]) if _slingshot_controls.size() > 1 else 0.0),
		spec.get("value", Callable()), spec.get("demo", Manipulator.DEMO_PULLS))
	manipulator.slingshot.connect(_on_slingshot)
	_make_slingshot_hud()
	var units: Dictionary = spec.get("units", {})
	_slingshot_units = PackedStringArray([str(units.get("angle", "°")), str(units.get("speed", "m/s"))])


## The big readout shown while a pull is held (white with a dark shadow, over the 3D view):
## "45도 · 1초에 9.0미터".
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


## The pull's readout text in a child's words: "45도 · 1초에 9.0미터" (the values the release throws,
## already on the grids; kid_value).
func slingshot_readout(value: Vector2) -> String:
	var own: Callable = _slingshot_spec.get("readout", Callable())
	if own.is_valid():
		return own.call(value)
	return "%s · %s" % [kid_value(_slingshot_units[0], roundf(value.x), 0), kid_value(_slingshot_units[1], value.y, 1)]


## The big pull readout centred under the key cards and the mission strip (clear of both).
func _fit_slingshot_hud() -> void:
	if _slingshot_hud == null:
		return
	_slingshot_hud.size = _slingshot_hud.get_combined_minimum_size()
	var top := _key_row.position.y + _key_row.size.y
	if _mission_pill != null:
		top = maxf(top, _mission_pill.get_rect().end.y)
	_slingshot_hud.position = Vector2((view.size.x - _slingshot_hud.size.x) * 0.5, top + 16.0)


## Manipulator.slingshot: "rearm" resets a finished run (the next shot), "pull" moves the readout
## and the arrow, "release" commits the pull and throws, "cancel" puts everything back as it was.
func _on_slingshot(state: String, value: Variant) -> void:
	match state:
		"rearm":
			_new_attempt()
			_updating = true
			experiment.change_from_input(experiment.run_action.bind(str(_slingshot_spec.get("rearm", "reset"))))
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
				experiment.begin_batch()
				experiment.set_control(_slingshot_controls[0], on_grid(definition, _slingshot_controls[0], v.x))
				if _slingshot_controls.size() > 1:
					experiment.set_control(_slingshot_controls[1], on_grid(definition, _slingshot_controls[1], v.y))
				experiment.end_batch())
			for id in _slingshot_controls:
				_sync_control(id)
			experiment.change_from_input(experiment.run_action.bind(str(_slingshot_spec.get("action", "release"))))
			_updating = false
			if cast != null:
				cast.user_changed()
			_refresh()


## `value` (a pull's value, a 32-bit Vector2 component) on the slider `id`'s grid in 64 bit: whole
## steps counted from 0 (0.1 m/s: 23 / 10.0 = 2.3, not 2.29999995). A value off the grid (a pull's
## finer grid than the slider's) or a control without a step stays as it is.
static func on_grid(lab_definition: Dictionary, id: String, value: float) -> float:
	for control in lab_definition.get("controls", []):
		if control.id != id or float(control.get("step", 0.0)) <= 0.0:
			continue
		var step := float(control.step)
		if step >= 1.0:
			var whole := roundf(value / step) * step
			return whole if absf(whole - value) < 1e-4 else value
		var cells := roundf(1.0 / step)
		var snapped := roundi(value * cells) / cells
		return snapped if absf(snapped - value) < 1e-4 else value
	return value


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
	var judging := not _judged_run and _missions.stage() >= 0 and status in MissionTracker.judge_on(definition, _missions.stage())
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
	_stamps_landed = _missions.stamps
	_make_mission_strip()
	_show_stamps(_missions.stamps)
	var predict := MissionTracker.predict(definition)
	if _missions.stage() < 0 or dialogue == null:
		_predict_ended = true   # the round is done (or no Dugi to ask): no question, no clue
		return
	# The story: Puppy's clue, once per spot, before the question (the same shield and box).
	if Story.enabled and not Story.clue_seen(str(definition.id)):
		_clue = Story.clue(definition)
	if predict.is_empty():
		_predict_ended = true   # no question: the clue alone, if any
		if _clue != "":
			_ask("", [])
		return
	_reason_pending = str(predict.get("reason", ""))
	_ask(str(predict.get("question", "")), predict.get("choices", []))


## The stamp strip: one 도장 per stage (filled by the saved count) and the current stage's text,
## on a soft paper pill (UiTheme "MissionPill") so the words stay readable over trees and sky.
func _make_mission_strip() -> void:
	_mission_pill = Ui.panel("MissionPill")
	_mission_pill.name = "MissionPill"
	_mission_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_mission_pill)
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


## The stamps and the text side by side under the key cards; the pill behind both fits the text's
## own width (a short stage text gets a short pill), at most the view's width.
func _fit_mission_strip() -> void:
	if _mission_strip == null:
		return
	var m := OVERLAY_MARGIN
	var pad := _mission_pill.get_theme_stylebox("panel").get_minimum_size() * 0.5 if _mission_pill != null else Vector2.ZERO
	var key_bottom := _key_row.position.y + maxf(_key_row.size.y, 80.0)
	var x := m + pad.x
	var y := key_bottom + 8.0 + pad.y
	_mission_strip.size = _mission_strip.get_combined_minimum_size()
	_mission_strip.position = Vector2(x, y)
	if _mission_text == null:
		return
	var max_w := maxf(120.0, view.size.x - m * 2.0 - pad.x * 2.0 - _mission_strip.size.x - 8.0)
	_mission_text.custom_minimum_size.x = 0.0
	var line := _mission_text.get_theme_font("font").get_string_size(_mission_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_mission_text.get_theme_font_size("font_size")).x
	_mission_text.custom_minimum_size.x = minf(max_w, ceilf(line) + 2.0)
	_mission_text.size = Vector2(_mission_text.custom_minimum_size.x, 0.0)
	_mission_text.size.y = _mission_text.get_minimum_size().y
	_mission_text.position = Vector2(x + _mission_strip.size.x + 8.0, y)
	if _mission_pill != null:
		_mission_text.visible = _mission_text.text != ""   # a finished round: the stamps only
		var inner := Rect2(_mission_strip.position, _mission_strip.size)
		if _mission_text.visible:
			inner = inner.merge(_mission_text.get_rect())
		_mission_pill.position = inner.position - pad
		_mission_pill.size = inner.size + pad * 2.0


func _show_stamps(count: int) -> void:
	var stages: Array = MissionTracker.missions(definition).get("stages", [])
	var filled := mini(count, _stamps_landed)   # a stamp still flying (StampSlam) fills its slot when it lands
	for i in _stamp_labels.size():
		var stamp := _stamp_labels[i] as Label
		stamp.text = "●" if i < filled else "○"
		stamp.add_theme_color_override("font_color",
			StampSlam.GREEN if i < filled else StampSlam.EMPTY)
	if _mission_text == null:
		return
	if count >= stages.size():
		_mission_text.text = DONE_TEXT
	else:
		_mission_text.text = str(stages[count].get("text", ""))
	var before := _key_ids
	_build_key_cards(count if count < stages.size() else -1)
	if _key_ids != before:
		_update_readouts(false)
		_fit_overlays()
	_fit_mission_strip()
	_build_picks(count if count < stages.size() else -1)


## Dugi asks (Plan G4): his dialogue box with the question (portrait and name tag, held open until
## an answer) and the two picture buttons above it. Nothing behind them takes a touch until the
## child picks (2026-10-28 user request): a full-view shield over every other overlay and the 3D
## view dims them (it fades in), and the box is lifted above it.
func _ask(question: String, choices: Array) -> void:
	_asking = true
	SoundBoard.play(&"question")
	dialogue.hold = true
	_question_shield = ColorRect.new()
	_question_shield.name = "QuestionShield"
	_question_shield.color = QUESTION_DIM
	_question_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_question_shield.set_anchors_preset(Control.PRESET_FULL_RECT)
	_question_shield.modulate.a = 0.0
	view.add_child(_question_shield)
	create_tween().tween_property(_question_shield, "modulate:a", 1.0, QUESTION_DIM_FADE)
	_dialogue_index = dialogue.get_index()
	view.move_child(dialogue, -1)
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
	var button := Ui.button("", "ChoiceButton", 0)
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


## The picture buttons in the middle of the dimmed view (2026-10-28 user request: easier to see),
## kept above the dialogue box and its name tag.
func _fit_choices() -> void:
	if _choices == null:
		return
	_choices.size = _choices.get_combined_minimum_size()
	var box: Rect2 = dialogue.rects()[0]
	var lowest := box.position.y - DialogueBox.NAME_LIFT - _choices.size.y - 12.0 - CHOICE_HOP
	var top := minf((view.size.y - _choices.size.y) * 0.5, lowest)
	# A small hop (up only: the row never reaches the box) that says "tap one of us".
	var hop := absf(sin(Time.get_ticks_msec() / 1000.0 * CHOICE_HOP_SPEED)) * CHOICE_HOP
	_choices.position = Vector2((view.size.x - _choices.size.x) * 0.5, top - hop)
	if not _choices_popped and _choices.visible:
		_choices_popped = true   # first shown: the row pops in from a little smaller
		_choices.pivot_offset = _choices.size * 0.5
		_choices.scale = Vector2.ONE * 0.8
		create_tween().tween_property(_choices, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
		_mission_text.text = PICK_PREFIX + picked
		_fit_mission_strip()


## The question ends (an answer, or the round's end): the box closes, the buttons and the shield go.
func _end_question() -> void:
	if not _asking:
		return
	_asking = false
	_clue = ""
	_clue_open = false
	dialogue.hold = false
	dialogue.close(true)
	dialogue.set_speaker("dugi")
	if _choices != null:
		_choices.queue_free()
		_choices = null
	if _question_shield != null:
		_question_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE   # gone for a touch in this same frame
		_question_shield.queue_free()
		_question_shield = null
	if _dialogue_index >= 0:
		view.move_child(dialogue, _dialogue_index)   # back under the overlays it sat under
		_dialogue_index = -1
	_fit_picks()


## The first throw has ended (judged): the question is over and the strip shows the stage again.
## Dugi tells the reason the next time he explains (once: _reason_pending).
func _predict_finish() -> void:
	if _predict_ended:
		return
	_predict_ended = true
	_end_question()
	_show_stamps(_missions.stamps)


## A stamp was saved (MissionTracker, more than was stored): the next stage's text appears at once;
## the stamp drops in the middle of the view, lands with a thump and flies into its slot (StampSlam), which
## then fills; the bread cat hops. On the last one the whole round celebrates when it lands. A stamp
## still flying when the next one comes lands at once first.
func _mission_progress(_id: String, stamps: int) -> void:
	if _slam != null:
		_slam.finish()
	_show_stamps(stamps)
	_slam = StampSlam.new()
	var slot := clampi(stamps - 1, 0, maxi(0, _stamp_labels.size() - 1))
	_slam.slot = _stamp_slot_center.bind(slot)
	_slam.slot_radius = _stamp_slot_radius(slot)
	_slam.start = view.size * Vector2(0.5, 0.46)
	_slam.landed.connect(_on_stamp_landed.bind(stamps))
	view.add_child(_slam)
	var cat := lab_cat()
	if cat != null:
		cat.cheer(cat.mode == "free")


## The strip's slot `i` on the view (its centre), where a flying stamp lands.
func _stamp_slot_center(i: int) -> Vector2:
	if i >= _stamp_labels.size() or _mission_strip == null:
		return view.size * 0.5
	var label := _stamp_labels[i] as Label
	return _mission_strip.position + label.position + label.size * 0.5


func _stamp_slot_radius(i: int) -> float:
	if i >= _stamp_labels.size():
		return 14.0
	return maxf(8.0, (_stamp_labels[i] as Label).size.y * 0.32)


## A flying stamp is in its slot: the slot fills; the last one starts the round's celebration.
func _on_stamp_landed(stamps: int) -> void:
	_slam = null
	_stamps_landed = maxi(_stamps_landed, stamps)
	_show_stamps(_missions.stamps if _missions != null else stamps)
	if stamps >= MissionTracker.missions(definition).get("stages", []).size():
		_celebrate_round()


## The whole round is done (in this visit): confetti, the puppy, Dugi and the bread cat cheer
## together, then the round-done card. Pictures and motion only.
func _celebrate_round() -> void:
	if _confetti != null and is_instance_valid(_confetti):
		_confetti.queue_free()
	_confetti = Confetti.new()
	view.add_child(_confetti)
	SoundBoard.play(&"fanfare")
	if cast != null and cast.puppy != null:
		cast.puppy.celebrate()
	if cast != null and cast.dugi != null:
		_close_dialogue()
		cast.dugi.celebrate()
	var cat := lab_cat()
	if cat != null:
		cat.cheer(cat.mode == "free", 4)
	_card_left = CARD_DELAY_S
	if Story.enabled:
		_show_piece()
		_card_left += PIECE_HOLD_S


## The story: the round's star piece appears over the bread cat, who lifts it (its cheer); pictures
## only. A node beside the lab (the cast's place), never in it.
func _show_piece() -> void:
	if _piece != null and is_instance_valid(_piece):
		_piece.queue_free()
	var cat := lab_cat()
	var height := cat.bounds().size.y if cat != null else 1.4
	_piece = StarArt.make(true, clampf(height * 0.32, 0.25, 1.0))   # big enough to see its face
	_piece.name = "FoundPiece"
	_piece_t = 0.0
	_piece.scale = Vector3.ONE * 0.01
	view.viewport.add_child(_piece)
	_place_piece(0.0)
	SoundBoard.play(&"glint")


## The piece above the cat's raised paws (or the lab's middle without a cat): it pops in, bobs, turns.
func _place_piece(delta: float) -> void:
	if _piece == null or not is_instance_valid(_piece):
		return
	_piece_t += delta
	var cat := lab_cat()
	var at := experiment.follow_point() + Vector3.UP * 1.5
	var height := 1.4
	if cat != null:
		var box := cat.bounds()
		height = box.size.y
		at = Vector3(box.get_center().x, box.end.y + height * 0.32, box.get_center().z)
	_piece.position = at + Vector3.UP * height * 0.05 * sin(_piece_t * 5.0)
	StarArt.face_camera(_piece, view.rig, _piece_t)
	var k := clampf(_piece_t / PIECE_POP_S, 0.0, 1.0)
	_piece.scale = Vector3.ONE * maxf(0.01, 1.0 + 0.35 * sin(PI * k) - (1.0 - k) * (1.0 - k))


## The found piece over the cat (tests; null when none).
func found_piece() -> Node3D:
	return _piece if _piece != null and is_instance_valid(_piece) else null


## The bread cat acting in the lab (inside its props; null in a lab without it).
func lab_cat() -> CatActor:
	if _cat != null and is_instance_valid(_cat):
		return _cat
	if experiment == null:
		return null
	for node in experiment.find_children("*", "Node3D", true, false):
		if node is CatActor:
			_cat = node
			return _cat
	return null


## Shows the round-done card (the stamps, 지도로, 더 해 보기); everything behind it waits.
func _show_done_card() -> void:
	if _done_card != null:
		return
	if is_sidebar_open():
		close_sidebar(false)
	_hide_tip()
	_done_card = RoundDoneCard.new(_stamp_labels.size(), Story.enabled)
	if _piece != null and is_instance_valid(_piece):
		_piece.queue_free()   # the card shows the piece now
	_piece = null
	_done_card.to_map.connect(func() -> void:
		_done_card = null
		back_requested.emit())
	_done_card.stay.connect(func() -> void: _done_card = null)
	view.add_child(_done_card)


## The card's timer and the screenshot demo (--demo-celebrate: one stamp every DEMO_STAMP_EVERY_S,
## shown as earned, nothing judged or saved).
func _run_celebration(delta: float) -> void:
	_place_piece(delta)
	if _card_left >= 0.0:
		_card_left -= delta
		if _card_left < 0.0:
			_show_done_card()
	if _demo_left >= 0.0 and _missions != null:
		_demo_left -= delta
		if _demo_left < 0.0:
			var total: int = MissionTracker.missions(definition).get("stages", []).size()
			if _demo_stamps == 0:
				_predict_ended = true
				_end_question()   # the demo answers nothing: Dugi's question goes
				_stamps_landed = 0
				_show_stamps(0)
			_demo_stamps += 1
			_missions.stamps = _demo_stamps   # in memory only: the strip's text
			_mission_progress(str(definition.id), _demo_stamps)
			_demo_left = DEMO_STAMP_EVERY_S if _demo_stamps < total else -1.0


# --- game: the condition picture buttons (2026-10-27) ------------------------------------------

## The row of the stage's condition buttons (ConditionPicks.groups): built again when the stage
## changes, empty (and hidden) for a stage without conditions or a finished round.
func _build_picks(stage: int) -> void:
	if stage == _picks_stage:
		return
	_picks_stage = stage
	if _picks_row != null:
		_picks_row.queue_free()
		_picks_row = null
	_picks.clear()
	var groups := ConditionPicks.groups(definition, stage)
	if groups.is_empty():
		_fit_overlays()
		return
	_picks_row = Ui.hbox(int(PICK_GAP))
	_picks_row.name = "ConditionPicks"
	_picks_row.mouse_filter = Control.MOUSE_FILTER_IGNORE   # only the buttons take touches
	view.add_child(_picks_row)
	for g in groups.size():
		if g > 0:
			var gap := Control.new()
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gap.custom_minimum_size.x = PICK_GROUP_GAP - PICK_GAP * 2.0
			_picks_row.add_child(gap)
		for preset in groups[g].presets:
			var button := _pick_button(groups[g].control, preset)
			_picks_row.add_child(button)
			_picks.append({"control": groups[g].control, "preset": preset, "button": button})
	for pick in _picks:   # in the tree now: the words have their font, a long one widens its button
		var button: Button = pick.button
		button.custom_minimum_size.x = maxf(PICK_SIZE.x, (button.get_meta("caption") as Label).get_minimum_size().x + 24.0)
	for id in groups.map(func(group: Dictionary) -> String: return group.control):
		_sync_picks(id)
	_picks_for = Vector4(NAN, 0, 0, 0)
	_fit_overlays()


## One picture button: its drawing (PickPictures) over a few words; a tap sets the control the way
## the sidebar does (_set_control), so the row, the sidebar and the run all follow.
func _pick_button(control_id: String, preset: Dictionary) -> Button:
	var button := Ui.button("", "PickButton", 0)
	button.name = "Pick_%s_%s" % [control_id, str(preset.value)]
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = PICK_SIZE
	var stack := Ui.vbox(2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	button.add_child(stack)
	var picture := Control.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.custom_minimum_size = Vector2(PICK_SIZE.x - 16.0, PICK_SIZE.y - 52.0)
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var kind := str(preset.picture)
	var amount := float(preset.get("size", 0.5))
	var count := int(preset.get("count", 1))
	picture.draw.connect(func() -> void: PickPictures.draw(picture, kind, amount, count))
	stack.add_child(picture)
	var caption := Ui.label(str(preset.label), "PickLabel")
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption)
	button.set_meta("caption", caption)
	button.pressed.connect(_set_control.bind(control_id, preset.value))
	return button


## The buttons of `id` show its current value (the chosen one yellow), after any change of it.
func _sync_picks(id: String) -> void:
	if _picks.is_empty():
		return
	var have: Variant = experiment.control_value(id)
	for pick in _picks:
		if pick.control == id:
			(pick.button as Button).set_pressed_no_signal(ConditionPicks.selected(pick.preset, have))


## The row's place: the bottom left of the view; over Dugi's box (beside his portrait) while it is
## open; hidden while he asks (his picture buttons are the question's), or when it would reach the
## action buttons (a narrow view beside the open sidebar: the same settings are in it).
func _fit_picks() -> void:
	if _picks_row == null:
		return
	var talking := dialogue != null and dialogue.active and dialogue.visible
	# Every frame (it follows the dialogue): only scalars compared, nothing allocated until a change.
	var key := Vector4(view.size.x, view.size.y, 1.0 if talking else 0.0, 1.0 if _asking else 0.0)
	var box := Rect2(dialogue.position + dialogue.box.position, dialogue.box.size) if talking else Rect2()
	if key == _picks_for and box == _picks_box:
		return
	_picks_for = key
	_picks_box = box
	var m := OVERLAY_MARGIN
	_picks_row.size = _picks_row.get_combined_minimum_size()
	var at := Vector2(m, view.size.y - m - _picks_row.size.y)
	var right := _action_row.position.x - m
	if talking:
		var rects := dialogue.rects()
		at = Vector2(rects[1].end.x + m, rects[0].position.y - DialogueBox.NAME_LIFT - m - _picks_row.size.y)
		right = view.size.x - m
	_picks_row.position = at
	_picks_row.visible = not _asking and at.x + _picks_row.size.x <= right
	_fit_tip()   # the tip stands over the row


## The row is shown (tests: the buttons of the stage, their place).
func picks_shown() -> bool:
	return _picks_row != null and _picks_row.visible


## The buttons now: [{"control", "preset", "button"}] (tests).
func pick_buttons() -> Array:
	return _picks


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
	var title := Ui.label(ExperimentRegistry.kid_text(definition, "title"), "HeadingLabel")
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
	_build_key_cards(-1)

	_action_row = Ui.hbox(10)
	_action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_action_row)
	# A game lab keeps few buttons (2026-10-27): its main action, and "reset" as a small "다시";
	# other actions (the orbit's "동그랗게 돌게") sit under the conditions in "자세히".
	for action in definition.actions:
		var small: bool = game and action.id == "reset"
		var button := Ui.button(RESET_SHORT if small else action.label, "PrimaryButton" if action.get("style") == "primary" and not small else "", 64)
		button.custom_minimum_size.x = 96 if small else 140
		button.pressed.connect(experiment_action.bind(action.id))
		_action_buttons[action.id] = button
		if game and not small and action.get("style") != "primary":
			_extra_actions.append(button)
		else:
			_action_row.add_child(button)
	if game and _action_row.get_child_count() > 1:
		_action_row.move_child(_action_buttons.reset, 0)   # the small one on the left, the main action at the right edge

	_tip = Ui.label(ExperimentRegistry.kid_text(definition, "tip"), "HintLabel", true)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_tip)
	_tip.visible = _tip.text != "" and not _tips_shown.has(definition.id)   # recorded in _hide_tip(), once it was seen
	view.resized.connect(_fit_overlays)
	# Wrapped card texts settle their height after the first layout pass (and change with status texts).
	_key_row.minimum_size_changed.connect(_fit_overlays)


## The key cards of mission stage `stage` (-1: the lab's own, ExperimentRegistry.shown_cards): built
## again only when the stage shows other cards (the spring's first stage: how far it was pulled).
## A card is a caption and its value in a child's words, or a bar (kid.bars) for a force.
func _build_key_cards(stage: int) -> void:
	var ids := ExperimentRegistry.shown_cards(definition, stage)
	if ids == _key_ids:
		return
	_key_ids = ids.duplicate()
	for child in _key_row.get_children():
		_key_row.remove_child(child)
		child.queue_free()
	_key_labels.clear()
	_key_bars.clear()
	for id in ids:
		var card := Ui.panel("KeyCard")
		card.name = "KeyCard_" + str(id)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card.custom_minimum_size.x = KEY_CARD_WIDTH
		var stack := Ui.vbox(4)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(stack)
		var caption := Ui.label(ExperimentRegistry.card_label(definition, id), "KeyLabel", true)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(caption)
		var value := Ui.label("—", "KeyValueLabel", true)   # a status text may take two lines
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(value)
		if ExperimentRegistry.card_bar(definition, id) > 0.0:
			var bar := KidBar.new()
			bar.name = "KidBar"
			bar.visible = false
			stack.add_child(bar)
			_key_bars[id] = bar
		_key_row.add_child(card)
		_key_labels[id] = value


## The key cards shown now (their observation ids).
func key_card_ids() -> Array:
	return _key_ids.duplicate()


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
	_picks_for = Vector4(NAN, 0, 0, 0)
	_fit_picks()
	_fit_tip()


## The gesture tip: beside the actions when there is room, otherwise above them (a narrow view with
## many actions: orbit's three buttons beside the open sidebar on a tablet); over the picture buttons
## while they show.
func _fit_tip() -> void:
	if _tip == null or _title_bar == null:
		return
	var m := OVERLAY_MARGIN
	var width := view.size.x
	var beside := width - _action_row.size.x - m * 3.0
	var tip_width := minf(TIP_MAX_WIDTH, beside if beside >= TIP_MIN_WIDTH else width - m * 2.0)
	# An autowrap label's minimum height depends on its width: set the width first.
	_tip.size = Vector2(tip_width, 0.0)
	_tip.size.y = _tip.get_minimum_size().y
	var bottom := view.size.y - m if beside >= TIP_MIN_WIDTH else _action_row.position.y - 8.0
	if picks_shown():
		bottom = minf(bottom, _picks_row.position.y - 8.0)   # the tip stands over the picture buttons
	_tip.position = Vector2(m, bottom - _tip.size.y)


## --scroll-to's older names: the numbers were "observations", the texts "explanation" (now in 더 보기).
const SECTION_ALIASES := {"observations": "numbers", "explanation": "more"}
## The sections inside the collapsed 더 보기 (scrolling to one opens it first).
const MORE_SECTIONS := ["more", "more_observations", "more_graph", "more_explanation"]


func _scroll_to(section: String) -> void:
	section = SECTION_ALIASES.get(section, section)
	if section in MORE_SECTIONS:
		set_more_open(true)
	# Containers sort over the first frames; the card's offset inside the scrolled content
	# (its parent margin included) is the same measure as scroll_vertical.
	await get_tree().process_frame
	await get_tree().process_frame
	var content: Control = _scroll.get_child(0)
	_scroll.scroll_vertical = int(_sections[section].global_position.y - content.global_position.y)


## The science note (2026-10-28 "세부쪽도 좀 정리가 필요해", for older children and adults): a few
## cards with clear headings in this order —
##   법칙 (the law in one plain sentence and its formula), 이번 실험 숫자 (3-4 numbers of this run in
##   their units, a "before → after" pair on one row), 조건 바꾸기 (the sliders and choices), 그래프
##   (only where it shows the law: note.graph), and 더 보기 (collapsed): every other observation, the
##   graph when it is not kept above, the steps, the observe card, the shared law and its terms.
## Last comes "AI에게 더 물어보기" (ScienceNote: this run as a question for the AI app the child picks
## in the system chooser of the AI apps; not in a measurement).
## Every observation has one label (_observation_labels) wherever it sits, with format_observation's
## text, so nothing the panel showed before is lost (ExperimentRegistry.note).
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

	var note := ExperimentRegistry.note(definition)
	_sections = {
		"law": _build_law(note),
		"numbers": _build_numbers(note),
		"conditions": _build_conditions(),
	}
	var graph := _build_graph()
	if note.get("graph", true):
		_sections["graph"] = graph
	for id in _sections:
		_sections[id].name = "Note_" + id
		column.add_child(_sections[id])

	# 더 보기: a button and the collapsed rest.
	_more_button = Ui.button(MORE_CLOSED, "", 56)
	_more_button.name = "MoreButton"
	_more_button.pressed.connect(func() -> void: set_more_open(not _more.visible))
	column.add_child(_more_button)
	_sections["more"] = _more_button
	_more = Ui.vbox(16)
	_more.name = "More"
	_more.visible = false
	column.add_child(_more)
	var shown: Dictionary = {}
	for row in note.get("numbers", []):
		for id in row.get("ids", []):
			shown[id] = true
	var rest: Array = definition.observations.filter(func(o: Dictionary) -> bool: return not shown.has(o.id))
	if not rest.is_empty():
		_sections["more_observations"] = _build_observations(rest)
		_more.add_child(_sections.more_observations)
	if not note.get("graph", true):
		_sections["more_graph"] = graph
		_more.add_child(graph)
	_sections["more_explanation"] = _build_explanation()
	_more.add_child(_sections.more_explanation)
	# Last: the question for an AI app (or any app), never in a measurement.
	if not measurement:
		_sections["ask"] = _build_ask()
		_sections.ask.name = "Note_ask"
		column.add_child(_sections.ask)


## The note's last card: one button that opens the system chooser of the AI apps, and a line when
## the question was copied instead.
func _build_ask() -> Control:
	var box := Ui.vbox(6)
	_ask_button = Ui.button(ASK_TEXT, "", 56)
	_ask_button.name = "AskAi"
	_ask_button.pressed.connect(ask_ai)
	box.add_child(_ask_button)
	box.add_child(Ui.label(ASK_CAPTION, "MutedLabel", true))
	_ask_status = Ui.label(ScienceNote.COPIED, "MutedLabel", true)
	_ask_status.name = "AskStatus"
	_ask_status.visible = false
	box.add_child(_ask_status)
	return box


## The ask button's tap: this run's question (the hidden answers left out, as at that tap) and the AI
## apps' packages go to ask_handler once (on Android the system chooser with those apps only); a copy
## shows the line.
func ask_ai() -> void:
	if measurement or experiment == null:
		return
	var packages := ScienceNote.ai_apps().map(func(app: Dictionary) -> String: return app.package)
	var text := ScienceNote.question(definition, experiment, _hidden_answers(experiment.observations()))
	_ask_status.visible = str(ask_handler.call(packages, text)) == "clipboard"


## Opens or folds 더 보기 (closed when the screen opens).
func set_more_open(open: bool) -> void:
	if _more == null:
		return
	_more.visible = open
	_more_button.text = MORE_OPEN if open else MORE_CLOSED


func is_more_open() -> bool:
	return _more != null and _more.visible


## 법칙: the lab's law in one plain sentence and its formula (note.law, note.formula).
func _build_law(note: Dictionary) -> Control:
	var parts := _section("법칙")
	var body: VBoxContainer = parts[1]
	body.add_child(Ui.label(str(note.get("law", "")), "", true))
	var formula := Ui.label(str(note.get("formula", "")), "EquationLabel", true)
	formula.name = "Formula"
	formula.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(formula)
	return parts[0]


## 이번 실험 숫자: note.numbers, a caption and the value(s) of this run in their units (the panel's
## format_observation text); two ids read "before → after".
func _build_numbers(note: Dictionary) -> Control:
	var parts := _section("이번 실험 숫자")
	var body: VBoxContainer = parts[1]
	for row in note.get("numbers", []):
		var tile := Ui.panel("Tile")
		var stack := Ui.vbox(2)
		tile.add_child(stack)
		stack.add_child(Ui.label(str(row.get("label", "")), "MutedLabel", true))
		var values := HFlowContainer.new()
		values.add_theme_constant_override("h_separation", 8)
		stack.add_child(values)
		var ids: Array = row.get("ids", [])
		for i in ids.size():
			if i > 0:
				values.add_child(Ui.label("→", "MutedLabel"))
			var value := Ui.label("—", "ValueLabel")
			values.add_child(value)
			_observation_labels[ids[i]] = value
		body.add_child(tile)
	return parts[0]


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
	for button in _extra_actions:   # built with the view's overlays (_build_view_overlays runs first)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		body.add_child(button)
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
	_new_attempt()   # an object put down or put back (a let-go hold, a placed ball)
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
	_sync_picks(id)


## The other numbers (in 더 보기): the observations the note does not list, two per row.
func _build_observations(observations: Array) -> Control:
	var parts := _section("다른 숫자")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for observation in observations:
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


## The sidebar's text of an observation value (ScienceNote.format_observation: the question for
## the AI app reads the same text).
static func format_observation(observation: Dictionary, value: Variant) -> String:
	return ScienceNote.format_observation(observation, value)


## A number in a child's words (ExperimentRegistry.KID_UNITS): one decimal at most and the unit
## spelled out, "1.3초", "12.5미터", "1초에 12.5미터", "45도", "2줄". A mission stage judges this
## rounded number (MissionTracker.shown). `minus` (optional) reads a
## negative value as its size after that word ("눌려서 0.3미터"). Only the rounding and the words
## differ from format_observation: the value is the same formula value.
static func kid_value(unit: String, value: float, digits: int, minus := "") -> String:
	var words: Array = ExperimentRegistry.KID_UNITS.get(unit, ["", " " + unit])
	var places := mini(digits, MissionTracker.CARD_PLACES)
	var text := Ui.number(absf(value), places)
	var lead := ""
	if value < 0.0 and text != Ui.number(0.0, places):   # a -0.04 reads 0.0, never "-0.0"
		lead = minus + " " if minus != "" else "-"
	return lead + str(words[0]) + text + str(words[1])


## The text of a key card over the 3D view (the sidebar keeps format_observation): a number in
## kid_value words, a lab status text in the definition's kid.states words, "?" with the unit's words
## while the answer is hidden ("? 미터", "1초에 ? 미터"). A bar card (kid.bars) has no text for a
## number (its bar shows it, bar_fraction) and "?" while hidden.
static func card_text(definition: Dictionary, observation: Dictionary, value: Variant, hidden := false) -> String:
	var unit := str(observation.get("unit", ""))
	var bar := ExperimentRegistry.card_bar(definition, str(observation.get("id", ""))) > 0.0
	var words: Array = ExperimentRegistry.KID_UNITS.get(unit, ["", " " + unit]) if not bar else ["", ""]
	if hidden:
		return (str(words[0]) + "? " + str(words[1])).strip_edges()
	var kid: Dictionary = definition.get("kid", {}) if definition.get("kid") is Dictionary else {}
	if bar and (value is float or value is int):
		return ""
	if value is float or value is int:
		return kid_value(unit, float(value), int(observation.get("digits", 2)), str(kid.get("minus", {}).get(observation.id, "")))
	if value is String:
		return str(kid.get("states", {}).get(value, value))
	return "—"


## A bar card's length for `value` (0..1 of kid.bars' full value; 0 for no number).
static func bar_fraction(definition: Dictionary, id: String, value: Variant) -> float:
	var full := ExperimentRegistry.card_bar(definition, id)
	if full <= 0.0 or not (value is float or value is int):
		return 0.0
	return clampf(float(value) / full, 0.0, 1.0)


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
		if key == null:
			continue
		var card := card_text(definition, observation, values.get(observation.id), hidden.has(observation.id))
		if key.text != card:
			key.text = card
		var bar: KidBar = _key_bars.get(observation.id)
		if bar != null:
			var value: Variant = values.get(observation.id)
			bar.visible = not hidden.has(observation.id) and (value is float or value is int)
			key.visible = not bar.visible
			bar.fraction = bar_fraction(definition, observation.id, value)
	var revision := experiment.graph_revision()
	var series_hidden := _missions != null and not MissionTracker.result_in(definition, experiment.status(), values)
	if force_graph or revision < 0 or revision != _graph_revision or series_hidden != _series_hidden:
		_graph_revision = revision
		_series_hidden = series_hidden
		var series := experiment.graph_series()
		if series_hidden:
			# The formula's answer as a line (missions.hidden_series_until_end): drawn once the run has
			# its result, like the hidden values.
			for id in MissionTracker.missions(definition).get("hidden_series_until_end", []):
				if series.has(id):
					series[id] = PackedVector2Array()
		_graph.set_data(series)


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
