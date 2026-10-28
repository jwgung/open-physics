## "AI에게 더 물어보기" (2026-10-28 user decision, an AI app picker since 2026-10-29): the science
## note's last button turns this run of a lab into a Korean question and hands it to the AI app the
## user picks in a small picker (content/ai_apps.json: names and Play package names), or to any app
## through the share sheet. The question holds the lab's content only — title, question, law and
## formula, the conditions and the note's numbers of this run, Dugi's explanation — never a name, a
## device id or the child's progress. The app itself calls no network: an Android intent
## (ACTION_SEND, text/plain, EXTRA_TEXT; setPackage for a picked app, createChooser for the share
## sheet) hands the text over, and the user sends it or not in that app.
## Why an intent: the AI apps have no official deep link that fills in a prompt, and an AI API called
## from the app is not allowed for apps likely used by people under 18 (e.g. the Gemini API terms,
## https://ai.google.dev/gemini-api/terms).
class_name ScienceNote
extends RefCounted

const ROLE := "나는 '빵고양이 과학섬' 앱에서 물리 실험을 하고 있어. 초등학생도 이해하게 쉽게 설명해 줘."
const ENDING := "이 실험에 대해 더 궁금한 걸 물어볼게:"
const CHOOSER_TITLE := "질문을 보낼 앱 고르기"
const COPIED := "질문을 복사했어요. AI 앱에 붙여 넣어 보세요."
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


## The AI apps of the picker in their order: {name, package} (content/ai_apps.json).
static func ai_apps() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(APPS_PATH))
	var apps: Array = []
	if parsed is Dictionary:
		for app in parsed.get("apps", []):
			if app is Dictionary and str(app.get("name", "")) != "" and str(app.get("package", "")) != "":
				apps.append({"name": str(app.name), "package": str(app.package)})
	return apps


## Which of `packages` can take the question on this device, or null when that cannot be told
## (desktop, or Android found none). Android 11+ hides other apps from this one unless the manifest
## lists them (<queries>, a Gradle build): on SM-X115 (Android 16, 2026-10-29) resolveActivity,
## queryIntentActivities and getLaunchIntentForPackage all came back empty even for the Gemini that
## is installed. So "none found" means "unknown": the picker shows every app and a tap on a missing
## one says so (send_to's "missing"). Where the apps can be seen (Android 10 and older, or a later
## manifest with <queries>), only those found show.
static func installed(packages: Array) -> Variant:
	var android := _android()
	if android.is_empty():
		return null
	var manager: Object = android.activity.getPackageManager()
	if manager == null:
		return null
	var found: Array = []
	for package in packages:
		var intent := _send_intent(android.intent_class, "", package)
		if intent == null:
			return null
		var target: Variant = intent.resolveActivity(manager)
		if JavaClassWrapper.get_exception() != null:
			return null
		if target != null:
			found.append(package)
	return found if not found.is_empty() else null


## Hands `text` to the app `package` (an AI app of the picker), or with "" to the share sheet.
## Returns "sent" (the app opened), "missing" (no such app here; nothing was sent), "share" (the
## share sheet opened) or "clipboard" (desktop or a failed intent: the text was copied, and the
## screen shows COPIED).
static func send_to(package: String, text: String) -> String:
	var android := _android()
	if not android.is_empty():
		var intent := _send_intent(android.intent_class, text, package)
		if intent != null:
			if package != "":
				# Straight from this thread (not runOnUiThread), so a missing app's
				# ActivityNotFoundException comes back here (SM-X115, 2026-10-29).
				android.activity.startActivity(intent)
				return "sent" if JavaClassWrapper.get_exception() == null else "missing"
			var chooser: Object = android.intent_class.createChooser(intent, CHOOSER_TITLE)
			if chooser != null and JavaClassWrapper.get_exception() == null:
				var activity: Object = android.activity
				activity.runOnUiThread(android.runtime.createRunnableFromGodotCallable(func() -> void:
					activity.startActivity(chooser)))
				return "share"
	DisplayServer.clipboard_set(text)
	return "clipboard"


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


## Intent(ACTION_SEND), text/plain with `text` as EXTRA_TEXT, for `package` only when it is not "".
static func _send_intent(intent_class: JavaClass, text: String, package: String) -> Object:
	var intent: Object = intent_class.Intent(intent_class.ACTION_SEND)
	if intent == null or JavaClassWrapper.get_exception() != null:
		return null
	intent.setType("text/plain")
	if text != "":
		intent.putExtra(intent_class.EXTRA_TEXT, text)
	if package != "":
		intent.setPackage(package)
	return intent
