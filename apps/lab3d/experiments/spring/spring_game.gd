## The spring's piece game (2026-10-29 "조각 꺼내기"; reworked the same day, user chose "종 치기"): a
## gold bell hangs over the rod on the squeezed side (towards the post), its pull cord's wooden knob
## in front of the coil at the rod's height. Let go from a pull x₀ the ball swings to −x₀ (the formula
## SpringModel: no damping by default, the first turn at −x₀ e^(−γT/2) with damping) and pushes the
## knob when it gets past the bell's spot: the bell rings at the formula moment the ball's extension
## reaches −d. A stage asks for the bell at d = 0.5, 1 and 1.5 m (MissionRound: the lab's
## `bell_reach` = how far the first swing goes past the rest, as shown, beyond the stage's threshold
## d − 0.05), the last with the heavy ball ("무거운 공도 같은 길이만큼 당기면 종에 닿아요": the swing's
## size does not depend on the mass). The piece hangs in the bell as its clapper; each stamp lights a
## lamp on the bell's post, the last shakes the piece out (LabGame.launch_piece). Visual only: no body;
## the ball and the numbers are SpringModel's as before.
class_name SpringGame
extends LabGame

const POST_Z := -1.75                   # the bell's post behind the rod (clear of the heavy ball and of the cat stepping back)
const KNOB_Z := 0.32                    # the knob's centre in front of the rod (outside the coil, r 0.235)
const KNOB_R := 0.07
const CORD := 1.05                      # m from the bell's mouth down to the knob's centre
const BELL_H := 0.5
const BELL_R := 0.32
const IDLE_BELL := 1.0                  # m: the bell's distance once the round is done
const RING_S := 1.2
const MOVE_S := 0.6                     # the bell moves to the next stage's spot in this long

var _post: Node3D                       # the post, its arm and lamps (moves with the bell's spot)
var _post_mesh: MeshInstance3D
var _bell: Node3D                       # hangs from the arm's end; rocks when rung
var _cord: Node3D                       # from the bell's mouth down to the knob; swings when pushed
var _ring_at := -10.0
var _rang := false                      # the bell rang in this run (once per run)
var rang_time := -1.0                   # the formula clock (s since the release) when it rang (tests)
var _bell_d := 0.5                      # the bell's distance shown now (m from the rest, squeezed side)
var _move_from := 0.5
var _move_at := -10.0


func build() -> void:
	_post = Node3D.new()
	_post.name = "BellPost"
	add_child(_post)
	_post_mesh = ArtKit.instance(post_mesh(0))
	_post.add_child(_post_mesh)
	_bell = Node3D.new()
	_bell.name = "Bell"
	_post.add_child(_bell)
	var b := ArtKit.builder()
	# A gold bell (a flared cone, its mouth down at the node's origin) on a little crown.
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, BELL_H * 0.5, 0.0)), BELL_R, BELL_R * 0.45, BELL_H, 8, Color("ffc61a"), true, Color("ffe14a"))
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)), BELL_R * 1.08, BELL_R * 1.08, 0.06, 8, Color("e0a400"))
	b.add_sphere(Transform3D(Basis(), Vector3(0.0, BELL_H + 0.07, 0.0)), 0.08, 3, 6, Color("8f5a2c"))
	_bell.add_child(ArtKit.instance(b.commit()))
	_cord = Node3D.new()
	_cord.name = "Cord"
	_bell.add_child(_cord)
	var c := ArtKit.builder()
	c.add_cylinder(Transform3D(Basis(), Vector3(0.0, -CORD * 0.5, 0.0)), 0.018, 0.018, CORD, 6, ArtPalette.WHITE, false)
	c.add_sphere(Transform3D(Basis(), Vector3(0.0, -CORD, 0.0)), KNOB_R, 3, 6, Color("c98d4f"))
	_cord.add_child(ArtKit.instance(c.commit()))
	# The piece is the bell's clapper: just under its mouth.
	make_piece(Vector3.ZERO, PIECE_SIZE * 0.8)
	_bell_d = stage_bell(0)
	_place_bell()
	_jump(0)


static var _post_meshes := {}


## The bell's post (behind the rod) with its arm forward over the rod and `lit` of three lamps on.
static func post_mesh(lit: int) -> Mesh:
	if _post_meshes.has(lit):
		return _post_meshes[lit]
	var b := ArtKit.builder()
	var top := SpringLab_ROD_Y() + CORD + BELL_H + 0.3
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.06, POST_Z)), Vector3(0.5, 0.12, 0.5), 0.03, 1, Color("8f5a2c"))
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, top * 0.5, POST_Z)), Vector3(0.12, top, 0.12), 0.02, 1, Color("c98d4f"), Color("dba56a"))
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, top - 0.06, (POST_Z + KNOB_Z) * 0.5)), Vector3(0.1, 0.1, KNOB_Z - POST_Z + 0.12), 0.02, 1, Color("c98d4f"), Color("dba56a"))
	LabGame.add_lamps(b, Vector3(0.0, 0.2, POST_Z + 0.2), lit, 0.15, 0.06)
	_post_meshes[lit] = b.commit()
	return _post_meshes[lit]


## The rod's height (SpringLab ROD_Y) without a typed reference to the lab script.
static func SpringLab_ROD_Y() -> float:
	return 1.0


## Stage `i`'s bell distance d (m on the squeezed side): its threshold + 0.05 (a shown reach of d
## beats it, d − 0.1 does not).
func stage_bell(i: int) -> float:
	var stages_list: Array = MissionRound.missions(lab.definition.raw).get("stages", []) if lab != null else []
	if i >= 0 and i < stages_list.size():
		return snappedf(float(stages_list[i].get("threshold", IDLE_BELL - 0.05)) + 0.05, 0.01)
	return IDLE_BELL


## The bell's distance now (m): where a swing must reach to ring it.
func bell_distance() -> float:
	return _bell_d


func _spring_lab() -> Variant:
	return host()


## The rest point's x (world) and the ball's look radius now.
func _rest_x() -> float:
	var l: Variant = _spring_lab()
	return float(l.ANCHOR_X + l.REST_LENGTH) if l != null else -1.5


func _ball_r() -> float:
	var l: Variant = _spring_lab()
	return float(l.look_radius()) if l != null else 0.35


## How far from the ball's centre (along x) the knob is when the ball's surface touches it.
func _touch_gap() -> float:
	var r := _ball_r() + KNOB_R
	return sqrt(maxf(r * r - KNOB_Z * KNOB_Z, 0.0))


## The knob's resting x (world) for the bell at `d`: the ball touches it when its centre is at −d.
func knob_x(d: float) -> float:
	return _rest_x() - d - _touch_gap()


func _place_bell() -> void:
	var x := knob_x(_bell_d)
	_post.position = Vector3(x, 0.0, 0.0)
	_bell.position = Vector3(0.0, SpringLab_ROD_Y() + CORD, KNOB_Z)


func _cleared(stage_index: int, last: bool) -> void:
	_post_mesh.mesh = post_mesh(stage_index + 1)
	if last:
		launch_piece(Vector3(0.6, 2.0, 1.4), 9.81)
	else:
		_move_from = _bell_d
		_move_at = _t + RING_S * 0.6   # after it rang: the bell moves on to the next stage's spot
	SoundBoard.play(&"glint")


func _jump(stamps: int) -> void:
	_post_mesh.mesh = post_mesh(mini(stamps, 3))
	_move_at = -10.0
	_bell_d = stage_bell(stamps) if stamps < stages else stage_bell(stages - 1)
	_rang = false
	if stamps < stages and piece != null and piece_state != "held":
		set_piece_state("held")


## A new run (a new pull, 처음으로): the bell may ring again.
func run_reset() -> void:
	super()


## The formula ball is at the bell now: its extension at or past −d, or past the first turn (T/2) of a
## swing that turns at −d or beyond.
func reaches_bell(l: Variant) -> bool:
	if l.model.extension <= -_bell_d + 1e-9:
		return true
	return l.model.time() >= l.model.period() * 0.5 and l.first_swing_reach() >= _bell_d - 1e-9


## The formula ball got to the bell in this run (tests).
func rang() -> bool:
	return _rang


func _process(delta: float) -> void:
	super(delta)
	if _move_at >= 0.0 and _t >= _move_at:
		var k := (_t - _move_at) / MOVE_S
		_bell_d = lerpf(_move_from, stage_bell(stage), smooth(k))
		if k >= 1.0:
			_move_at = -10.0
	_place_bell()
	var l: Variant = _spring_lab()
	var ball_x := INF
	if l != null and l.ball != null:
		ball_x = l.ball.global_position.x
		# The ring: the formula ball got to −d in this run (once): its extension crossed −d, or the first
		# swing turns exactly there (x₀ = d: the turn at T/2 falls between two steps).
		if l.released and l.holding == "" and not _rang and _move_at < 0.0 and reaches_bell(l):
			_rang = true
			rang_time = l.model.time()
			_ring_at = _t
			SoundBoard.play(&"glint")
		if not l.released or l.holding != "":
			_rang = false
	# The cord: pushed by the ball's surface past the knob's resting spot, it swings away (−x).
	var rest_knob := knob_x(_bell_d)
	var want := minf(rest_knob, ball_x - _touch_gap()) if is_finite(ball_x) else rest_knob
	_cord.rotation.z = asin(clampf((want - rest_knob) / CORD, -0.95, 0.0))
	_bell.rotation.z = wobble(_t, _ring_at, 0.35, RING_S)
	if piece != null and piece_state == "held":
		piece.global_position = _bell.global_position + _bell.global_transform.basis.y * (-PIECE_SIZE * 0.55)


## The clue's glow (LabGame.highlight): the bell with the piece in it.
func highlight_spots() -> Array:
	return [{"at": _post.position + _bell.position + Vector3.UP * BELL_H * 0.4, "radius": 0.75}]
