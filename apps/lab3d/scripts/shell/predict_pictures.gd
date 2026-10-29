## The prediction's picture buttons (Plan G4, G2): one small drawing per choice, drawn with the
## canvas's 2D calls (no textures). Each shows the two cases side by side, the one the choice says
## in orange (thick) and the other pale: "the strong throw lands farther" against "both land
## together". The same few colours as the first round's throws (orange, pale sand, brown ground,
## water blue). The definition's predict.choices[].picture names a kind (ExperimentRegistry checks it).
class_name PredictPictures
extends RefCounted

const KINDS := ["long_arc", "same_arc", "fall_together", "fall_heavy_first", "light_flies", "both_stop",
	"spring_slow", "spring_even", "rubber_floor", "steel_floor", "push_harder", "push_same", "lever_far", "lever_same",
	"orbit_leave", "orbit_stay", "drum_big", "drum_small", "swing_slow", "swing_same",
	"pulley_many", "pulley_same", "slope_steep", "slope_same", "throw_slant", "throw_steep"]
const STRONG := Color("e2683c")
const PALE := Color("c9b892")
const GROUND := Color("8a6a46")
const WATER := Color("7fb8e0")
const STEEL := Color("9aa7b0")


## Draws `kind` filling `canvas` (an unknown kind draws the ground only).
static func draw(canvas: Control, kind: String) -> void:
	var r := Rect2(Vector2.ZERO, canvas.size).grow(-6.0)
	match kind:
		"long_arc", "same_arc":
			_throws(canvas, r, kind == "long_arc")
		"throw_slant", "throw_steep":
			_angles(canvas, r, kind == "throw_steep")
		"fall_together", "fall_heavy_first":
			_fall(canvas, r, kind == "fall_heavy_first")
		"light_flies", "both_stop":
			_collide(canvas, r, kind == "light_flies")
		"spring_slow", "spring_even":
			_springs(canvas, r, kind == "spring_slow")
		"rubber_floor", "steel_floor":
			_floor(canvas, r, kind == "rubber_floor")
		"push_harder", "push_same":
			_push(canvas, r, kind == "push_harder")
		"lever_far", "lever_same":
			_lever(canvas, r, kind == "lever_far")
		"orbit_leave", "orbit_stay":
			_orbit(canvas, r, kind == "orbit_leave")
		"drum_big", "drum_small":
			_drums(canvas, r, kind == "drum_big")
		"swing_slow", "swing_same":
			_swings(canvas, r, kind == "swing_slow")
		"pulley_many", "pulley_same":
			_pulleys(canvas, r, kind == "pulley_many")
		"slope_steep", "slope_same":
			_slopes(canvas, r, kind == "slope_steep")
		_:
			_ground(canvas, r)


static func _ground(canvas: Control, r: Rect2) -> void:
	canvas.draw_line(Vector2(r.position.x, r.end.y), r.end, GROUND, 3.0)


## An arrow from `from` to `to` with a small head.
static func _arrow(canvas: Control, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	canvas.draw_line(from, to, color, width, true)
	var d := (to - from).normalized() * (4.0 + width * 1.5)
	var side := Vector2(-d.y, d.x) * 0.6
	canvas.draw_colored_polygon(PackedVector2Array([to + d * 0.5, to - d + side, to - d - side]), color)


## Two throws from the same hand, a soft one (thin, pale) and a strong one (thick): the strong one
## lands farther ("long_arc"), or both land together ("same_arc").
static func _throws(canvas: Control, r: Rect2, far: bool) -> void:
	_ground(canvas, r)
	var soft := 0.45
	_arc(canvas, r, 0.95 if far else soft, 0.9 if far else 0.5, STRONG, 6.0)
	_arc(canvas, r, soft, 0.5, PALE, 3.0)   # on top: both show when they land together
	canvas.draw_circle(Vector2(r.position.x + 8.0, r.end.y - 8.0), 7.0, STRONG)


## Two throws of the same speed (2026-10-29, the angle game): a slanted one landing far and a steep
## one going high and landing near; the choice's one thick orange, the other pale.
static func _angles(canvas: Control, r: Rect2, steep: bool) -> void:
	_ground(canvas, r)
	_arc(canvas, r, 0.95, 0.5, PALE if steep else STRONG, 3.0 if steep else 6.0)
	_arc(canvas, r, 0.45, 0.95, STRONG if steep else PALE, 6.0 if steep else 3.0)
	canvas.draw_circle(Vector2(r.position.x + 8.0, r.end.y - 8.0), 7.0, STRONG)


## A throw drawn as a parabola from the left end over `reach` of the width, `rise` of the height.
static func _arc(canvas: Control, r: Rect2, reach: float, rise: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in 17:
		var k := i / 16.0
		points.append(Vector2(r.position.x + 8.0 + k * (r.size.x - 8.0) * reach, r.end.y - 8.0 - 4.0 * k * (1.0 - k) * r.size.y * rise))
	canvas.draw_polyline(points, color, width, true)


## A big (orange) and a small (pale) ball falling: side by side ("fall_together") or the big one
## ahead ("fall_heavy_first"), each with its fall arrow.
static func _fall(canvas: Control, r: Rect2, heavy_first: bool) -> void:
	_ground(canvas, r)
	var big := Vector2(r.position.x + r.size.x * 0.33, r.end.y - r.size.y * (0.3 if heavy_first else 0.62))
	var small := Vector2(r.position.x + r.size.x * 0.67, r.end.y - r.size.y * 0.62)
	_arrow(canvas, big + Vector2(0.0, 16.0), big + Vector2(0.0, 30.0), STRONG, 3.0)
	_arrow(canvas, small + Vector2(0.0, 11.0), small + Vector2(0.0, 25.0), PALE, 3.0)
	canvas.draw_circle(big, 14.0, STRONG)
	canvas.draw_circle(small, 8.0, PALE)


## A big ball (pale) has hit a small one (orange): the small one flies off fast ("light_flies") or
## both stand still together ("both_stop").
static func _collide(canvas: Control, r: Rect2, flies: bool) -> void:
	_ground(canvas, r)
	var y := r.end.y - 16.0
	var big := Vector2(r.position.x + r.size.x * 0.3, y)
	var small := Vector2(big.x + 14.0 + 8.0 + (r.size.x * 0.22 if flies else 0.0), r.end.y - 8.0)
	canvas.draw_circle(big, 14.0, PALE)
	canvas.draw_circle(small, 8.0, STRONG)
	if flies:
		_arrow(canvas, big + Vector2(16.0, -22.0), big + Vector2(30.0, -22.0), PALE, 3.0)
		_arrow(canvas, small + Vector2(12.0, -16.0), small + Vector2(r.size.x * 0.35, -16.0), STRONG, 4.0)
	else:
		for k in [-1.0, 1.0]:   # small still marks over both
			canvas.draw_line(Vector2(big.x + k * 6.0, y - 30.0), Vector2(big.x + k * 6.0, y - 22.0), PALE, 3.0)
			canvas.draw_line(Vector2(small.x + k * 5.0, y - 30.0), Vector2(small.x + k * 5.0, y - 22.0), STRONG, 3.0)


## Two springs from a wall pulled out as far and let go together, a small ball (pale, top) and a big
## one (orange, bottom), a moment later: the small one is already back near the wall with a long
## "fast" arrow while the big one is still out with a short one ("spring_slow"), or both are at the
## same place with the same arrow ("spring_even").
static func _springs(canvas: Control, r: Rect2, slow: bool) -> void:
	var wall := r.position.x + 6.0
	canvas.draw_line(Vector2(wall, r.position.y), Vector2(wall, r.end.y), GROUND, 4.0)
	var top := r.position.y + r.size.y * 0.28
	var bottom := r.position.y + r.size.y * 0.74
	var back := r.size.x * 0.42
	var out := r.size.x * 0.78 if slow else back
	_spring(canvas, Vector2(wall, top), back, PALE, 8.0)
	_spring(canvas, Vector2(wall, bottom), out, STRONG, 13.0)
	# Each ball's speed back towards the wall: an arrow above it, the longer the faster.
	var quick := r.size.x * (0.32 if slow else 0.2)
	var steady := r.size.x * (0.12 if slow else 0.2)
	_arrow(canvas, Vector2(wall + back + quick * 0.5, top - 15.0), Vector2(wall + back - quick * 0.5, top - 15.0), PALE, 3.0)
	_arrow(canvas, Vector2(wall + out + steady * 0.5, bottom - 20.0), Vector2(wall + out - steady * 0.5, bottom - 20.0), STRONG, 3.0)


## A zigzag spring of `length` from `from` with a ball of `radius` at its end.
static func _spring(canvas: Control, from: Vector2, length: float, color: Color, radius: float) -> void:
	var points := PackedVector2Array([from])
	var coils := 8
	for i in coils:
		points.append(from + Vector2((i + 0.5) / coils * (length - radius), -7.0 if i % 2 == 0 else 7.0))
	points.append(from + Vector2(length - radius, 0.0))
	canvas.draw_polyline(points, color, 3.0, true)
	canvas.draw_circle(from + Vector2(length, 0.0), radius, color)


## A box with a push arrow on a rubber floor (dark bumps) or a metal floor (flat grey, shine marks).
static func _floor(canvas: Control, r: Rect2, rubber: bool) -> void:
	var y := r.end.y - 6.0
	if rubber:
		var bumps := PackedVector2Array()
		for i in 13:
			bumps.append(Vector2(r.position.x + i / 12.0 * r.size.x, y + (0.0 if i % 2 == 0 else 6.0)))
		canvas.draw_rect(Rect2(r.position.x, y, r.size.x, 6.0), Color("5b4636"))
		canvas.draw_polyline(bumps, Color("3b2c22"), 4.0, true)
	else:
		canvas.draw_rect(Rect2(r.position.x, y, r.size.x, 6.0), STEEL)
		for x in [0.2, 0.55, 0.85]:
			canvas.draw_line(Vector2(r.position.x + r.size.x * x, y + 2.0), Vector2(r.position.x + r.size.x * x + 14.0, y + 2.0), Color("ffffff"), 2.0)
	var box := Rect2(r.position.x + r.size.x * 0.45, y - 40.0, 40.0, 40.0)
	canvas.draw_rect(box, STRONG)
	_arrow(canvas, Vector2(r.position.x + 10.0, y - 20.0), Vector2(box.position.x - 4.0, y - 20.0), GROUND, 4.0)


## A light box (pale, small) and a heavy box (orange, big) on one floor, each with its push arrow:
## the heavy one's is longer ("push_harder": it needs a harder push) or the same ("push_same").
static func _push(canvas: Control, r: Rect2, harder: bool) -> void:
	_ground(canvas, r)
	var y := r.end.y - 6.0
	var light := Rect2(r.position.x + r.size.x * 0.26, y - 22.0, 22.0, 22.0)
	canvas.draw_rect(light, PALE)
	_arrow(canvas, Vector2(light.position.x - 22.0, y - 11.0), Vector2(light.position.x - 3.0, y - 11.0), PALE, 4.0)
	var heavy := Rect2(r.position.x + r.size.x * 0.68, y - 44.0, 44.0, 44.0)
	canvas.draw_rect(heavy, STRONG)
	var reach := 52.0 if harder else 19.0
	_arrow(canvas, Vector2(heavy.position.x - 3.0 - reach, y - 22.0), Vector2(heavy.position.x - 3.0, y - 22.0), STRONG, 6.0 if harder else 4.0)


## A lever: the load on the left, the fulcrum, a hand arrow near it (pale) and one at the far end
## (orange): the far one is shorter ("lever_far": less force) or the same ("lever_same").
static func _lever(canvas: Control, r: Rect2, less: bool) -> void:
	_ground(canvas, r)
	var y := r.end.y - 26.0
	canvas.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), GROUND, 5.0)
	var pivot := r.position.x + r.size.x * 0.32
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(pivot, y + 3.0), Vector2(pivot - 12.0, r.end.y), Vector2(pivot + 12.0, r.end.y)]), PALE)
	canvas.draw_rect(Rect2(r.position.x + 4.0, y - 26.0, 26.0, 24.0), Color("5b4636"))
	var near := r.position.x + r.size.x * 0.5
	var far := r.end.x - 8.0
	_arrow(canvas, Vector2(near, y - 52.0), Vector2(near, y - 6.0), PALE, 4.0)
	var top := y - (22.0 if less else 52.0)
	_arrow(canvas, Vector2(far, top), Vector2(far, y - 6.0), STRONG, 5.0)


## The star and the planet's path: off the picture ("orbit_leave") or a closed loop ("orbit_stay").
static func _orbit(canvas: Control, r: Rect2, leave: bool) -> void:
	var star := Vector2(r.position.x + r.size.x * 0.38, r.get_center().y)
	canvas.draw_circle(star, 14.0, Color("f2c14e"))
	var points := PackedVector2Array()
	if leave:
		for i in 17:   # from under the star, round its right side and away (an opening spiral)
			var k := i / 16.0
			var a := PI * 0.5 - k * PI * 0.85
			var d := 24.0 + k * k * r.size.x * 0.45
			points.append(star + Vector2(cos(a) * d, sin(a) * d * 0.4))
		canvas.draw_polyline(points, STRONG, 4.0, true)
		_arrow(canvas, points[-2], points[-1], STRONG, 4.0)
	else:
		for i in 33:
			var a := i / 32.0 * TAU
			points.append(star + Vector2(cos(a) * r.size.x * 0.34 + r.size.x * 0.08, sin(a) * r.size.y * 0.42))
		canvas.draw_polyline(points, STRONG, 4.0, true)
	canvas.draw_circle(points[0], 6.0, STRONG)


## A big and a small drum of the same weight in water: the one the choice names floats higher
## (orange), the other sits deeper (pale).
static func _drums(canvas: Control, r: Rect2, big_wins: bool) -> void:
	var water := r.position.y + r.size.y * 0.5
	canvas.draw_rect(Rect2(r.position.x, water, r.size.x, r.end.y - water), WATER)
	var big := Vector2(56.0, 50.0)
	var small := Vector2(34.0, 34.0)
	# Out of the water: most of the winner (0.7), little of the other (0.2).
	var big_out := 0.7 if big_wins else 0.2
	var small_out := 0.2 if big_wins else 0.7
	canvas.draw_rect(Rect2(r.position.x + r.size.x * 0.12, water - big.y * big_out, big.x, big.y), STRONG if big_wins else PALE)
	canvas.draw_rect(Rect2(r.position.x + r.size.x * 0.64, water - small.y * small_out, small.x, small.y), PALE if big_wins else STRONG)
	canvas.draw_line(Vector2(r.position.x, water), Vector2(r.end.x, water), Color("4f86b3"), 2.0)


## A short (pale) and a long (orange) pendulum let go together: the long one is still behind
## ("swing_slow") or both swing at the same angle ("swing_same").
static func _swings(canvas: Control, r: Rect2, slow: bool) -> void:
	var beam := r.position.y + 2.0
	canvas.draw_line(Vector2(r.position.x, beam), Vector2(r.end.x, beam), GROUND, 4.0)
	var short_top := Vector2(r.position.x + r.size.x * 0.3, beam)
	var long_top := Vector2(r.position.x + r.size.x * 0.7, beam)
	var short_end := short_top + Vector2(0.0, r.size.y * 0.5).rotated(-0.5)
	var long_end := long_top + Vector2(0.0, r.size.y * 0.92).rotated(0.45 if slow else -0.5)
	canvas.draw_line(short_top, short_end, PALE, 3.0)
	canvas.draw_circle(short_end, 8.0, PALE)
	canvas.draw_line(long_top, long_end, STRONG, 3.0)
	canvas.draw_circle(long_end, 10.0, STRONG)


## Two pulleys lifting the same load: one rope (pale, long hand arrow) and four ropes (orange): the
## four-rope hand pulls with a shorter arrow ("pulley_many") or the same ("pulley_same").
static func _pulleys(canvas: Control, r: Rect2, less: bool) -> void:
	var beam := r.position.y + 2.0
	canvas.draw_line(Vector2(r.position.x, beam), Vector2(r.end.x, beam), GROUND, 4.0)
	var box_y := r.end.y - 22.0
	for side in [[0.22, 1, PALE], [0.68, 4, STRONG]]:
		var x: float = r.position.x + r.size.x * float(side[0])
		var n: int = side[1]
		var color: Color = side[2]
		for i in n:
			var sx := x - 9.0 + (18.0 * i / maxf(1.0, n - 1.0) if n > 1 else 9.0)
			canvas.draw_line(Vector2(sx, beam), Vector2(sx, box_y), color, 2.0)
		canvas.draw_rect(Rect2(x - 14.0, box_y, 28.0, 22.0), Color("5b4636"))
		var length := 46.0 if (n == 1 or not less) else 18.0
		_arrow(canvas, Vector2(x + 26.0, beam + 12.0), Vector2(x + 26.0, beam + 12.0 + length), color, 4.0)


## A gentle (pale) and a steep (orange) slope with a box: the steep box's arrow is longer
## ("slope_steep") or both arrows are the same ("slope_same").
static func _slopes(canvas: Control, r: Rect2, faster: bool) -> void:
	_ground(canvas, r)
	var half := r.size.x * 0.5
	for side in [[0.0, 0.25, PALE, 22.0], [half, 0.75, STRONG, 44.0 if faster else 22.0]]:
		var x0: float = r.position.x + float(side[0]) + 4.0
		var rise: float = r.size.y * float(side[1])
		var color: Color = side[2]
		var top := Vector2(x0, r.end.y - rise)
		var foot := Vector2(x0 + half - 10.0, r.end.y)
		canvas.draw_colored_polygon(PackedVector2Array([top, foot, Vector2(x0, r.end.y)]), Color(color, 0.45))
		canvas.draw_line(top, foot, color, 3.0, true)
		var down := (foot - top).normalized()
		var normal := Vector2(down.y, -down.x)
		var at := top + down * 18.0 + normal * 9.0
		canvas.draw_circle(at, 8.0, color)
		_arrow(canvas, at + down * 12.0, at + down * (12.0 + float(side[3])), color, 3.0)
