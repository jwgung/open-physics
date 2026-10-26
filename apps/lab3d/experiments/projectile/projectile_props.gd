## Grass island props of the projectile lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the floor, ball and arrow-knob bodies are built by projectile.gd.
## - the purple velocity arrow (the web's purple arrow, VelocityArrow) from the ball to the yellow
##   knob (VelocityArrow.knob_mesh), rebuilt only when its length changes (about 60 vertices),
## - the formula path: PATH_DOTS white dots on x(t), y(t) from the launch to the landing (one
##   MultiMesh, updated only when a condition or the start changes) and a white ring where the
##   formula lands,
## - white distance ticks on the floor every metre (every 5 m longer), the island and the ball's
##   ArtJuice,
## - the fences at both ends of the throw line (Task 4f): white board walls between blue posts, one
##   mesh; a landed ball bounces back from their faces (RollingContact; the engine has no fence body).
## - the bread cat (CatActor wearing the BreadCat look, Task 4g) behind the launch point, holding
##   the waiting ball in its left paw: its paw is the launch point (2026-10-23 user decision: no
##   launch post or pad). When the launch point is higher than its paw reaches from the floor, it
##   stands on a stack of wooden bread crates as tall as needed (crate_mesh). "공 놓기" makes it
##   wind up and swing, and the ball leaves its paw at the launch point on the frame the lab
##   releases it (throw()); it cheers when the ball lands. Only meshes: the ball body waits at the launch point the whole time (the paw
##   carries the ball's mesh, ArtJuice.set_carry), and the formula clock starts at the release.
class_name ProjectileProps
extends PadProps

## Bread crates under the cat: each about CRATE_H tall (a stack of n crates of height / n, n the
## fewest with crates no taller than CRATE_H), the cat's footprint plus a rim.
const CRATE_H := 0.42
const CRATE_RIM := 0.04
const CRATE_MAX := 10
const PATH_DOTS := 28
const DOT_RADIUS := 0.05
const TICKS_FROM := -8
const TICKS_TO := 12
const TICKS_Z := 0.9
## Centre of the island (its top is ArtKit.ISLAND_RADIUS around it): the fences stand inside.
const ISLAND_CENTER := Vector3(0.5, 0.0, -0.8)
## Fence boards: the gap under the lowest and between them (m); the posts' square section and the
## least distance of a post's side from the throw line z = 0 (more than the ball radius 0.25 m).
const BOARD_FOOT := 0.02
const BOARD_GAP := 0.03
const POST_SIZE := 0.16
const POST_CLEAR := 0.27

var juice: ArtJuice
var arrow: VelocityArrow
var path: MultiMeshInstance3D
var ring: MeshInstance3D
var fence: MeshInstance3D
var cat: CatActor
var cat_stand: MeshInstance3D
## The cat grips the waiting ball (false while a finger holds the ball).
var cat_grip := true
var _ball: RigidBody3D
var _launch_dir := Vector3.RIGHT   # direction of the arrow (the throw)
var _crates := 1                   # crates in the stand mesh now
var _path_count := 0               # dots set by set_path (show_dots shows at most these)
## The last formula dot drawn (where the preview path ends: the landing or a fence; tests).
var path_end := Vector3.INF


func ticks_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	for x in range(TICKS_FROM, TICKS_TO + 1):
		var long := x % 5 == 0
		var depth := 0.4 if long else 0.22
		b.add_rounded_box(Transform3D(Basis(), Vector3(x, 0.006, TICKS_Z + depth * 0.5)),
			Vector3(0.06, 0.02, depth), 0.0, 1, ArtPalette.WHITE)
	return b.commit()


## Both fences in the lab's space, centred on z = 0 (the throw line): a wall of three white boards
## (`thickness` along x, from the floor gap up to exactly `height`, the model's wall_top) between blue
## posts about every metre, its face towards the throw at x = `right_face` (it stands at
## x >= right_face, `right_width` along z) and x = `left_face` (x <= left_face, `left_width`). The
## posts (0.1 m above the boards) come in an even number, so none stands on the throw line: the
## nearest is POST_CLEAR or more from z = 0, beyond the ball (the model has boards only).
static func fence_mesh(right_face: float, left_face: float, height: float, right_width: float, left_width: float, thickness: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = 0.3
	for face_side in [[right_face, 1.0, right_width], [left_face, -1.0, left_width]]:
		var face: float = face_side[0]
		var side: float = face_side[1]
		var width: float = face_side[2]
		var x := face + side * thickness * 0.5
		var boards := 3
		var slot := (height - BOARD_FOOT) / boards
		for i in boards:
			# Board i from its gap below up to the top of its slot: the top board ends at `height`.
			b.add_rounded_box(Transform3D(Basis(), Vector3(x, BOARD_FOOT + slot * (i + 1) - (slot - BOARD_GAP) * 0.5, 0.0)),
				Vector3(thickness, slot - BOARD_GAP, width), 0.0, 1, ArtPalette.WHITE)
		var posts := maxi(2, ceili(width) + 1)
		posts += posts % 2   # even: no post on z = 0
		for i in posts:
			var z := -width * 0.5 + width * i / float(posts - 1)
			b.add_rounded_box(Transform3D(Basis(), Vector3(x + side * thickness * 0.5, (height + 0.1) * 0.5, z)),
				Vector3(POST_SIZE, height + 0.1, POST_SIZE), 0.02, 1, ArtPalette.BLUE)
	return b.commit()


## A stack of `count` wooden bread crates `footprint` wide, of total height 1 (the node is scaled
## to the stand height): each a dark inside, two plank bands around it, four corner posts and a
## dark seam to the next one.
static func crate_mesh(footprint: Vector2, count: int) -> Mesh:
	var b := ArtKit.builder()
	var size := Vector2(footprint.x + CRATE_RIM, footprint.y + CRATE_RIM)
	var h := 1.0 / count
	b.ao_height = 0.3
	for i in count:
		var y0 := h * i
		b.ao_min = 0.8 if i == 0 else 0.95
		b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, y0 + h * 0.5, 0.0)), Vector3(size.x - 0.04, h, size.y - 0.04), 0.0, 1, ArtPalette.TRUNK)
		b.ao_min = 1.0
		for k in 2:
			b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, y0 + h * (0.3 + 0.42 * k), 0.0)), Vector3(size.x - 0.01, h * 0.3, size.y - 0.01), 0.0, 1, ArtPalette.CRATE, ArtPalette.CRATE_TOP)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				b.add_rounded_box(Transform3D(Basis(), Vector3(cx * (size.x * 0.5 - 0.035), y0 + h * 0.5, cz * (size.y * 0.5 - 0.035))), Vector3(0.07, h * 0.9, 0.07), 0.0, 1, ArtPalette.CRATE_TOP)
	return b.commit()


func ring_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, 0.005, 0.0)), 0.34, 0.34, 0.02, 8, ArtPalette.WHITE, true)
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, 0.008, 0.0)), 0.24, 0.24, 0.02, 8, ArtPalette.GRASS_TOP, true)
	return b.commit()


func dress(experiment: Node3D, ball: RigidBody3D, ball_visual: MeshInstance3D, ball_size: float) -> void:
	ArtKit.add_world(experiment, ISLAND_CENTER)
	var ticks := ArtKit.instance(ticks_mesh())
	ticks.name = "DistanceTicks"
	experiment.add_child(ticks)
	arrow = VelocityArrow.new()
	arrow.name = "VelocityArrow"
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
	fence = ArtKit.instance(fence_mesh(experiment.FENCE_X, experiment.FENCE_LEFT_X, experiment.FENCE_HEIGHT, experiment.FENCE_WIDTH, experiment.FENCE_LEFT_WIDTH, experiment.FENCE_THICKNESS))
	fence.name = "Fences"
	experiment.add_child(fence)
	ring = ArtKit.instance(ring_mesh())
	ring.name = "LandingRing"
	ring.visible = false
	experiment.add_child(ring)
	juice = ArtJuice.new()
	juice.name = "BallJuice"
	experiment.add_child(juice)
	juice.round_body = true   # the ball turns (Task 4f): its extent is the same in every direction
	juice.setup(ball, ball_visual, ball_size, 0.0, ball.collision_mask)   # not the arrow knob (its own layer)
	_ball = ball
	cat = CatActor.new(BreadCat.new())
	cat_stand = ArtKit.instance(crate_mesh(cat.look.footprint, 1))
	cat_stand.name = "CatCrates"
	cat_stand.visible = false
	experiment.add_child(cat_stand)
	cat.look_target = ball
	cat.carried = func(center: Vector3) -> void: juice.set_carry(center - _ball.global_position)
	experiment.add_child(cat)


## The cat takes the waiting ball whose bottom is at `bottom` (the launch point: its paw).
func place_stand(bottom: Vector3) -> void:
	_hold_cat(bottom + Vector3.UP * juice.size * 0.5)


## The cat holds (or, a finger holding the ball, stands by) a waiting ball centred at `center`; its
## stand grows to the height it needs. The ball's mesh is back on its body.
func _hold_cat(center: Vector3) -> void:
	if cat == null:
		return
	juice.set_carry(Vector3.ZERO)
	cat.hold(center, juice.size * 0.5, 0.0, cat_grip)
	var height := cat.stand_height
	cat_stand.visible = height > 0.01
	if cat_stand.visible:
		var count := clampi(ceili(height / CRATE_H - 1e-6), 1, CRATE_MAX)
		if count != _crates:
			_crates = count
			cat_stand.mesh = crate_mesh(cat.look.footprint, count)   # only when the count changes
		cat_stand.position = Vector3(cat.position.x, 0.0, cat.position.z)
		cat_stand.scale = Vector3(1.0, height, 1.0)


## "공 놓기": the cat throws, and `release` (the lab's release) runs on the frame the ball leaves its
## paw at the launch point.
func throw(release: Callable) -> void:
	cat.throw(_launch_dir, release)


func throwing() -> bool:
	return cat != null and cat.throwing()


## A finger picks up (false) or puts down (true) the waiting ball: the cat lets it go / grips again.
func set_cat_grip(on: bool) -> void:
	cat_grip = on
	if cat != null and not cat.throwing():
		_hold_cat(_ball.global_position)   # the waiting ball's centre either way (its body is where it waits)


## The velocity arrow from the ball centre along (angle, speed), ending at the knob's near face.
func set_arrow(center: Vector3, angle_deg: float, tip_length: float, knob_half: float) -> void:
	arrow.point(center, angle_deg, tip_length - knob_half)
	_launch_dir = Vector3(cos(deg_to_rad(angle_deg)), sin(deg_to_rad(angle_deg)), 0.0)


func show_arrow(on: bool) -> void:
	arrow.visible = on


## Dots on the formula path `points` (world positions, at most PATH_DOTS used) and the landing ring.
func set_path(points: PackedVector3Array, landing: Variant) -> void:
	var multimesh := path.multimesh
	var count := mini(points.size(), PATH_DOTS)
	for i in count:
		multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))
	multimesh.visible_instance_count = count
	_path_count = count
	path_end = points[count - 1] if count > 0 else Vector3.INF
	ring.visible = landing != null
	if landing != null:
		ring.position = landing


## Shows the first `count` dots of the path (the slingshot game's trail grows with the flight).
func show_dots(count: int) -> void:
	var shown := mini(count, _path_count)
	if path.multimesh.visible_instance_count != shown:
		path.multimesh.visible_instance_count = shown


## Release: the ball stretches, the arrow hides; a ball let go without the cat's throw (tests, a
## direct release) leaves its paw too.
func released() -> void:
	show_arrow(false)
	juice.set_carry(Vector3.ZERO)
	juice.stretch()
	if cat != null:
		cat.let_go(_launch_dir)


func reset() -> void:
	show_arrow(true)
	juice.pop()


## The ball landed (or met a fence): the cat cheers.
func status_changed(_previous: String, status: String) -> void:
	if cat != null and status in ["landed", "fence"]:
		cat.cheer()

