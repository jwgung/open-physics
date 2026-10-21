## Header picture of the experiment list (art direction "list screen"): a small floating grass
## island with the yellow incline and red box, under a sky band with clouds. Drawn with a handful
## of flat polygons in this rect only (no texture, no full-screen layer).
class_name IslandBanner
extends Control

const HEIGHT := 168.0

var _sky := _make_sky()


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_style_box(_sky, Rect2(Vector2.ZERO, size))
	# Clouds.
	for c in [[0.14, 0.3, 1.0], [0.82, 0.22, 1.25], [0.6, 0.62, 0.8]]:
		_cloud(Vector2(w * c[0], h * c[1]), 16.0 * c[2])
	# Island: grass top (a flat octagon), soil underside (a faceted wedge).
	var cx := w * 0.38
	var top := h * 0.56
	var r := minf(w * 0.3, 190.0)
	var grass := PackedVector2Array([
		Vector2(cx - r, top), Vector2(cx - r * 0.82, top - 14), Vector2(cx + r * 0.82, top - 14), Vector2(cx + r, top),
		Vector2(cx + r * 0.9, top + 14), Vector2(cx - r * 0.9, top + 14)])
	var soil := PackedVector2Array([
		Vector2(cx - r * 0.9, top + 14), Vector2(cx + r * 0.9, top + 14), Vector2(cx + r * 0.45, top + 44),
		Vector2(cx + r * 0.12, top + 62), Vector2(cx - r * 0.2, top + 56), Vector2(cx - r * 0.55, top + 38)])
	draw_colored_polygon(soil, ArtPalette.SOIL)
	draw_colored_polygon(PackedVector2Array([soil[3], soil[4], Vector2(cx - r * 0.02, top + 70)]), ArtPalette.SOIL_DEEP)
	draw_colored_polygon(grass, ArtPalette.GRASS_TOP)
	draw_colored_polygon(PackedVector2Array([grass[0], grass[3], grass[4], grass[5]]), ArtPalette.GRASS)
	# Trees.
	for t in [[-0.7, 1.0], [-0.52, 0.75], [0.72, 0.9]]:
		_tree(Vector2(cx + r * t[0], top - 8), 30.0 * t[1])
	# Incline on its blue post, red box near the top.
	var low := Vector2(cx - r * 0.42, top - 12)
	var high := Vector2(cx + r * 0.5, top - 72)
	var post_x := cx + r * 0.05
	var post_top := lerpf(low.y, high.y, (post_x - low.x) / (high.x - low.x))
	draw_rect(Rect2(Vector2(post_x - 5, post_top), Vector2(10, top - 4 - post_top)), ArtPalette.BLUE)
	draw_colored_polygon(PackedVector2Array([low, high, high + Vector2(0, 11), low + Vector2(0, 11)]), ArtPalette.YELLOW_DARK)
	draw_colored_polygon(PackedVector2Array([low, high, high + Vector2(0, 5), low + Vector2(0, 5)]), ArtPalette.YELLOW)
	var along := (high - low).normalized()
	var up := Vector2(along.y, -along.x)
	var corner := low.lerp(high, 0.74)
	var side := 16.0
	draw_colored_polygon(PackedVector2Array([corner, corner + along * side, corner + (along + up) * side, corner + up * side]), ArtPalette.RED)


func _make_sky() -> StyleBoxFlat:
	var sky := StyleBoxFlat.new()
	sky.bg_color = ArtPalette.SKY
	sky.set_corner_radius_all(18)
	sky.anti_aliasing = true
	return sky


func _cloud(at: Vector2, k: float) -> void:
	draw_circle(at, k, ArtPalette.CLOUD, true, -1.0, true)
	draw_circle(at + Vector2(k * 1.1, k * 0.25), k * 0.75, ArtPalette.CLOUD, true, -1.0, true)
	draw_circle(at + Vector2(-k * 1.1, k * 0.3), k * 0.7, ArtPalette.CLOUD, true, -1.0, true)


func _tree(foot: Vector2, k: float) -> void:
	draw_rect(Rect2(foot + Vector2(-k * 0.1, -k * 0.35), Vector2(k * 0.2, k * 0.35)), ArtPalette.TRUNK)
	draw_colored_polygon(PackedVector2Array([foot + Vector2(-k * 0.55, -k * 0.3), foot + Vector2(k * 0.55, -k * 0.3), foot + Vector2(0, -k * 1.2)]), ArtPalette.LEAF)
	draw_colored_polygon(PackedVector2Array([foot + Vector2(-k * 0.42, -k * 0.85), foot + Vector2(k * 0.42, -k * 0.85), foot + Vector2(0, -k * 1.6)]), ArtPalette.LEAF_LIGHT)
