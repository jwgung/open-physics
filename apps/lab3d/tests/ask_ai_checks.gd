## "AI에게 더 물어보기" (2026-10-28 user decision, ScienceNote; the system chooser with the AI apps
## only since 2026-10-29):
## - every lab's 자세히 ends with the button (after 더 보기 and its collapsed rest),
## - the question holds the lab's title, law, formula, the conditions and the note's numbers of this
##   run in their units, Dugi's explanation and the open ending; nothing personal (no device id or
##   model, no progress words),
## - it follows the run: a changed condition is in the next question,
## - one tap (a touch and its emulated click) hands this run's question and the AI apps' packages of
##   content/ai_apps.json (in order) to the handler once; no in-app picker comes up,
## - a copy (desktop, ScienceNote.send_to_ai off Android) puts the question on the clipboard and
##   shows its line,
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
	await check_one_tap()
	await check_desktop_copy()
	await check_web_link()
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
	var text := ScienceNote.question(ExperimentDefinition.new(definition), screen.experiment, hidden)
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
	var control: Dictionary = screen.definition.controls().filter(func(c: Dictionary) -> bool: return c.id == "height")[0]
	var before := ScienceNote.question(screen.definition, screen.experiment)
	screen._set_control("height", 3.0)
	await tree.process_frame
	var after := ScienceNote.question(screen.definition, screen.experiment)
	var old_text := "%s: %s" % [control.label, ScienceNote.condition_text(control, 5.0)]
	var new_text := "%s: %s" % [control.label, "3m"]   # whole metres (1 m step, 2026-10-29)
	expect.call(before.contains(old_text) and after.contains(new_text) and not after.contains(old_text),
		"ask AI: the question follows the run (height 5m -> 3m)", "%s / %s" % [old_text, new_text])
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


## The chooser's apps come from content/ai_apps.json: names and package names, none twice, Gemini first.
func check_app_list() -> void:
	var apps := ScienceNote.ai_apps()
	var packages := apps.map(func(app: Dictionary) -> String: return app.package)
	var unique := {}
	for package in packages:
		unique[package] = true
	expect.call(apps.size() >= 5 and unique.size() == apps.size() and packages[0] == "com.google.android.apps.bard"
		and apps.all(func(app: Dictionary) -> bool: return app.name != "" and app.package.contains(".")),
		"ask AI: the chooser's apps come from content/ai_apps.json (%d apps, Gemini first, no package twice)" % apps.size(),
		str(packages))


## A screen at the ask card, the sidebar open, recording hand-offs (packages, text) and answering `answer`.
func _open_asking(id: String, calls: Array, answer := "chooser") -> Control:
	var screen := await _open(id)
	screen.ask_handler = func(packages: Array, text: String) -> String:
		calls.append([packages, text])
		return answer
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


func _packages() -> Array:
	return ScienceNote.ai_apps().map(func(app: Dictionary) -> String: return app.package)


## One tap through the real input path: one hand-off of every AI package (in the list's order) and
## this run's question; no in-app picker or other overlay comes up, no copy line.
func check_one_tap() -> void:
	var calls: Array = []
	var screen := await _open_asking("projectile", calls)
	var button: Button = screen._ask_button
	var at := button.get_global_rect().get_center()
	var inside: bool = screen._sidebar.get_global_rect().has_point(at) and screen._scroll.get_global_rect().has_point(at)
	var children := screen.get_child_count()
	var want := [_packages(), _question(screen)]
	await _tap(button)
	expect.call(inside and calls.size() == 1 and calls[0] == want and screen.get_child_count() == children
		and not screen._ask_status.visible,
		"ask AI: one tap (touch + emulated click) hands the %d AI packages and this run's question once; no in-app picker" % want[0].size(),
		"inside %s, %d calls, children %d -> %d" % [inside, calls.size(), children, screen.get_child_count()])
	await _close(screen)


## Off Android ScienceNote.send_to_ai copies the question and the screen shows '질문을 복사했어요'.
func check_desktop_copy() -> void:
	var calls: Array = []
	var screen := await _open_asking("spring", calls, "clipboard")
	var want := _question(screen)
	await _tap(screen._ask_button)
	var shown: bool = screen._ask_status.visible and screen._ask_status.text == ScienceNote.COPIED
	var clipboard_works := DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	if clipboard_works:
		DisplayServer.clipboard_set("")
	var result := ScienceNote.send_to_ai(_packages(), want)
	var copied := DisplayServer.clipboard_get() if clipboard_works else ""
	expect.call(calls.size() == 1 and shown and result == "clipboard" and (copied == want or not clipboard_works),
		"ask AI: off Android the question is copied ('clipboard') and the screen shows '%s'" % ScienceNote.COPIED,
		"calls %d, line %s, result %s, copied %s" % [calls.size(), shown, result, copied == want])
	await _close(screen)


## A measurement's note has no button, and nothing is handed over.
func check_measurement() -> void:
	var screen := await _open("free-fall", true)
	var calls: Array = []
	screen.ask_handler = func(packages: Array, text: String) -> String:
		calls.append([packages, text])
		return "chooser"
	screen.ask_ai()
	var none: bool = not screen._sections.has("ask") and screen._ask_button == null and calls.is_empty()
	expect.call(none and Story.measurement_run(PackedStringArray(["--progress=bench"])),
		"ask AI: a measurement (--progress=bench, auto runs, --sound=0) shows no button and hands nothing over", "")
	await _close(screen)


## A device with no AI app (the chooser then has nothing): the link under the button copies this
## run's question and opens the web AI once per tap, and the line says to paste it (2026-10-29).
func check_web_link() -> void:
	var calls: Array = []
	var screen := await _open_asking("projectile", [])
	screen.web_handler = func(text: String) -> void: calls.append(text)
	var link: Button = screen._web_button
	var below: bool = link != null and link.get_global_rect().position.y > screen._ask_button.get_global_rect().position.y
	await _tap(link)
	var want := _question(screen)
	expect.call(below and calls.size() == 1 and calls[0] == want and screen._ask_status.visible
		and screen._ask_status.text == ScienceNote.COPIED_WEB and link.text == ScienceNote.WEB_LINK
		and ScienceNote.ai_web().begins_with("https://"),
		"ask AI: the web link under the button copies this run's question and opens the web AI once (no AI app is not stuck)",
		"below %s, %d calls, status %s" % [below, calls.size(), screen._ask_status.text])
	await _close(screen)
