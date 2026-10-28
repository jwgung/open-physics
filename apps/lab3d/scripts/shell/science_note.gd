## "Gemini에게 더 물어보기" (2026-10-28 user decision): the science note's last button turns this run
## of a lab into a Korean question and hands it to another app the user picks (Gemini, or any app
## that takes text). The question holds the lab's content only — title, question, law and formula,
## the conditions and the note's numbers of this run, Dugi's explanation — never a name, a device id
## or the child's progress. The app itself calls no network: the share sheet (Android
## Intent.ACTION_SEND + createChooser) hands the text over, and the user sends it or not.
## Why a share sheet: Gemini has no official deep link that fills in a prompt, and the Gemini API
## terms do not allow apps likely used by people under 18 (https://ai.google.dev/gemini-api/terms).
class_name ScienceNote
extends RefCounted

const ROLE := "나는 '빵고양이 과학섬' 앱에서 물리 실험을 하고 있어. 초등학생도 이해하게 쉽게 설명해 줘."
const ENDING := "이 실험에 대해 더 궁금한 걸 물어볼게:"
const CHOOSER_TITLE := "질문을 보낼 앱 고르기"
const COPIED := "질문을 복사했어요. Gemini에 붙여 넣어 보세요."
const GEMINI_URL := "https://gemini.google.com/app"


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


## Hands `text` to another app: on Android the share sheet (ACTION_SEND, text/plain, a chooser),
## elsewhere (desktop, a failed intent) the clipboard and Gemini's page in the browser. Returns
## "share" or "clipboard" (the screen shows COPIED for the latter).
static func share(text: String) -> String:
	if _android_share(text):
		return "share"
	DisplayServer.clipboard_set(text)
	if DisplayServer.get_name() != "headless":
		OS.shell_open(GEMINI_URL)
	return "clipboard"


## Godot 4.4+ JNI from GDScript (no Gradle build, no plugin): AndroidRuntime's activity and
## JavaClassWrapper build the intent; startActivity runs on the Android UI thread
## (runOnUiThread with a Runnable made from a Godot Callable).
static func _android_share(text: String) -> bool:
	if not Engine.has_singleton("AndroidRuntime"):
		return false
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	var activity: Object = runtime.getActivity()
	if activity == null:
		return false
	var intent_class: JavaClass = JavaClassWrapper.wrap("android.content.Intent")
	var intent: Object = intent_class.Intent(intent_class.ACTION_SEND)
	if intent == null:
		return false
	intent.setType("text/plain")
	intent.putExtra(intent_class.EXTRA_TEXT, text)
	var chooser: Object = intent_class.createChooser(intent, CHOOSER_TITLE)
	if chooser == null or JavaClassWrapper.get_exception() != null:
		return false
	activity.runOnUiThread(runtime.createRunnableFromGodotCallable(func() -> void:
		activity.startActivity(chooser)))
	return true
