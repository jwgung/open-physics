## The push's piece game (2026-10-29 "조각 꺼내기"; reworked the same day, user: "상자가 별을 막고 있어서,
## 이걸 치우면 별에 도달하는 길이 열리는 거로"): a dirt path crosses the track at the box's start and
## runs back-left to the star piece on a stump; the box sits on the path and blocks it, three little
## gates stand on its last leg. A stage asks for the light, the normal and the heavy box to be pushed
## off the path (MissionTracker: the formula distance from the start past the stage's threshold,
## PushFrictionModel; the box's mass). Each stamp swings one gate open; after the last the bread cat
## walks the opened path to the piece (once the box is at rest) and the screen hands it the piece
## there (piece_ready). Visual only: the path, the gates and the piece are pictures (no body); the
## box, its push and the numbers are the lab's as before. The cat only walks once the round is done.
class_name FrictionGame
extends LabGame

const START_X := -3.0                    # the box's start (FrictionLab START_X): the path crosses here
## The path (a polyline on the floor): from behind the track, through the box's start (the box sits on
## it), front-left off the track, then straight towards the camera to the piece. The last leg's gates
## face the camera, left of the box and near it (2026-10-29 device check: a path behind the box was
## hidden by it, or too small to read, in the front view).
const POINTS := [Vector3(-3.0, 0.0, -1.8), Vector3(-3.0, 0.0, 0.0), Vector3(-4.4, 0.0, 1.15), Vector3(-4.4, 0.0, 4.6)]
const PATH_WIDTH := 0.9
const TRACK_HALF_W := 0.8                # FrictionProps.TRACK_WIDTH / 2: the path is drawn off the track
const GATES := [0.6, 1.3, 2.0]           # m along the last leg: the gates, nearest the box first
const GATE_W := 0.86
const GATE_H := 0.95
const STUMP_AT := 2.7                    # m along the last leg: the stump with the piece
const STUMP_H := 0.45
const CAT_STOP := 2.15                   # m along the last leg where the walking cat stops (before the stump)
const OPEN_S := 0.5
const OPEN_DEG := 90.0
const WALK_SPEED := 2.2                  # m/s
const WALK_HOP := 0.09
const WALK_STEP := 0.32                  # m per hop
const SIZE := PIECE_SIZE * 1.15

var _doors: Array[Node3D] = []           # per gate its hinge node (the gate swings up about the path)
var _open_at: Array[float] = [-1.0, -1.0, -1.0]
## The cat's walk after the last stamp: "" (none), "pending" (waits for the box to rest), "walking",
## "there" (at the piece).
var walk_state := ""
var _walk_points: Array[Vector3] = []
var _walk_d := 0.0
var _walk_after := 0.0                   # _t when the walk may start (the last gate opened)


## The last leg's direction (towards the camera).
static func path_dir() -> Vector3:
	return (POINTS[3] - POINTS[2]).normalized()


## The point `s` m along the last leg from its corner (on the floor).
static func path_point(s: float) -> Vector3:
	return POINTS[2] + path_dir() * s


## A strip of the path from `a` to `e` (on the floor).
static func _strip(b: ArtMeshBuilder, a: Vector3, e: Vector3, colour: Color) -> void:
	var d := e - a
	b.add_rounded_box(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), (a + e) * 0.5 + Vector3.UP * 0.012), Vector3(PATH_WIDTH, 0.024, d.length()), 0.01, 1, colour, colour.lightened(0.12))


## The point where the segment a -> e crosses z = `z` (a, e on either side of it).
static func _at_z(a: Vector3, e: Vector3, z: float) -> Vector3:
	return a.lerp(e, (z - a.z) / (e.z - a.z))


func build() -> void:
	var u := path_dir()
	var yaw := atan2(u.x, u.z)
	var b := ArtKit.builder()
	# The dirt path, off the track (in front of it and behind it).
	var dirt := Color("b98a5a")
	var p: Array = POINTS
	_strip(b, p[0], _at_z(p[0], p[1], -TRACK_HALF_W - 0.05), dirt)
	_strip(b, _at_z(p[1], p[2], TRACK_HALF_W + 0.05), p[2] + (p[2] - p[1]).normalized() * PATH_WIDTH * 0.3, dirt)
	_strip(b, p[2], path_point(STUMP_AT + 0.45), dirt)
	# The gates' posts (the doors are their own nodes) and the stump.
	var across := Vector3(u.z, 0.0, -u.x)
	for s: float in GATES:
		for side in [-1.0, 1.0]:
			var post: Vector3 = path_point(s) + across * float(side) * (GATE_W * 0.5 + 0.06)
			b.add_rounded_box(Transform3D(Basis(Vector3.UP, yaw), post + Vector3.UP * GATE_H * 0.55), Vector3(0.12, GATE_H * 1.1, 0.12), 0.02, 1, Color("8f5a2c"), Color("a86d3a"))
			b.add_sphere(Transform3D(Basis(), post + Vector3.UP * (GATE_H * 1.1 + 0.06)), 0.08, 3, 6, ArtPalette.YELLOW)
	var stump := path_point(STUMP_AT)
	b.add_cylinder(Transform3D(Basis(), stump + Vector3.UP * STUMP_H * 0.5), 0.3, 0.34, STUMP_H, 8, Color("8f5a2c"), true, Color("dba56a"))
	var ground := ArtKit.instance(b.commit())
	ground.name = "Path"
	add_child(ground)
	# Each gate: a plank gate hinged at the foot of its left post; opened it swings up (about the path's
	# direction) to stand beside the path, so an open gate never reaches the next one.
	var d := ArtKit.builder()
	for k in 3:
		d.add_rounded_box(Transform3D(Basis(), Vector3(GATE_W * (k + 0.5) / 3.0, GATE_H * 0.5, 0.0)), Vector3(GATE_W / 3.0 - 0.03, GATE_H * 0.9, 0.05), 0.015, 1, ArtPalette.ORANGE, ArtPalette.ORANGE.lightened(0.2))
	for y in [0.3, 0.75]:
		d.add_rounded_box(Transform3D(Basis(), Vector3(GATE_W * 0.5, GATE_H * y, 0.035)), Vector3(GATE_W, 0.09, 0.03), 0.01, 1, Color("8f5a2c"))
	var door_mesh := d.commit()
	for i in GATES.size():
		var hinge := Node3D.new()
		hinge.name = "Gate%d" % (i + 1)
		hinge.position = path_point(GATES[i]) - across * (GATE_W * 0.5)
		add_child(hinge)
		hinge.add_child(ArtKit.instance(door_mesh))
		_doors.append(hinge)
	make_piece(_piece_home(), SIZE)
	_jump(0)


func _piece_home() -> Vector3:
	return path_point(STUMP_AT) + Vector3.UP * (STUMP_H + SIZE)


## A gate's hinge basis `k` (0 shut .. 1 open) of the way open: shut it stands across the path, open
## it is turned up OPEN_DEG about the path's direction (beside the path, over its left post).
static func door_basis(k: float) -> Basis:
	return Basis(Vector3.UP, atan2(path_dir().x, path_dir().z)) * Basis(Vector3.BACK, deg_to_rad(OPEN_DEG) * smooth(k))


## How far gate `i` is open now (0 shut .. 1 open; tests).
func gate_open(i: int) -> float:
	var up := _doors[i].basis * Vector3.RIGHT
	return clampf(up.y, 0.0, 1.0)


func _cleared(stage_index: int, last: bool) -> void:
	if stage_index >= 0 and stage_index < GATES.size():
		_open_at[stage_index] = _t
	SoundBoard.play(&"glint")
	if last:
		walk_state = "pending"
		_walk_after = _t + OPEN_S


func _jump(stamps: int) -> void:
	for i in GATES.size():
		_open_at[i] = -1.0
		_doors[i].basis = door_basis(1.0 if i < stamps else 0.0)
	walk_state = ""
	if stamps < stages and piece != null and piece_state != "taken":
		piece.position = _piece_home()
		set_piece_state("held")


## The lab's run starts over (a new box, 처음으로): a walk still to come or under way is over (the cat
## goes back to the box), the gates stay as the stamps opened them.
func run_reset() -> void:
	super()


## The cat walks (or will) the opened path: the lab leaves its pose to the game meanwhile.
func cat_busy() -> bool:
	return walk_state != ""


func piece_ready() -> bool:
	return walk_state not in ["pending", "walking"]


func _cat() -> CatActor:
	var push_lab: Variant = host()
	if push_lab == null or not ("props" in push_lab) or push_lab.props == null:
		return null
	return push_lab.props.cat


func _process(delta: float) -> void:
	super(delta)
	for i in GATES.size():
		if _open_at[i] >= 0.0:
			var k := (_t - _open_at[i]) / OPEN_S
			_doors[i].basis = door_basis(k)
			if k >= 1.0:
				_open_at[i] = -1.0
	match walk_state:
		"pending":
			var push_lab: Variant = host()
			var resting: bool = push_lab == null or (not push_lab.push.held and push_lab.status() != "sliding")
			var cat := _cat()
			if cat == null:
				walk_state = "there"
				_rest_at = piece.global_position
				piece_state = "out"
			elif resting and _t >= _walk_after:
				_walk_points = [Vector3(cat.position.x, 0.0, cat.position.z), POINTS[1], POINTS[2], path_point(CAT_STOP)]
				_walk_d = 0.0
				walk_state = "walking"
		"walking":
			_walk_d += delta * WALK_SPEED
			_step_cat()


## The cat at _walk_d along its walk (a polyline), facing where it goes, hopping; at the end it stands
## facing the camera beside the stump.
func _step_cat() -> void:
	var cat := _cat()
	if cat == null:
		walk_state = "there"
		return
	var left := _walk_d
	for i in _walk_points.size() - 1:
		var a: Vector3 = _walk_points[i]
		var e: Vector3 = _walk_points[i + 1]
		var length := a.distance_to(e)
		if left <= length:
			var at := a.lerp(e, left / length) if length > 1e-6 else e
			cat.walk(at, CatActor.facing(a, e), WALK_HOP * absf(sin(PI * _walk_d / WALK_STEP)))
			return
		left -= length
	cat.walk(_walk_points[-1], 0.0, 0.0)
	cat.mode = "free"
	walk_state = "there"
	if piece != null and piece_state == "held":
		_rest_at = piece.global_position   # it waits on its stump for the cat's paws (the screen hands it over)
		piece_state = "out"


## The clue's glow (LabGame.highlight): the piece on its stump and the box on the path.
func highlight_spots() -> Array:
	return [{"at": _piece_home(), "radius": 0.7}]
