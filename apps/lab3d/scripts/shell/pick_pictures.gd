## The drawings of the mission's picture buttons (ConditionPicks): one small picture per setting,
## drawn with the canvas's 2D calls (no textures, nothing downloaded), in the storybook colours of
## the prediction pictures (PredictPictures) and the labs' own toy colours (ArtPalette): the earth,
## the moon and Jupiter, a light or a heavy box, a steel, wooden or rubber slide, a planet near or far
## from its star, one, two or four ropes, the hand near or far on the lever, a small or a big ball,
## a big or a small drum, a weight, a short or a long string. `size` (0..1) and `count` say how much
## the drawing shows (kid.picks entries). The words under the picture say the same thing.
class_name PickPictures
extends RefCounted

const KINDS := ["earth", "moon", "jupiter", "box", "slide_steel", "slide_wood", "slide_rubber", "orbit",
	"pulley", "lever", "ball_blue", "ball_orange", "drum_big", "drum_small", "weight", "rope"]
const OUTLINE := Color("8a6a46")   # PredictPictures.GROUND: the brown of the storybook lines
const STEEL := Color("9aa7b0")


## Draws `kind` filling `canvas` (an unknown kind draws nothing).
static func draw(canvas: Control, kind: String, size := 0.5, count := 1) -> void:
	var r := Rect2(Vector2.ZERO, canvas.size).grow(-4.0)
	var c := r.get_center()
	match kind:
		"earth":
			canvas.draw_circle(c, r.size.y * 0.45, ArtPalette.SEA)
			for blob in [[Vector2(-8, -6), 9.0], [Vector2(9, 6), 8.0], [Vector2(-3, 11), 5.0]]:
				canvas.draw_circle(c + blob[0], blob[1], ArtPalette.GRASS)
			canvas.draw_arc(c, r.size.y * 0.45, 0.0, TAU, 32, OUTLINE, 2.0, true)
		"moon":
			canvas.draw_circle(c, r.size.y * 0.32, Color("d9dbe2"))
			for crater in [[Vector2(-6, -4), 4.0], [Vector2(6, 5), 3.0], [Vector2(3, -8), 2.5]]:
				canvas.draw_circle(c + crater[0], crater[1], Color("aeb3c0"))
			canvas.draw_arc(c, r.size.y * 0.32, 0.0, TAU, 32, OUTLINE, 2.0, true)
		"jupiter":
			var radius := r.size.y * 0.5
			canvas.draw_circle(c, radius, Color("e8b77d"))
			for band in [-0.45, 0.0, 0.45]:   # stripes as chords of the disc
				var y: float = band * radius
				var half := sqrt(maxf(0.0, radius * radius - y * y)) - 1.0
				canvas.draw_line(c + Vector2(-half, y), c + Vector2(half, y), Color("b9784a"), 4.0, true)
			canvas.draw_circle(c + Vector2(radius * 0.35, radius * 0.25), 3.5, Color("c4573a"))
			canvas.draw_arc(c, radius, 0.0, TAU, 32, OUTLINE, 2.0, true)
		"box":
			_ground(canvas, r)
			var side := lerpf(14.0, r.size.y - 4.0, size)
			var box := Rect2(c.x - side * 0.5, r.end.y - side, side, side)
			canvas.draw_rect(box, ArtPalette.ORANGE)
			canvas.draw_rect(box, OUTLINE, false, 2.0)
			canvas.draw_line(Vector2(box.position.x, box.position.y + side * 0.3), Vector2(box.end.x, box.position.y + side * 0.3), Color("ffffff", 0.7), 2.0)
		"slide_steel", "slide_wood", "slide_rubber":
			_slide(canvas, r, kind)
		"orbit":
			var star := Vector2(r.position.x + 16.0, c.y)
			canvas.draw_circle(star, 11.0, ArtPalette.YELLOW)
			var d := lerpf(26.0, r.size.x - 22.0, size)
			canvas.draw_arc(star, d, -0.55, 0.55, 12, Color(OUTLINE, 0.6), 2.0, true)
			canvas.draw_circle(star + Vector2(d, 0.0), 7.0, ArtPalette.BLUE)
		"pulley":
			var beam := r.position.y + 2.0
			canvas.draw_line(Vector2(r.position.x + 10.0, beam), Vector2(r.end.x - 10.0, beam), OUTLINE, 4.0)
			var box_y := r.end.y - 18.0
			var span := 34.0
			for i in count:
				var x := c.x if count == 1 else c.x - span * 0.5 + span * i / (count - 1.0)
				canvas.draw_line(Vector2(x, beam), Vector2(x, box_y), ArtPalette.RED if i == 0 else Color("ffffff"), 3.0)
				canvas.draw_line(Vector2(x, beam), Vector2(x, box_y), OUTLINE, 1.0)
			canvas.draw_rect(Rect2(c.x - 22.0, box_y, 44.0, 18.0), Color("5b4636"))
		"lever":
			_ground(canvas, r)
			var y := r.end.y - 20.0
			var left := r.position.x + 4.0
			canvas.draw_line(Vector2(left, y), Vector2(r.end.x - 4.0, y), ArtPalette.YELLOW, 6.0)
			var pivot := left + r.size.x * 0.32
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(pivot, y + 3.0), Vector2(pivot - 9.0, r.end.y), Vector2(pivot + 9.0, r.end.y)]), ArtPalette.BLUE)
			canvas.draw_rect(Rect2(left + 2.0, y - 18.0, 18.0, 15.0), ArtPalette.ORANGE)
			var grip := lerpf(pivot + 10.0, r.end.x - 8.0, size)
			canvas.draw_line(Vector2(grip, y - 4.0), Vector2(grip, r.position.y + 6.0), Color("ffffff"), 3.0)
			canvas.draw_circle(Vector2(grip, r.position.y + 8.0), 7.0, ArtPalette.RED)
			_arrow(canvas, Vector2(grip + 12.0, r.position.y + 4.0), Vector2(grip + 12.0, y - 10.0), ArtPalette.RED, 3.0)
		"ball_blue", "ball_orange":
			_ground(canvas, r)
			var radius := lerpf(8.0, r.size.y * 0.5 - 2.0, size)
			var at := Vector2(c.x, r.end.y - radius - 1.0)
			canvas.draw_circle(at, radius, ArtPalette.BLUE if kind == "ball_blue" else ArtPalette.ORANGE)
			canvas.draw_arc(at, radius, 0.0, TAU, 24, OUTLINE, 2.0, true)
			canvas.draw_arc(at, radius * 0.6, -2.4, -1.2, 8, Color("ffffff", 0.8), 2.0, true)
		"drum_big", "drum_small":
			var water := r.position.y + r.size.y * 0.55
			canvas.draw_rect(Rect2(r.position.x, water, r.size.x, r.end.y - water), Color("7fb8e0"))
			var drum := Vector2(46.0, 40.0) if kind == "drum_big" else Vector2(28.0, 28.0)
			var rect := Rect2(c.x - drum.x * 0.5, water - drum.y * 0.5, drum.x, drum.y)
			canvas.draw_rect(rect, ArtPalette.ORANGE)
			canvas.draw_line(Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y), Color("ffffff"), 3.0)
			canvas.draw_rect(rect, OUTLINE, false, 2.0)
			canvas.draw_line(Vector2(r.position.x, water), Vector2(r.end.x, water), Color("4f86b3"), 2.0)
		"weight":
			_ground(canvas, r)
			var w := lerpf(20.0, r.size.y * 0.95, size)
			var h := w * 0.75
			var foot := r.end.y
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.5, foot), Vector2(c.x + w * 0.5, foot),
				Vector2(c.x + w * 0.35, foot - h), Vector2(c.x - w * 0.35, foot - h)]), Color("4a4f5c"))
			canvas.draw_arc(Vector2(c.x, foot - h), w * 0.22, PI, TAU, 10, Color("4a4f5c"), 4.0, true)
		"rope":
			var top := Vector2(c.x, r.position.y + 2.0)
			canvas.draw_line(top + Vector2(-26.0, 0.0), top + Vector2(26.0, 0.0), OUTLINE, 4.0)
			var bob := top + Vector2(0.0, lerpf(14.0, r.size.y - 9.0, size)).rotated(-0.35)
			canvas.draw_line(top, bob, Color("ffffff"), 3.0)
			canvas.draw_line(top, bob, OUTLINE, 1.0)
			canvas.draw_circle(bob, 8.0, ArtPalette.BLUE)


static func _ground(canvas: Control, r: Rect2) -> void:
	canvas.draw_line(Vector2(r.position.x, r.end.y), r.end, OUTLINE, 3.0)


## An arrow from `from` to `to` with a small head.
static func _arrow(canvas: Control, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	canvas.draw_line(from, to, color, width, true)
	var d := (to - from).normalized() * (4.0 + width * 1.5)
	var side := Vector2(-d.y, d.x) * 0.6
	canvas.draw_colored_polygon(PackedVector2Array([to + d * 0.5, to - d + side, to - d - side]), color)


## A slide with a box on it: shiny grey steel, brown wood with grain lines, dark bumpy rubber.
static func _slide(canvas: Control, r: Rect2, kind: String) -> void:
	_ground(canvas, r)
	var top := Vector2(r.position.x + 6.0, r.position.y + 6.0)
	var foot := Vector2(r.end.x - 4.0, r.end.y)
	var color: Color = {"slide_steel": STEEL, "slide_wood": Color("c98d4f"), "slide_rubber": Color("4a3b31")}[kind]
	canvas.draw_colored_polygon(PackedVector2Array([top, foot, Vector2(top.x, foot.y)]), color)
	var down := (foot - top).normalized()
	var normal := Vector2(down.y, -down.x)
	match kind:
		"slide_steel":
			for k in [0.3, 0.62]:
				var p := top.lerp(foot, k) - normal * 4.0
				canvas.draw_line(p, p + down * 12.0, Color("ffffff"), 2.0)
		"slide_wood":
			for k in [0.35, 0.7]:
				var a := Vector2(top.x + 4.0, top.lerp(foot, k).y)
				canvas.draw_line(a, Vector2(top.lerp(foot, k).x - 4.0, a.y), Color("8f5a2c"), 2.0)
		"slide_rubber":
			var bumps := PackedVector2Array()
			for i in 9:
				bumps.append(top.lerp(foot, i / 8.0) + normal * (2.0 if i % 2 == 0 else -1.0))
			canvas.draw_polyline(bumps, Color("2b211b"), 3.0, true)
	canvas.draw_line(top, foot, OUTLINE, 2.0, true)
	var box_at := top.lerp(foot, 0.3) + normal * 9.0
	canvas.draw_set_transform(box_at, down.angle(), Vector2.ONE)
	canvas.draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), ArtPalette.ORANGE)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
