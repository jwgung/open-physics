## OPBENCH frame-time reporter (autoload "Bench"), ported from spikes/godot/scripts/bench.gd
## (this copy is the reference from now on; the spike stays frozen).
## Emits one JSON line per second in the exact format of docs/3d-phase0/benchmark-spec.md section 6.
## Android: android.util.Log.i("OPBENCH", line) through JavaClassWrapper, so `adb logcat -s OPBENCH:I` sees it.
## Everywhere: also print("OPBENCH " + line) (logcat tag "godot", stdout on desktop/web console).
## Alongside it, one OPPERF line per second (separate tag, so OPBENCH stays spec-exact) with the
## window means of Godot monitors and the active quality label; field meanings are in
## spikes/godot/README.md ("OPPERF"). `scene` is the experiment's bench id (incline friction = "S3",
## the guided incline of the benchmark spec) or "home" (the island map) / "list" / "settings" outside an
## experiment.
extends Node

signal report(line: String, fps: float, scene: String, p95_ms: float)

const LONG_FRAME_MS := 33.0
## OPPERF fields averaged per window, in emit order.
const PERF_FIELDS := ["process_ms", "physics_ms", "render_cpu_ms", "gpu_ms", "draws", "prims", "objects"]

var scene_name := "list"
var _elapsed := 0.0
var _window := 0.0
var _last_usec := -1   # -1 = next frame only sets the baseline (discarded interval)
var _frames: PackedFloat32Array = PackedFloat32Array()
var _android_log: Object = null
var _perf_sums: PackedFloat64Array = PackedFloat64Array()
var _perf_gpu_max := 0.0
var _viewport_rid: RID


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_name() == "Android" and ClassDB.class_exists("JavaClassWrapper"):
		_android_log = JavaClassWrapper.wrap("android.util.Log")
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_perf_sums.resize(PERF_FIELDS.size())


func reset(new_scene: String) -> void:
	scene_name = new_scene
	_elapsed = 0.0
	_window = 0.0
	_last_usec = -1
	_frames.clear()
	_reset_perf()


## Intervals come from Time.get_ticks_usec(), not the _process delta (delta_smoothing is also off in project.godot).
## The first frame after reset only sets the baseline, so the scene load / shader compile frame is not measured.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec < 0:
		_last_usec = now
		return
	var delta := (now - _last_usec) / 1000000.0
	_last_usec = now
	_frames.append(delta * 1000.0)
	_sample_perf()
	_window += delta
	if _window >= 1.0:
		_elapsed += _window
		_emit_window()
		_emit_perf()
		_window = 0.0
		_frames.clear()
		_reset_perf()


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
	var p95 := _percentile(sorted, 0.95)
	var line := '{"t":%d,"scene":%s,"fps":%.1f,"p50ms":%.1f,"p95ms":%.1f,"p99ms":%.1f,"frames":%d,"long":%d}' % [
		int(round(_elapsed)), JSON.stringify(scene_name), fps,
		_percentile(sorted, 0.50), p95, _percentile(sorted, 0.99),
		count, long_frames]
	if _android_log != null:
		_android_log.call("i", "OPBENCH", line)
	print("OPBENCH ", line)
	report.emit(line, fps, scene_name, p95)


## Monitors describe the previous frame; one sample per measured frame.
func _sample_perf() -> void:
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
	var values := [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid) + RenderingServer.get_frame_setup_time_cpu(),
		gpu,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
	]
	for i in values.size():
		_perf_sums[i] += values[i]
	_perf_gpu_max = maxf(_perf_gpu_max, gpu)


func _reset_perf() -> void:
	_perf_sums.fill(0.0)
	_perf_gpu_max = 0.0


func _emit_perf() -> void:
	var count := _frames.size()
	if count == 0:
		return
	var parts := PackedStringArray([
		'"t":%d' % int(round(_elapsed)), '"scene":%s' % JSON.stringify(scene_name), '"quality":"%s"' % Quality.label(),
		'"renderer":"%s"' % RenderingServer.get_current_rendering_method()])
	# The Compatibility renderer (or a driver without timestamp queries) has no GPU time; report null
	# instead of a misleading 0.
	var has_gpu_time := RenderingServer.get_current_rendering_method() != "gl_compatibility" and _perf_gpu_max > 0.0
	for i in PERF_FIELDS.size():
		var value := _perf_sums[i] / count
		parts.append('"%s":%s' % [PERF_FIELDS[i], "%.2f" % value if has_gpu_time or PERF_FIELDS[i] != "gpu_ms" else "null"])
	parts.append('"gpu_max_ms":%s' % ("%.2f" % _perf_gpu_max if has_gpu_time else "null"))
	var line := "{%s}" % ",".join(parts)
	if _android_log != null:
		_android_log.call("i", "OPPERF", line)
	print("OPPERF ", line)


## Nearest-rank percentile on an ascending array.
static func _percentile(sorted: PackedFloat32Array, q: float) -> float:
	var rank := int(ceil(q * sorted.size())) - 1
	return sorted[clampi(rank, 0, sorted.size() - 1)]
