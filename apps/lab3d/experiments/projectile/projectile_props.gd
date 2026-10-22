## Grass island props of the projectile lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the floor, ball and arrow-knob bodies are built by projectile.gd.
## - launch stand: a blue post behind the launch point with an arm and a yellow pad under the
##   waiting ball; the pad flips down on release (the ball falls past the stand on a vertical throw),
## - the purple velocity arrow (the web's purple arrow) from the ball to the yellow knob, rebuilt
##   only when the angle or speed changes (about 60 vertices),
## - the formula path: PATH_DOTS white dots on x(t), y(t) from the launch to the landing (one
##   MultiMesh, updated only when a condition or the start changes) and a white ring where the
##   formula lands,
## - white distance ticks on the floor every metre (every 5 m longer), the island and the ball's
##   ArtJuice.
class_name ProjectileProps
extends PadProps

const POST_BACK := 0.45          # m behind the ball (-x) the post stands
const PAD_SIZE := Vector3(0.5, 0.06, 0.5)
const PATH_DOTS := 28
const DOT_RADIUS := 0.05
const TICKS_FROM := -8
const TICKS_TO := 12
const TICKS_Z := 0.9
const ARROW_RADIUS := 0.05
const HEAD_LENGTH := 0.22

var juice: ArtJuice
var post: MeshInstance3D
var pad: MeshInstance3D
var arrow: MeshInstance3D
var path: MultiMeshInstance3D
var ring: MeshInstance3D
## (angle, speed) the arrow mesh was built for.
var _arrow_key := Vector2(-1.0, -1.0)


func ticks_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	for x in range(TICKS_FROM, TICKS_TO + 1):
		var long := x % 5 == 0
		var depth := 0.4 if long else 0.22
		b.add_rounded_box(Transform3D(Basis(), Vector3(x, 0.006, TICKS_Z + depth * 0.5)),
			Vector3(0.06, 0.02, depth), 0.0, 1, ArtPalette.WHITE)
	return b.commit()


## Post of unit height (scaled to the launch height) with a foot.
func post_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = 0.2
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)), Vector3(0.14, 1.0, 0.14), 0.0, 1, ArtPalette.BLUE)
	return b.commit()


## Pad with its arm to the post, hinged at the arm's post end (the node origin): it flips down
## around that edge.
func pad_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.85
	add_pad_slab(b, Vector3(POST_BACK, -PAD_SIZE.y * 0.5, 0.0), PAD_SIZE)
	b.add_rounded_box(Transform3D(Basis(), Vector3(POST_BACK * 0.5 - 0.06, -PAD_SIZE.y * 0.5, 0.0)),
		Vector3(POST_BACK - 0.1, 0.05, 0.12), 0.0, 1, ArtPalette.BLUE_DARK)
	return b.commit()


func knob_mesh(size: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D.IDENTITY, Vector3.ONE * size, 0.05, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	return b.commit()


func ring_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, 0.005, 0.0)), 0.34, 0.34, 0.02, 8, ArtPalette.WHITE, true)
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, 0.008, 0.0)), 0.24, 0.24, 0.02, 8, ArtPalette.GRASS_TOP, true)
	return b.commit()


func dress(experiment: Node3D, ball: RigidBody3D, ball_visual: MeshInstance3D, ball_size: float) -> void:
	ArtKit.add_world(experiment, Vector3(0.5, 0.0, -0.8))
	var ticks := ArtKit.instance(ticks_mesh())
	ticks.name = "DistanceTicks"
	experiment.add_child(ticks)
	post = ArtKit.instance(post_mesh())
	post.name = "LaunchPost"
	experiment.add_child(post)
	pad = ArtKit.instance(pad_mesh())
	pad.name = "LaunchPad"
	experiment.add_child(pad)
	arrow = MeshInstance3D.new()
	arrow.name = "VelocityArrow"
	arrow.material_override = ArtKit.lit_material()
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	experiment.add_child(arrow)
	var dot := ArtKit.builder()
	dot.ao_min = 1.0
	dot.add_sphere(Transform3D.IDENTITY, DOT_RADIUS, 3, 5, ArtPalette.WHITE)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dot.commit()
	multimesh.instance_count = PATH_DOTS
	multimesh.visible_instance_count = 0
	path = MultiMeshInstance3D.new()
	path.name = "FormulaPath"
	path.multimesh = multimesh
	path.material_override = ArtKit.lit_material()
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	experiment.add_child(path)
	ring = ArtKit.instance(ring_mesh())
	ring.name = "LandingRing"
	ring.visible = false
	experiment.add_child(ring)
	juice = ArtJuice.new()
	juice.name = "BallJuice"
	experiment.add_child(juice)
	juice.setup(ball, ball_visual, ball_size, 0.0, ball.collision_mask)   # not the arrow knob (its own layer)


## The stand under a waiting ball whose bottom is at `bottom` (no stand for a ball on the floor).
func place_stand(bottom: Vector3) -> void:
	stop_flip("pad")
	var up := bottom.y > PAD_MIN_HEIGHT
	post.visible = up
	pad.visible = up
	post.position = bottom + Vector3(-POST_BACK, -bottom.y, 0.0)
	post.scale = Vector3(1.0, maxf(bottom.y, 0.01), 1.0)
	pad.position = bottom + Vector3(-POST_BACK, 0.0, 0.0)
	pad.rotation = Vector3.ZERO


## The velocity arrow from the ball centre along (angle, speed), ending at the knob's near face.
func set_arrow(center: Vector3, angle_deg: float, speed: float, tip_length: float, knob_half: float) -> void:
	arrow.position = center
	arrow.rotation = Vector3(0.0, 0.0, deg_to_rad(angle_deg))
	var key := Vector2(angle_deg, speed)
	if key == _arrow_key:
		return
	_arrow_key = key
	var length := maxf(tip_length - knob_half, 0.3)
	var b := ArtKit.builder()
	b.ao_min = 1.0
	var shaft := length - HEAD_LENGTH
	# Built along +x (cylinders grow along +y from their base: turn them by -90 deg about z).
	var along := Basis(Vector3.BACK, -PI * 0.5)
	b.add_cylinder(Transform3D(along, Vector3.ZERO), ARROW_RADIUS, ARROW_RADIUS, shaft, 6,
		ArtPalette.PURPLE, true, ArtPalette.PURPLE_TOP)
	b.add_cylinder(Transform3D(along, Vector3(shaft, 0.0, 0.0)), ARROW_RADIUS * 2.6, 0.0, HEAD_LENGTH, 6,
		ArtPalette.PURPLE, true, ArtPalette.PURPLE_TOP)
	arrow.mesh = b.commit()


func show_arrow(on: bool) -> void:
	arrow.visible = on


## Dots on the formula path `points` (world positions, at most PATH_DOTS used) and the landing ring.
func set_path(points: PackedVector3Array, landing: Variant) -> void:
	var multimesh := path.multimesh
	var count := mini(points.size(), PATH_DOTS)
	for i in count:
		multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))
	multimesh.visible_instance_count = count
	ring.visible = landing != null
	if landing != null:
		ring.position = landing


## Release: the pad flips down and hides, the ball stretches, the arrow hides.
func released() -> void:
	show_arrow(false)
	if pad.visible:
		flip_pad("pad", pad, "rotation:z", -PI * 0.5)
	juice.stretch()


func reset() -> void:
	show_arrow(true)
	juice.pop()

