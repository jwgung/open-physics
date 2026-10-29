## The throw's piece game (2026-10-29 "조각 꺼내기"): three wooden crates on tree stumps along the
## throw, nearer and lower to farther and higher; the star piece sits on the last, highest crate.
## A stage asks for its crate to be hit (MissionTracker: the stage's "hit_<n>" is 1). The lab knows
## the hit from the formula path alone (hit_time: the ball's centre on x(t) = x0 + vx t,
## y(t) = y0 + vy t − ½ g t², closer than its radius to the crate's box, before the formula landing,
## the fence or the island's edge); the crate tips when the formula clock reaches that time. The
## engine ball flies on through it as it always did (the crates are pictures, not bodies). The last
## crate's tip drops the piece on the same uniform gravity (LabGame.launch_piece).
class_name ProjectileGame
extends LabGame

const CRATE := 0.6                       # m, the crate's side (its box is the target)
## The stages' crates: (centre x, stump height) on the throw's line z = 0. From the launch at x = −6
## (ball bottom 0.5 m): 2.8 m out at 0.5 m, 5.5 m out at 1 m, 7.2 m out at 1.2 m. On the slingshot's
## grid (5°, 0.5 m/s, up to 9 m/s) from the default height 81, 24 and 10 throws hit them, none
## slower than 4.5 m/s (tests/game_piece_checks.gd). The near crate stands off the line between the
## front camera and Puppy (tests/island_cast_checks.gd).
const TARGETS := [Vector2(-3.2, 0.5), Vector2(-0.5, 1.0), Vector2(1.2, 1.2)]
const STUMP_RADIUS := 0.32
const SAMPLE_DT := 1.0 / 1200.0          # s between the path points the hit is looked for at
const TIP_S := 0.55
const CALL_EVERY_S := 2.4                # the crate to hit gives a little shake this often
const WOOD := Color("c98d4f")
const WOOD_DARK := Color("8f5a2c")

var _pivots: Array[Node3D] = []
var _tipped: Array = [false, false, false]
var _tip_since: Array = [-1.0, -1.0, -1.0]


static func target_box(i: int) -> Rect2:
	var t: Vector2 = TARGETS[i]
	return Rect2(t.x - CRATE * 0.5, t.y, CRATE, CRATE)


## The first formula time (s) at which a ball of radius `r`, its centre launched from `c` (x, height)
## with (vx, vy) in gravity `g`, touches crate `i` (the circle meets its box), no later than
## `t_end` (the landing, the fence, the island's edge); INF when it never does. The path is the
## projectile formula's, looked at every SAMPLE_DT (under a centimetre at the slingshot's 9 m/s).
static func hit_time(i: int, c: Vector2, vx: float, vy: float, g: float, r: float, t_end: float) -> float:
	var box := target_box(i)
	if not is_finite(t_end):
		return INF
	var n := ceili(t_end / SAMPLE_DT)
	for k in n + 1:
		var t := minf(k * SAMPLE_DT, t_end)
		var x := c.x + PhysicsLaws.constant_acceleration_displacement(vx, 0.0, t)
		var y := c.y + PhysicsLaws.constant_acceleration_displacement(vy, -g, t)
		var dx := maxf(maxf(box.position.x - x, 0.0), x - box.end.x)
		var dy := maxf(maxf(box.position.y - y, 0.0), y - box.end.y)
		if dx * dx + dy * dy <= r * r:
			return t
	return INF


func build() -> void:
	var stumps := ArtKit.builder()
	for i in TARGETS.size():
		var t: Vector2 = TARGETS[i]
		stumps.add_cylinder(Transform3D(Basis(), Vector3(t.x, t.y * 0.5, 0.0)), STUMP_RADIUS * 1.08, STUMP_RADIUS, t.y, 8, ArtPalette.TRUNK, true, Color("d9a066"))
		var pivot := Node3D.new()
		pivot.name = "Crate%d" % (i + 1)
		add_child(pivot)
		var crate := ArtKit.instance(crate_mesh())
		crate.position = Vector3(-CRATE * 0.5, CRATE * 0.5, 0.0)   # the pivot is the crate's bottom far edge
		pivot.add_child(crate)
		_pivots.append(pivot)
	add_child(ArtKit.instance(stumps.commit()))
	var top: Vector2 = TARGETS[TARGETS.size() - 1]
	make_piece(Vector3(top.x, top.y + CRATE + PIECE_SIZE * 0.95, 0.0))
	_jump(0)


static func crate_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.add_rounded_box(Transform3D(), Vector3.ONE * CRATE, 0.05, 1, WOOD, Color("dba56a"))
	# Dark slats across the front and back faces and an X brace: a toy crate.
	for side in [-1.0, 1.0]:
		for y in [-0.2, 0.0, 0.2]:
			b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, y * CRATE / 0.6, side * (CRATE * 0.5 + 0.012))), Vector3(CRATE * 0.92, 0.05, 0.03), 0.01, 1, WOOD_DARK)
	return b.commit()


## The formula path reached crate `i` (the lab's clock passed its hit time): it tips when it is the
## crate of the stage being played; the last one drops the piece on the lab's gravity `g`.
func hit(i: int, g: float) -> void:
	if i != stage or _tipped[i]:
		return
	_tip(i)
	if i == TARGETS.size() - 1:
		launch_piece(Vector3(1.1, 1.6, 0.0), g)


func _tip(i: int) -> void:
	_tipped[i] = true
	_tip_since[i] = _t
	SoundBoard.play(&"land")


func _cleared(stage_index: int, last: bool) -> void:
	if stage_index >= 0 and stage_index < TARGETS.size() and not _tipped[stage_index]:
		_tip(stage_index)   # (the demo, a lab without throws): the crate goes now
	if last:
		launch_piece(Vector3(1.1, 1.6, 0.0), lab_g())


## Crates of the cleared stages lie on the ground, the others stand on their stumps.
func _jump(stamps: int) -> void:
	for i in TARGETS.size():
		_tipped[i] = i < stamps
		_tip_since[i] = -1.0
		_pose(i, 1.0 if _tipped[i] else 0.0)
	if stamps < TARGETS.size() and piece != null and piece_state != "held":
		var top: Vector2 = TARGETS[TARGETS.size() - 1]
		piece.position = Vector3(top.x, top.y + CRATE + PIECE_SIZE * 0.95, 0.0)
		set_piece_state("held")


## Crate `i` at tip progress `k` (0 standing, 1 lying on the ground past its stump).
func _pose(i: int, k: float) -> void:
	var t: Vector2 = TARGETS[i]
	var e := smooth(k)
	var pivot := _pivots[i]
	pivot.position = Vector3(t.x + CRATE * 0.5 + 0.35 * e, t.y * (1.0 - k * k), 0.0)
	pivot.rotation = Vector3(0.0, 0.0, -PI * 0.5 * e)


func _process(delta: float) -> void:
	super(delta)
	for i in TARGETS.size():
		if _tip_since[i] >= 0.0:
			var k := clampf((_t - _tip_since[i]) / TIP_S, 0.0, 1.0)
			_pose(i, k)
			if k >= 1.0:
				_tip_since[i] = -1.0
		elif not _tipped[i] and i == stage:
			# The crate to hit: a small shake now and then ("me!").
			_pivots[i].rotation.z = wobble(fmod(_t, CALL_EVERY_S), 0.0, 0.06)
