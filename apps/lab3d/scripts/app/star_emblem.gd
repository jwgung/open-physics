## The map corner's star emblem (the story "별 조각 찾기", 2026-10-28): a big chubby star (StarArt's
## round-tipped rim, with a face like the 3D star: 2026-10-29 user wanted it cute) cut into one wedge
## per piece (11). The face sleeps (eyes shut) with no piece, looks up once pieces come, and beams
## (cheeks, a big smile) when the star is whole. A piece at the lookout fills its wedge (yellow); the others are pale
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


## The star's outline points (StarArt's chubby rim, starting at the top), radius r about c.
static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector3 in StarArt.round_rim():
		out.append(c + Vector2(p.x, -p.y) * r)
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
	_draw_face(c, r * 1.5)   # a bigger face than the 3D star: the emblem is small on screen


## The star's face (StarArt's proportions): asleep with no piece, awake with some, beaming when whole.
func _draw_face(c: Vector2, r: float) -> void:
	var ink := StarArt.FACE_INK
	var whole := filled >= total
	for x in [-1.0, 1.0]:
		var eye := c + Vector2(x * StarArt.EYE_X, -StarArt.EYE_Y) * r
		if filled == 0:   # asleep: closed eyes, little arcs
			draw_arc(eye + Vector2(0.0, -StarArt.EYE_R * 0.4 * r), StarArt.EYE_R * r, PI * 0.2, PI * 0.8, 8, ink, 2.0, true)
		else:
			draw_circle(eye, StarArt.EYE_R * r, ink)
			draw_circle(eye + Vector2(-StarArt.EYE_R * 0.3, -StarArt.EYE_R * 0.35) * r, StarArt.EYE_R * 0.38 * r, Color.WHITE)
		if whole or filled > 0:
			var cheek := Color(StarArt.CHEEK, 1.0 if whole else 0.6)
			draw_circle(c + Vector2(x * StarArt.EYE_X * 1.75, -(StarArt.EYE_Y - 0.13)) * r, StarArt.CHEEK_R * r, cheek)
	var mouth_r := (StarArt.MOUTH_R * (1.5 if whole else 1.0) + StarArt.MOUTH_W * 0.5) * r
	var mouth := c + Vector2(0.0, -(StarArt.MOUTH_Y + StarArt.MOUTH_R)) * r
	draw_arc(mouth, mouth_r, PI * 0.15, PI * 0.85, 10, ink, maxf(2.0, StarArt.MOUTH_W * r), true)
