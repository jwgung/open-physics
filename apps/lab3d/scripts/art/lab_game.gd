## The piece game of a lab (2026-10-29 user: "실제 실험을 통해서 조각을 꺼내거나, 받거나 하는 식이면
## 좋겠어 … 게임스럽게 녹여내자"). The round's star piece (StarArt) is in the lab from the start, in or
## behind a game object (a crate on a stump, an ice block, a little house, a clock …). Each stage's
## stamp moves the object a step (a crate tips, the ice cracks, a lamp lights); the last stamp
## releases the piece, which flies or falls on the lab's own uniform gravity (p = p0 + v t − ½ g t² ŷ)
## and waits on the ground until the screen hands it to the bread cat (ExperimentScreen._show_piece).
##
## Visual only, like every prop (art-direction.md section 1): meshes under the experiment, no body,
## no collision, nothing the formulas or the panels read. The objects react to formula results the
## lab already has (a hit time, a landing, the speed at the slide's end) and to the stamps the screen
## hands over (show_stage); the stamp itself is MissionTracker's, judged on the formula values.
class_name LabGame
extends Node3D

const PIECE_SIZE := 0.3                 # the piece's outer radius (m): its face reads from the front view
const PIECE_SPIN := 1.4                 # rad/s the waiting piece turns (a little "find me" sparkle)
const LAND_BOUNCES := 2                 # small hops after it lands (visual only)
const CHEST_WOOD := Color("c98d4f")      # the treasure chests of batch B (chest_mesh)
const CHEST_DARK := Color("8f5a2c")
const CHEST_GOLD := Color("ffc61a")
const LAMP_OFF := Color("6b7a90")
const LAMP_ON := Color("ffe14a")

var lab: Experiment
## The stages of the round (the missions' stage count) and the stamps the screen showed last.
var stages := 3
var cleared := 0
## The stage being played (stages once the round is done).
var stage := 0
## The piece: "held" (in its object), "flying" (released, on the formula fall), "out" (on the
## ground, waiting for the cat), "taken" (handed to the screen or found before).
var piece: Node3D
var piece_size := PIECE_SIZE              # its outer radius (make_piece): it lands on its point
var piece_state := "held"
var ground_y := 0.0
var _t := 0.0
var _fly_from := Vector3.ZERO
var _fly_v := Vector3.ZERO
var _fly_g := 9.81
var _fly_t := 0.0
var _hops := 0
var _rest_at := Vector3.ZERO
## The clue's faint glow (2026-10-29 user "해당 포인트를 희미하게 강조"): while Puppy says the lab's
## clue, the object holding the piece glows (ClueGlow, built on the first clue; none in a bench run,
## which has no story). [glow, spot index] pairs following highlight_spots().
var _glows: Array = []
var _highlight := false


func _init(experiment: Experiment = null) -> void:
	lab = experiment
	name = "Game"


## The lab untyped (its own members: g, model, formula_x … are the lab's, not Experiment's).
func host() -> Variant:
	return lab


## The lab's uniform gravity g (m/s²) when it has one, else the earth's.
func lab_g() -> float:
	var l: Variant = lab
	return float(l.g) if l != null and "g" in l else 9.81


## Builds the object and the piece (subclasses; called once from the lab's _build_world).
func build() -> void:
	pass


## The piece in its object: a cute star of PIECE_SIZE (or `size`) at `at` (local to the game).
func make_piece(at: Vector3, size := PIECE_SIZE) -> Node3D:
	piece = StarArt.make(true, size)
	piece_size = size
	piece.name = "Piece"
	piece.position = at
	add_child(piece)
	return piece


## The screen's stamps (ExperimentScreen._setup_game, _mission_progress): `stage_now` is the stage
## being played (-1 when the round is done), `stamps` the stamps so far. `just_cleared`: this stamp
## was earned now, the object reacts (and the last one releases the piece); otherwise the object
## jumps to the state after `stamps` (a re-entered spot, a finished round: no piece any more).
func show_stage(stage_now: int, stamps: int, just_cleared: bool) -> void:
	var before := cleared
	cleared = stamps
	stage = stage_now if stage_now >= 0 else stages
	if just_cleared and stamps > before:
		_cleared(stamps - 1, stamps >= stages)
	else:
		_jump(stamps)
		if stamps >= stages:
			set_piece_state("taken")


## A stage was cleared now (subclasses: the object's reaction; `last`: release the piece).
func _cleared(_stage_index: int, _last: bool) -> void:
	pass


## The object as it is after `stamps` stamps, without animation (subclasses).
func _jump(_stamps: int) -> void:
	pass


## The lab's run was reset (a new attempt): the object goes back to the state of the stamps so far
## (a reaction that earned no stamp — a wobble, a near miss — is undone).
func run_reset() -> void:
	_jump(cleared)


## The clue is told (true) or its box closed (false): the game object faintly glows and pulses
## while on, and fades out after. Visual only.
func highlight(on: bool) -> void:
	if on == _highlight:
		return
	_highlight = on
	if on and _glows.is_empty():
		var spots := highlight_spots()
		for i in spots.size():
			var spot: Dictionary = spots[i]
			var glow := ClueGlow.ring(float(spot.radius)) if spot.get("flat", false) else ClueGlow.halo(float(spot.radius))
			add_child(glow)
			_glows.append(glow)
		_place_glows()
	for glow: ClueGlow in _glows:
		glow.set_on(on)


## Whether the clue's glow shows now (tests: asked on, or still fading out).
func highlighting() -> bool:
	return _glows.any(func(glow: ClueGlow) -> bool: return glow.shown())


## The glow's spots (local to the game): [{at, radius, flat}] — by default a halo of HIGHLIGHT_R at
## the piece in its object (the piece sits inside the crate, the ice, the house …), which moves with
## the object (a chest on a rope, a load on a pulley). Subclasses aim at their object's middle.
func highlight_spots() -> Array:
	if piece == null:
		return []
	return [{"at": to_local(piece.global_position) if piece.is_inside_tree() else piece.position, "radius": highlight_radius()}]


## The halo's radius (m) around the piece by default (subclasses: their object's size).
func highlight_radius() -> float:
	return 0.8


func _place_glows() -> void:
	var spots := highlight_spots()
	for i in mini(spots.size(), _glows.size()):
		var glow: ClueGlow = _glows[i]
		glow.position = spots[i].at + (Vector3.UP * 0.02 if spots[i].get("flat", false) else Vector3.ZERO)


func set_piece_state(state: String) -> void:
	piece_state = state
	if piece != null:
		piece.visible = state != "taken"


## Releases the piece from where it is now with velocity `v` (m/s, world axes) on uniform gravity
## `g` (the lab's own: the moon's piece falls slowly) down to `ground` (the floor height of the
## piece's centre minus its radius). Its path is the formula's: p(t) = p0 + v t − ½ g t² ŷ.
func launch_piece(v: Vector3, g: float, ground := 0.0) -> void:
	if piece == null or piece_state != "held":
		return
	_fly_from = piece.global_position
	_fly_v = v
	_fly_g = maxf(g, 0.5)   # a zero-gravity lab still lets its piece down (slowly)
	_fly_t = 0.0
	_hops = 0
	ground_y = ground
	piece_state = "flying"
	SoundBoard.play(&"glint")


## Where the released piece is `t` seconds after its launch (the uniform-gravity formula).
static func fly_point(from: Vector3, v: Vector3, g: float, t: float) -> Vector3:
	return from + v * t + Vector3.DOWN * 0.5 * g * t * t


## The screen takes the piece for the bread cat: its world position now (it hides here), or null
## when there is no piece to take (none in this lab, or already taken).
func take_piece() -> Variant:
	if piece == null or piece_state == "taken":
		return null
	var at := piece.global_position
	set_piece_state("taken")
	return at


func _process(delta: float) -> void:
	_t += delta
	if not _glows.is_empty() and (_glows[0] as ClueGlow).visible:
		_place_glows()
	if piece == null or not piece.visible:
		return
	match piece_state:
		"held":
			piece.rotation.y = sin(_t * PIECE_SPIN) * 0.5
		"flying":
			_fly_t += delta
			var p := fly_point(_fly_from, _fly_v, _fly_g, _fly_t)
			var rest := ground_y + piece_size
			if p.y <= rest and _fly_t > 0.0 and fly_velocity_y() <= 0.0:
				p.y = rest
				if _hops < LAND_BOUNCES:   # a small hop on the ground (the same fall, smaller)
					_hops += 1
					_fly_from = p
					_fly_v = Vector3(_fly_v.x * 0.4, absf(fly_velocity_y()) * 0.3, _fly_v.z * 0.4)
					_fly_t = 0.0
				else:
					piece_state = "out"
					_rest_at = p
			piece.global_position = p
			piece.rotation.y += delta * 6.0
		"out":
			piece.global_position = _rest_at + Vector3.UP * 0.05 * absf(sin(_t * 3.0))
			piece.rotation.y = sin(_t * PIECE_SPIN) * 0.6


func fly_velocity_y() -> float:
	return _fly_v.y - _fly_g * _fly_t


# --- small shared pieces of the objects ------------------------------------------------------------

## A tween-free wobble value: a decaying shake `amount` rad over `duration` s since `since`.
static func wobble(now: float, since: float, amount: float, duration := 0.6) -> float:
	var k := now - since
	if since < 0.0 or k < 0.0 or k > duration:
		return 0.0
	return amount * sin(k * 28.0) * (1.0 - k / duration)


## smoothstep 0..1 of `k`.
static func smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## A treasure chest of outer `size` (centred at the origin; batch B, 2026-10-29): a wooden box with
## a darker lid band, two gold straps and a gold lock. `lid`: false leaves the lid off (a separate
## hinged node, chest_lid_mesh). `window`: a dark barred window in the front (the piece shows
## through it; the bars are the door, a separate node).
static func chest_mesh(size: Vector3, lid := true, window := false) -> Mesh:
	var b := ArtKit.builder()
	var body_h := size.y * 0.7
	b.ao_height = size.y
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -size.y * 0.5 + body_h * 0.5, 0.0)), Vector3(size.x, body_h, size.z), 0.03, 1, CHEST_WOOD, CHEST_WOOD.lightened(0.12))
	if lid:
		b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -size.y * 0.5 + body_h + (size.y - body_h) * 0.5, 0.0)), Vector3(size.x * 1.02, size.y - body_h, size.z * 1.02), 0.04, 1, CHEST_DARK, CHEST_DARK.lightened(0.15))
	b.ao_min = 1.0
	var strap_h := size.y if lid else body_h
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * size.x * 0.32, -size.y * 0.5 + strap_h * 0.5, 0.0)), Vector3(size.x * 0.08, strap_h + 0.01, size.z + 0.02), 0.01, 1, CHEST_GOLD, CHEST_GOLD.lightened(0.2))
	if window:
		b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -size.y * 0.5 + body_h * 0.5, size.z * 0.5 + 0.004)), Vector3(size.x * 0.5, body_h * 0.62, 0.01), 0.0, 1, Color("3a2416"))
	else:
		b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -size.y * 0.5 + body_h - 0.02, size.z * 0.5 + 0.02)), Vector3(size.x * 0.14, size.y * 0.16, 0.04), 0.01, 1, CHEST_GOLD, CHEST_GOLD.lightened(0.2))
	return b.commit()


## The chest's lid alone (`size`: the chest's outer size), hinged at its back bottom edge: the origin
## is the hinge, the lid lies forward (+z) and up from it.
static func chest_lid_mesh(size: Vector3) -> Mesh:
	var b := ArtKit.builder()
	var h := size.y * 0.3
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, h * 0.5, size.z * 0.5)), Vector3(size.x * 1.02, h, size.z * 1.02), 0.04, 1, CHEST_DARK, CHEST_DARK.lightened(0.15))
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, h * 0.3, size.z * 1.02 + 0.015)), Vector3(size.x * 0.14, h * 0.8, 0.04), 0.01, 1, CHEST_GOLD, CHEST_GOLD.lightened(0.2))
	return b.commit()


## Three lamps in a row (off / lit), the batch-A house's and clock's colours.
static func add_lamps(b: ArtMeshBuilder, at: Vector3, lit: int, spacing := 0.22, radius := 0.075) -> void:
	b.ao_min = 1.0
	for i in 3:
		b.add_sphere(Transform3D(Basis(), at + Vector3((i - 1) * spacing, 0.0, 0.0)), radius, 3, 6, LAMP_ON if i < lit else LAMP_OFF)
