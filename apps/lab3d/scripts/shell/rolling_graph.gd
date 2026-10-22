## Graph samples over a sliding time window (Phase 1 Task 4e: the lever and pulley labs, whose clock
## runs only while a handle is held, like the web's graph time). add() keeps the samples of the last
## `window` seconds; series() gives them shifted so the window starts at x = 0 (GraphView's fixed x
## range). `revision` changes with every add() / clear() (Experiment.graph_revision()).
class_name RollingGraph
extends RefCounted

var window := 10.0
var revision := 0
var _ids: Array[String] = []
var _t := PackedFloat64Array()
var _values: Array[PackedFloat64Array] = []


func _init(series_ids: Array[String] = [], window_s := 10.0) -> void:
	_ids = series_ids
	window = window_s
	for id in _ids:
		_values.append(PackedFloat64Array())


func clear() -> void:
	_t.clear()
	for v in _values:
		v.clear()
	revision += 1


func size() -> int:
	return _t.size()


## Appends one sample at time `t` (s): `values` in the order of the series ids.
func add(t: float, values: Array) -> void:
	_t.append(t)
	for i in _values.size():
		_values[i].append(float(values[i]))
	var drop := 0
	while drop < _t.size() and _t[drop] < t - window - 1e-6:
		drop += 1
	if drop > 0:
		_t = _t.slice(drop)
		for i in _values.size():
			_values[i] = _values[i].slice(drop)
	revision += 1


## Time of the last sample (0 when empty).
func last_time() -> float:
	return _t[-1] if not _t.is_empty() else 0.0


## id -> PackedVector2Array of (t - offset, value), offset = how far the window has slid.
func series() -> Dictionary:
	var result := {}
	var offset := maxf(0.0, last_time() - window)
	for i in _ids.size():
		var points := PackedVector2Array()
		for k in _t.size():
			points.append(Vector2(_t[k] - offset, _values[i][k]))
		result[_ids[i]] = points
	return result
