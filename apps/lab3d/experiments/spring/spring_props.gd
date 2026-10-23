## Grass island props of the spring lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the ball body is built and posed by spring.gd; nothing here touches a body.
## - the rig (its board's top 2 mm above the island, under the ball's blob shadow): a blue post (the spring's anchor) and a blue end stand holding a white rod at the
##   ball's height, a yellow board on the grass under it with white ticks every 0.5 m and a long
##   white "제자리" (rest length) mark,
## - the purple coil (the spring energy's colour) from the post to the ball, one mesh stretched
##   along the rod to the ball,
## - the orange ball (the hero) with its ArtJuice (shadow, squash, pop),
## - the energy bar beside the rig: one stack, kinetic K (blue, bottom) and spring U (purple, on top)
##   of the formula model, and a white mark at the release energy: without damping the stack always
##   reaches the mark (K + U kept), with damping it sinks below it,
## - the red restoring force arrow F = -kx above the ball (0.15 m per N),
## - reactions: release = stretch; reset = pop; the ball comes to rest = wobble.
class_name SpringProps
extends RefCounted

const BOARD_WIDTH := 1.0
const POST_HALF := 0.15          # half thickness of the post (the coil starts at its face)
const COIL_RADIUS := 0.2
const COIL_WIRE := 0.035
const COIL_TURNS := 11
const COIL_SIDES := 8            # segments per turn
const BAR_X := 2.6               # energy bar position (x, z) and size
const BAR_Z := -0.9
const BAR_WIDTH := 0.5
const BAR_MAX := 2.2             # m: the release energy's height
const FORCE_SCALE := 0.15        # m of arrow per N
const ARROW_LIFT := 0.35         # m above the ball top

var juice: ArtJuice
var coil: MeshInstance3D
var bar_kinetic: MeshInstance3D
var bar_spring: MeshInstance3D
var bar_mark: MeshInstance3D
var force_arrow: VelocityArrow
var _coil_base := 1.0            # coil length the mesh was built for
var _coil_from := 0.0            # x of the post face
var _radius := 0.35


## The static rig: post at `anchor_x`, rod at `rod_y` to the stand at `end_x`, the board with ticks
## and the rest mark at `rest_x`.
func rig_mesh(anchor_x: float, end_x: float, rod_y: float, rest_x: float) -> Mesh:
	var b := ArtKit.builder()
	var left := anchor_x - 0.4
	var right := end_x + 0.4
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3((left + right) * 0.5, -0.028, 0.0)), Vector3(right - left, 0.06, BOARD_WIDTH), 0.02, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	b.ao_min = 1.0
	var x := ceilf(left * 2.0) * 0.5
	while x <= right - 0.2:
		var long := is_equal_approx(fmod(absf(x), 1.0), 0.0)
		b.add_rounded_box(Transform3D(Basis(), Vector3(x, 0.006, BOARD_WIDTH * 0.5 - (0.17 if long else 0.1))), Vector3(0.04, 0.02, 0.34 if long else 0.2), 0.0, 1, ArtPalette.WHITE)
		x += 0.5
	b.add_rounded_box(Transform3D(Basis(), Vector3(rest_x, 0.008, 0.0)), Vector3(0.08, 0.02, BOARD_WIDTH - 0.12), 0.0, 1, ArtPalette.WHITE)
	# Post (anchor) and end stand, blue structure; the white rod between them.
	b.ao_min = 0.8
	b.ao_height = 0.6
	b.add_rounded_box(Transform3D(Basis(), Vector3(anchor_x - 0.1, rod_y * 0.5 + 0.15, 0.0)), Vector3(POST_HALF * 2.0 + 0.2, rod_y + 0.6, 0.5), 0.05, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(end_x, rod_y * 0.5 + 0.05, 0.0)), Vector3(0.16, rod_y + 0.2, 0.3), 0.04, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(anchor_x, rod_y, 0.0)), 0.03, 0.03, end_x - anchor_x, 6, ArtPalette.WHITE)
	# The energy bar's base and back plate.
	b.ao_min = 0.85
	b.add_rounded_box(Transform3D(Basis(), Vector3(BAR_X, 0.04, BAR_Z)), Vector3(BAR_WIDTH + 0.3, 0.08, BAR_WIDTH + 0.3), 0.03, 1, ArtPalette.BLUE_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(BAR_X, (BAR_MAX + 0.4) * 0.5, BAR_Z - BAR_WIDTH * 0.5 - 0.06)), Vector3(BAR_WIDTH + 0.3, BAR_MAX + 0.4, 0.06), 0.02, 1, ArtPalette.WHITE)
	return b.commit()


## A coil of `length` along +x from the origin (wound around the x axis).
static func coil_mesh(length: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	var n := COIL_TURNS * COIL_SIDES
	var prev := Vector3(0.0, COIL_RADIUS, 0.0)
	for i in range(1, n + 1):
		var a := TAU * i / COIL_SIDES
		var p := Vector3(length * i / n, COIL_RADIUS * cos(a), COIL_RADIUS * sin(a))
		var d := p - prev
		var up := d.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP).normalized()
		b.add_cylinder(Transform3D(Basis(side, up, side.cross(up)), prev), COIL_WIRE, COIL_WIRE, d.length(), 4, ArtPalette.PURPLE, false)
		prev = p
	return b.commit()


## A bar of height 1 from its base (scaled along y).
static func bar_mesh(color: Color, top: Color) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)), Vector3(BAR_WIDTH, 1.0, BAR_WIDTH), 0.0, 1, color, top)
	return b.commit()


func dress(experiment: Node3D, ball: RigidBody3D, radius: float, anchor_x: float, end_x: float, rod_y: float, rest_x: float) -> void:
	_radius = radius
	ArtKit.add_world(experiment, Vector3(-1.0, 0.0, -0.8))
	var rig := ArtKit.instance(rig_mesh(anchor_x, end_x, rod_y, rest_x))
	rig.name = "Rig"
	experiment.add_child(rig)
	_coil_from = anchor_x + POST_HALF
	_coil_base = rest_x - radius - _coil_from
	coil = ArtKit.instance(coil_mesh(_coil_base))
	coil.name = "Coil"
	coil.position = Vector3(_coil_from, rod_y, 0.0)
	experiment.add_child(coil)
	var visual := Node3D.new()   # the juice squashes this node; the yarn ball (Task 4g) is scaled under it
	visual.name = "Visual"
	ball.add_child(visual)
	var yarn := ArtKit.yarn_ball(radius, ArtPalette.ORANGE)
	yarn.name = "Yarn"
	visual.add_child(yarn)
	juice = ArtJuice.new()
	juice.name = "BallJuice"
	juice.round_body = true
	juice.dust_amount = 10
	experiment.add_child(juice)
	juice.setup(ball, visual, radius * 2.0)
	bar_kinetic = _bar(experiment, "BarKinetic", ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	bar_spring = _bar(experiment, "BarSpring", ArtPalette.PURPLE, ArtPalette.PURPLE_TOP)
	var mark := ArtKit.builder()
	mark.ao_min = 1.0
	mark.add_rounded_box(Transform3D.IDENTITY, Vector3(BAR_WIDTH + 0.24, 0.05, BAR_WIDTH + 0.24), 0.0, 1, ArtPalette.WHITE)
	bar_mark = ArtKit.instance(mark.commit())
	bar_mark.name = "EnergyMark"
	bar_mark.position = Vector3(BAR_X, BAR_MAX, BAR_Z)
	experiment.add_child(bar_mark)
	force_arrow = VelocityArrow.new(ArtPalette.RED, ArtPalette.RED_TOP)
	force_arrow.name = "ForceArrow"
	experiment.add_child(force_arrow)


func _bar(experiment: Node3D, bar_name: String, color: Color, top: Color) -> MeshInstance3D:
	var bar := ArtKit.instance(bar_mesh(color, top))
	bar.name = bar_name
	bar.position = Vector3(BAR_X, 0.08, BAR_Z)
	bar.visible = false
	experiment.add_child(bar)
	return bar


## The coil from the post face to the ball's near side at `ball_x`.
func stretch_coil(ball_x: float) -> void:
	if coil == null:
		return
	coil.scale = Vector3(maxf(0.05, ball_x - _radius - _coil_from) / _coil_base, 1.0, 1.0)


## The stack for kinetic `k` and spring `u` energy (J) against the release energy `release` (the
## mark's height; nothing shown when it is 0).
func show_energy(k: float, u: float, release: float) -> void:
	if bar_kinetic == null:
		return
	var shown := release > 1e-9
	bar_mark.visible = shown
	var hk := k / release * BAR_MAX if shown else 0.0
	var hu := u / release * BAR_MAX if shown else 0.0
	bar_kinetic.visible = hk > 0.005
	bar_spring.visible = hu > 0.005
	bar_kinetic.scale = Vector3(1.0, maxf(hk, 0.001), 1.0)
	bar_spring.position.y = 0.08 + hk
	bar_spring.scale = Vector3(1.0, maxf(hu, 0.001), 1.0)
	bar_mark.position.y = 0.08 + BAR_MAX if shown else 0.08


## The restoring force `force` (N, + = towards +x) above the ball at `at`; hidden below 0.05 N.
func show_force(at: Vector3, force: float) -> void:
	if force_arrow == null:
		return
	var l := snappedf(absf(force) * FORCE_SCALE, 0.02)
	force_arrow.visible = absf(force) >= 0.05
	if force_arrow.visible:
		force_arrow.point(Vector3(at.x, at.y + _radius + ARROW_LIFT, at.z), 0.0 if force > 0.0 else 180.0, l)


func released() -> void:
	if juice != null:
		juice.stretch()


func reset() -> void:
	if juice != null:
		juice.pop()


func status_changed(_previous: String, current: String) -> void:
	if current == "rest" and juice != null:
		juice.wobble()
