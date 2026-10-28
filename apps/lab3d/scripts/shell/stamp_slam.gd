## The stamp slam (2026-10-28): a cleared stage's stamp drops into the middle of the view, lands with a
## squash and a small burst of stars, then flies and shrinks into its slot in the mission strip.
## `landed` fires when it arrives (the screen fills the slot then) and the node frees itself.
## Pictures and motion only (2026-10-28 user decision: no words). It never takes a touch
## (MOUSE_FILTER_IGNORE) and never touches the lab: the run goes on under it.
##
## The stamp itself (draw_stamp) is a drawing, no glyph: a green disc with the characters' brown
## outline, a cream ring and the bread cat's paw print. The round-done card draws the same stamp.
class_name StampSlam
extends Control

signal landed

const DROP_S := 0.16          # falls from DROP_SCALE to 1 (speeding up)
const DROP_SCALE := 2.4
const SQUASH := 0.28          # the landing squash (wider and flatter), decays over SQUASH_S
const SQUASH_S := 0.42
const HOLD_END_S := 0.58      # sits until then, then flies
const FLY_S := 0.36
const TOTAL_S := HOLD_END_S + FLY_S   # ~0.94 s
const RADIUS := 78.0          # UI units in the middle of the view
const STARS := 8
const STAR_S := 0.5
const STAR_REACH := 1.9       # of the radius

const GREEN := Color("4d8f3f")         # the strip's filled stamp colour
const EMPTY := Color("c9b892")         # the strip's empty stamp colour
const PAPER := Color("fff6e6")         # UiTheme.DIALOGUE_PAPER
const STAR_COLORS := [Color("ffc61a"), Color("ff7a1a"), Color("ff4fa3"), Color("ffffff")]

## Where the stamp lands first (view units) and its slot: a Callable -> Vector2 centre and the
## slot's radius (the strip may move while it flies).
var start := Vector2.ZERO
var slot: Callable
var slot_radius := 14.0
var t := 0.0
var _done := false


func _init() -> void:
	name = "StampSlam"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	advance(delta)


## Moves the clock on (tests step it exactly).
func advance(delta: float) -> void:
	if _done:
		return
	t += delta
	queue_redraw()
	if t >= TOTAL_S:
		finish()


## Ends now: the stamp is in its slot (landed fires once) and the node goes.
func finish() -> void:
	if _done:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	landed.emit()
	queue_free()


## The stamp's centre, radius and squash (x, y scale) at the time t.
func pose() -> Array:
	var target: Vector2 = slot.call() if slot.is_valid() else start
	if t < DROP_S:
		var k := t / DROP_S
		return [start, RADIUS * lerpf(DROP_SCALE, 1.0, k * k), Vector2.ONE]
	if t < HOLD_END_S:
		var s := t - DROP_S
		var e := exp(-s / SQUASH_S * 4.0) * cos(s / SQUASH_S * TAU * 1.25)
		return [start, RADIUS, Vector2(1.0 + SQUASH * e, 1.0 - SQUASH * e)]
	var k := clampf((t - HOLD_END_S) / FLY_S, 0.0, 1.0)
	var eased := k * k * (3.0 - 2.0 * k)
	var at := start.lerp(target, eased) + Vector2(0.0, -60.0 * sin(PI * k))   # a little arc up
	return [at, lerpf(RADIUS, slot_radius, eased), Vector2.ONE]


func _draw() -> void:
	if _done:
		return
	var p := pose()
	var alpha := clampf(t / (DROP_S * 0.6), 0.0, 1.0)
	# The star burst from the landing.
	var st := t - DROP_S
	if st >= 0.0 and st < STAR_S:
		var k := st / STAR_S
		for i in STARS:
			var a := TAU * i / STARS + 0.3
			var r: float = RADIUS * lerpf(0.9, STAR_REACH, 1.0 - (1.0 - k) * (1.0 - k))
			var size := 15.0 * (1.0 - k * 0.6)
			var color: Color = STAR_COLORS[i % STAR_COLORS.size()]
			color.a = 1.0 - k * k
			draw_star(self, start + Vector2(cos(a), sin(a)) * r, size, color, k * 3.0 + i)
	draw_set_transform(p[0], 0.0, p[2])
	draw_stamp(self, Vector2.ZERO, p[1], true, alpha)
	draw_set_transform(Vector2.ZERO)


## The stamp drawing on `canvas` at `center` (radius `r`): filled = the green paw stamp, else the
## empty one (a pale ring).
static func draw_stamp(canvas: CanvasItem, center: Vector2, r: float, filled := true, alpha := 1.0) -> void:
	var line := Color(ArtPalette.OUTLINE, alpha)
	if not filled:
		canvas.draw_circle(center, r, Color(PAPER, 0.9 * alpha))
		canvas.draw_arc(center, r * 0.86, 0.0, TAU, 40, Color(EMPTY, alpha), maxf(2.0, r * 0.12), true)
		return
	canvas.draw_circle(center, r, line)
	canvas.draw_circle(center, r * 0.9, Color(GREEN, alpha))
	canvas.draw_arc(center, r * 0.74, 0.0, TAU, 40, Color(PAPER, alpha), maxf(1.5, r * 0.07), true)
	var paw := Color(PAPER, alpha)
	canvas.draw_circle(center + Vector2(0.0, r * 0.16), r * 0.27, paw)
	canvas.draw_circle(center + Vector2(-r * 0.22, r * 0.3), r * 0.15, paw)
	canvas.draw_circle(center + Vector2(r * 0.22, r * 0.3), r * 0.15, paw)
	for i in 4:
		var a := deg_to_rad(-150.0 + 40.0 * i)
		canvas.draw_circle(center + Vector2(cos(a), sin(a)) * r * 0.4 + Vector2(0.0, r * 0.1), r * 0.11, paw)


## A five-point star (a drawing, no glyph) at `center`, outer radius `r`, turned `turn` rad.
static func draw_star(canvas: CanvasItem, center: Vector2, r: float, color: Color, turn := 0.0) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var a := turn - PI * 0.5 + PI * i / 5.0
		points.append(center + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	canvas.draw_colored_polygon(points, color)
