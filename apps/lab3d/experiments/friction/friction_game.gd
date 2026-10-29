## The push's piece game (2026-10-29 "조각 꺼내기"; the user kept the push: "이건 좋아"): the star piece
## is pressed into the floor at the box's start, peeking out from under its front. A stage asks for
## the light, the normal and the heavy box to move (MissionTracker: the state "sliding", the box's
## mass); each stamp loosens the piece a step out of the floor, and the heavy box's stamp pops it out
## where the box was once the box has slid off it (or after POP_WAIT_S), on uniform gravity
## (LabGame.launch_piece). Visual only: the piece is a picture (no body); the box, its push and the
## numbers are the lab's as before.
class_name FrictionGame
extends LabGame

## The piece's centre height (in its radii) after 0, 1, 2 stamps: deep in the floor, then rising.
const RISE := [-0.15, 0.1, 0.35]
const RISE_S := 0.45
const POP_WAIT_S := 1.2
const START_X := -3.0                    # the box's start (FrictionLab START_X)
const SIZE := PIECE_SIZE * 1.3          # a bigger piece: it reads under the box from the front view

var box_half := 0.35                     # the box look's half size now (the lab sets it with the mass)
var _from_y := 0.0
var _to_y := 0.0
var _rise_at := -1.0
var _pop_at := -1.0                      # the last stamp: the piece waits for the box to leave (time it came)


func build() -> void:
	make_piece(_home(0), SIZE)
	piece.rotation_degrees = Vector3(0.0, 0.0, 28.0)
	_jump(0)


## The piece's place after `stamps` stamps: under the front edge of the box at its start.
func _home(stamps: int) -> Vector3:
	return Vector3(START_X + 0.12, SIZE * RISE[mini(stamps, RISE.size() - 1)], box_half * 0.8 + SIZE * 0.2)


func _cleared(stage_index: int, last: bool) -> void:
	if last:
		_pop_at = _t
		return
	_from_y = piece.position.y
	_to_y = _home(stage_index + 1).y
	_rise_at = _t
	SoundBoard.play(&"glint")


func _jump(stamps: int) -> void:
	_rise_at = -1.0
	_pop_at = -1.0
	if stamps < stages and piece != null and piece_state != "taken":
		piece.position = _home(stamps)
		set_piece_state("held")


## The lab's run starts over (a new box, 처음으로): the piece stays as loose as the stamps made it; a
## pop still waiting goes now.
func run_reset() -> void:
	if _pop_at >= 0.0:
		_pop()
		return
	super()


func _pop() -> void:
	_pop_at = -1.0
	piece.rotation = Vector3.ZERO
	launch_piece(Vector3(-0.3, 2.6, 1.2), 9.81)


func _process(delta: float) -> void:
	super(delta)
	if piece == null:
		return
	if piece_state == "held":
		piece.position.z = _home(cleared).z
	if _rise_at >= 0.0:
		var k := (_t - _rise_at) / RISE_S
		piece.position.y = lerpf(_from_y, _to_y, smooth(k)) + 0.04 * sin(minf(k, 1.0) * PI * 4.0)
		if k >= 1.0:
			_rise_at = -1.0
	if _pop_at >= 0.0:
		var push_lab: Variant = host()
		var moved: float = absf(push_lab.formula_x() - START_X) if push_lab != null and push_lab.has_method("formula_x") else INF
		if moved > box_half + PIECE_SIZE or _t - _pop_at > POP_WAIT_S:
			_pop()
