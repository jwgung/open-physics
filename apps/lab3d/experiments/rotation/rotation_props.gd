## Grass island props of the lever lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the beam, the load, the fulcrum stand and the handle are bodies built and posed by
## rotation.gd; nothing here moves a body.
## - the static base (one mesh): a yellow board on the grass and the blue rest block under the beam's
##   left end (the load side rests on it until the lever lifts),
## - the beam (yellow, white ticks every 0.5 m) under the beam body; the three effort points on it
##   (white pegs, the chosen one red, rebuilt when the fulcrum or the choice changes),
## - the fulcrum stand: a blue triangular prism with its blob shadow, under the stand body,
## - the orange load box (the web's load colour) with its ArtJuice; the red handle grip, and a white
##   rod from the grip down to the effort point on the beam (posed each frame),
## - arrows: the red force on the beam at the effort point (down) and the orange weight of the load,
##   FORCE_SCALE m per N (at most ARROW_MAX m),
## - reactions: lifted = the load stretches; back down = a small squash; reset = pop.
class_name RotationProps
extends RefCounted

const BEAM_COLOR := ArtPalette.YELLOW
const FORCE_SCALE := 0.006        # m of arrow per N
const ARROW_MAX := 2.4
const ROD_RADIUS := 0.04

var juice: ArtJuice
var markers: MeshInstance3D
var rod: MeshInstance3D
var force_arrow: VelocityArrow
var weight_arrow: VelocityArrow
var _marker_key := Vector4(INF, INF, INF, INF)   # the three points and the chosen one


## Base board and the rest block under the beam's left end (top at `rest_top`).
static func base_mesh(beam_half: float, rest_x: float, rest_top: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -0.028, 0.0)), Vector3(beam_half * 2.0 + 1.6, 0.06, 2.4), 0.02, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	b.ao_min = 0.8
	b.ao_height = 0.6
	b.add_rounded_box(Transform3D(Basis(), Vector3(rest_x, rest_top * 0.5, 0.0)), Vector3(0.5, rest_top, 0.7), 0.05, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	return b.commit()


## The beam around its centre: `half` long either way, `thick` high, `depth` deep, ticks every 0.5 m.
static func beam_mesh(half: float, thick: float, depth: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.85
	b.ao_height = thick
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), Vector3(half * 2.0, thick, depth), 0.04, 1, BEAM_COLOR, ArtPalette.YELLOW_TOP)
	b.ao_min = 1.0
	var x := -half + 0.5
	while x <= half - 0.49:
		var long := is_zero_approx(fmod(absf(x), 1.0))
		b.add_rounded_box(Transform3D(Basis(), Vector3(x, thick * 0.5 + 0.006, depth * 0.5 - (0.12 if long else 0.07))), Vector3(0.035, 0.012, 0.24 if long else 0.14), 0.0, 1, ArtPalette.WHITE)
		x += 0.5
	return b.commit()


## The three effort points (beam-local x) as pegs on the beam's front; `chosen` is red.
static func marker_mesh(points: Array[float], chosen: int, thick: float, depth: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	for i in points.size():
		var big := i == chosen
		var r := 0.11 if big else 0.08
		b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(points[i], 0.0, depth * 0.5)), r, r, 0.05, 8, ArtPalette.RED if big else ArtPalette.WHITE)
		b.add_rounded_box(Transform3D(Basis(), Vector3(points[i], thick * 0.5 + 0.01, 0.0)), Vector3(0.06, 0.02, depth - 0.04), 0.0, 1, ArtPalette.RED if big else ArtPalette.WHITE)
	return b.commit()


## The fulcrum: a triangular prism `height` high (apex up, `depth` deep along z) on a foot plate.
static func stand_mesh(height: float, depth: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.75
	b.ao_height = height
	# A 3-sided cylinder turned to lie along z with a corner up: circumradius r puts the apex at r
	# above its axis and the base r / 2 below it (height 1.5 r, base width sqrt(3) r).
	var r := height / 1.5
	var turn := Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)
	b.add_cylinder(Transform3D(turn, Vector3(0.0, r * 0.5, -depth * 0.5)), r, r, depth, 3, ArtPalette.BLUE, true, ArtPalette.BLUE_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.05, 0.0)), Vector3(sqrt(3.0) * r + 0.2, 0.1, depth + 0.2), 0.03, 1, ArtPalette.BLUE_DARK)
	return b.commit()


static func load_mesh(size: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = size
	b.add_rounded_box(Transform3D.IDENTITY, Vector3.ONE * size, 0.07, 1, ArtPalette.ORANGE, ArtPalette.ORANGE_TOP)
	return b.commit()


static func grip_mesh(size: Vector3) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D.IDENTITY, size, 0.08, 1, ArtPalette.RED, ArtPalette.RED_TOP)
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, size.y * 0.5 + 0.005, 0.0)), Vector3(size.x * 0.6, 0.01, 0.06), 0.0, 1, ArtPalette.WHITE)
	return b.commit()


func dress(experiment: Node3D, parts: Dictionary, sizes: Dictionary) -> void:
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.6))
	var base := ArtKit.instance(base_mesh(sizes.beam_half, sizes.rest_x, sizes.rest_top))
	base.name = "Base"
	experiment.add_child(base)
	var beam_visual := ArtKit.instance(beam_mesh(sizes.beam_half, sizes.beam_thick, sizes.beam_depth))
	beam_visual.name = "Visual"
	parts.beam.add_child(beam_visual)
	markers = MeshInstance3D.new()
	markers.name = "EffortPoints"
	markers.material_override = ArtKit.lit_material()
	parts.beam.add_child(markers)
	var stand_visual := ArtKit.instance(stand_mesh(sizes.stand_height, sizes.beam_depth * 0.8))
	stand_visual.name = "Visual"
	stand_visual.position.y = -sizes.stand_height * 0.5   # the stand body's centre is half its height up
	parts.stand.add_child(stand_visual)
	var shadow := ArtKit.shadow_builder()
	shadow.add_soft_rect(Transform3D(Basis(), Vector3(0.0, 0.012 - sizes.stand_height * 0.5, 0.0)), Vector2(0.75, 0.55), 0.25, ArtKit.shadow_alpha())
	var stand_shadow := ArtKit.instance(shadow.commit(), ArtKit.shadow_material())
	stand_shadow.name = "Shadow"
	parts.stand.add_child(stand_shadow)
	var load_visual := ArtKit.instance(load_mesh(sizes.load_size))
	load_visual.name = "Visual"
	parts.load.add_child(load_visual)
	juice = ArtJuice.new()
	juice.name = "LoadJuice"
	juice.dust_amount = 10
	experiment.add_child(juice)
	juice.setup(parts.load, load_visual, sizes.load_size)
	var grip := ArtKit.instance(grip_mesh(sizes.handle))
	grip.name = "Visual"
	parts.handle.add_child(grip)
	rod = ArtKit.instance(ArtKit.link_mesh(ROD_RADIUS, ArtPalette.WHITE))
	rod.name = "HandleRod"
	experiment.add_child(rod)
	force_arrow = VelocityArrow.new(ArtPalette.RED, ArtPalette.RED_TOP)
	force_arrow.name = "ForceArrow"
	experiment.add_child(force_arrow)
	weight_arrow = VelocityArrow.new(ArtPalette.ORANGE, ArtPalette.ORANGE_TOP)
	weight_arrow.name = "WeightArrow"
	experiment.add_child(weight_arrow)


## The effort pegs for beam-local points `points` (rebuilt only when they or the choice changed).
func show_markers(points: Array[float], chosen: int, thick: float, depth: float) -> void:
	var key := Vector4(points[0], points[1], points[2], chosen)
	if key == _marker_key:
		return
	_marker_key = key
	markers.mesh = marker_mesh(points, chosen, thick, depth)


## The rod from the grip's bottom `grip_bottom` to the effort point `effort`; the force arrow above
## the effort point (`force` N, down) and the weight arrow below the load centre (`weight` N).
func show_forces(grip_bottom: Vector3, effort: Vector3, force: float, load_centre: Vector3, load_half: float, weight: float) -> void:
	ArtKit.stretch_link(rod, grip_bottom, effort)
	force_arrow.visible = force >= 0.5
	if force_arrow.visible:
		var l := minf(ARROW_MAX, snappedf(force * FORCE_SCALE, 0.02))
		force_arrow.point(effort + Vector3(0.0, l + 0.08, 0.35), -90.0, l)
	var w := minf(ARROW_MAX, snappedf(weight * FORCE_SCALE, 0.02))
	weight_arrow.point(load_centre + Vector3(0.0, 0.0, load_half + 0.12), -90.0, w)


func lifted() -> void:
	if juice != null:
		juice.stretch()


func lowered() -> void:
	if juice != null:
		juice.settle()


func reset() -> void:
	if juice != null:
		juice.pop()


func status_changed(previous: String, current: String) -> void:
	if current == "lifted":
		lifted()
	elif previous == "lifted":
		lowered()
