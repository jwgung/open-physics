## Grass island props of the push friction lab (apps/lab3d/docs/art-direction.md, section 9). Meshes
## and reactions only: the floor, box and handle bodies are built by friction.gd and are not changed
## here.
## - a yellow floor track (the web's "마찰이 있는 바닥" strip) with white metre ticks, a white start
##   line and blue bumpers beyond both ends,
## - an orange box (the web's box colour) with its ArtJuice (shadow, dust, squash),
## - the red handle (grip on a white post with a blue foot) and the rod from the box to it: blue
##   while friction holds the box, red once it moves (the web's line colours),
## - reactions: the box starts to move = dust puff + small stretch + red rod; it stops = settle;
##   a track end = wobble; grabbing the handle = the grip grows a little.
class_name FrictionProps
extends RefCounted

const TRACK_WIDTH := 1.6
const ROD_RADIUS := 0.05
const GRIP := Vector3(0.18, 0.18, 0.56)
const GRAB_SCALE := 1.18

var juice: ArtJuice
var rod_hold: MeshInstance3D    # blue rod (friction holds the box)
var rod_move: MeshInstance3D    # red rod (the box moves)
var _grip: MeshInstance3D
var _rod_from := Vector3.INF    # box / handle positions the rod was last placed for
var _rod_to := Vector3.INF
var _rod_holding := true


## Yellow track on the island top (its top face 2 mm above y = 0, under the box's collision bottom
## at y = 0 only by its bevel), ticks every metre, start line at the box's start (x = -3 m).
func track_mesh(length: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -0.028, 0.0)), Vector3(length, 0.06, TRACK_WIDTH), 0.02, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	b.ao_min = 1.0
	var half := int(floorf(length * 0.5))
	for i in range(-half + 1, half):
		b.add_rounded_box(Transform3D(Basis(), Vector3(i, 0.006, TRACK_WIDTH * 0.5 - 0.2)), Vector3(0.05, 0.02, 0.3), 0.0, 1, ArtPalette.WHITE)
	b.add_rounded_box(Transform3D(Basis(), Vector3(-3.0, 0.006, 0.0)), Vector3(0.07, 0.02, TRACK_WIDTH - 0.3), 0.0, 1, ArtPalette.WHITE)
	# Bumpers just beyond both ends (the box stops before them; visual only).
	b.ao_min = 0.85
	b.ao_height = 0.4
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (length * 0.5 + 0.18), 0.25, 0.0)), Vector3(0.3, 0.5, TRACK_WIDTH), 0.05, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	return b.commit()


func box_mesh(size: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = size * 0.6
	b.add_rounded_box(Transform3D.IDENTITY, Vector3.ONE * size, 0.06, 1, ArtPalette.ORANGE, ArtPalette.ORANGE_TOP)
	return b.commit()


## The handle (mesh origin = the pick box centre, `height` tall): blue foot on the floor, white post,
## red grip across the track at the centre (rod height).
func handle_mesh(height: float) -> Mesh:
	var b := ArtKit.builder()
	var floor_y := -height * 0.5
	b.ao_height = 0.15
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, floor_y, 0.0)), 0.2, 0.17, 0.06, 8, ArtPalette.BLUE_DARK)
	b.ao_min = 0.9
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, floor_y, 0.0)), 0.035, 0.035, height * 0.5, 6, ArtPalette.WHITE)
	return b.commit()


func grip_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D.IDENTITY, GRIP, 0.07, 1, ArtPalette.RED, ArtPalette.RED_TOP)
	return b.commit()


## A rod of length 1 along +x from the node origin (scaled along x to the handle).
static func rod_mesh(color: Color) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO), ROD_RADIUS, ROD_RADIUS, 1.0, 6, color)
	return b.commit()


## Island, rod meshes, grip and the box reactions. `handle_visual` is the handle's mesh node.
func dress(experiment: Node3D, box_body: RigidBody3D, box_visual: MeshInstance3D, box_size: float, handle_visual: MeshInstance3D) -> void:
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.8))
	_grip = ArtKit.instance(grip_mesh())
	_grip.name = "Grip"
	handle_visual.add_child(_grip)
	rod_hold = ArtKit.instance(rod_mesh(ArtPalette.BLUE))
	rod_hold.name = "RodHold"
	experiment.add_child(rod_hold)
	rod_move = ArtKit.instance(rod_mesh(ArtPalette.RED))
	rod_move.name = "RodMove"
	rod_move.visible = false
	experiment.add_child(rod_move)
	juice = ArtJuice.new()
	juice.name = "BoxJuice"
	experiment.add_child(juice)
	juice.setup(box_body, box_visual, box_size)


## Places the rod from the box's right face (at its centre height) to the handle grip; the colour
## shows whether friction holds the box. Only moves the rod when one of the ends moved.
func update_rod(box_center: Vector3, grip: Vector3, holding: bool) -> void:
	if rod_hold == null:
		return
	if holding != _rod_holding:
		_rod_holding = holding
		rod_hold.visible = holding
		rod_move.visible = not holding
		_rod_from = Vector3.INF   # place the now visible rod
	if box_center == _rod_from and grip == _rod_to:
		return
	_rod_from = box_center
	_rod_to = grip
	var rod := rod_hold if holding else rod_move
	var start := box_center
	var length := grip.x - start.x
	var xf := Transform3D(Basis(Vector3.UP, PI if length < 0.0 else 0.0).scaled(Vector3(maxf(absf(length), 0.01), 1.0, 1.0)), Vector3(start.x, grip.y, start.z))
	rod.global_transform = xf


## The handle was picked up (true) or let go (false): the grip grows a little while held.
func grab(on: bool) -> void:
	if _grip != null:
		_grip.scale = Vector3.ONE * (GRAB_SCALE if on else 1.0)


## Experiment status change -> reactions: starts to move = puff + stretch; comes to rest = settle.
func status_changed(previous: String, status: String) -> void:
	if juice == null:
		return
	if status == "sliding" and previous == "holding":
		juice.puff(0.7)
		juice.stretch()
	elif status == "holding" and previous == "sliding":
		juice.settle()


## The box reached a track end and stopped at the bumper.
func hit_end() -> void:
	if juice != null:
		juice.wobble()


## The box is back at its start.
func reset() -> void:
	if juice != null:
		juice.pop()
	grab(false)
