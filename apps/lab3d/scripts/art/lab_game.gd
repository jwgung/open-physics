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
