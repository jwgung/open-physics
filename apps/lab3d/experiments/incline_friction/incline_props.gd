## Grass island props of the incline experiment (apps/lab3d/docs/art-direction.md, section 9).
## Meshes only: the collision boxes of the incline, floor and box are built by incline_friction.gd
## and are not changed here. Yellow incline (thicker than its collision box, growing downwards so
## the top face stays on the collision surface) made of the chosen surface material (set_surface,
## 2026-10-28: the whole slide is steel grey, wood brown, rubber dark or clay red, its top and its
## front face patterned like that stuff, SurfaceSkin: the front view sees the slide from the side),
## blue stand, red box, white start line, the island and the blob shadows, and the box's reactions
## (ArtJuice) driven by the experiment's status.
## The bread cat (CatActor wearing the BreadCat look, 2026-10-27) stands on the incline beside the
## waiting box (behind it, clear of its way down, a little below it), level on a wooden wedge cut to the slope, and
## holds the box with both paws on its top; "상자 놓기" lets go (the paws follow down the slope); a
## finger holding the box: it stands by. It cheers when the run's result comes (the box stays, or
## it has run off the incline). Only meshes: the box slides as Jolt and the correction layer say.
class_name InclineProps
extends RefCounted

const INCLINE_THICKNESS := 0.5      # visual thickness (the collision box is 0.3 m)
const STAND_WIDTH := 0.5
const STAND_Z := -0.7
const AXLE_RADIUS := 0.34           # the hinge axle under the incline (z direction)
const AXLE_DEPTH := 0.68            # axle centre below the incline's top face / pivot (incline-local, m)
const AXLE_LENGTH := 1.0
const POST_INSET := 0.1             # the post top sits this far short of the axle centre
const POST_MIN := 0.25              # a shorter post (a nearly flat slide, its hinge at the ground) is hidden
## The cat: its base z (behind the box, on the 2 m wide incline), its paws on the box top near its
## back edge (z) either side of its middle (along the incline), the wedge's rim beyond its bag and
## how deep the wedge reaches into the slope (no gap at its low corner).
const CAT_Z := -0.72
const CAT_PAW_Z := -0.12
const CAT_PAW_HALF := 0.12
## m along the incline below the box's middle, more on a steeper slope (lower: in the front view,
## a shorter reach up to the box).
const CAT_DOWNHILL := 0.35
const CAT_DOWNHILL_STEEP := 0.6   # more, times sin(angle)
const CAT_LEAN_MAX := 30.0        # deg: the bag stays behind the box (the arms reach the rest)
const WEDGE_RIM := 0.03
const WEDGE_SINK := 0.04

var juice: ArtJuice
var cat: CatActor
var wedge: MeshInstance3D
var _ramp_shadow: MeshInstance3D
var _incline_length := 8.0
var _wedge_angle := NAN             # the slope the wedge mesh was cut for (deg)
## The incline's mesh node and the surface material it shows (set_surface).
var incline_visual: MeshInstance3D
var surface := ""
var _incline_size := Vector3.ZERO
var _incline_meshes := {}           # material id -> mesh


## The incline (mesh origin = the collision box's centre, its top face at size.y / 2) made of
## surface material `material`: its colour, and its pattern on the top and the front (+z) face.
func incline_mesh(size: Vector3, material := "wood") -> Mesh:
	_incline_length = size.x
	var b := ArtKit.builder()
	b.ao_min = 0.85
	var stuff := SurfaceSkin.colour(material)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, (size.y - INCLINE_THICKNESS) * 0.5, 0.0)),
		Vector3(size.x, INCLINE_THICKNESS, size.z), 0.06, 1, stuff, stuff.lerp(Color.WHITE, 0.12))
	SurfaceSkin.add_to(b, Transform3D(Basis(), Vector3(0.0, size.y * 0.5, 0.0)), material, size.x - 0.2, size.z - 0.2)
	# The front face: the skin turned to face +z (its "up"), across the incline's thickness.
	var front := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, size.y * 0.5 - INCLINE_THICKNESS * 0.5, size.z * 0.5))
	SurfaceSkin.add_to(b, front, material, size.x - 0.2, INCLINE_THICKNESS - 0.12)
	# Hinge: two lugs from the underside to a white axle, all tilting with the incline. The post top
	# ends inside the axle's circle, so there is no gap and no crossing at any angle.
	var axle_y := -AXLE_DEPTH + size.y * 0.5          # mesh space: the node sits size.y / 2 under the pivot
	var under_y := -INCLINE_THICKNESS + size.y * 0.5
	var lug_h := under_y - axle_y + 0.12
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, under_y - lug_h * 0.5 + 0.05, STAND_Z + side * 0.4)),
			Vector3(0.3, lug_h + 0.1, 0.14), 0.03, 1, ArtPalette.BLUE)
	b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, axle_y, STAND_Z + AXLE_LENGTH * 0.5)),
		AXLE_RADIUS, AXLE_RADIUS, AXLE_LENGTH, 8, ArtPalette.WHITE)
	return b.commit()


## The incline's node (its mesh) for an incline of `size`; set_surface swaps its mesh.
func make_incline(size: Vector3, material: String) -> MeshInstance3D:
	_incline_size = size
	incline_visual = ArtKit.instance(null)
	incline_visual.name = "InclineVisual"
	set_surface(material)
	return incline_visual


## The incline's top shows surface material `material` (one mesh per material, cached).
func set_surface(material: String) -> void:
	surface = material
	if incline_visual == null:
		return
	if not _incline_meshes.has(material):
		_incline_meshes[material] = incline_mesh(_incline_size, material)
	incline_visual.mesh = _incline_meshes[material]


func start_line_mesh(width: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.005, 0.0)), Vector3(0.07, 0.02, width - 0.25), 0.009, 1, ArtPalette.WHITE)
	return b.commit()


## Tick positions along the incline (pivot x): every multiple of `step` m from the pivot (the grid
## the box snaps to), not at the two ends.
static func tick_positions(length: float, step: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if step <= 0.0:
		return result
	var first := int(ceilf((-length * 0.5 + 1e-4) / step))
	var last := int(floorf((length * 0.5 - 1e-4) / step))
	for i in range(first, last + 1):
		result.append(i * step)
	return result


## Scale ticks along the front edge of the incline's top face (incline-local, the pivot frame):
## a short mark at each tick position, a longer one at every whole metre. Visual only.
func ticks_mesh(length: float, width: float, step: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	for x in tick_positions(length, step):
		var metres := absf(x)
		var whole := is_equal_approx(metres, roundf(metres))
		var depth := 0.34 if whole else 0.18
		b.add_rounded_box(Transform3D(Basis(), Vector3(x, 0.005, width * 0.5 - 0.06 - depth * 0.5)),
			Vector3(0.05, 0.02, depth), 0.0, 1, ArtPalette.WHITE)   # flat marks: no bevel (36 vertices each)
	return b.commit()


## Round foot on the ground (the post is a separate mesh that leans, see post_pose).
func foot_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = 0.12
	b.add_cylinder(Transform3D.IDENTITY, 0.75, 0.62, 0.16, 8, ArtPalette.BLUE_DARK)
	return b.commit()


## Post of `height` from the ground up (scaled/leaned along its axis by post_pose).
func post_mesh(height: float) -> Mesh:
	var b := ArtKit.builder()
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, height * 0.5, 0.0)), Vector3(STAND_WIDTH, height, STAND_WIDTH), 0.05, 2, ArtPalette.BLUE)
	return b.commit()


## Hinge axle centre relative to the pivot in the xy plane at this incline angle (it tilts with it).
static func axle_offset(angle_deg: float) -> Vector2:
	var t := deg_to_rad(angle_deg)
	return Vector2(AXLE_DEPTH * sin(t), -AXLE_DEPTH * cos(t))


## Post from its foot centre to just short of the axle centre (`pivot` is the pivot from the foot,
## x/y): z rotation (rad) and the length. The axle circle then always contains the post top (half
## width 0.25 < AXLE_RADIUS).
static func post_pose(pivot: Vector3, angle_deg: float) -> Vector2:
	var c := axle_offset(angle_deg)
	var to_axle := Vector2(pivot.x + c.x, pivot.y + c.y)
	return Vector2(-atan2(to_axle.x, to_axle.y), to_axle.length() - POST_INSET)


## Island, static shadows, the incline's moving shadow and the box reactions.
func dress(experiment: Node3D, stand_position: Vector3, box_body: RigidBody3D, box_visual: MeshInstance3D, box_size: float) -> void:
	ArtKit.add_world(experiment, Vector3(-1.5, 0.0, -0.8), stand_position, 0.9)
	# One mesh at the flat incline's footprint; angle_changed only scales it along x.
	var s := ArtKit.shadow_builder()
	s.add_soft_rect(Transform3D(Basis(), Vector3(0.0, 0.01, 0.0)), Vector2(_ramp_shadow_half(0.0), 0.7), 0.7, ArtKit.shadow_alpha(0.45))
	_ramp_shadow = ArtKit.instance(s.commit(), ArtKit.shadow_material())
	_ramp_shadow.name = "InclineShadow"
	experiment.add_child(_ramp_shadow)
	juice = ArtJuice.new()
	juice.name = "BoxJuice"
	experiment.add_child(juice)
	juice.setup(box_body, box_visual, box_size)
	cat = CatActor.new(BreadCat.new())
	cat.look_target = box_body
	wedge = ArtKit.instance(wedge_mesh(cat.look.footprint, 0.0))
	wedge.name = "CatWedge"
	wedge.visible = false
	experiment.add_child(wedge)
	experiment.add_child(cat)


## A wooden wedge under a `footprint` wide base: its top level at y = 0 (the node's origin, under the
## middle of the base), its bottom cut to a slope rising along +x at `angle_deg` that passes through
## the top's +x edge (WEDGE_SINK lower: into the slope).
static func wedge_mesh(footprint: Vector2, angle_deg: float) -> Mesh:
	var size := Vector2(footprint.x + WEDGE_RIM * 2.0, footprint.y + WEDGE_RIM * 2.0)
	var t := tan(deg_to_rad(angle_deg))
	var height := t * size.x + WEDGE_SINK
	var b := ArtKit.builder()
	b.ao_min = 0.85
	b.ao_height = 0.4
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -height * 0.5, 0.0)), Vector3(size.x, height, size.y), 0.0, 1, ArtPalette.CRATE, ArtPalette.CRATE_TOP)
	var mesh := b.commit()
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		if v[i].y < -height + 1e-4:   # a bottom corner: onto the slope
			v[i].y = -t * (size.x * 0.5 - v[i].x) - WEDGE_SINK
	arrays[Mesh.ARRAY_VERTEX] = v
	var cut := ArrayMesh.new()
	cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return cut


## The cat beside the waiting box (incline `pivot`, the box `box` m centred `start_x` along it at
## `angle_deg`): it holds the box (`grip`) or stands by, level on its wedge.
func place_cat(pivot: Transform3D, start_x: float, box: float, angle_deg: float, grip: bool) -> void:
	if cat == null:
		return
	var at := pivot * Vector3(start_x - CAT_DOWNHILL - CAT_DOWNHILL_STEEP * sin(deg_to_rad(angle_deg)), 0.0, 0.0)
	var t := tan(deg_to_rad(angle_deg))
	var edge := at.x + cat.look.footprint.x * 0.5 + WEDGE_RIM
	# The slope's top face under the base's uphill edge: the base rests there, level.
	var root := Vector3(at.x, pivot.origin.y + (edge - pivot.origin.x) * t, CAT_Z)
	if grip:
		var targets: Array[Vector3] = [pivot * Vector3(start_x - CAT_PAW_HALF, box, CAT_PAW_Z), pivot * Vector3(start_x + CAT_PAW_HALF, box, CAT_PAW_Z)]
		cat.grab(root, 0.0, targets, 0.0, CAT_LEAN_MAX)
	else:
		cat.let_go(Vector3.ZERO)
		cat.position = root
	if not is_equal_approx(angle_deg, _wedge_angle):
		_wedge_angle = angle_deg
		wedge.mesh = wedge_mesh(cat.look.footprint, angle_deg)
	wedge.position = root
	wedge.visible = t * cat.look.footprint.x > 0.02


## The box was let go down the slope (world direction `downhill`).
func cat_let_go(downhill: Vector3) -> void:
	if cat != null:
		cat.let_go(downhill)


## Half length of the incline shadow's inner rectangle at this angle.
func _ramp_shadow_half(angle_deg: float) -> float:
	return _incline_length * 0.5 * cos(deg_to_rad(angle_deg)) - 0.3


## The incline casts a soft shadow straight below it (its footprint shrinks as it tilts and its
## middle `middle_x` moves, the lower end staying put): the mesh made in dress() is scaled along x
## and moved, not rebuilt.
func angle_changed(angle_deg: float, middle_x: float) -> void:
	if _ramp_shadow == null:
		return
	_ramp_shadow.scale.x = _ramp_shadow_half(angle_deg) / _ramp_shadow_half(0.0)
	_ramp_shadow.position.x = middle_x


## Experiment status change -> reactions: placed = pop, let go = stretch, starts sliding = puff.
func status_changed(previous: String, status: String) -> void:
	# The run's result: the box stays where it was let go, or it has run off the incline.
	if cat != null and ((status == "holding" and previous == "ready") or status == "left"):
		cat.cheer()
	if juice == null:
		return
	match status:
		"ready":
			juice.pop()
		"holding", "sliding":
			if previous == "ready":
				juice.stretch()
			if status == "sliding":
				juice.puff(0.6)
