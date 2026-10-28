## Grass island props of the free-fall lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the floor and ball bodies are built by free_fall.gd and are not changed here.
## - a blue height ruler (pole + white ticks every 0.5 m, longer every metre) behind the balls,
## - a yellow drop pad under each waiting ball that flips down and hides on release (the "놓기"
##   reaction) and comes back with a pop when the balls are put back,
## - the island, the ruler's blob shadow and each ball's ArtJuice (squash, dust, shadow; dust kept
##   to 10 grains per ball so three landings at once stay under the 32-grain budget),
## - each ball looks as heavy as it is (set_look, 2026-10-28): one stuff, its radius the cube root
##   of its mass against the 1 kg violet ball's 0.25 m, grown from the body's bottom (ArtJuice.look_scale),
## - the bread cat (CatActor wearing the BreadCat look, 2026-10-27) behind and left of the leftmost
##   ball, holding it on its pad with its left paw, on a stack of bread crates as tall as the ball is
##   high (CatCrates); "공 놓기" lets go (the arm follows down), it cheers when all balls landed. A
##   finger holding that ball: the cat only stands by. Only meshes: the balls wait and fall as the
##   formula says.
class_name FreeFallProps
extends PadProps

const RULER_AT := Vector3(-3.6, 0.0, -1.4)
const CRATE_MAX := 20             # a ball up to 8 m: crates no taller than about 0.4 m
## Shoulder -> held ball: out to the left and in front (the cat stands behind the ball's pad).
const CAT_HOLD_DIR := Vector3(0.36, 0.24, 0.9)
const RULER_HEIGHT := 8.5
const PAD_SIZE := Vector3(0.56, 0.06, 0.56)

var juices: Dictionary = {}    # ball id -> ArtJuice
var pads: Dictionary = {}      # ball id -> MeshInstance3D (the pad hinge node is the instance itself)
var cat: CatActor
var cat_stand: CatCrates
## The ball the cat holds (the leftmost one) and the ball a finger holds ("" = none).
var cat_ball := ""
var finger := ""
var _ball_nodes: Dictionary = {}   # ball id -> body
var _radius := 0.25                # the bodies' radius
## Ball id -> the radius its look has (set_look).
var look_radii: Dictionary = {}


## The ruler: a pole on a round foot, ticks on its front face (one static mesh).
func ruler_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = 0.15
	b.add_cylinder(Transform3D.IDENTITY, 0.42, 0.36, 0.12, 8, ArtPalette.BLUE_DARK)
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, RULER_HEIGHT * 0.5, 0.0)),
		Vector3(0.18, RULER_HEIGHT, 0.18), 0.03, 1, ArtPalette.BLUE)
	b.ao_min = 1.0
	var steps := int(RULER_HEIGHT / 0.5)
	for i in range(1, steps):
		var whole := i % 2 == 0
		var length := 0.34 if whole else 0.2
		b.add_rounded_box(Transform3D(Basis(), Vector3(0.09 + length * 0.5 - 0.02, i * 0.5, 0.06)),
			Vector3(length, 0.05, 0.05), 0.0, 1, ArtPalette.WHITE)
	return b.commit()


func pad_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.85
	# The pad hangs from its back edge (the node origin): it flips down around that edge.
	add_pad_slab(b, Vector3(0.0, -PAD_SIZE.y * 0.5, PAD_SIZE.z * 0.5), PAD_SIZE)
	return b.commit()


## Island, ruler, pads and the ball reactions. `balls` id -> [body, visual MeshInstance3D].
func dress(experiment: Node3D, balls: Dictionary, ball_size: float) -> void:
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.6), RULER_AT, 0.6)
	var ruler := ArtKit.instance(ruler_mesh())
	ruler.name = "Ruler"
	ruler.position = RULER_AT
	experiment.add_child(ruler)
	var mesh := pad_mesh()
	for id in balls:
		var pad := ArtKit.instance(mesh)
		pad.name = "Pad_%s" % id
		experiment.add_child(pad)
		pads[id] = pad
		var juice := ArtJuice.new()
		juice.name = "Juice_%s" % id
		juice.dust_amount = DUST_PER_BALL
		experiment.add_child(juice)
		var ball: RigidBody3D = balls[id][0]
		juice.round_body = true   # a ball (it may turn, Task 4f)
		juice.setup(ball, balls[id][1], ball_size, 0.0, ball.collision_mask)   # the shadow lands where the ball can
		juices[id] = juice
		_ball_nodes[id] = ball
		look_radii[id] = ball_size * 0.5
	_radius = ball_size * 0.5
	cat = CatActor.new(BreadCat.new())
	cat_stand = CatCrates.new(cat.look.footprint, CRATE_MAX)
	experiment.add_child(cat_stand)
	experiment.add_child(cat)


## Ball `id` looks `radius` m round (its bottom stays the body's bottom).
func set_look(id: String, radius: float) -> void:
	look_radii[id] = radius
	(juices[id] as ArtJuice).set_look_scale(radius / _radius)


## The cat holds the leftmost waiting ball (its look's centre = `starts` + its look radius; id ->
## bottom point) on its pad, or stands by while a finger holds that ball; its crates fit under it.
func place_cat(starts: Dictionary) -> void:
	if cat == null:
		return
	var left := ""
	for id in starts:
		if left == "" or starts[id].x < starts[left].x:
			left = id
	cat_ball = left
	cat.look_target = _ball_nodes.get(left)
	var r: float = look_radii.get(left, _radius)
	cat.hold(starts[left] + Vector3.UP * r, r, 0.0, finger != left, CAT_HOLD_DIR)
	cat_stand.fit(cat, 0.0)


## A finger picked up (`id`) or put down ("") a ball: the cat stands by while it holds the cat's ball.
func set_finger(id: String, starts: Dictionary) -> void:
	finger = id
	place_cat(starts)


## Puts the pad of a waiting ball under it (`bottom` = the ball's lowest point), as wide as the ball
## looks (PAD_SIZE for the 0.25 m look); no pad on the floor.
func place_pad(id: String, bottom: Vector3) -> void:
	var pad: MeshInstance3D = pads.get(id)
	if pad == null:
		return
	stop_flip(id)
	var k: float = look_radii.get(id, _radius) / _radius
	pad.scale = Vector3(k, 1.0, k)
	pad.position = bottom + Vector3(0.0, 0.0, -PAD_SIZE.z * 0.5 * k)
	pad.rotation = Vector3.ZERO
	pad.visible = bottom.y > PAD_MIN_HEIGHT


## Release: the pads flip down around their back edge and hide; the balls stretch.
func released() -> void:
	for id in pads:
		var pad: MeshInstance3D = pads[id]
		if pad.visible:
			flip_pad(id, pad, "rotation:x", PI * 0.5)
	for juice: ArtJuice in juices.values():
		juice.stretch()
	if cat != null:
		cat.let_go(Vector3.DOWN)


## The balls were put back (reset, condition change): they pop in again.
func reset() -> void:
	for juice: ArtJuice in juices.values():
		juice.pop()



## All balls landed: the cat cheers.
func status_changed(_previous: String, status: String) -> void:
	if cat != null and status == "landed":
		cat.cheer()
