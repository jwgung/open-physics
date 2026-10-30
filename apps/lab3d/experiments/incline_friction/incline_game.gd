## The slide's piece game (2026-10-29 "조각 꺼내기"): three rows of dominoes, small, bigger and the big
## pillar with the star piece on top. A stage asks for the box to get to its row past the slide's end
## (reach_n below): the faster it leaves the end (v = √(2 a d), a = g (sin θ − μk cos θ), d the run
## from the start to the end), the farther it goes, on steel → steeper wood → steepest rubber.
##
## Where the box arrives (2026-10-29 user, twice: "미끄럼틀은 여전히 착지 지점과 도미노의 위치가
## 안맞다"): past the slide's end the box drops on g from the end (fixed 0.3 m over the ground at
## every slope, 2026-10-29), lands on the floor and the floor's friction stops it
## (InclineFriction.arrival(): the formula's projectile and v²/(2μg) on the floor, which the engine
## box follows within 1 cm).
##
## One fixed row per stage (2026-10-29 user: the row that moved to where the box would stop gave the
## answer away before the release): the stage's row stands in the box's lane (z 0) at LANE_FACE (its
## first domino's near face), whatever the material, slope or start. The stage is judged by whether
## the formula's way meets the row (the lab's contact_step() and reach_1–3): the box's square on its
## flight and floor run against the standing dominoes' boxes. So a box can fall short. Where it meets
## the row:
## - the moment the engine box's square reaches a standing domino (touched()) the row's chain starts
##   (each domino NEXT_S after the one before), stamped or not (a setting the stage does not want
##   knocks it over too: it stands again at the next attempt), and the box shoves each domino it
##   reaches so it never sits inside one (push());
## - a box that stops short within NEAR_MISS of the row makes it wobble.
## The other rows wait beside the lane (ROW_Z, past the slide's end, as before), standing or fallen.
## The pillar's fall throws the piece down on uniform gravity (LabGame.launch_piece) on the last
## stamp; knocked over without it, the piece rides on its top. Visual only: the dominoes are pictures
## on the floor (no body), the box and the numbers are the lab's.
class_name InclineGame
extends LabGame

## Per row: [the dominoes' x from the row's start (their far foot edge, the pivot), size (thick, tall,
## wide), colour]. A domino tips onto the next (spacing < its height).
const ROWS := [
	[[0.0, -0.24, -0.48], Vector3(0.11, 0.44, 0.44), Color("ffc61a")],
	[[-1.05, -1.35, -1.65], Vector3(0.14, 0.6, 0.54), Color("2d7cf6")],
	[[-2.5], Vector3(0.22, 1.05, 0.7), Color("ff3b3b")],
]
const GAP := 0.3                         # m from the slide's lower end (x) to a waiting row's start
const ROW_Z := -1.15                     # the waiting rows' middle (z): beside the box's lane, behind it
## Per stage: the world x of its row's first domino's near (+x) face in the lane, fixed (m), 3.8,
## 3.45 and 2.8 m past the slide's lower end (x −2.6, the same at every slope). From the top steeper
## goes farther: steel at 20°/30°/40° gets to −6.4 (20°: 0.14 m past its face; wood 30° stops 0.13 m
## short); wood at 30°/40° to −6.05 (30°: 0.22 m past; rubber 45° 0.24 m short); rubber at 40°/45°
## to −5.4 (40°: 0.26 m past; clay 45° 0.28 m short). README "고정 도미노 줄".
const LANE_FACE := [-6.4, -6.05, -5.4]
const NEAR_MISS := 0.5                   # m: a box stopping this close short of the row makes it wobble
const FALL_S := 0.35
const NEXT_S := 0.12                     # the next domino starts falling this long after the one before
const TOUCH_KEEP_S := 0.5                # a stamp this soon after the box's touch starts the chain at it
const STOP_SPEED := 0.05                 # m/s: the braked box has stopped (settled, the near-miss wobble)

## The x of the slide's lower end (world) the waiting rows start from (place()).
var end_x := -2.6
## The row standing in the box's lane (-1: none, the round is done) and its first domino's near face (x).
var lane := -1
var face_x := 0.0
## The formula's way meets the lane row with the lab's setting now (the lab's contact_step(), when placed).
var hits := false
var _touch_at := -10.0                   # game clock of the box's touch (-10: not yet this run)
var _stopped := false

var _pivots: Array = []                  # per row: [Node3D, ...] (pivot at the domino's far foot edge)
var _home: Array = []                    # per row: [x, ...] the pivots' standing x now (world)
var _fall_at: Array = []                 # per row: the time its first domino started (-1: standing)
var _down: Array = [false, false, false]
var _wobble_at := -10.0
var _wobble_row := -1


func build() -> void:
	for r in ROWS.size():
		var spec: Array = ROWS[r]
		var size: Vector3 = spec[1]
		var colour: Color = spec[2]
		var b := ArtKit.builder()
		b.add_rounded_box(Transform3D(Basis(), Vector3(size.x * 0.5, size.y * 0.5, 0.0)), size, 0.03, 1, colour, colour.lightened(0.2))
		# Two white dots on the face toward the camera (a domino).
		for y in [0.3, 0.7]:
			b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(size.x * 0.5, size.y * y, size.z * 0.5 + 0.006)), size.y * 0.07, size.y * 0.07, 0.012, 6, ArtPalette.WHITE)
		var mesh := b.commit()
		var row: Array = []
		for x: float in spec[0]:
			var pivot := Node3D.new()
			pivot.name = "Domino%d_%d" % [r + 1, row.size() + 1]
			add_child(pivot)
			var mi := ArtKit.instance(mesh)
			# The pivot is the far (−x) foot edge: a turn about +z tips it away from the slide.
			pivot.add_child(mi)
			row.append(pivot)
		_pivots.append(row)
		_home.append([])
		_fall_at.append(-1.0)
	make_piece(Vector3.ZERO)
	_jump(0)


## The stage being played earns its stamp with the lab's setting now (MissionRound's own rule:
## the stage's conditions and its formula value, reach_n: the box's way meets the stage's row).
func fits() -> bool:
	var definition: Dictionary = lab.definition.raw
	var all: Array = MissionRound.missions(definition).get("stages", [])
	if stage < 0 or stage >= all.size():
		return false
	var entry: Dictionary = all[stage]
	var how := MissionRound.rule(definition, stage)
	if not MissionRound.conditions_met(entry.get("conditions", {}), lab):
		return false
	return how.observe == "" or MissionRound.beats(definition, how.observe, how.compare, entry, lab.observations())


## Puts the rows (the lab calls it on every reset: an angle, a material, a new start, a new attempt).
## The stage's row into the box's lane at its fixed place, the others beside the lane past the
## slide's lower end.
func place() -> void:
	var l: Variant = lab
	end_x = l.lower_end().x
	lane = stage if stage >= 0 and stage < ROWS.size() and not _down[stage] else -1
	face_x = LANE_FACE[lane] if lane >= 0 else 0.0
	hits = lane >= 0 and l.contact_step(l.arrival(), lane) >= 0
	for r in ROWS.size():
		var xs: Array = ROWS[r][0]
		_home[r] = []
		for k in xs.size():
			var x: float = lane_x(r, k) if r == lane else end_x - GAP + xs[k]
			_home[r].append(x)
			var pivot: Node3D = _pivots[r][k]
			pivot.position = Vector3(x, 0.0, 0.0 if r == lane else ROW_Z)
	if piece != null and piece_state == "held":
		piece.position = _piece_home()


## World x of the domino k of row r (its far foot edge, the pivot) standing in the lane.
static func lane_x(row: int, k: int) -> float:
	var xs: Array = ROWS[row][0]
	var size: Vector3 = ROWS[row][1]
	return float(LANE_FACE[row]) - size.x + (float(xs[k]) - float(xs[0]))


## The box's square (centre x, y; half size `half`) overlaps a domino of row r standing in the lane
## with its pivot at `pivot` (the lane's floor plane x, y).
static func overlaps(row: int, pivot: float, left: float, right: float, bottom: float) -> bool:
	var size: Vector3 = ROWS[row][1]
	return left <= pivot + size.x and right >= pivot and bottom <= size.y


## World x of the domino k of row r standing now.
func home_x(row: int, k: int) -> float:
	return _home[row][k]


func _piece_home() -> Vector3:
	var last := ROWS.size() - 1
	var size: Vector3 = ROWS[last][1]
	var pillar: Node3D = _pivots[last][0]
	return Vector3(home_x(last, 0) + size.x * 0.5, size.y + PIECE_SIZE * 0.95, pillar.position.z)


## The dominoes' boxes now (world AABBs, tests): each tilted domino's mesh bounds.
func domino_boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	for row: Array in _pivots:
		for pivot: Node3D in row:
			var mi := pivot.get_child(0) as MeshInstance3D
			out.append(mi.global_transform * mi.get_aabb())
	return out


## The time the stage's row started its chain (s on the game clock, tests; -1: standing).
func chain_started(row: int) -> float:
	return _fall_at[row] if row >= 0 and row < _fall_at.size() else -1.0


## The box's front has reached the lane row's first domino this run (the game clock then; tests).
func touched() -> bool:
	return _touch_at >= 0.0


func touch_time() -> float:
	return _touch_at


## The box has stopped on the floor without reaching the row (the lab's settled report).
func stopped() -> bool:
	return _stopped


## The box's front (its engine AABB's −x face, world) now.
func _box_front() -> float:
	var box: RigidBody3D = (lab as Variant).box
	var half: float = (lab as Variant).BOX * 0.5
	return (box.global_transform * AABB(-Vector3.ONE * half, Vector3.ONE * half * 2.0)).position.x


## Watches the released box (each frame): its touch on the lane row (its square on a standing
## domino), or its stop.
func _watch_box() -> void:
	var l: Variant = lab
	if not l.released or l.status() != "left" or touched() or _stopped:
		return
	if lane >= 0 and _meets_row():
		_touch_at = _t
		if _fall_at[lane] < 0.0:
			_start_chain(lane, _t)   # the box knocks the row over, stamped or not
		SoundBoard.play(&"stop")
	elif l.box.freeze or (l.braking() and l.box.linear_velocity.length() < STOP_SPEED):
		_stopped = true
		var short := _box_front() - face_x
		if lane >= 0 and short > 0.0 and short <= NEAR_MISS:
			_wobble_at = _t
			_wobble_row = lane


## The engine box's square (its world AABB in the lane's x, y) overlaps a standing lane domino.
func _meets_row() -> bool:
	var box: RigidBody3D = (lab as Variant).box
	var half: float = (lab as Variant).BOX * 0.5
	var aabb := box.global_transform * AABB(-Vector3.ONE * half, Vector3.ONE * half * 2.0)
	for k in (_home[lane] as Array).size():
		if overlaps(lane, _home[lane][k], aabb.position.x, aabb.end.x, aabb.position.y):
			return true
	return false


func _cleared(stage_index: int, last: bool) -> void:
	if stage_index < 0 or stage_index >= ROWS.size() or _down[stage_index]:
		return
	_down[stage_index] = true
	var l: Variant = lab
	var on_its_way: bool = stage_index == lane and hits and l.released and not touched() and not _stopped
	if _fall_at[stage_index] < 0.0 and not on_its_way:
		_start_chain(stage_index, _t)   # not in the lane (a restored or skipped stage): it goes at once
	# On its way: the chain starts at the box's touch (_watch_box); touched: it already started then.
	if last:
		_pending_piece = true


func _start_chain(row: int, at: float) -> void:
	_fall_at[row] = at


var _pending_piece := false


func _jump(stamps: int) -> void:
	_pending_piece = false
	_touch_at = -10.0
	_stopped = false
	_wobble_row = -1
	for r in ROWS.size():
		_down[r] = r < stamps
		_fall_at[r] = -1.0
		for pivot: Node3D in _pivots[r]:
			pivot.rotation.z = PI * 0.5 if _down[r] else 0.0
	if lab != null and (lab as Variant)._pivot != null:
		place()
	if stamps < stages and piece != null and piece_state != "held":
		piece.position = _piece_home()
		set_piece_state("held")


## The dominoes follow the box node as it is drawn this frame (its transform syncs from the engine
## at the physics frame): watched and posed here, before the frame is drawn.
func _physics_process(_delta: float) -> void:
	_watch_box()
	var front := _box_front() if lane >= 0 and touched() else INF
	for r in ROWS.size():
		var row: Array = _pivots[r]
		var size: Vector3 = ROWS[r][1]
		for k in row.size():
			var pivot: Node3D = row[k]
			var tilt := 0.0
			if _fall_at[r] >= 0.0:
				tilt = PI * 0.5 * smooth((_t - _fall_at[r] - NEXT_S * k) / FALL_S)
			elif _down[r]:
				tilt = PI * 0.5
			elif r == _wobble_row:
				tilt = wobble(_t, _wobble_at, 0.12, 0.6)
			var x: float = home_x(r, k)
			if r == lane and front < INF:
				var pushed := push(x, size.x, tilt, front)   # every domino the box gets to
				tilt = pushed.x
				x -= pushed.y
			pivot.rotation.z = tilt
			pivot.position.x = x
	var last := ROWS.size() - 1
	if _pending_piece and _fall_at[last] >= 0.0:
		var pillar: Array = ROWS[last]
		if _t >= _fall_at[last] + FALL_S * 0.6 + NEXT_S * ((pillar[0] as Array).size() - 1):
			_pending_piece = false
			launch_piece(Vector3(0.4, 1.6, 1.2), 9.81)   # the slide lab's g (InclineFriction G)
	elif piece != null and piece_state == "held" and not _pending_piece:
		piece.position = _piece_on_pillar()   # knocked over without the stamp: it rides on the top


## The piece on the pillar's top as the pillar stands or lies now (local to the game).
func _piece_on_pillar() -> Vector3:
	var last := ROWS.size() - 1
	var size: Vector3 = ROWS[last][1]
	var pillar: Node3D = _pivots[last][0]
	var at := pillar.transform * Vector3(size.x * 0.5, size.y + PIECE_SIZE * 0.95, 0.0)
	at.y = maxf(at.y, PIECE_SIZE)
	return at


## A domino as the box presses it (visual only): standing at `home` (its far foot edge) with
## thickness `thick` and tilt `tilt`, the box's front at `front`. Its nearest point to the box is the
## near foot corner home + thick cos(tilt): the domino tips at least so far that the corner stays at the
## box's front, and once it lies flat the box shoves it along. Returns (tilt, shove).
static func push(home: float, thick: float, tilt: float, front: float) -> Vector2:
	var depth := home + thick - front   # how far the box's front is past the standing near face
	if depth <= 0.0:
		return Vector2(tilt, 0.0)
	var least := acos(clampf(1.0 - depth / thick, -1.0, 1.0)) if depth < thick else PI * 0.5
	var phi := maxf(tilt, least)
	return Vector2(phi, maxf(0.0, home + thick * cos(phi) - front))


## The clue's glow (LabGame.highlight): the red pillar with the piece on its top.
func highlight_spots() -> Array:
	var last := ROWS.size() - 1
	var size: Vector3 = ROWS[last][1]
	var pillar: Node3D = _pivots[last][0]
	return [{"at": Vector3(home_x(last, 0) + size.x * 0.5, size.y * 0.8, pillar.position.z), "radius": 0.95}]
