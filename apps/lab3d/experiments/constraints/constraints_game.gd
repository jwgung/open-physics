## The pendulum's piece game (2026-10-29 "조각 꺼내기", batch B; the spring's metronome, slower:
## "거북이 박자"): a turtle clock stands behind the two stands, a little pendulum on its back ticking
## the stage's slow beat (MissionRound: the stage's threshold, the beat in seconds); the star piece
## waits in the barred porch on the front of its shell. A stage asks for the string bob's swing to
## match the beat (the half swing x 2 of the formula model, as shown, within the stage's tolerance:
## the earth's long rope 3.2 s, the Moon's short rope 6.3 s, the Moon's very long rope 8.8 s). During a
## run the clock's pendulum starts with the bob on the bob's side (both let go at their far end), so
## a matching swing goes along with it. A stamp lights a lamp; the last one opens the porch and the
## piece hops out on the lab's own gravity (LabGame.launch_piece: on the Moon it floats down slowly).
## Visual only: no body; the bobs and the numbers are PendulumLabModel's as before.
class_name ConstraintsGame
extends LabGame

const AT := Vector3(3.3, 0.0, -2.6)          # right of the rod's stand, behind it: clear of the bread cat's crates (middle) and Dugi
const SHELL := Vector3(0.95, 0.72, 0.8)  # the shell's radii (x, up, z): a squashed half sphere
const SHELL_Y := 0.32                    # the shell's rim (its legs below)
const PORCH := Vector3(0.56, 0.5, 0.42)  # the barred porch on the shell's front (w, h, d)
const PORCH_Y := 0.34
const ARCH_Y := 1.9                      # the clock's pendulum pivot on the arch over the shell
const ARM := 0.62
const SWING := 0.4                       # rad, the clock pendulum's swing to each side
const IDLE_BEAT := 6.3                   # s, the beat once the round is done
const DOOR_S := 0.5
const SHELL_GREEN := Color("3fae5a")
const SHELL_TOP := Color("63c977")
const SKIN := Color("a8d878")

var _clock: Node3D
var _arm: Node3D
var _door: Node3D
var _body: MeshInstance3D
var _door_open_at := -1.0
var _phase := 0.0
var _ring_at := -10.0
static var _body_meshes := {}


func build() -> void:
	_clock = Node3D.new()
	_clock.name = "TurtleClock"
	_clock.position = AT
	add_child(_clock)
	_body = ArtKit.instance(body_mesh(0))
	_body.name = "Body"
	_clock.add_child(_body)
	_arm = Node3D.new()
	_arm.name = "Arm"
	_arm.position = Vector3(0.0, ARCH_Y, 0.12)
	_clock.add_child(_arm)
	var a := ArtKit.builder()
	a.ao_min = 1.0
	a.add_cylinder(Transform3D(Basis(), Vector3(0.0, -ARM * 0.5, 0.0)), 0.025, 0.025, ARM, 6, ArtPalette.STEEL)
	a.add_sphere(Transform3D(Basis(), Vector3(0.0, -ARM, 0.0)), 0.12, 3, 8, ArtPalette.YELLOW)
	_arm.add_child(ArtKit.instance(a.commit()))
	# The porch's barred door (hinged on its left), the piece behind it.
	_door = Node3D.new()
	_door.name = "Door"
	_door.position = Vector3(-PORCH.x * 0.5, PORCH_Y, _porch_front() + 0.02)
	_clock.add_child(_door)
	var d := ArtKit.builder()
	d.ao_min = 1.0
	for y in [0.0, PORCH.y]:
		d.add_rounded_box(Transform3D(Basis(), Vector3(PORCH.x * 0.5, y, 0.0)), Vector3(PORCH.x, 0.05, 0.04), 0.01, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	for k in 4:
		d.add_cylinder(Transform3D(Basis(), Vector3(PORCH.x * (k + 0.5) / 4.0, PORCH.y * 0.5, 0.0)), 0.02, 0.02, PORCH.y, 6, ArtPalette.YELLOW, false)
	_door.add_child(ArtKit.instance(d.commit()))
	make_piece(_piece_home(), PIECE_SIZE * 0.75)
	_jump(0)


static func _porch_front() -> float:
	return SHELL.z * 0.82 + PORCH.z * 0.5


func _piece_home() -> Vector3:
	return AT + Vector3(0.0, PORCH_Y + PORCH.y * 0.5, _porch_front() - PORCH.z * 0.5)


## The turtle clock with `lit` of its three lamps on (cached per count): legs, the shell (a squashed
## half sphere on its rim), the head looking right, the porch box on the shell's front and the arch
## over the shell that holds the clock's pendulum, the lamps on the arch.
static func body_mesh(lit: int) -> Mesh:
	if _body_meshes.has(lit):
		return _body_meshes[lit]
	var b := ArtKit.builder()
	b.ao_height = 0.4
	for lx in [-0.55, 0.55]:
		for lz in [-0.45, 0.45]:
			b.add_cylinder(Transform3D(Basis(), Vector3(lx, SHELL_Y * 0.5, lz)), 0.17, 0.15, SHELL_Y, 8, SKIN)
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, SHELL_Y - 0.02, 0.0)), SHELL.x * 0.98, SHELL.x * 0.98, 0.08, 12, Color("d9c27a"))
	# The shell: a sphere scaled to SHELL, its lower half inside the belly plate.
	b.ao_min = 0.9
	b.add_sphere(Transform3D(Basis.from_scale(SHELL), Vector3(0.0, SHELL_Y, 0.0)), 1.0, 6, 12, SHELL_GREEN)
	for k in 5:
		var ang := TAU * k / 5.0
		b.add_sphere(Transform3D(Basis.from_scale(Vector3(0.22, 0.08, 0.22)), Vector3(cos(ang) * 0.42, SHELL_Y + 0.6, sin(ang) * 0.36)), 1.0, 3, 6, SHELL_TOP)
	# The head on the right, two eyes.
	b.add_sphere(Transform3D(Basis(), Vector3(SHELL.x + 0.22, SHELL_Y + 0.3, 0.0)), 0.26, 4, 8, SKIN)
	b.ao_min = 1.0
	for ez in [-0.11, 0.11]:
		b.add_sphere(Transform3D(Basis(), Vector3(SHELL.x + 0.38, SHELL_Y + 0.38, ez)), 0.06, 3, 6, ArtPalette.INK)
	# The porch: a small wooden box on the shell's front (its open front is the barred door).
	var pz := _porch_front() - PORCH.z * 0.5
	b.ao_min = 0.85
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, PORCH_Y - 0.03, pz)), Vector3(PORCH.x + 0.1, 0.06, PORCH.z), 0.02, 1, CHEST_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, PORCH_Y + PORCH.y + 0.04, pz)), Vector3(PORCH.x + 0.14, 0.08, PORCH.z + 0.04), 0.02, 1, ArtPalette.RED, ArtPalette.RED_TOP)
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (PORCH.x * 0.5 + 0.03), PORCH_Y + PORCH.y * 0.5, pz)), Vector3(0.06, PORCH.y, PORCH.z), 0.01, 1, CHEST_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, PORCH_Y + PORCH.y * 0.5, pz - PORCH.z * 0.5 + 0.02)), Vector3(PORCH.x, PORCH.y, 0.04), 0.0, 1, Color("3a2416"))
	# The arch over the shell (two wooden posts and a bar) holding the pendulum's pin.
	b.ao_min = 0.9
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * 0.5, (SHELL_Y + 0.55 + ARCH_Y + 0.1) * 0.5, 0.0)), Vector3(0.1, ARCH_Y + 0.1 - SHELL_Y - 0.55, 0.1), 0.02, 1, CHEST_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, ARCH_Y + 0.12, 0.0)), Vector3(1.2, 0.14, 0.16), 0.03, 1, Color("c98d4f"), Color("dba56a"))
	b.add_sphere(Transform3D(Basis(), Vector3(0.0, ARCH_Y, 0.1)), 0.05, 3, 6, ArtPalette.WHITE)
	add_lamps(b, Vector3(0.0, ARCH_Y + 0.27, 0.0), lit, 0.26, 0.08)
	_body_meshes[lit] = b.commit()
	return _body_meshes[lit]


## The stage's beat (s): its threshold, the period a matching swing has (MissionRound "near").
func beat() -> float:
	var stages_list: Array = MissionRound.missions(lab.definition.raw).get("stages", []) if lab != null else []
	if stage < stages_list.size():
		return float(stages_list[stage].get("threshold", IDLE_BEAT))
	return IDLE_BEAT


func _cleared(stage_index: int, last: bool) -> void:
	_body.mesh = body_mesh(stage_index + 1)
	_ring_at = _t
	if last:
		_door_open_at = _t
		launch_piece(Vector3(0.4, 2.0, 1.6), lab_g())
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
	var side := 1.0
	var swing_lab: Variant = host()
	if swing_lab != null and swing_lab.released and swing_lab.holding == "" and swing_lab.g > 0.0:
		# The clock's pendulum starts at the string bob's side with it: in step when they match.
		var m: PendulumLabModel = swing_lab.models[0]
		side = signf(m.start_angle) if m.start_angle != 0.0 else 1.0
		_phase = fmod(m.time() / period, 1.0)
	else:
		_phase = fmod(_phase + delta / period, 1.0)
	_arm.rotation.z = SWING * side * cos(TAU * _phase) + wobble(_t, _ring_at, 0.1, 0.5)
	if _door_open_at >= 0.0:
		_door.rotation.y = -PI * 0.6 * smooth((_t - _door_open_at) / DOOR_S)


## The clue's glow (LabGame.highlight): the turtle clock (its shell and the arch over it).
func highlight_spots() -> Array:
	return [{"at": AT + Vector3(0.0, ARCH_Y * 0.45, 0.0), "radius": 1.3}]
