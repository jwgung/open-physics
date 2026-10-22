## Line/point graph for definition.graph (lab-graph.ts look: light grid, round 2.5-unit lines,
## latest point emphasised). The x range is fixed (graph.x.max); y grows to fit the data with
## graph.y.min_max as the smallest top value. With graph.y.signed the y axis runs from -top to +top
## around a zero line in the middle (signed values: the collision lab's momenta, + = to the right).
## Axis ticks are numbers with units.
class_name GraphView
extends Control

const PAD_LEFT := 64.0
const PAD_RIGHT := 16.0
const PAD_TOP := 14.0
const PAD_BOTTOM := 44.0

var spec: Dictionary = {}
var series: Dictionary = {}   # id -> PackedVector2Array
var updates := 0              # set_data calls so far (each one redraws)
var _bg := _background()


func _init() -> void:
	custom_minimum_size = Vector2(0, 260)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Always redraws: the caller decides when the data changed (ExperimentScreen compares
## Experiment.graph_revision() at 10 Hz). Comparing contents here would see an experiment's own
## growing array as unchanged.
func set_data(new_series: Dictionary) -> void:
	series = new_series
	updates += 1
	queue_redraw()


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	var font_size := 17
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))
	var plot := Rect2(PAD_LEFT, PAD_TOP, size.x - PAD_LEFT - PAD_RIGHT, size.y - PAD_TOP - PAD_BOTTOM)
	if plot.size.x < 10.0 or plot.size.y < 10.0:
		return
	var x_spec: Dictionary = spec.get("x", {})
	var y_spec: Dictionary = spec.get("y", {})
	var x_max: float = x_spec.get("max", 1.0)
	var signed: bool = y_spec.get("signed", false)
	var y_max := y_top(spec, series)
	var y_min := -y_max if signed else 0.0
	var muted := UiTheme.MUTED
	var grid := Color("e1ebf5")
	for i in 3:
		var y := plot.position.y + plot.size.y * i / 2.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid, 1.0)
		draw_string(font, Vector2(4.0, y + 6.0), _format(y_tick_values(y_max, signed)[i]), HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 12.0, font_size, muted)
	for i in 4:
		var x := plot.position.x + plot.size.x * i / 3.0
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), grid if i > 0 else Color("c9d8e8"), 1.0)
		var text := _format(x_max * i / 3.0)
		draw_string(font, Vector2(x - 40.0, plot.end.y + 24.0), text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, font_size, muted)
	var x_label := "%s (%s)" % [x_spec.get("label", ""), x_spec.get("unit", "")]
	draw_string(font, Vector2(plot.end.x - 300.0, size.y - 4.0), x_label, HORIZONTAL_ALIGNMENT_RIGHT, 300.0, font_size, muted)

	var to_screen := func(p: Vector2) -> Vector2:
		return Vector2(plot.position.x + p.x / x_max * plot.size.x, plot.end.y - (p.y - y_min) / (y_max - y_min) * plot.size.y)
	for entry in spec.get("series", []):
		var points: PackedVector2Array = series.get(entry.id, PackedVector2Array())
		if points.is_empty():
			continue
		var color := Color(entry.get("color", "#365eea"))
		var screen := PackedVector2Array()
		for p in points:
			screen.append(to_screen.call(p))
		if entry.get("style", "line") == "points":
			for p in screen:
				draw_circle(p, 4.5, color, true, -1.0, true)
			draw_circle(screen[-1], 7.0, color, true, -1.0, true)
		elif screen.size() >= 2:
			draw_polyline(screen, color, 3.0, true)


## The top value of the y axis: the data (with 8 % headroom) rounded up to a nice number, at least
## graph.y.min_max.
static func y_top(graph_spec: Dictionary, data: Dictionary) -> float:
	var y_spec: Dictionary = graph_spec.get("y", {})
	var signed: bool = y_spec.get("signed", false)
	var top: float = y_spec.get("min_max", 1.0)
	for id in data:
		for point in data[id]:
			top = maxf(top, (absf(point.y) if signed else point.y) * 1.08)
	return _nice_ceiling(top)


## The values of the three horizontal grid lines, top to bottom: max, max/2, 0 - or, on a signed axis
## (zero line in the middle), +max, 0, -max.
static func y_tick_values(top: float, signed: bool) -> Array[float]:
	if signed:
		return [top, 0.0, -top]
	return [top, top * 0.5, 0.0]


static func _format(value: float) -> String:
	if absf(value) >= 10.0:
		return "%d" % roundi(value)
	return ("%.1f" % value).trim_suffix(".0")


static func _nice_ceiling(value: float) -> float:
	var magnitude := pow(10.0, floorf(log(value) / log(10.0)))
	for step in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if value <= step * magnitude:
			return step * magnitude
	return value


static func _background() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.WHITE
	box.set_corner_radius_all(12)
	box.border_color = Color("dfeaf5")
	box.set_border_width_all(2)
	return box
