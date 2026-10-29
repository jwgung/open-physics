## The spring's piece game (2026-10-29 "조각 꺼내기"): a toy metronome clock ticks the stage's beat,
## its arm swinging with the stage's period (MissionTracker: the stage's threshold, the beat in
## seconds); the star piece waits behind the barred little door in its face. A stage asks for the
## ball's swing to match the beat (the formula period T = 2π√(m/k), as shown, within the stage's
## tolerance: a light ball the quick 2.8 s beat, a heavy one the slow 4.9 s beat, then the light ball
## again pulled only a little — the beat does not care how far it was pulled). During a run the arm
## starts with the ball (the ball is let go from its far end, the arm from its far side), so a
## matching swing goes with the arm. A stamp lights a lamp; the last opens the door and the piece
## hops out on uniform gravity (LabGame.launch_piece). Visual only: no body; the ball and the
## numbers are SpringModel's as before.
class_name SpringGame
extends LabGame

const AT := Vector3(1.6, 0.0, -2.8)
const BODY_H := 2.0
const BODY_R := Vector2(0.78, 0.4)      # the pyramid's corner radius at its foot and top
const WINDOW_Y := 1.0                   # the barred door's foot: the piece shows over the rod from the front view
const ARM := 1.55
const SWING := 0.42                     # rad, the arm's swing to each side
const IDLE_BEAT := 2.8                  # s, the beat once the round is done
const DOOR_S := 0.5

var _clock: Node3D
var _arm: Node3D
var _door: Node3D
var _body: MeshInstance3D
var _door_open_at := -1.0
var _phase := 0.0                         # the arm's phase (0..1 of a beat) while no run goes
var _ring_at := -10.0


func build() -> void:
	_clock = Node3D.new()
	_clock.name = "Metronome"
	_clock.position = AT
	add_child(_clock)
	_body = ArtKit.instance(body_mesh(0))
	_body.name = "Body"
	_clock.add_child(_body)
	# The arm: a thin rod from its pivot low on the face up, with a weight.
	_arm = Node3D.new()
	_arm.name = "Arm"
	_arm.position = Vector3(0.0, 0.32, _face_z(0.32) + 0.08)
	_clock.add_child(_arm)
	var a := ArtKit.builder()
	a.add_cylinder(Transform3D(Basis(), Vector3(0.0, ARM * 0.5, 0.0)), 0.025, 0.025, ARM, 6, ArtPalette.STEEL)
	a.add_rounded_box(Transform3D(Basis(), Vector3(0.0, ARM * 0.62, 0.0)), Vector3(0.16, 0.12, 0.08), 0.02, 1, ArtPalette.RED, ArtPalette.RED_TOP)
	_arm.add_child(ArtKit.instance(a.commit()))
	# The little barred door low on the face (hinged on its left), the piece behind it.
	_door = Node3D.new()
	_door.name = "Door"
	_door.position = Vector3(-0.27, WINDOW_Y, _face_z(WINDOW_Y + 0.27) + 0.03)
	_clock.add_child(_door)
	var d := ArtKit.builder()
	for y in [0.0, 0.54]:
		d.add_rounded_box(Transform3D(Basis(), Vector3(0.27, y, 0.0)), Vector3(0.54, 0.05, 0.04), 0.01, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	for k in 4:
		d.add_cylinder(Transform3D(Basis(), Vector3(0.54 * (k + 0.5) / 4.0, 0.27, 0.0)), 0.02, 0.02, 0.54, 6, ArtPalette.YELLOW, false)
	_door.add_child(ArtKit.instance(d.commit()))
	make_piece(_piece_home(), PIECE_SIZE * 0.85)
	_jump(0)


func _piece_home() -> Vector3:
	return AT + Vector3(0.0, WINDOW_Y + 0.27, _face_z(WINDOW_Y + 0.27) - 0.06)


## The front face's z (from the clock's middle) at height `y`: the square pyramid turned 45°.
static func _face_z(y: float) -> float:
	var k := clampf((y - 0.16) / BODY_H, 0.0, 1.0)
	return lerpf(BODY_R.x, BODY_R.y, k) * sqrt(0.5)


static var _body_meshes := {}


## The clock's body with `lit` of its three lamps on (cached per count): a wooden pyramid on a
## foot, a cap, the lamps on top.
static func body_mesh(lit: int) -> Mesh:
	if _body_meshes.has(lit):
		return _body_meshes[lit]
	var b := ArtKit.builder()
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.08, 0.0)), Vector3(1.3, 0.16, 1.3), 0.04, 1, Color("8f5a2c"))
	b.add_cylinder(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, 0.16 + BODY_H * 0.5, 0.0)), BODY_R.x, BODY_R.y, BODY_H, 4, Color("c98d4f"), true, Color("dba56a"))
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.16 + BODY_H + 0.05, 0.0)), Vector3(0.6, 0.1, 0.6), 0.03, 1, Color("8f5a2c"))
	b.ao_min = 1.0
	for i in 3:
		b.add_sphere(Transform3D(Basis(), Vector3((i - 1) * 0.2, 0.16 + BODY_H + 0.18, 0.0)), 0.08, 3, 6, LAMP_ON if i < lit else LAMP_OFF)
	_body_meshes[lit] = b.commit()
	return _body_meshes[lit]


## The stage's beat (s): its threshold, the period a matching swing has (MissionTracker "near").
func beat() -> float:
	var stages_list: Array = MissionTracker.missions(lab.definition).get("stages", []) if lab != null else []
	if stage < stages_list.size():
		return float(stages_list[stage].get("threshold", IDLE_BEAT))
	return IDLE_BEAT


func _cleared(stage_index: int, last: bool) -> void:
	_body.mesh = body_mesh(stage_index + 1)
	_ring_at = _t
	if last:
		_door_open_at = _t
		launch_piece(Vector3(0.3, 2.2, 1.4), 9.81)
	SoundBoard.play(&"glint")


func _jump(stamps: int) -> void:
	_body.mesh = body_mesh(mini(stamps, 3))
	_door_open_at = -1.0
	_door.rotation.y = -PI * 0.6 if stamps >= stages else 0.0
	if stamps < stages and piece != null and piece_state != "held":
		piece.position = _piece_home()
		set_piece_state("held")


func _process(delta: float) -> void:
	super(delta)
	var period := beat()
	var spring_lab: Variant = host()
	if spring_lab != null and spring_lab.released and spring_lab.holding == "":
		# The arm starts on its far side with the ball let go from its far end: in step when they match.
		_phase = fmod(spring_lab.model.time() / period, 1.0)
	else:
		_phase = fmod(_phase + delta / period, 1.0)
	_arm.rotation.z = -SWING * cos(TAU * _phase) + wobble(_t, _ring_at, 0.1, 0.5)
	if _door_open_at >= 0.0:
		_door.rotation.y = -PI * 0.6 * smooth((_t - _door_open_at) / DOOR_S)


## The clue's glow (LabGame.highlight): the metronome clock.
func highlight_spots() -> Array:
	return [{"at": AT + Vector3(0.0, BODY_H * 0.6, 0.0), "radius": 1.35}]
