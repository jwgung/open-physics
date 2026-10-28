## The slingshot's pull line (2026-10-28, collision and orbit labs): white dots from the pulled
## object back to where the finger pulls it (the reversed launch), shown only while a pull is held.
## One MultiMesh; show_line() places up to MAX_DOTS dots SPACING apart, hide_line() hides them.
class_name PullDots
extends MultiMeshInstance3D

const MAX_DOTS := 24
const SPACING := 0.22      # m between dots
const DOT_RADIUS := 0.06

## World positions of the shown dots (the MultiMesh keeps them on the rendering server).
var points := PackedVector3Array()


func _init() -> void:
	name = "PullDots"
	var dot := ArtKit.builder()
	dot.ao_min = 1.0
	dot.add_sphere(Transform3D.IDENTITY, DOT_RADIUS, 3, 5, ArtPalette.WHITE)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dot.commit()
	multimesh.instance_count = MAX_DOTS
	multimesh.visible_instance_count = 0
	material_override = ArtKit.lit_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Dots from `from` (not on it: the object is there) to `to`, SPACING apart.
func show_line(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	var count := clampi(int(floorf(length / SPACING)), 0, MAX_DOTS)
	points.resize(count)
	for i in count:
		points[i] = from.lerp(to, (i + 1) / float(count))
		multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))
	multimesh.visible_instance_count = count


func hide_line() -> void:
	points.clear()
	multimesh.visible_instance_count = 0


func dots() -> int:
	return multimesh.visible_instance_count
