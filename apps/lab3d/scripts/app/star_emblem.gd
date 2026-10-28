## The map corner's star emblem (the story "별 조각 찾기", 2026-10-28): a big five-point star cut into
## one wedge per piece (11). A piece at the lookout fills its wedge (yellow); the others are pale
## paper. A newly filled wedge pops (a short bounce of the whole emblem). Pictures only, no number
## and no words. 2D shapes only (one canvas item); it takes no touch.
class_name StarEmblem
extends Control

const SIZE := 104.0
const PAPER := Color("fff6e6")        # UiTheme.DIALOGUE_PAPER
const EMPTY := Color("f1e2c0")
const FILL := Color("ffc61a")         # ArtPalette.YELLOW
const FILL_LIGHT := Color("ffe27a")
const POP_S := 0.45

var total := 11
var filled := 0
var _pop := -1.0


func _init(count: int) -> void:
	name = "StarEmblem"
	total = count
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	pivot_offset = size * 0.5


## Shows `count` pieces at the lookout; `pop` when one just arrived.
func set_filled(count: int, pop := false) -> void:
	filled = clampi(count, 0, total)
	if pop:
		_pop = 0.0
		set_process(true)
	queue_redraw()


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_pop += delta
	var k := clampf(_pop / POP_S, 0.0, 1.0)
	scale = Vector2.ONE * (1.0 + 0.35 * sin(PI * k) * (1.0 - k * 0.5))
	if k >= 1.0:
		scale = Vector2.ONE
		set_process(false)


## The star's outline points (10, starting at the top), radius r about c.
static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		out.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.48))
	return out


## The point of the star's outline at angle `a` (from the centre, radius r): the outline is
## a polygon, so the ray meets one of its edges.
static func outline_at(c: Vector2, r: float, a: float) -> Vector2:
	var pts := star_points(c, r)
	var dir := Vector2(cos(a), sin(a))
	for i in pts.size():
		var p0 := pts[i] - c
		var p1 := pts[(i + 1) % pts.size()] - c
		var hit: Variant = Geometry2D.segment_intersects_segment(Vector2.ZERO, dir * r * 2.0, p0, p1)
		if hit != null:
			return c + (hit as Vector2)
	return c + dir * r


func _draw() -> void:
	var c := size * 0.5
	var r := SIZE * 0.5 - 4.0
	var line := ArtPalette.OUTLINE
	draw_colored_polygon(star_points(c, r + 4.0), line)
	draw_colored_polygon(star_points(c, r), PAPER)
	# The wedges: equal angles from the top, clockwise; each edge follows the star's outline.
	var steps := 6
	for i in total:
		var a0 := -PI * 0.5 + TAU * i / total
		var a1 := -PI * 0.5 + TAU * (i + 1) / total
		var poly := PackedVector2Array([c])
		for s in steps + 1:
			poly.append(outline_at(c, r, lerpf(a0, a1, float(s) / steps)))
		var color := (FILL if i % 2 == 0 else FILL_LIGHT) if i < filled else EMPTY
		draw_colored_polygon(poly, color)
	for i in total:
		var a := -PI * 0.5 + TAU * i / total
		draw_line(c, outline_at(c, r, a), Color(line, 0.55), 1.5, true)
	var outline := star_points(c, r)
	outline.append(outline[0])
	draw_polyline(outline, line, 3.0, true)
