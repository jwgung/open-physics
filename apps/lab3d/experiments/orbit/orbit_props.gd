## Grass island props of the orbit lab (apps/lab3d/docs/art-direction.md, section 9): a small "space"
## stage on the island with the orbit floating above it. Meshes and reactions only: the planet and
## knob bodies are built and posed by orbit.gd.
## - the stage: a deep blue disk (SPACE) on the grass with white and yellow star dots, and a blue
##   pedestal holding the big yellow star at the orbit's height,
## - the blue planet (a yarn ball, Task 4g; a white band before), its ArtJuice (shadow on the stage, squash, pop),
## - a white dashed circle at the start radius in the orbit plane (the circular orbit),
## - the predicted path of OrbitChallenge (the web's dashed path) as dots in the outcome's colour:
##   green orbit, red crash, purple escape (the web's colours),
## - the purple velocity arrow (to the yellow knob while waiting, the planet's velocity in flight) and
##   the red gravity arrow towards the star in flight (0.15 m per m/s^2),
## - reactions: launch = stretch; crash = bump towards the star; reset = pop.
class_name OrbitProps
extends RefCounted

const STAGE_RADIUS := 7.5
const PATH_DOTS := 90
const DOT_RADIUS := 0.06
const GRAVITY_SCALE := 0.15      # m of arrow per m/s^2
const GRAVITY_MAX := 2.5
const DASHES := 48

var juice: ArtJuice
var guide: MultiMeshInstance3D
var path: MultiMeshInstance3D
var velocity_arrow: VelocityArrow
var gravity_arrow: VelocityArrow
var knob_visual: Node3D
## World positions of the shown path dots (the MultiMesh keeps them on the rendering server).
var dots := PackedVector3Array()
var _dots := {}                  # outcome -> dot mesh in its colour
var _plane_y := 1.6
var _guide_radius := -1.0


static func stage_mesh(star_y: float, star_radius: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.95
	b.ao_height = 0.2
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, -0.05, 0.0)), STAGE_RADIUS, STAGE_RADIUS, 0.058, 28, ArtPalette.SPACE, true, ArtPalette.SPACE_TOP)
	b.ao_min = 1.0
	# Star dots: a fixed scatter (golden angle spiral), white and yellow.
	for i in 70:
		var r := STAGE_RADIUS * 0.95 * sqrt((i + 0.5) / 70.0)
		var a := i * 2.399963
		var color := ArtPalette.YELLOW if i % 5 == 0 else ArtPalette.WHITE
		var s := 0.07 if i % 5 == 0 else 0.045
		b.add_rounded_box(Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * r, 0.012, sin(a) * r)), Vector3(s, 0.012, s), 0.0, 1, color)
	# The star's pedestal and the star.
	b.ao_min = 0.85
	b.ao_height = 0.6
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), 0.45, 0.35, 0.12, 10, ArtPalette.BLUE_DARK)
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, 0.1, 0.0)), 0.12, 0.12, star_y - star_radius - 0.05, 8, ArtPalette.BLUE)
	b.ao_min = 1.0
	b.add_sphere(Transform3D(Basis(), Vector3(0.0, star_y, 0.0)), star_radius, 6, 10, ArtPalette.YELLOW)
	return b.commit()


## One dash of the guide circle: 1 m long (x), 0.03 m tall, 0.05 m wide; each instance stretches
## it along x to its length (guide_dash).
static func dash_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D.IDENTITY, Vector3(1.0, 0.03, 0.05), 0.0, 1, ArtPalette.WHITE)
	return b.commit()


## Dash `i` of the dashed circle of `radius` around the origin (level): DASHES dashes, each 55 % of
## its arc, along the circle. A transform of the one dash mesh (moving the circle to another radius
## sets DASHES transforms instead of building a mesh: SM-P200 spent 18-39 ms per guide mesh while the
## planet was dragged, 2026-10-24).
static func guide_dash(i: int, radius: float) -> Transform3D:
	var a := TAU * i / DASHES
	var dash := TAU * radius / DASHES * 0.55
	return Transform3D(Basis(Vector3.UP, -a + PI * 0.5).scaled_local(Vector3(dash, 1.0, 1.0)), Vector3(cos(a) * radius, 0.0, sin(a) * radius))


static func dot_mesh(color: Color) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_sphere(Transform3D.IDENTITY, DOT_RADIUS, 3, 5, color)
	return b.commit()


func dress(experiment: Node3D, planet: RigidBody3D, planet_radius: float, knob: Node3D, star_y: float, star_radius: float) -> void:
	_plane_y = star_y
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.5), Vector3.ZERO, 0.6)
	var stage := ArtKit.instance(stage_mesh(star_y, star_radius))
	stage.name = "Stage"
	experiment.add_child(stage)
	var visual := Node3D.new()   # the juice squashes this node; the planet is a yarn ball (Task 4g)
	visual.name = "Visual"
	planet.add_child(visual)
	var yarn := ArtKit.yarn_ball(planet_radius, ArtPalette.BLUE)
	yarn.name = "Yarn"
	visual.add_child(yarn)
	juice = ArtJuice.new()
	juice.name = "PlanetJuice"
	juice.round_body = true
	juice.dust_amount = 10
	experiment.add_child(juice)
	juice.setup(planet, visual, planet_radius * 2.0)
	var guide_multimesh := MultiMesh.new()
	guide_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	guide_multimesh.mesh = dash_mesh()
	guide_multimesh.instance_count = DASHES
	guide_multimesh.visible_instance_count = 0
	guide = MultiMeshInstance3D.new()
	guide.name = "Guide"
	guide.multimesh = guide_multimesh
	guide.material_override = ArtKit.lit_material()
	guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	experiment.add_child(guide)
	for outcome in [["orbit", ArtPalette.LEAF], ["crash", ArtPalette.RED], ["escape", ArtPalette.PURPLE]]:
		_dots[outcome[0]] = dot_mesh(outcome[1])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _dots.orbit
	multimesh.instance_count = PATH_DOTS
	multimesh.visible_instance_count = 0
	path = MultiMeshInstance3D.new()
	path.name = "PredictedPath"
	path.multimesh = multimesh
	path.material_override = ArtKit.lit_material()
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	experiment.add_child(path)
	velocity_arrow = VelocityArrow.new()
	velocity_arrow.name = "VelocityArrow"
	experiment.add_child(velocity_arrow)
	gravity_arrow = VelocityArrow.new(ArtPalette.RED, ArtPalette.RED_TOP)
	gravity_arrow.name = "GravityArrow"
	gravity_arrow.visible = false
	experiment.add_child(gravity_arrow)
	knob_visual = knob.get_node("Visual")


## The dashed circular-orbit guide at `radius` (moved only when the radius changes).
func set_guide(radius: float) -> void:
	if guide == null or radius == _guide_radius:
		return
	_guide_radius = radius
	for i in DASHES:
		guide.multimesh.set_instance_transform(i, guide_dash(i, radius))
	guide.multimesh.visible_instance_count = DASHES
	guide.position = Vector3(0.0, _plane_y, 0.0)


## The predicted path (plane points [x0, z0, x1, z1, ...] of OrbitChallenge) as at most PATH_DOTS
## evenly picked dots in the outcome's colour.
func set_path(points: PackedFloat64Array, outcome: String) -> void:
	if path == null:
		return
	var multimesh := path.multimesh
	multimesh.mesh = _dots.get(outcome, _dots.orbit)
	var n := points.size() / 2
	var count := mini(n, PATH_DOTS)
	dots.resize(count)
	for i in count:
		var k := 0 if count == 1 else int(roundf(float(i) * (n - 1) / (count - 1)))
		dots[i] = Vector3(points[2 * k], _plane_y, points[2 * k + 1])
		multimesh.set_instance_transform(i, Transform3D(Basis(), dots[i]))
	multimesh.visible_instance_count = count


## The velocity arrow from the planet centre `at` along (vx, vz) with `length` m; hidden when 0.
func show_velocity(at: Vector3, vx: float, vz: float, length: float) -> void:
	velocity_arrow.visible = length > 0.0 and (vx != 0.0 or vz != 0.0)
	if velocity_arrow.visible:
		velocity_arrow.point_along(at, Vector3(vx, 0.0, vz), snappedf(length, 0.02))


## In flight: the gravity arrow from the planet towards the star (acceleration `a` m/s^2).
func show_gravity(at: Vector3, towards: Vector3, a: float) -> void:
	gravity_arrow.visible = a > 0.0
	if gravity_arrow.visible:
		gravity_arrow.point_along(at, towards - at, snappedf(minf(a * GRAVITY_SCALE, GRAVITY_MAX), 0.02))


func hide_gravity() -> void:
	if gravity_arrow != null:
		gravity_arrow.visible = false


func launched() -> void:
	knob_visual.visible = false
	juice.stretch()


## Picked up (in flight or waiting): the waiting look again, the yellow knob back and no gravity arrow.
func picked_up() -> void:
	if juice == null:
		return
	knob_visual.visible = true
	hide_gravity()


func reset() -> void:
	if juice == null:
		return
	knob_visual.visible = true
	gravity_arrow.visible = false
	juice.pop()


## The planet hit the star (from the direction `towards_star`).
func crashed(towards_star: Vector3) -> void:
	if juice != null:
		juice.bump(towards_star, 0.8)
