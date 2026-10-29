## The buoyancy's piece game (2026-10-29 "조각 꺼내기", batch B): a small treasure chest is tied by a
## short rope to the drum's side and hangs under the water beside it; the star piece peeks out under
## its lid. The drum moves as BuoyancyModel says and the chest only follows it (it hangs ROPE below
## the drum's bottom, and lies on the tank floor when the drum is that low). A stage asks for the
## drum with the chest to float (MissionTracker: "floating", the stage's mass and volume: the mass
## is the drum's and the chest's together, the stage's words). A stamp opens the lid a notch; the
## last one throws it open and the piece jumps out of the water onto the grass on uniform gravity
## (LabGame.launch_piece).
## Visual only: the chest has no body, no mass and no volume in the model (the drum's mass slider is
## the whole load; the chest's own water is not counted, the user's design: "the chest is a visual
## hanging below following the drum"); the drum and every number are the model's as before.
class_name BuoyancyGame
extends LabGame

const CHEST := Vector3(0.4, 0.3, 0.3)
const ROPE := 0.5                        # m from the drum's bottom down to the chest's lid
const GAP := 0.06                        # m between the drum's side and the chest
## The lid's angle (deg) after 0, 1, 2 stamps; the last stamp throws it open.
const LID_DEG := [22.0, 42.0, 62.0]
const LID_OPEN := 115.0
const LID_S := 0.45
const FLOOR_Y := 0.2                     # the tank floor (BuoyancyLab FLOOR_Y)

var _chest: Node3D
var _lid: Node3D
var _rope: MeshInstance3D
var _lid_from := 0.0
var _lid_to := 0.0
var _lid_at := -1.0


func build() -> void:
	_chest = Node3D.new()
	_chest.name = "Chest"
	add_child(_chest)
	var body := ArtKit.instance(chest_mesh(CHEST, false))
	body.name = "Body"
	_chest.add_child(body)
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(0.0, -CHEST.y * 0.5 + CHEST.y * 0.7, -CHEST.z * 0.5)
	_chest.add_child(_lid)
	_lid.add_child(ArtKit.instance(chest_lid_mesh(CHEST)))
	_rope = ArtKit.instance(ArtKit.link_mesh(0.02, Color("e8dcc0")))
	_rope.name = "Rope"
	add_child(_rope)
	make_piece(Vector3.ZERO, PIECE_SIZE * 0.55)
	_jump(0)
	_follow()


## The chest's centre now: beside the drum, ROPE under its bottom, not under the tank floor.
func chest_centre() -> Vector3:
	var l: Variant = host()
	if l == null or l.drum == null:
		return Vector3(0.6, FLOOR_Y + CHEST.y * 0.5, 0.0)
	var at: Vector3 = l.drum.global_position
	var bottom: float = at.y - l.drum_height() * 0.5
	var x: float = at.x + l.drum_radius() + GAP + CHEST.x * 0.5
	return Vector3(x, maxf(FLOOR_Y + CHEST.y * 0.5, bottom - ROPE - CHEST.y * 0.5), at.z + 0.1)


func _follow() -> void:
	var c := chest_centre()
	_chest.global_position = c
	var l: Variant = host()
	if l != null and l.drum != null:
		var at: Vector3 = l.drum.global_position
		var hook := Vector3(at.x + l.drum_radius() * 0.9, at.y - l.drum_height() * 0.5 + 0.06, at.z + 0.1)
		ArtKit.stretch_link(_rope, hook, c + Vector3(0.0, CHEST.y * 0.5, 0.0))
	if piece != null and piece_state == "held":
		piece.global_position = c + Vector3(0.0, CHEST.y * 0.5 - 0.02, 0.03)


func _cleared(stage_index: int, last: bool) -> void:
	_lid_from = _lid.rotation_degrees.x
	_lid_to = -LID_OPEN if last else -float(LID_DEG[mini(stage_index + 1, LID_DEG.size() - 1)])
	_lid_at = _t
	if last:
		launch_piece(Vector3(1.6, 6.2, 0.6), lab_g())
	SoundBoard.play(&"glint")


func _jump(stamps: int) -> void:
	_lid_at = -1.0
	_lid.rotation_degrees.x = -LID_OPEN if stamps >= stages else -float(LID_DEG[mini(stamps, LID_DEG.size() - 1)])
	if stamps < stages and piece != null and piece_state != "taken":
		set_piece_state("held")
	_follow()


func _process(delta: float) -> void:
	super(delta)
	_follow()
	if _lid_at >= 0.0:
		var k := (_t - _lid_at) / LID_S
		_lid.rotation_degrees.x = lerpf(_lid_from, _lid_to, smooth(k))
		if k >= 1.0:
			_lid_at = -1.0


## The clue's glow (LabGame.highlight): a halo on the sunk chest (the piece under its lid), following the drum.
func highlight_radius() -> float:
	return 0.5
