## The pulley's piece game (2026-10-29 "조각 꺼내기", batch B): the load is a treasure chest (the load
## look's mesh, the same size and mass look as the parcel it replaces) with the star piece behind a
## barred window in its front, and a shelf with three lamps stands on the gantry's left post at the
## height the chest reaches at the top (PulleyLab MAX_LIFT). A stage asks for the chest to be pulled
## up to the shelf with the stage's strands (MissionRound: the state "top", the required force
## F = m g / n under the stage's threshold: 1 → 2 → 4 strands, the 20 kg load). The chest goes where
## the pulley model puts it (lift = rope pulled / n); a stamp lights a lamp, the last one swings the
## window's bars open and the piece hops out onto the shelf's side and down on uniform gravity
## (LabGame.launch_piece). Visual only: no body; the load and every number are the model's as before.
class_name PulleyGame
extends LabGame

const CHEST := 0.8                       # the load body's side (PulleyLab LOAD_SIZE)
const WINDOW := Vector2(0.4, 0.34)       # the barred window in the chest's front (w, h)
const SHELF_W := 0.78
const SHELF_D := 0.7
const DOOR_S := 0.5

var shelf_x := -1.85                     # the shelf's middle: between the left post (x −2.4) and the chest (x −1.4 … −0.6)
var shelf_y := 2.4                       # its top: the chest's bottom at the top
var _shelf: MeshInstance3D
var _door: Node3D
var _lit := -1
var _door_open_at := -1.0
var _ring_at := -10.0
static var _shelf_meshes := {}


func build() -> void:
	var l: Variant = host()
	var visual := l.load_body.get_node_or_null("Visual") as MeshInstance3D if l != null and l.load_body != null else null
	if visual != null:
		visual.mesh = chest_mesh(Vector3.ONE * CHEST, true, true)
		visual.material_override = ArtKit.lit_material()
	_shelf = MeshInstance3D.new()
	_shelf.name = "Shelf"
	_shelf.material_override = ArtKit.lit_material()
	_shelf.position = Vector3(shelf_x, shelf_y, 0.0)
	add_child(_shelf)
	# The window's bars: hinged on the window's left, a child of the chest's look (it rides and scales with it).
	_door = Node3D.new()
	_door.name = "Bars"
	if visual != null:
		visual.add_child(_door)
	else:
		add_child(_door)
	_door.position = Vector3(-WINDOW.x * 0.5, -CHEST * 0.5 + CHEST * 0.35 - WINDOW.y * 0.5, CHEST * 0.5 + 0.03)
	var d := ArtKit.builder()
	d.ao_min = 1.0
	for y in [0.0, WINDOW.y]:
		d.add_rounded_box(Transform3D(Basis(), Vector3(WINDOW.x * 0.5, y, 0.0)), Vector3(WINDOW.x, 0.04, 0.03), 0.01, 1, CHEST_GOLD, CHEST_GOLD.lightened(0.2))
	for k in 4:
		d.add_cylinder(Transform3D(Basis(), Vector3(WINDOW.x * (k + 0.5) / 4.0, WINDOW.y * 0.5, 0.0)), 0.018, 0.018, WINDOW.y, 6, CHEST_GOLD, false)
	_door.add_child(ArtKit.instance(d.commit()))
	make_piece(Vector3.ZERO, PIECE_SIZE * 0.6)
	_jump(0)


## The shelf on the post with `lit` of its three lamps on (cached per count): a plank on two
## brackets, the lamps along its front edge.
static func shelf_mesh(lit: int) -> Mesh:
	if _shelf_meshes.has(lit):
		return _shelf_meshes[lit]
	var b := ArtKit.builder()
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -0.05, 0.0)), Vector3(SHELF_W, 0.1, SHELF_D), 0.02, 1, CHEST_DARK, Color("a86b38"))
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(-SHELF_W * 0.5 + 0.06, -0.3, side * SHELF_D * 0.3)), Vector3(0.08, 0.4, 0.06), 0.01, 1, CHEST_DARK)
	add_lamps(b, Vector3(0.0, 0.06, SHELF_D * 0.5 - 0.08), lit, 0.24, 0.07)
	_shelf_meshes[lit] = b.commit()
	return _shelf_meshes[lit]


## The piece behind the window, where the chest's look is now (world).
func _piece_home() -> Vector3:
	var l: Variant = host()
	if l == null or l.load_body == null:
		return Vector3.ZERO
	var centre: Vector3 = l.props.look_centre(l.load_body)
	var k: float = l.props.look
	return centre + Vector3(0.0, (-CHEST * 0.5 + CHEST * 0.35) * k, (CHEST * 0.5 - 0.12) * k)


func _cleared(stage_index: int, last: bool) -> void:
	_set_lamps(stage_index + 1)
	_ring_at = _t
	if last:
		_door_open_at = _t
		piece.global_position = _piece_home()
		launch_piece(Vector3(0.7, 2.4, 1.5), lab_g())
	SoundBoard.play(&"glint")


func _set_lamps(lit: int) -> void:
	if lit != _lit:
		_lit = lit
		_shelf.mesh = shelf_mesh(lit)


func _jump(stamps: int) -> void:
	_set_lamps(mini(stamps, 3))
	_door_open_at = -1.0
	_door.rotation.y = -PI * 0.6 if stamps >= stages else 0.0
	if stamps < stages and piece != null and piece_state != "held":
		set_piece_state("held")


func _process(delta: float) -> void:
	super(delta)
	if piece != null and piece_state == "held":
		piece.global_position = _piece_home()
	if _door_open_at >= 0.0:
		_door.rotation.y = -PI * 0.6 * smooth((_t - _door_open_at) / DOOR_S)
	elif _shelf != null:
		_shelf.position.y = shelf_y + absf(wobble(_t, _ring_at, 0.03, 0.4))


## The clue's glow (LabGame.highlight): a halo on the chest (the piece behind its window), following the load.
func highlight_radius() -> float:
	return 0.75
