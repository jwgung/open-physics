## The free fall's piece game (2026-10-29 "조각 꺼내기"): a red and a yellow floor button under the red
## and the yellow ball, and a little barred house with the star piece inside. A stage asks for the two
## balls (a heavy red one and the light yellow one) to press their buttons together: MissionTracker
## judges "together_time", the formula landing time of both when their landings are within one fixed
## step of each other (|√(2h_red/g) − √(2h_yellow/g)| ≤ 1/60 s; the same height lands together
## whatever the mass), with the world of the stage (the earth, the Moon past 3 s, Jupiter under 1 s).
## Each button lights when its formula ball lands; a stamp lights one of the house's three lamps,
## the last opens its door and the piece hops out on the lab's own gravity (slowly on the Moon).
## Visual only: no body, the balls and the numbers are the lab's as before. Three drawn nodes and the
## piece's two: the buttons and the house (with its lamps) are one mesh each, rebuilt when one lights.
class_name FreeFallGame
extends LabGame

const BUTTON_R := 0.38                   # (0.3 until 2026-10-29: hard to see on the tablet)
const HOUSE_AT := Vector3(3.5, 0.0, -0.7)
const HOUSE := Vector3(0.95, 1.05, 0.75)   # (kept: a bigger house hides behind Dugi from the front view, tests/island_cast_checks.gd)
const DOOR_S := 0.5

static var _house_meshes := {}

var _buttons: MeshInstance3D              # both buttons in one mesh (rebuilt when one lights)
var _pressed := {"red": -1.0, "yellow": -1.0}   # ball id -> time its formula landing pressed it (-1: up)
var _button_x := {"red": 1.5, "yellow": -1.5}
var _house: MeshInstance3D                # walls, roof and the three lamps (rebuilt when a lamp lights)
var _door: Node3D
var _door_open_at := -1.0
var _rattle_at := -10.0
var _lit := -1


func build() -> void:
	_buttons = ArtKit.instance(buttons_mesh(_button_x, {}))
	_buttons.name = "Buttons"
	add_child(_buttons)
	_house = ArtKit.instance(house_mesh(0))
	_house.name = "House"
	_house.position = HOUSE_AT
	add_child(_house)
	_door = Node3D.new()
	_door.name = "Door"
	_door.position = HOUSE_AT + Vector3(-HOUSE.x * 0.5 + 0.08, 0.08, HOUSE.z * 0.5 - 0.02)
	add_child(_door)
	var d := ArtKit.builder()
	var door_w := HOUSE.x - 0.16
	var door_h := HOUSE.y - 0.12
	for y in [0.03, door_h - 0.03]:
		d.add_rounded_box(Transform3D(Basis(), Vector3(door_w * 0.5, y, 0.0)), Vector3(door_w, 0.06, 0.05), 0.01, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	for k in 5:
		d.add_cylinder(Transform3D(Basis(), Vector3(door_w * (k + 0.5) / 5.0, door_h * 0.5, 0.0)), 0.022, 0.022, door_h, 6, ArtPalette.YELLOW, false)
	var bars := ArtKit.instance(d.commit())
	bars.name = "Bars"
	_door.add_child(bars)
	make_piece(_piece_home())
	_jump(0)


func _piece_home() -> Vector3:
	return HOUSE_AT + Vector3(0.0, 0.08 + PIECE_SIZE + 0.05, 0.0)


## The two floor buttons at their x (a white ring and a cap in the ball's colour, pale and pressed
## down when lit).
static func buttons_mesh(xs: Dictionary, lit: Dictionary) -> Mesh:
	var b := ArtKit.builder()
	for id in xs:
		var colour: Color = ArtPalette.RED if id == "red" else ArtPalette.YELLOW
		var on: bool = lit.get(id, false)
		var x: float = xs[id]
		b.add_cylinder(Transform3D(Basis(), Vector3(x, 0.006, 0.0)), BUTTON_R + 0.08, BUTTON_R + 0.06, 0.012, 12, ArtPalette.WHITE)
		var cap := colour.lightened(0.45) if on else colour.darkened(0.15)
		b.add_cylinder(Transform3D(Basis(), Vector3(x, 0.01 if on else 0.016, 0.0)), BUTTON_R, BUTTON_R * 0.92, 0.012 if on else 0.02, 12, cap, true, cap.lightened(0.15))
	return b.commit()


## The house with `lit` of its three lamps on (cached per count).
static func house_mesh(lit: int) -> Mesh:
	if _house_meshes.has(lit):
		return _house_meshes[lit]
	var b := ArtKit.builder()
	var w := HOUSE
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, w.y * 0.5, -w.z * 0.5 + 0.04)), Vector3(w.x, w.y, 0.08), 0.03, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (w.x * 0.5 - 0.04), w.y * 0.5, 0.0)), Vector3(0.08, w.y, w.z), 0.03, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.04, 0.0)), Vector3(w.x, 0.08, w.z), 0.03, 1, ArtPalette.BLUE_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, w.y + 0.06, 0.0)), Vector3(w.x + 0.16, 0.12, w.z + 0.16), 0.04, 1, ArtPalette.RED, ArtPalette.RED_TOP)
	b.ao_min = 1.0
	for i in 3:
		b.add_sphere(Transform3D(Basis(), Vector3((i - 1) * 0.28, w.y + 0.22, w.z * 0.5 - 0.02)), 0.09, 3, 6, LAMP_ON if i < lit else LAMP_OFF)
	_house_meshes[lit] = b.commit()
	return _house_meshes[lit]


## The buttons stay under their balls (the lab's start x of each).
func place_buttons(starts: Dictionary) -> void:
	var xs := {}
	for id in _button_x:
		xs[id] = float(starts[id].x) if starts.has(id) else float(_button_x[id])
	if xs != _button_x:
		_button_x = xs
		_show_buttons()


func _show_buttons() -> void:
	var lit := {}
	for id in _pressed:
		lit[id] = float(_pressed[id]) >= 0.0
	_buttons.mesh = buttons_mesh(_button_x, lit)


## The formula ball `id` has landed on its button: it lights.
func press(id: String) -> void:
	if _pressed.has(id):
		_pressed[id] = _t
		_show_buttons()


## Both buttons were pressed but not together: the door rattles (no lamp).
func rattle() -> void:
	_rattle_at = _t


## Whether ball `id`'s button is lit now (tests).
func pressed(id: String) -> bool:
	return float(_pressed.get(id, -1.0)) >= 0.0


func _cleared(stage_index: int, last: bool) -> void:
	_set_lamps(stage_index + 1)
	if last:
		_door_open_at = _t
		launch_piece(Vector3(-0.5, 2.0, 1.6), lab_g())
	else:
		_rattle_at = _t
	SoundBoard.play(&"glint")


func _set_lamps(lit: int) -> void:
	if lit != _lit:
		_lit = lit
		_house.mesh = house_mesh(lit)


func _jump(stamps: int) -> void:
	_set_lamps(stamps)
	_door_open_at = -1.0
	for id in _pressed:
		_pressed[id] = -1.0
	_show_buttons()
	if stamps < stages and piece != null and piece_state != "held":
		piece.position = _piece_home()
		set_piece_state("held")


func _process(delta: float) -> void:
	super(delta)
	if _door_open_at >= 0.0:
		_door.rotation.y = -PI * 0.6 * smooth((_t - _door_open_at) / DOOR_S)
	else:
		_door.rotation.y = (-PI * 0.6 if cleared >= stages else 0.0) + wobble(_t, _rattle_at, 0.08, 0.5)
