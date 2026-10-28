## Grass island props of the push friction lab (apps/lab3d/docs/art-direction.md, section 9). Meshes
## and reactions only: the floor and box bodies are built by friction.gd and are not changed here.
## - a yellow floor track (the web's "마찰이 있는 바닥" strip) with white metre ticks, a white start
##   line and blue bumpers beyond both ends; inside its yellow rim the track shows the chosen
##   material (SurfaceSkin, set_surface: 2026-10-28, rubber / wood / steel / clay),
## - an orange box (the web's box colour) with its ArtJuice (shadow, dust, squash); it looks as heavy
##   as it is (set_look, 2026-10-28): one stuff, its side the cube root of its mass against the 8 kg
##   start box's 0.7 m, grown from the body's bottom (ArtJuice.look_scale). The body (a 0.7 m cube),
##   its friction and the formula's track-end stops stay; the bumpers move to where the look stops,
##   and the cat's paws go to the look's height,
## - the push gauge (ForceGauge, 2026-10-28: the red handle and its rod went, the child presses and
##   holds the box itself) beside the box's +x face while the box is held: the push's share of
##   the most a hold gives (no numbers),
## - reactions: the box starts to move = dust puff + small stretch; it stops = settle; a track end =
##   wobble.
## - the bread cat (CatActor wearing the BreadCat look, Task 4g) behind the box (-x): both paws on
##   the box's left face (where the box mesh is, squash included), leaning into the push with the
##   force's share of the maximum static friction (the held push grows, so does the lean), shuffling
##   along while the box moves; a small hop when the box comes to rest. Only meshes: the force, the
##   box and the panel are the lab's.
class_name FrictionProps
extends RefCounted

const TRACK_WIDTH := 1.6
const GAUGE_GAP := 0.35          # m from the box look's +x face to the gauge
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
var gauge: ForceGauge
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


## Island, bumpers, the push gauge and the box reactions. `stop` = |x| of the box centre where the
## formula stops it at a track end.
func dress(experiment: Node3D, box_body: RigidBody3D, box_visual: MeshInstance3D, box_size: float, stop: float) -> void:
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.8))
	_stop = stop
	bumpers = MeshInstance3D.new()
	bumpers.name = "Bumpers"
	bumpers.material_override = ArtKit.lit_material()
	bumpers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	experiment.add_child(bumpers)
	gauge = ForceGauge.new()
	experiment.add_child(gauge)
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


## The box looks `k` times its body's size: the juice's look and the bumpers BUMPER_GAP beyond
## where the look stops.
func set_look(k: float) -> void:
	_look = k
	juice.set_look_scale(k)
	var face := snappedf(_stop + k * _box_size * 0.5 + BUMPER_GAP, 0.001)
	if not _bumper_meshes.has(face):
		_bumper_meshes[face] = bumper_mesh(face)
	bumpers.mesh = _bumper_meshes[face]


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


## The push gauge beside the box at `box_center` (its body's centre): shown while `held`, filled to
## `fraction` of the most a hold gives.
func show_gauge(box_center: Vector3, held: bool, fraction: float) -> void:
	if gauge == null:
		return
	gauge.visible = held
	if not held:
		return
	gauge.set_fraction(fraction)
	gauge.global_position = Vector3(box_center.x + _look * _box_size * 0.5 + GAUGE_GAP + ForceGauge.WIDTH * 0.5, 0.05, box_center.z)


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
