## Grass island props of the push friction lab (apps/lab3d/docs/art-direction.md, section 9). Meshes
## and reactions only: the floor, box and handle bodies are built by friction.gd and are not changed
## here.
## - a yellow floor track (the web's "마찰이 있는 바닥" strip) with white metre ticks, a white start
##   line and blue bumpers beyond both ends; inside its yellow rim the track shows the chosen
##   material (SurfaceSkin, set_surface: 2026-10-28, rubber / wood / steel / clay),
## - an orange box (the web's box colour) with its ArtJuice (shadow, dust, squash); it looks as heavy
##   as it is (set_look, 2026-10-28): one stuff, its side the cube root of its mass against the 8 kg
##   start box's 0.7 m, grown from the body's bottom (ArtJuice.look_scale). The body (a 0.7 m cube),
##   its friction and the formula's track-end stops stay; the bumpers move to where the look stops,
##   and the rod, the grip and the cat's paws go to the look's height,
## - the red handle (grip on a white post with a blue foot) and the rod from the box to it: blue
##   while friction holds the box, red once it moves (the web's line colours),
## - reactions: the box starts to move = dust puff + small stretch + red rod; it stops = settle;
##   a track end = wobble; grabbing the handle = the grip grows a little.
## - the bread cat (CatActor wearing the BreadCat look, Task 4g) behind the box (-x): both paws on
##   the box's left face (where the box mesh is, squash included), leaning into a push or back on a
##   pull with the force's share of the maximum static friction, shuffling along while the box
##   moves; a small hop when the box comes to rest. Only meshes: the force, the box and the panel are the lab's.
class_name FrictionProps
extends RefCounted

const TRACK_WIDTH := 1.6
const ROD_RADIUS := 0.05
const GRIP := Vector3(0.18, 0.18, 0.56)
const GRAB_SCALE := 1.18
## Height of the cat's paws on the box face (m above the floor) on the 0.7 m start box; a smaller look
## takes them down in proportion.
const CAT_HAND_Y := 0.62
const BUMPER_GAP := 0.05         # m between a stopped box's look and the bumper face
## Force (as a share of the maximum static friction) at which the cat leans fully.
const CAT_FULL_EFFORT := 1.5

var juice: ArtJuice
var cat: CatActor
var _box_visual: MeshInstance3D
var _box_size := 0.7
var rod_hold: MeshInstance3D    # blue rod (friction holds the box)
var rod_move: MeshInstance3D    # red rod (the box moves)
var _grip: MeshInstance3D
var _rod_from := Vector3.INF    # box / handle positions the rod was last placed for
var _rod_to := Vector3.INF
var _rod_holding := true
var _look := 1.0                # the box look's size against the body's (set_look)
var _stop := 5.63               # |x| of the box centre where the formula stops it at a track end
## The track's node and the surface material it shows (set_surface).
var track_visual: MeshInstance3D
var surface := ""
var _track_args := Vector2.ZERO
var _track_meshes := {}          # material id -> mesh
var bumpers: MeshInstance3D      # both bumpers, one mesh (rebuilt for a new look size, cached)
var _bumper_meshes := {}         # face |x| -> mesh


## Yellow track on the island top (its top face 2 mm above y = 0, under the box's collision bottom
## at y = 0 only by its bevel) with the skin of surface material `material` inside a yellow rim,
## ticks every metre, start line at the box's start (`start_x`, the lab's START_X).
func track_mesh(length: float, start_x: float, material := "wood") -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -0.028, 0.0)), Vector3(length, 0.06, TRACK_WIDTH), 0.02, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	SurfaceSkin.add_to(b, Transform3D(Basis(), Vector3(0.0, 0.002, 0.0)), material, length - 0.16, TRACK_WIDTH - 0.16)
	b.ao_min = 1.0
	var half := int(floorf(length * 0.5))
	for i in range(-half + 1, half):
		b.add_rounded_box(Transform3D(Basis(), Vector3(i, 0.006, TRACK_WIDTH * 0.5 - 0.2)), Vector3(0.05, 0.02, 0.3), 0.0, 1, ArtPalette.WHITE)
	b.add_rounded_box(Transform3D(Basis(), Vector3(start_x, 0.006, 0.0)), Vector3(0.07, 0.02, TRACK_WIDTH - 0.3), 0.0, 1, ArtPalette.WHITE)
	return b.commit()


## The bumpers beyond both track ends (the box stops before them; visual only), their faces at
## x = +-`face`.
static func bumper_mesh(face: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.85
	b.ao_height = 0.4
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (face + 0.15), 0.25, 0.0)), Vector3(0.3, 0.5, TRACK_WIDTH), 0.05, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
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


## The track node for a track of `length` with its start line at `start_x`; set_surface swaps its mesh.
func make_track(length: float, start_x: float, material: String) -> MeshInstance3D:
	_track_args = Vector2(length, start_x)
	track_visual = ArtKit.instance(null)
	track_visual.name = "TrackVisual"
	set_surface(material)
	return track_visual


## The track shows surface material `material` (one mesh per material, cached).
func set_surface(material: String) -> void:
	surface = material
	if track_visual == null:
		return
	if not _track_meshes.has(material):
		_track_meshes[material] = track_mesh(_track_args.x, _track_args.y, material)
	track_visual.mesh = _track_meshes[material]


## A rod of length 1 along +x from the node origin (scaled along x to the handle).
static func rod_mesh(color: Color) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO), ROD_RADIUS, ROD_RADIUS, 1.0, 6, color)
	return b.commit()


## Island, rod meshes, grip, bumpers and the box reactions. `handle_visual` is the handle's mesh node;
## `stop` = |x| of the box centre where the formula stops it at a track end.
func dress(experiment: Node3D, box_body: RigidBody3D, box_visual: MeshInstance3D, box_size: float, handle_visual: MeshInstance3D, stop: float) -> void:
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.8))
	_stop = stop
	bumpers = MeshInstance3D.new()
	bumpers.name = "Bumpers"
	bumpers.material_override = ArtKit.lit_material()
	bumpers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	experiment.add_child(bumpers)
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
	_box_visual = box_visual
	_box_size = box_size
	cat = CatActor.new(BreadCat.new())
	cat.push_face = cat_face_x
	experiment.add_child(cat)   # after the juice: it reads the box mesh the juice moved this frame
	set_look(1.0)


## The box looks `k` times its body's size: the juice's look, the grip at the look's middle height
## and the bumpers BUMPER_GAP beyond where the look stops.
func set_look(k: float) -> void:
	_look = k
	juice.set_look_scale(k)
	_grip.position.y = (k - 1.0) * _box_size * 0.5
	var face := snappedf(_stop + k * _box_size * 0.5 + BUMPER_GAP, 0.001)
	if not _bumper_meshes.has(face):
		_bumper_meshes[face] = bumper_mesh(face)
	bumpers.mesh = _bumper_meshes[face]
	_rod_from = Vector3.INF   # the rod goes to the new height


## The box look's bounds now (world, at rest size): its body's bottom, k times the body's side.
func look_bounds(box_center: Vector3) -> AABB:
	var side := _look * _box_size
	var bottom := box_center - Vector3(side * 0.5, _box_size * 0.5, side * 0.5)
	return AABB(bottom, Vector3.ONE * side)


## The face of the box mesh the cat pushes (its -x face, where the squashed / wobbling mesh is now).
func cat_face_x() -> float:
	return (_box_visual.global_transform * Vector3(-_box_size * 0.5, 0.0, 0.0)).x


## Poses the cat at the box: `force` (N, + = +x) against `max_static` sets the lean, `travel` (box x,
## m) and `speed` (m/s) the shuffle.
func update_cat(force: float, max_static: float, travel: float, speed: float) -> void:
	if cat == null:
		return
	var effort := force / (max_static * CAT_FULL_EFFORT) if max_static > 0.0 else 0.0
	cat.push(cat_face_x(), CAT_HAND_Y * _look, effort, travel, speed, _box_visual.global_position.z)


## Places the rod from the box's centre (at the grip's height, the look's middle) to the handle grip;
## the colour shows whether friction holds the box. Only moves the rod when one of the ends moved.
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
	var xf := Transform3D(Basis(Vector3.UP, PI if length < 0.0 else 0.0).scaled(Vector3(maxf(absf(length), 0.01), 1.0, 1.0)), Vector3(start.x, grip.y + _grip.position.y, start.z))
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
		if cat != null:
			cat.cheer(false)   # the paws stay on the box


## The box reached a track end and stopped at the bumper.
func hit_end() -> void:
	if juice != null:
		juice.wobble()


## The box is back at its start.
func reset() -> void:
	if juice != null:
		juice.pop()
	grab(false)
