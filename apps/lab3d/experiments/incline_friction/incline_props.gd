## Grass island props of the incline experiment (apps/lab3d/docs/art-direction.md, section 9).
## Meshes only: the collision boxes of the incline, floor and box are built by incline_friction.gd
## and are not changed here. Yellow incline (thicker than its collision box, growing downwards so
## the top face stays on the collision surface), blue stand, red box, white start line, the island
## and the blob shadows, and the box's reactions (ArtJuice) driven by the experiment's status.
class_name InclineProps
extends RefCounted

const INCLINE_THICKNESS := 0.5      # visual thickness (the collision box is 0.3 m)
const STAND_WIDTH := 0.5
const STAND_Z := -0.7
const AXLE_RADIUS := 0.34           # the hinge axle under the incline (z direction)
const AXLE_DEPTH := 0.68            # axle centre below the incline's top face / pivot (incline-local, m)
const AXLE_LENGTH := 1.0
const POST_INSET := 0.1             # the post top sits this far short of the axle centre

var juice: ArtJuice
var _ramp_shadow: MeshInstance3D
var _incline_length := 8.0


func incline_mesh(size: Vector3) -> Mesh:
	_incline_length = size.x
	var b := ArtKit.builder()
	b.ao_min = 0.85
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, (size.y - INCLINE_THICKNESS) * 0.5, 0.0)),
		Vector3(size.x, INCLINE_THICKNESS, size.z), 0.06, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
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


## Post from its foot centre to just short of the axle centre: z rotation (rad) and the length.
## The axle circle then always contains the post top (half width 0.25 < AXLE_RADIUS).
static func post_pose(pivot_height: float, angle_deg: float) -> Vector2:
	var c := axle_offset(angle_deg)
	var to_axle := Vector2(c.x, pivot_height + c.y)
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


## Half length of the incline shadow's inner rectangle at this angle.
func _ramp_shadow_half(angle_deg: float) -> float:
	return _incline_length * 0.5 * cos(deg_to_rad(angle_deg)) - 0.3


## The incline casts a soft shadow straight below it (its footprint shrinks as it tilts): the mesh
## made in dress() is scaled along x, not rebuilt.
func angle_changed(angle_deg: float) -> void:
	if _ramp_shadow == null:
		return
	_ramp_shadow.scale.x = _ramp_shadow_half(angle_deg) / _ramp_shadow_half(0.0)


## Experiment status change -> reactions: placed = pop, let go = stretch, starts sliding = puff.
func status_changed(previous: String, status: String) -> void:
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
