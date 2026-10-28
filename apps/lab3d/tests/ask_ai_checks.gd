## "AI에게 더 물어보기" (2026-10-28 user decision, ScienceNote; an AI app picker since 2026-10-29):
## - every lab's 자세히 ends with the button (after 더 보기 and its collapsed rest),
## - the question holds the lab's title, law, formula, the conditions and the note's numbers of this
##   run in their units, Dugi's explanation and the open ending; nothing personal (no device id or
##   model, no progress words),
## - it follows the run: a changed condition is in the next question,
## - a tap opens the AI app picker (AiPicker) over the whole screen: one button per app of
##   content/ai_apps.json in its order (only the installed ones when the device can tell, and a line
##   when there is none), "다른 앱으로 보내기" (the share sheet) and 닫기; nothing behind it takes a touch,
## - one tap on an app (a touch and its emulated click) hands this run's question to that package
##   once and closes the card; a missing app shows its line and the card stays; a copy shows its line,
## - a measurement (bench store, auto runs, silent) has no button and hands nothing over.
## Read only: nothing here changes a lab's physics.
extends RefCounted

var tree: SceneTree
var expect: Callable
var _number_rows := 0                   # the number rows the questions held, over every lab
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const TABLET := Vector2(1152, 720)
## Words that would be the child's progress or identity, never in the question.
const PERSONAL := ["도장", "별 조각", "진행", "이름"]


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	for definition in ExperimentRegistry.load_all():
		await check_lab(definition)
	expect.call(_number_rows >= 20, "ask AI: the questions carry this run's numbers (%d rows over the labs at open)" % _number_rows, "")
	check_app_list()
	await check_follows_run()
	await check_picker_opens_and_closes()
	await check_one_tap()
	await check_missing_app()
	await check_installed_only()
	await check_share_sheet()
	await check_shield()
	await check_measurement()


func _open(id: String, measurement := false) -> Control:
	DirAccess.remove_absolute(ProgressStore.path)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	screen.measurement = measurement
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	for i in 3:
		await tree.process_frame
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProgressStore.path)


## The button's place and the question's content for one lab.
func check_lab(definition: Dictionary) -> void:
	var screen := await _open(definition.id)
	screen.open_sidebar(false)
	await tree.process_frame
	var problems := []
	var ask: Control = screen._sections.get("ask")
	var column: Control = screen._sections.law.get_parent()
	if ask == null or ask.get_parent() != column:
		problems.append("no ask card in the note")
	elif ask.get_index() != column.get_child_count() - 1 or ask.get_index() != screen._more.get_index() + 1:
		problems.append("ask card at %d (더 보기's rest at %d, %d cards)" % [ask.get_index(), screen._more.get_index(), column.get_child_count()])
	if screen._ask_button == null or screen._ask_button.text != "AI에게 더 물어보기" or not ask.is_ancestor_of(screen._ask_button):
		problems.append("button %s" % (screen._ask_button.text if screen._ask_button != null else "-"))
	var hidden: Array = screen._hidden_answers(screen.experiment.observations())
	var text := ScienceNote.question(definition, screen.experiment, hidden)
	var note := ExperimentRegistry.note(definition)
	var want := [ScienceNote.ROLE, ScienceNote.ENDING, str(definition.title), str(note.law), str(note.formula),
		ExperimentRegistry.kid_text(definition, "say")]
	for control in definition.controls:
		want.append("%s: %s" % [control.label, ScienceNote.condition_text(control, screen.experiment.control_value(control.id))])
	var values: Dictionary = screen.experiment.observations()
	var numbers := 0
	for row in note.numbers:
		if not row.ids.all(func(id: String) -> bool: return not hidden.has(id) and ScienceNote.shown_value(values.get(id))):
			if text.contains(str(row.label)):
				problems.append("hidden or empty row '%s' in the question" % row.label)
			continue
		want.append(str(row.label))
		for id in row.ids:
			var observation: Dictionary = screen._observation(id)
			var shown := ExperimentScreen.format_observation(observation, values.get(id))
			want.append(shown)
			if not values.get(id) is String and str(observation.get("unit", "")) != "" and not shown.ends_with(str(observation.unit)):
				problems.append("%s without its unit: %s" % [id, shown])
		numbers += 1
	for part in want:
		if part == "" or not text.contains(part):
			problems.append("missing '%s'" % part)
	_number_rows += numbers
	for word in PERSONAL:
		if text.contains(word):
			problems.append("personal word '%s'" % word)
	for id in [OS.get_unique_id(), OS.get_model_name()]:
		if id.length() > 3 and text.contains(id):
			problems.append("device id '%s'" % id)
	var lines := text.split("\n").size()
	if lines < 6 or lines > 16:
		problems.append("%d lines" % lines)
	expect.call(problems.is_empty(),
		"ask AI (%s): last in 자세히 after 더 보기; title, law, %s, %d conditions, %d number rows in units, Dugi, nothing personal" % [
			definition.id, note.formula, definition.controls.size(), numbers],
		"; ".join(problems))
	await _close(screen)


## The question follows the run: a slider moved is in the next question (and the old value is not).
func check_follows_run() -> void:
	var screen := await _open("free-fall")
	var control: Dictionary = screen.definition.controls.filter(func(c: Dictionary) -> bool: return c.id == "height")[0]
	var before := ScienceNote.question(screen.definition, screen.experiment)
	screen._set_control("height", 2.5)
	await tree.process_frame
	var after := ScienceNote.question(screen.definition, screen.experiment)
	var old_text := "%s: %s" % [control.label, ScienceNote.condition_text(control, 5.0)]
	var new_text := "%s: %s" % [control.label, "2.5m"]
	expect.call(before.contains(old_text) and after.contains(new_text) and not after.contains(old_text),
		"ask AI: the question follows the run (height 5.0m -> 2.5m)", new_text)
	await _close(screen)


func _touch(canvas_at: Vector2, pressed: bool) -> void:
	var at: Vector2 = tree.root.get_final_transform() * canvas_at   # window pixels (canvas_items stretch)
	var touch := InputEventScreenTouch.new()
	touch.position = at
	touch.pressed = pressed
	tree.root.push_input(touch)
	var click := InputEventMouseButton.new()   # the click Godot emulates from that touch
	click.position = at
	click.global_position = at
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.device = InputEvent.DEVICE_ID_EMULATION
	tree.root.push_input(click)
	await tree.process_frame


## The picker's apps come from content/ai_apps.json: names and package names, none twice, Gemini first.
func check_app_list() -> void:
	var apps := ScienceNote.ai_apps()
	var packages := apps.map(func(app: Dictionary) -> String: return app.package)
	var unique := {}
	for package in packages:
		unique[package] = true
	expect.call(apps.size() >= 5 and unique.size() == apps.size() and packages[0] == "com.google.android.apps.bard"
		and apps.all(func(app: Dictionary) -> bool: return app.name != "" and app.package.contains(".")),
		"ask AI: the picker's apps come from content/ai_apps.json (%d apps, Gemini first, no package twice)" % apps.size(),
		str(packages))


## A screen at the ask card, the sidebar open, recording hand-offs (package, text) and answering
## `answer` (a String, or a Callable(package) -> String); `installed` is what the device tells.
func _open_asking(id: String, calls: Array, answer: Variant = "sent", installed: Variant = null) -> Control:
	var screen := await _open(id)
	screen.ask_handler = func(package: String, text: String) -> String:
		calls.append([package, text])
		return answer.call(package) if answer is Callable else str(answer)
	screen.ask_installed = func(_packages: Array) -> Variant: return installed
	screen.open_sidebar(false)
	await screen._scroll_to("ask")
	await tree.process_frame
	return screen


func _tap(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await _touch(at, true)
	await _touch(at, false)
	await tree.process_frame


func _question(screen: Control) -> String:
	return ScienceNote.question(screen.definition, screen.experiment, screen._hidden_answers(screen.experiment.observations()))


## The card has closed (it frees itself right after).
func _gone(picker: Variant) -> bool:
	return not is_instance_valid(picker) or picker.closed


func _names(picker: AiPicker) -> Array:
	return picker.app_buttons.map(func(b: Button) -> String: return b.text)


## A tap on the button opens the picker over the whole screen with every app of the list (the
## device cannot tell which are there); 닫기 closes it and hands nothing over.
func check_picker_opens_and_closes() -> void:
	var calls: Array = []
	var screen := await _open_asking("projectile", calls)
	await _tap(screen._ask_button)
	var picker: AiPicker = screen.ask_picker
	var want := ScienceNote.ai_apps().map(func(app: Dictionary) -> String: return app.name)
	var problems := []
	if picker == null or not picker.is_inside_tree():
		problems.append("no picker")
	else:
		if _names(picker) != want:
			problems.append("apps %s" % [_names(picker)])
		if picker.get_parent() != screen or picker.get_index() != screen.get_child_count() - 1:
			problems.append("not on top of the screen")
		if not picker.get_global_rect().encloses(screen.get_global_rect()) or picker.dim.mouse_filter != Control.MOUSE_FILTER_STOP:
			problems.append("the dim does not cover the screen")
		if not screen.get_global_rect().encloses(picker.card.get_global_rect()):
			problems.append("card off screen %s" % picker.card.get_global_rect())
		if picker.status.visible or picker.other_button.text != AiPicker.OTHER:
			problems.append("status or share button")
		await _tap(picker.close_button)
		if not _gone(picker):
			problems.append("닫기 left it open")
	expect.call(problems.is_empty() and calls.is_empty(),
		"ask AI: a tap opens the picker on top of the screen (every app of the list, names only, 다른 앱으로 보내기, 닫기); 닫기 closes it and sends nothing",
		"; ".join(problems) + " (%d calls)" % calls.size())
	await _close(screen)


## One tap on an app through the real input path: one hand-off of this run's question to that
## package, and the card closes.
func check_one_tap() -> void:
	var calls: Array = []
	var screen := await _open_asking("projectile", calls)
	var button: Button = screen._ask_button
	var at := button.get_global_rect().get_center()
	var inside: bool = screen._sidebar.get_global_rect().has_point(at) and screen._scroll.get_global_rect().has_point(at)
	await _tap(button)
	var picker: AiPicker = screen.ask_picker
	var app: Button = picker.app_buttons[1] if picker != null and picker.app_buttons.size() > 1 else null
	var package := str(app.get_meta("package")) if app != null else ""
	var app_name := app.text if app != null else "-"
	var want := _question(screen)
	if app != null:
		await _tap(app)
	expect.call(inside and app_name != "-" and package == ScienceNote.ai_apps()[1].package and calls.size() == 1
		and calls[0] == [package, want] and _gone(picker) and not screen._ask_status.visible,
		"ask AI: one tap on %s (touch + emulated click) hands this run's question to %s once; the card closes" % [app_name, package],
		"inside %s, calls %s" % [inside, calls.map(func(c: Array) -> String: return c[0])])
	await _close(screen)


## The device cannot tell which apps are there: a tap on a missing one shows "이 기기에는 ○○ 앱이
## 없어요" and the card stays; the next app then goes (one call per tap).
func check_missing_app() -> void:
	var calls: Array = []
	var gemini := "com.google.android.apps.bard"
	var screen := await _open_asking("free-fall", calls, func(package: String) -> String: return "sent" if package == gemini else "missing")
	await _tap(screen._ask_button)
	var picker: AiPicker = screen.ask_picker
	var claude: Button = picker.app_buttons.filter(func(b: Button) -> bool: return b.text == "Claude")[0]
	await _tap(claude)
	var stays := not _gone(picker) and picker.visible and picker.status.visible and picker.status.text == "이 기기에는 Claude 앱이 없어요"
	var status_text: String = picker.status.text if stays else "-"
	var calls_after_missing := calls.size()
	if stays:
		await _tap(picker.app_buttons[0])
	expect.call(stays and calls_after_missing == 1 and calls.size() == 2 and calls[0][0] == "com.anthropic.claude" and calls[1][0] == gemini and _gone(picker),
		"ask AI: a missing app shows '이 기기에는 Claude 앱이 없어요' and the card stays; Gemini then goes (one call per tap)",
		"stays %s, '%s', calls %s" % [stays, status_text, calls.map(func(c: Array) -> String: return c[0])])
	await _close(screen)


## When the device tells which apps are there, only those show; none shows the line and the share sheet.
func check_installed_only() -> void:
	var calls: Array = []
	var screen := await _open_asking("collision", calls, "sent", ["com.google.android.apps.bard", "ai.x.grok"])
	await _tap(screen._ask_button)
	var some: Array = _names(screen.ask_picker)
	await _tap(screen.ask_picker.close_button)
	screen.ask_installed = func(_packages: Array) -> Variant: return []
	await _tap(screen._ask_button)
	var picker: AiPicker = screen.ask_picker
	var none: bool = picker.app_buttons.is_empty() and picker.status.visible and picker.status.text == AiPicker.NONE and picker.other_button.is_visible_in_tree()
	expect.call(some == ["Gemini", "Grok"] and none and calls.is_empty(),
		"ask AI: only the installed apps show (Gemini, Grok); none shows '이 기기에는 AI 앱이 없어요' and 다른 앱으로 보내기",
		"some %s, none %s" % [some, none])
	await _close(screen)


## 다른 앱으로 보내기 hands the question to the share sheet (package ""); a copy (desktop) closes the
## card and shows '질문을 복사했어요'.
func check_share_sheet() -> void:
	var calls: Array = []
	var screen := await _open_asking("spring", calls, "clipboard")
	await _tap(screen._ask_button)
	var picker: AiPicker = screen.ask_picker
	var want := _question(screen)
	await _tap(picker.other_button)
	expect.call(calls == [["", want]] and _gone(picker) and screen._ask_status.visible and screen._ask_status.text == ScienceNote.COPIED,
		"ask AI: 다른 앱으로 보내기 hands the question to the share sheet once; a copy shows '질문을 복사했어요'",
		"calls %d" % calls.size())
	await _close(screen)


## While the picker is up nothing behind it takes a touch: not 더 보기, not the ask button again
## (no second picker), not the sidebar's 닫기.
func check_shield() -> void:
	var calls: Array = []
	var screen := await _open_asking("projectile", calls)
	await _tap(screen._ask_button)
	var picker: AiPicker = screen.ask_picker
	var more_at: Vector2 = screen._more_button.get_global_rect().get_center()
	var ask_at: Vector2 = screen._ask_button.get_global_rect().get_center()
	var covered: bool = not picker.card.get_global_rect().has_point(more_at) and not picker.card.get_global_rect().has_point(ask_at)
	for at in [more_at, ask_at]:
		await _touch(at, true)
		await _touch(at, false)
	await tree.process_frame
	var pickers := screen.get_children().filter(func(c: Node) -> bool: return c is AiPicker)
	expect.call(covered and not screen._more.visible and screen.ask_picker == picker and pickers.size() == 1
		and screen._sidebar.visible and not picker.closed and calls.is_empty(),
		"ask AI: while the picker is up, touches on 더 보기 and the ask button behind it do nothing",
		"more open %s, pickers %d, calls %d" % [screen._more.visible, pickers.size(), calls.size()])
	await _close(screen)


## A measurement's note has no button, and nothing is handed over.
func check_measurement() -> void:
	var screen := await _open("free-fall", true)
	var calls: Array = []
	screen.ask_handler = func(package: String, text: String) -> String:
		calls.append([package, text])
		return "sent"
	screen.open_ask_picker()
	var none: bool = not screen._sections.has("ask") and screen._ask_button == null and screen.ask_picker == null and calls.is_empty()
	expect.call(none and Story.measurement_run(PackedStringArray(["--progress=bench"])),
		"ask AI: a measurement (--progress=bench, auto runs, --sound=0) shows no button, no picker and hands nothing over", "")
	await _close(screen)
