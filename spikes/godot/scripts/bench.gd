## OPBENCH frame-time reporter (autoload "Bench").
## Emits one JSON line per second in the exact format of docs/3d-phase0/benchmark-spec.md section 6.
## Android: android.util.Log.i("OPBENCH", line) through JavaClassWrapper, so `adb logcat -s OPBENCH:I` sees it.
## Everywhere: also print("OPBENCH " + line) (logcat tag "godot", stdout on desktop/web console).
extends Node

signal report(line: String, fps: float)

const LONG_FRAME_MS := 33.0

var scene_name := "S1"
var _elapsed := 0.0
var _window := 0.0
var _frames: PackedFloat32Array = PackedFloat32Array()
var _android_log: Object = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_name() == "Android" and ClassDB.class_exists("JavaClassWrapper"):
		_android_log = JavaClassWrapper.wrap("android.util.Log")


func reset(new_scene: String) -> void:
	scene_name = new_scene
	_elapsed = 0.0
	_window = 0.0
	_frames.clear()


func _process(delta: float) -> void:
	_frames.append(delta * 1000.0)
	_window += delta
	if _window >= 1.0:
		_elapsed += _window
		_emit_window()
		_window = 0.0
		_frames.clear()


func _emit_window() -> void:
	var count := _frames.size()
	if count == 0:
		return
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	var long_frames := 0
	for ms in sorted:
		total += ms
		if ms > LONG_FRAME_MS:
			long_frames += 1
	var fps := count / (total / 1000.0)
	var line := '{"t":%d,"scene":"%s","fps":%.1f,"p50ms":%.1f,"p95ms":%.1f,"p99ms":%.1f,"frames":%d,"long":%d}' % [
		int(round(_elapsed)), scene_name, fps,
		_percentile(sorted, 0.50), _percentile(sorted, 0.95), _percentile(sorted, 0.99),
		count, long_frames]
	if _android_log != null:
		_android_log.call("i", "OPBENCH", line)
	print("OPBENCH ", line)
	report.emit(line, fps)


## Nearest-rank percentile on an ascending array.
static func _percentile(sorted: PackedFloat32Array, q: float) -> float:
	var rank := int(ceil(q * sorted.size())) - 1
	return sorted[clampi(rank, 0, sorted.size() - 1)]
