## The slide's piece game (2026-10-29 "조각 꺼내기"): three rows of dominoes on the floor past the
## slide's lower end, small, bigger and the big pillar with the star piece on top. A stage asks for
## the box to reach the end fast enough (MissionTracker: bottom_speed, the formula's v = √(2 a d) with
## a = g (sin θ − μk cos θ) and d the run from the start to the end, past 5 → 6 → 6.5 m/s on steel →
## steeper wood → steepest rubber). When the box leaves the slide (the formula's run end, status
## "left") the stage's row wobbles; its stamp knocks the row over one domino after the other, and the
## pillar's fall throws the piece down on uniform gravity (LabGame.launch_piece). Visual only: the
## dominoes are pictures on the floor (no body), the box and the numbers are the lab's as before.
class_name InclineGame
extends LabGame

## Per row: [the dominoes' x (world, their foot on the floor), size (thick, tall, wide), colour].
## (2026-10-29: 1.4x taller and wider than first made, the rows read on the tablet's front view.)
const ROWS := [
	[[-4.0, -4.22, -4.44], Vector3(0.11, 0.44, 0.44), Color("ffc61a")],
	[[-4.72, -4.97, -5.22], Vector3(0.14, 0.6, 0.54), Color("2d7cf6")],
	[[-5.55], Vector3(0.22, 1.05, 0.7), Color("ff3b3b")],
]
const FALL_S := 0.35
const NEXT_S := 0.12                     # the next domino starts falling this long after the one before

var _pivots: Array = []                  # per row: [Node3D, ...] (pivot at the domino's far foot edge)
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
			pivot.position = Vector3(x, 0.0, 0.0)
			add_child(pivot)
			var mi := ArtKit.instance(mesh)
			# The pivot is the far (−x) foot edge: a turn about +z tips it away from the slide.
			pivot.add_child(mi)
			row.append(pivot)
		_pivots.append(row)
		_fall_at.append(-1.0)
	var pillar: Array = ROWS[ROWS.size() - 1]
	make_piece(Vector3(pillar[0][0] + (pillar[1] as Vector3).x * 0.5, (pillar[1] as Vector3).y + PIECE_SIZE * 0.95, 0.0))
	_jump(0)


## The formula box reached the slide's end (status "left"): the stage's row wobbles (its stamp, if
## the speed was enough, knocks it over).
func arrive() -> void:
	if stage < ROWS.size() and not _down[stage]:
		_wobble_at = _t
		_wobble_row = stage


func _cleared(stage_index: int, last: bool) -> void:
	if stage_index >= 0 and stage_index < ROWS.size() and not _down[stage_index]:
		_down[stage_index] = true
		_fall_at[stage_index] = _t
		SoundBoard.play(&"stop")
	if last:
		var pillar: Array = ROWS[ROWS.size() - 1]
		_pending_piece_at = _t + FALL_S * 0.6 + NEXT_S * ((pillar[0] as Array).size() - 1)


var _pending_piece_at := -1.0


func _jump(stamps: int) -> void:
	_pending_piece_at = -1.0
	for r in ROWS.size():
		_down[r] = r < stamps
		_fall_at[r] = -1.0
		for pivot: Node3D in _pivots[r]:
			pivot.rotation.z = PI * 0.5 if _down[r] else 0.0
	if stamps < stages and piece != null and piece_state != "held":
		var pillar: Array = ROWS[ROWS.size() - 1]
		piece.position = Vector3(pillar[0][0] + (pillar[1] as Vector3).x * 0.5, (pillar[1] as Vector3).y + PIECE_SIZE * 0.95, 0.0)
		set_piece_state("held")


func _process(delta: float) -> void:
	super(delta)
	for r in ROWS.size():
		var row: Array = _pivots[r]
		for k in row.size():
			var pivot: Node3D = row[k]
			if _fall_at[r] >= 0.0:
				pivot.rotation.z = PI * 0.5 * smooth((_t - _fall_at[r] - NEXT_S * k) / FALL_S)
			elif not _down[r]:
				pivot.rotation.z = wobble(_t, _wobble_at, 0.12, 0.6) if r == _wobble_row else 0.0
	if _pending_piece_at >= 0.0 and _t >= _pending_piece_at:
		_pending_piece_at = -1.0
		launch_piece(Vector3(0.4, 1.6, 1.2), 9.81)   # the slide lab's g (InclineFriction G)


## The clue's glow (LabGame.highlight): the red pillar with the piece on its top.
func highlight_spots() -> Array:
	var pillar: Array = ROWS[ROWS.size() - 1]
	var size: Vector3 = pillar[1]
	return [{"at": Vector3(pillar[0][0] + size.x * 0.5, size.y * 0.8, 0.0), "radius": 0.95}]
