## Grass island props of the free-fall lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the floor and ball bodies are built by free_fall.gd and are not changed here.
## - a blue height ruler (pole + white ticks every 0.5 m, longer every metre) behind the balls,
## - a yellow drop pad under each waiting ball that flips down and hides on release (the "놓기"
##   reaction) and comes back with a pop when the balls are put back,
## - the island, the ruler's blob shadow and each ball's ArtJuice (squash, dust, shadow; dust kept
##   to 10 grains per ball so three landings at once stay under the 32-grain budget).
class_name FreeFallProps
extends PadProps

const RULER_AT := Vector3(-3.6, 0.0, -1.4)
const RULER_HEIGHT := 8.5
const PAD_SIZE := Vector3(0.56, 0.06, 0.56)

var juices: Dictionary = {}    # ball id -> ArtJuice
var pads: Dictionary = {}      # ball id -> MeshInstance3D (the pad hinge node is the instance itself)


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
		juice.setup(balls[id][0], balls[id][1], ball_size)
		juices[id] = juice


## Puts the pad of a waiting ball under it (`bottom` = the ball's lowest point); no pad on the floor.
func place_pad(id: String, bottom: Vector3) -> void:
	var pad: MeshInstance3D = pads.get(id)
	if pad == null:
		return
	stop_flip(id)
	pad.position = bottom + Vector3(0.0, 0.0, -PAD_SIZE.z * 0.5)
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


## The balls were put back (reset, condition change): they pop in again.
func reset() -> void:
	for juice: ArtJuice in juices.values():
		juice.pop()

