## The lever's piece game (2026-10-29 "조각 꺼내기", batch B): the load is a heavy treasure chest
## (the load look's mesh, the same size and mass look as the parcel it replaces) and the star piece
## is stuck in a little pit in the ground under the chest's side of the beam. A stage asks for the
## chest to be lifted with the stage's effort point (MissionTracker: "lifted", the force on the
## beam under the stage's threshold, the 20 kg load, near → mid → far). The beam turns to the lever
## model's one lift angle every time (the chest goes up the same way: LeverLabModel); the progress is
## the piece: each stamp wiggles it a step up out of its pit (it gets a little air while the chest is
## up), and the last stamp pops it out on uniform gravity (LabGame.launch_piece). Visual only: no
## body; the beam, the load and every number are the lever model's as before.
class_name RotationGame
extends LabGame

const CHEST := 0.7                       # the load body's side (RotationLab LOAD_SIZE)
## The piece's place: under the beam's chest side, right of the rest block (x −3.0 … −2.5), in front.
const PIT := Vector3(-2.05, 0.0, 0.22)
const SIZE := PIECE_SIZE * 1.2
## The piece's centre height (in its radii) after 0, 1, 2 stamps: deep in its pit, then rising.
const RISE := [-0.2, 0.25, 0.65]
const RISE_S := 0.45

var _pit: MeshInstance3D
var _from_y := 0.0
var _to_y := 0.0
var _rise_at := -1.0


func build() -> void:
	# The load's look becomes a treasure chest (the same node: the juice and the mass look still scale it).
	var l: Variant = host()
	if l != null and l.load_body != null:
		var visual := l.load_body.get_node_or_null("Visual") as MeshInstance3D
		if visual != null:
			visual.mesh = chest_mesh(Vector3.ONE * CHEST)
			visual.material_override = ArtKit.lit_material()
	var b := ArtKit.builder()
	b.ao_min = 0.6
	b.add_cylinder(Transform3D(Basis(), PIT + Vector3(0.0, 0.006, 0.0)), SIZE * 1.25, SIZE * 1.15, 0.012, 10, Color("6b4423"))
	b.add_cylinder(Transform3D(Basis(), PIT + Vector3(0.0, 0.013, 0.0)), SIZE * 0.95, SIZE * 0.95, 0.004, 10, Color("3a2416"))
	_pit = ArtKit.instance(b.commit())
	_pit.name = "Pit"
	add_child(_pit)
	make_piece(_home(0), SIZE)
	piece.rotation_degrees = Vector3(0.0, 0.0, -20.0)
	_jump(0)


func _home(stamps: int) -> Vector3:
	return PIT + Vector3(0.0, SIZE * RISE[mini(stamps, RISE.size() - 1)], 0.0)


func _cleared(stage_index: int, last: bool) -> void:
	if last:
		piece.rotation = Vector3.ZERO
		launch_piece(Vector3(0.9, 3.0, 1.3), lab_g())
		return
	_from_y = piece.position.y
	_to_y = _home(stage_index + 1).y
	_rise_at = _t
	SoundBoard.play(&"glint")


func _jump(stamps: int) -> void:
	_rise_at = -1.0
	if stamps < stages and piece != null and piece_state != "taken":
		piece.position = _home(stamps)
		piece.rotation_degrees = Vector3(0.0, 0.0, -20.0)
		set_piece_state("held")


func _process(delta: float) -> void:
	super(delta)
	if piece == null or piece_state != "held":
		return
	var y := _home(cleared).y
	if _rise_at >= 0.0:
		var k := (_t - _rise_at) / RISE_S
		y = lerpf(_from_y, _to_y, smooth(k)) + 0.05 * sin(minf(k, 1.0) * PI * 4.0)
		if k >= 1.0:
			_rise_at = -1.0
	# While the chest is up the piece shuffles in its pit (wants out).
	var l: Variant = host()
	if l != null and l.model.lifting():
		y += 0.03 * absf(sin(_t * 9.0))
	piece.position.y = y
