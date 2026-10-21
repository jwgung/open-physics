## Grass island props of the incline experiment (apps/lab3d/docs/art-direction.md, section 7).
## Meshes only: the collision boxes of the incline, floor and box are built by incline_friction.gd
## and are not changed here. Yellow incline (thicker than its collision box, growing downwards so
## the top face stays on the collision surface), blue stand, red box, white start line, the island
## and the blob shadows, and the box's reactions (ArtJuice) driven by the experiment's status.
class_name InclineProps
extends RefCounted

const INCLINE_THICKNESS := 0.5      # visual thickness (the collision box is 0.3 m)
const STAND_WIDTH := 0.5
const STAND_Z := -0.7

var juice: ArtJuice
var _ramp_shadow: MeshInstance3D
var _incline_length := 8.0
var _last_status := ""


func incline_mesh(size: Vector3) -> Mesh:
	_incline_length = size.x
	var b := ArtKit.builder()
	b.ao_min = 0.85
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, (size.y - INCLINE_THICKNESS) * 0.5, 0.0)),
		Vector3(size.x, INCLINE_THICKNESS, size.z), 0.06, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	return b.commit()


func start_line_mesh(width: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.005, 0.0)), Vector3(0.07, 0.02, width - 0.25), 0.009, 1, ArtPalette.WHITE)
	return b.commit()


## Post from the ground to just under the pivot, with a round foot.
func stand_mesh(height: float) -> Mesh:
	var b := ArtKit.builder()
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, height * 0.5, 0.0)), Vector3(STAND_WIDTH, height, STAND_WIDTH), 0.05, 2, ArtPalette.BLUE)
	b.ao_height = 0.12
	b.add_cylinder(Transform3D.IDENTITY, 0.75, 0.62, 0.16, 8, ArtPalette.BLUE_DARK)
	return b.commit()


func box_mesh(size: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = size * 0.6
	b.add_rounded_box(Transform3D.IDENTITY, Vector3.ONE * size, 0.05, 1, ArtPalette.RED, ArtPalette.RED_TOP)
	return b.commit()


## Island, static shadows, the incline's moving shadow and the box reactions.
func dress(experiment: Node3D, stand_position: Vector3, box_body: RigidBody3D, box_visual: MeshInstance3D, box_size: float) -> void:
	experiment.add_child(ArtKit.make_environment())
	ArtKit.build_island(experiment, Vector3(-1.5, 0.0, -0.8), func(s: ArtMeshBuilder) -> void:
		s.add_blob(Transform3D(Basis(), Vector3(stand_position.x, 0.012, stand_position.z)), 0.9, ArtKit.shadow_alpha(0.9)))
	_ramp_shadow = ArtKit.instance(ArrayMesh.new(), ArtKit.shadow_material())
	_ramp_shadow.name = "InclineShadow"
	experiment.add_child(_ramp_shadow)
	juice = ArtJuice.new()
	juice.name = "BoxJuice"
	experiment.add_child(juice)
	juice.setup(box_body, box_visual, box_size)


## The incline casts a soft shadow straight below it (its footprint shrinks as it tilts).
func angle_changed(angle_deg: float) -> void:
	if _ramp_shadow == null:
		return
	var s := ArtKit.shadow_builder()
	var half := _incline_length * 0.5 * cos(deg_to_rad(angle_deg))
	s.add_soft_rect(Transform3D(Basis(), Vector3(0.0, 0.01, 0.0)), Vector2(half - 0.3, 0.7), 0.7, ArtKit.shadow_alpha(0.45))
	_ramp_shadow.mesh = s.commit()


## Experiment status -> reactions: placed = pop, let go = stretch, starts sliding = puff.
func status_changed(status: String) -> void:
	if juice == null or status == _last_status:
		return
	var previous := _last_status
	_last_status = status
	match status:
		"ready":
			juice.pop()
		"holding", "sliding":
			if previous == "ready":
				juice.stretch()
			if status == "sliding":
				juice.puff(0.6)
