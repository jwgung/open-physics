## The slide's piece game (2026-10-29 "조각 꺼내기"): three rows of dominoes, small, bigger and the big
## pillar with the star piece on top. A stage asks for the box to reach the end fast enough
## (MissionTracker: bottom_speed, the formula's v = √(2 a d) with a = g (sin θ − μk cos θ) and d the
## run from the start to the end, past 5 → 6 → 6.5 m/s on steel → steeper wood → steepest rubber).
##
## Where the box arrives (2026-10-29 user, twice: "미끄럼틀은 여전히 착지 지점과 도미노의 위치가
## 안맞다"): past the slide's end the box flies on g from the end, lands on the frictionless floor and
## the floor brake stops it (InclineFriction.arrival(): the formula's projectile and the brake, which
## the engine box follows within 2 cm). The stage's row stands in the box's lane (z 0) there:
## - when the setting earns the stage (fits()), the first domino's near face is HIT_DEPTH short of the
##   box's front at rest, so the sliding box runs into it; the moment the engine box's front reaches
##   that face (touched()) the row's chain starts (each domino NEXT_S after the one before), and the
##   first domino is pushed over by the box so it never sits inside it (push());
## - otherwise the row stands MISS_GAP past where the box stops: it slides up to the row and the row
##   only wobbles.
## The other rows wait beside the lane (ROW_Z, past the slide's end, as before), standing or fallen.
## The pillar's fall throws the piece down on uniform gravity (LabGame.launch_piece). Visual only:
## the dominoes are pictures on the floor (no body), the box and the numbers are the lab's.
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
const HIT_DEPTH := 0.15                  # m the box at rest would reach past the first domino's near face
const MISS_GAP := 0.25                   # m between the box at rest and the row on a setting that falls short
const HOLD_GAP := 2.0                    # m past the slide's end the row waits when the box holds (a ≤ 0)
const FALL_S := 0.35
const NEXT_S := 0.12                     # the next domino starts falling this long after the one before
const TOUCH_KEEP_S := 0.5                # a stamp this soon after the box's touch starts the chain at it
const STOP_SPEED := 0.05                 # m/s: the braked box has stopped (settled, the near-miss wobble)

## The x of the slide's lower end (world) the waiting rows start from (place()).
var end_x := -3.76
## The row standing in the box's lane (-1: none, the round is done) and its first domino's near face (x).
var lane := -1
var face_x := 0.0
## The lane row is where the box gets there (fits() when placed).
var hits := false
var _touch_at := -10.0                   # game clock of the box's touch (-10: not yet this run)
var _stopped := false

var _pivots: Array = []                  # per row: [Node3D, ...] (pivot at the domino's far foot edge)
var _home: Array = []                    # per row: [x, ...] the pivots' standing x now (world)
var _fall_at: Array = []                 # per row: the time its first domino started (-1: standing)
var _armed: Array = [false, false, false]   # stamped, waiting for the box's touch to start the chain
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


## The stage being played earns its stamp with the lab's setting now (MissionTracker's own rule:
## the stage's conditions and its formula value, bottom_speed, past the threshold).
func fits() -> bool:
	var definition: Dictionary = lab.definition
	var all: Array = MissionTracker.missions(definition).get("stages", [])
	if stage < 0 or stage >= all.size():
		return false
	var entry: Dictionary = all[stage]
	var how := MissionTracker.rule(definition, stage)
	if not MissionTracker.conditions_met(entry.get("conditions", {}), lab):
		return false
	return how.observe == "" or MissionTracker.beats(definition, how.observe, how.compare, entry, lab.observations())


## Puts the rows for the lab's setting now (the lab calls it on every reset: an angle, a material, a
## new start, a new attempt). The stage's row into the box's lane where the box arrives, the others
## beside the lane past the slide's lower end.
func place() -> void:
	var l: Variant = lab
	end_x = l.lower_end().x
	lane = stage if stage >= 0 and stage < ROWS.size() and not _down[stage] else -1
	var way: Dictionary = l.arrival()
	hits = lane >= 0 and not way.is_empty() and fits()
	if way.is_empty():
		face_x = end_x - HOLD_GAP
	else:
		var front: float = way.rest_x - l.BOX * 0.5   # the box's front (−x face) at rest
		face_x = front + HIT_DEPTH if hits else front - MISS_GAP
	for r in ROWS.size():
		var xs: Array = ROWS[r][0]
		var size: Vector3 = ROWS[r][1]
		_home[r] = []
		for k in xs.size():
			var x: float = face_x - size.x + (xs[k] - xs[0]) if r == lane else end_x - GAP + xs[k]
			_home[r].append(x)
			var pivot: Node3D = _pivots[r][k]
			pivot.position = Vector3(x, 0.0, 0.0 if r == lane else ROW_Z)
	if piece != null and piece_state == "held":
		piece.position = _piece_home()


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


## Watches the released box (each frame): its touch on the lane row's first domino, or its stop.
func _watch_box() -> void:
	var l: Variant = lab
	if not l.released or l.status() != "left" or touched() or _stopped:
		return
	if lane >= 0 and _box_front() <= face_x:
		_touch_at = _t
		if _armed[lane]:
			_start_chain(lane, _t)
		SoundBoard.play(&"stop")
	elif l.box.freeze or (l.box.linear_damp > 0.0 and l.box.linear_velocity.length() < STOP_SPEED):
		_stopped = true
		if lane >= 0:
			_wobble_at = _t
			_wobble_row = lane


func _cleared(stage_index: int, last: bool) -> void:
	if stage_index < 0 or stage_index >= ROWS.size() or _down[stage_index]:
		return
	_down[stage_index] = true
	if stage_index != lane:
		_start_chain(stage_index, _t)   # not in the lane (a restored or skipped stage): it goes at once
	elif touched() and _t - _touch_at <= TOUCH_KEEP_S:
		_start_chain(stage_index, _touch_at)   # the box touched it a moment ago (the judging poll)
	elif touched():
		_start_chain(stage_index, _t)
	else:
		_armed[stage_index] = true          # the box is on its way: the chain starts at its touch
	if last:
		_pending_piece = true


func _start_chain(row: int, at: float) -> void:
	_armed[row] = false
	_fall_at[row] = at


var _pending_piece := false


func _jump(stamps: int) -> void:
	_pending_piece = false
	_touch_at = -10.0
	_stopped = false
	_wobble_row = -1
	for r in ROWS.size():
		_down[r] = r < stamps
		_armed[r] = false
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
			elif _down[r] and not _armed[r]:
				tilt = PI * 0.5
			elif r == _wobble_row:
				tilt = wobble(_t, _wobble_at, 0.12, 0.6)
			var x: float = home_x(r, k)
			if r == lane and k == 0 and front < INF:
				var pushed := push(x, size.x, tilt, front)
				tilt = pushed.x
				x -= pushed.y
			pivot.rotation.z = tilt
			pivot.position.x = x
	if _pending_piece and _fall_at[ROWS.size() - 1] >= 0.0:
		var pillar: Array = ROWS[ROWS.size() - 1]
		if _t >= _fall_at[ROWS.size() - 1] + FALL_S * 0.6 + NEXT_S * ((pillar[0] as Array).size() - 1):
			_pending_piece = false
			launch_piece(Vector3(0.4, 1.6, 1.2), 9.81)   # the slide lab's g (InclineFriction G)


## The first domino as the box presses it (visual only): standing at `home` (its far foot edge) with
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
