## Confetti over the view when a whole round is done (2026-10-28): PIECES paper bits in the toy
## colours fall from above the view, swaying and turning, for about LIFE_S, then the node frees
## itself. 2D only (one canvas item, small rects: no particles, no 3D, no full-screen layer), and it
## never takes a touch (MOUSE_FILTER_IGNORE). The same pseudo-random fall every time (seeded).
class_name Confetti
extends Control

const PIECES := 64
const LIFE_S := 3.2
const COLORS := [Color("ff3b3b"), Color("ffc61a"), Color("2d7cf6"), Color("ff4fa3"), Color("4fbf3b"), Color("ff7a1a"), Color("7a5cf0")]

var t := 0.0
var _pieces: Array = []   # [x share, start y, fall speed, sway amp, sway rate, phase, spin, colour, size]


func _init() -> void:
	name = "Confetti"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	for i in PIECES:
		_pieces.append([rng.randf(), -rng.randf_range(20.0, 420.0), rng.randf_range(260.0, 430.0),
			rng.randf_range(10.0, 34.0), rng.randf_range(2.0, 4.5), rng.randf() * TAU, rng.randf_range(-7.0, 7.0),
			COLORS[i % COLORS.size()], Vector2(rng.randf_range(9.0, 14.0), rng.randf_range(14.0, 20.0))])


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	t += delta
	if t >= LIFE_S:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := clampf((LIFE_S - t) / 0.5, 0.0, 1.0)
	for p in _pieces:
		var at := Vector2(p[0] * size.x + p[3] * sin(t * p[4] + p[5]), p[1] + p[2] * t)
		if at.y < -30.0 or at.y > size.y + 30.0:
			continue
		var s: Vector2 = p[8]
		# A paper bit turning over: its width follows the spin's cosine.
		draw_set_transform(at, t * p[6], Vector2(absf(cos(t * p[6] * 0.7 + p[5])) * 0.8 + 0.2, 1.0))
		draw_rect(Rect2(-s * 0.5, s), Color(p[7], fade))
	draw_set_transform(Vector2.ZERO)
