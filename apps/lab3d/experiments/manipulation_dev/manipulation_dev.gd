## Development scene for the shell's object manipulation (Phase 1 Task 2b). Not on the list screen
## (content/experiments/index.json `hidden`); open with --experiment=manipulation-dev.
## Three boxes on the island floor and one fixed blue block: drag on the floor plane (0.25 m grid,
## inside an 8 x 6 m area), the height handle (0..2 m in 0.25 m steps), and placements blocked by
## another box or the block. "상자 떨어뜨리기" unfreezes the boxes so raised ones fall and land.
## Props are built here (a development scene, no separate *_props.gd).
extends Experiment

const AREA := Vector2(4.0, 3.0)   # half size of the floor area the boxes can be placed in (x, z)
## id -> [size (m), colour, top colour, start position (x, z)]
const BOXES := {
	"red": [0.5, ArtPalette.RED, ArtPalette.RED_TOP, Vector2(-2.0, 0.5)],
	"orange": [0.4, Color("ff7a1a"), Color("ff9440"), Vector2(0.0, 1.5)],
	"pink": [0.6, Color("ff4fa3"), Color("ff6fb5"), Vector2(-0.75, -1.5)],
}
const BLOCK_SIZE := Vector3(1.0, 0.6, 1.0)
const BLOCK_AT := Vector3(1.75, 0.3, -0.75)

var bodies: Dictionary = {}       # id -> RigidBody3D
var juices: Dictionary = {}       # id -> ArtJuice
var _floor: StaticBody3D


func _ready() -> void:
	add_child(ArtKit.make_environment())
	ArtKit.build_island(self, Vector3(0.0, 0.0, 0.0), func(s: ArtMeshBuilder) -> void:
		s.add_soft_rect(Transform3D(Basis(), Vector3(BLOCK_AT.x, 0.012, BLOCK_AT.z)), Vector2(0.45, 0.45), 0.3, ArtKit.shadow_alpha()))
	_floor = StaticBody3D.new()
	_add_box_shape(_floor, Vector3(30.0, 0.4, 12.0))
	_floor.position = Vector3(0.0, -0.2, 0.0)
	add_child(_floor)
	var block := StaticBody3D.new()
	block.name = "Block"
	_add_box_shape(block, BLOCK_SIZE)
	var b := ArtKit.builder()
	b.add_rounded_box(Transform3D.IDENTITY, BLOCK_SIZE, 0.06, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	block.add_child(ArtKit.instance(b.commit()))
	block.position = BLOCK_AT
	add_child(block)
	# Floor area outline (where boxes may be placed), visual only.
	var outline := ArtKit.builder()
	outline.ao_min = 1.0
	for side in [-1.0, 1.0]:
		outline.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.005, side * AREA.y)), Vector3(AREA.x * 2.0 + 0.06, 0.02, 0.06), 0.01, 1, ArtPalette.WHITE)
		outline.add_rounded_box(Transform3D(Basis(), Vector3(side * AREA.x, 0.005, 0.0)), Vector3(0.06, 0.02, AREA.y * 2.0), 0.01, 1, ArtPalette.WHITE)
	add_child(ArtKit.instance(outline.commit()))
	for id in BOXES:
		var spec: Array = BOXES[id]
		var size: float = spec[0]
		var body := RigidBody3D.new()
		body.name = id.capitalize()
		body.mass = 1.0
		body.can_sleep = false
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		_add_box_shape(body, Vector3.ONE * size)
		var mb := ArtKit.builder()
		mb.ao_height = size * 0.6
		mb.add_rounded_box(Transform3D.IDENTITY, Vector3.ONE * size, 0.05, 1, spec[1], spec[2])
		var visual := ArtKit.instance(mb.commit())
		visual.name = "Visual"
		body.add_child(visual)
		add_child(body)
		var juice := ArtJuice.new()
		juice.name = "%sJuice" % body.name
		add_child(juice)
		juice.setup(body, visual, size)
		juice.landed.connect(impact.emit)
		bodies[id] = body
		juices[id] = juice
	reset_boxes()


func run_action(id: String) -> void:
	match id:
		"drop":
			for body: RigidBody3D in bodies.values():
				body.freeze = false
				body.sleeping = false
		"reset":
			reset_boxes()


func reset_boxes() -> void:
	for id in BOXES:
		var spec: Array = BOXES[id]
		var body: RigidBody3D = bodies[id]
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.global_transform = Transform3D(Basis(), Vector3(spec[3].x, spec[0] * 0.5, spec[3].y))
		juices[id].pop()
	_changed()


func observations() -> Dictionary:
	var values := {}
	for id in bodies:
		values[id] = _base_height(id)
	return values


func graph_series() -> Dictionary:
	var points := PackedVector2Array()
	var i := 1
	for id in bodies:
		points.append(Vector2(i, _base_height(id)))
		i += 1
	return {"height": points}


func graph_revision() -> int:
	return -1   # heights change while boxes fall: rebuild on each poll (3 points)


func follow_point() -> Vector3:
	return bodies["red"].global_position


# --- manipulation -----------------------------------------------------------------------------

func manipulation_body(id: String) -> PhysicsBody3D:
	return bodies.get(id)


func manipulation_surface(surface_id: String) -> ManipSurface:
	if surface_id != "floor":
		return null
	var surface := ManipSurface.new(Transform3D.IDENTITY, -AREA, AREA)
	surface.exclude = [_floor.get_rid()]
	return surface


func manipulation_juice(id: String) -> ArtJuice:
	return juices.get(id)


## Placed boxes stay frozen where they were put (until "상자 떨어뜨리기").
func manipulation_placed(id: String, transform: Transform3D) -> void:
	var body: RigidBody3D = bodies[id]
	body.freeze = true
	body.global_transform = transform
	_changed()


func manipulation_cancelled(_id: String) -> void:
	_changed()


## Only boxes held in place are kept: a box that is falling (or has fallen) starts from its
## start position again, not frozen in mid-air.
func placements() -> Dictionary:
	var result := {}
	for id in bodies:
		if bodies[id].freeze:
			result[id] = bodies[id].global_transform
	return result


## Height of the box's base above the floor (m).
func _base_height(id: String) -> float:
	return maxf(0.0, bodies[id].global_position.y - BOXES[id][0] * 0.5)


func _changed() -> void:
	state_changed.emit()
