## "AI에게 더 물어보기" (2026-10-28 user decision; since 2026-10-29 the system share sheet with the
## AI apps only): the science note's last button turns this run of a lab into a Korean question and
## hands it to an AI app through Android's own chooser that lists only the AI apps of
## content/ai_apps.json that are on the device (their real names and icons; no contacts, no other
## apps). The question holds the lab's content only — title, question, law and formula, the
## conditions and the note's numbers of this run, Dugi's explanation — never a name, a device id or
## the child's progress. The app itself calls no network: an Android intent (ACTION_SEND,
## text/plain, EXTRA_TEXT) hands the text over, and the user sends it or not in that app.
## Why an intent: the AI apps have no official deep link that fills in a prompt, and an AI API called
## from the app is not allowed for apps likely used by people under 18 (e.g. the Gemini API terms,
## https://ai.google.dev/gemini-api/terms).
class_name ScienceNote
extends RefCounted

const ROLE := "나는 '빵고양이 과학섬' 앱에서 물리 실험을 하고 있어. 초등학생도 이해하게 쉽게 설명해 줘."
const ENDING := "이 실험에 대해 더 궁금한 걸 물어볼게:"
const CHOOSER_TITLE := "질문할 AI 앱 고르기"
## The chooser's own target: a package no app has, so only the AI apps (EXTRA_INITIAL_INTENTS) show.
const NO_APP := "invalid.open_physics.no_app"
const COPIED := "질문을 복사했어요. AI 앱에 붙여 넣어 보세요."
## The web link under the button (a device with no AI app is not stuck, 2026-10-29) and its line.
const WEB_LINK := "AI 앱이 없다면 웹에서 열기"
const COPIED_WEB := "질문을 복사했어요. 웹 화면에 붙여 넣어 보세요."


## The web way: the question on the clipboard and the web AI opened (a browser, or its app).
static func open_web_ai(text: String) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
	var web := ai_web()
	if web != "" and DisplayServer.get_name() != "headless":
		OS.shell_open(web)
const APPS_PATH := "res://content/ai_apps.json"


## The question for `experiment` (a running lab of `definition`) as the science note shows it now:
## the conditions in the sidebar's text (a slider's value and unit, a choice's label and note), the
## note's numbers in format_observation's text ("before → after" for a pair). `hidden` are the
## observation ids a mission round hides until its result (ExperimentScreen._hidden_answers): they
## are left out, as the note shows only "?" for them, and so are numbers with no value yet ("—").
static func question(definition: Dictionary, experiment: Experiment, hidden: Array = []) -> String:
	var note := ExperimentRegistry.note(definition)
	var lines := PackedStringArray([ROLE, ""])
	lines.append("실험: %s" % str(definition.get("title", "")))
	var asked := str(definition.get("question", ""))
	if asked != "":
		lines.append("실험 질문: %s" % asked)
	lines.append("법칙: %s (공식: %s)" % [str(note.get("law", "")), str(note.get("formula", ""))])
	var conditions := PackedStringArray()
	for control in definition.get("controls", []):
		var text := condition_text(control, experiment.control_value(control.id))
		if text != "":
			conditions.append("%s: %s" % [str(control.label), text])
	if not conditions.is_empty():
		lines.append("조건: " + " / ".join(conditions))
	var observations := {}
	for observation in definition.get("observations", []):
		observations[observation.id] = observation
	var values := experiment.observations()
	var numbers := PackedStringArray()
	for row in note.get("numbers", []):
		var ids: Array = row.get("ids", [])
		if not ids.all(func(id: Variant) -> bool: return shown_value(values.get(id)) and observations.has(id) and not hidden.has(id)):
			continue   # an answer hidden until the result, or no value yet ("—")
		var texts := ids.map(func(id: Variant) -> String: return format_observation(observations[id], values.get(id)))
		numbers.append("- %s: %s" % [str(row.get("label", "")), " → ".join(PackedStringArray(texts))])
	if not numbers.is_empty():
		lines.append("이번 실험 숫자:")
		lines.append_array(numbers)
	var say := ExperimentRegistry.kid_text(definition, "say")
	if say != "":
		lines.append("두기두기 설명: %s" % say)
	lines.append("")
	lines.append(ENDING)
	return "\n".join(lines)


## An observation value in its unit ("3.03 m/s", "45°"), a lab's status text as it is, "—" for none:
## the science note's text (ExperimentScreen.format_observation) and the question's.
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


## A value the question can show: a number or a lab's status text (not "—" before there is one).
static func shown_value(value: Variant) -> bool:
	return value is float or value is int or (value is String and value != "")


## A condition's value as the sidebar shows it: a slider's number and unit ("5.0m", "3.0 kg"), a
## choice's label with its note ("지구 (지구 · 1× · g = 9.81 m/s²)"); "" for an unknown value.
static func condition_text(control: Dictionary, value: Variant) -> String:
	if control.get("type") == "slider":
		if not (value is float or value is int):
			return ""
		return Ui.number(float(value), int(control.get("digits", 1))) + str(control.get("unit", ""))
	for option in control.get("options", []):
		if option.get("id") != value:
			continue
		var note: String = option.get("note", control.get("note", ""))
		if option.has("mu_s"):
			note = ("μs = %.2f · μk = %.2f   %s" % [option.mu_s, option.mu_k, note]).strip_edges()
		return str(option.label) + (" (%s)" % note if note != "" else "")
	return ""


## The AI apps of the chooser in their order: {name, package} (content/ai_apps.json).
## The web address the chooser also offers (a browser opens it), "" when none.
static func ai_web() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(APPS_PATH))
	return str(parsed.get("web", "")) if parsed is Dictionary else ""


static func ai_apps() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(APPS_PATH))
	var apps: Array = []
	if parsed is Dictionary:
		for app in parsed.get("apps", []):
			if app is Dictionary and str(app.get("name", "")) != "" and str(app.get("package", "")) != "":
				apps.append({"name": str(app.name), "package": str(app.package)})
	return apps


## Hands `text` to the AI apps `packages` through the system chooser, which lists only those of them
## that are on the device. Returns "chooser" (the chooser opened) or "clipboard" (desktop or a failed
## intent: the text was copied, and the screen shows COPIED).
## How (SM-X115, Android 16, 2026-10-29): Intent.createChooser(target, title) with a target that no
## app can take (ACTION_SEND for a package that does not exist), so the chooser has no apps of its
## own and no direct-share (contact) row, and EXTRA_INITIAL_INTENTS = one ACTION_SEND text/plain
## intent per AI app with setPackage. The chooser resolves those itself (the system sees every app;
## this app does not without a manifest <queries>), so a missing app is just not there and an
## installed one shows with its own name and icon. The array goes in through a Bundle
## (putParcelableArray: one signature, JavaClassWrapper turns an Array[Object] of Intents into an
## Intent[] for the Parcelable[] parameter). When none of the apps is there the chooser says so itself
## (this app cannot tell beforehand, Android 11+ package visibility).
static func send_to_ai(packages: Array, text: String) -> String:
	var android := _android()
	if not android.is_empty():
		var chooser := _ai_chooser(android.intent_class, packages, text)
		if chooser != null:
			var activity: Object = android.activity
			activity.runOnUiThread(android.runtime.createRunnableFromGodotCallable(func() -> void:
				activity.startActivity(chooser)))
			return "chooser"
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
	return "clipboard"


## The chooser intent of send_to_ai, or null when any step fails.
static func _ai_chooser(intent_class: JavaClass, packages: Array, text: String) -> Object:
	var target := _send_intent(intent_class, text, NO_APP)
	if target == null:
		return null
	var initial: Array[Object] = []
	for package in packages:
		var intent := _send_intent(intent_class, text, str(package))
		if intent == null:
			return null
		initial.append(intent)
	var extras: Object = JavaClassWrapper.wrap("android.os.Bundle").Bundle()
	if extras == null or JavaClassWrapper.get_exception() != null:
		return null
	extras.putParcelableArray(intent_class.EXTRA_INITIAL_INTENTS, initial)
	if JavaClassWrapper.get_exception() != null:
		return null
	var chooser: Object = intent_class.createChooser(target, CHOOSER_TITLE)
	if chooser == null or JavaClassWrapper.get_exception() != null:
		return null
	chooser.putExtras(extras)
	return chooser if JavaClassWrapper.get_exception() == null else null


## Godot 4.4+ JNI from GDScript (no Gradle build, no plugin): AndroidRuntime's activity and
## JavaClassWrapper's Intent class; {} when not on Android.
static func _android() -> Dictionary:
	if not Engine.has_singleton("AndroidRuntime"):
		return {}
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	var activity: Object = runtime.getActivity()
	if activity == null:
		return {}
	return {"runtime": runtime, "activity": activity, "intent_class": JavaClassWrapper.wrap("android.content.Intent")}


## Intent(ACTION_SEND), text/plain with `text` as EXTRA_TEXT, for `package` only.
static func _send_intent(intent_class: JavaClass, text: String, package: String) -> Object:
	var intent: Object = intent_class.Intent(intent_class.ACTION_SEND)
	if intent == null or JavaClassWrapper.get_exception() != null:
		return null
	intent.setType("text/plain")
	intent.putExtra(intent_class.EXTRA_TEXT, text)
	intent.setPackage(package)
	return intent
