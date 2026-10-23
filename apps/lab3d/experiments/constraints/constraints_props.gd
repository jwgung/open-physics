## Grass island props of the constraints lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the bobs are built and posed by constraints.gd; nothing here touches a body.
## - the stands (one mesh): for each pendulum a blue post behind its swing plane with an arm forward
##   to the anchor pin, on a yellow board on the grass (the swing plane stays free of the stand),
## - the string (a thin white cord) and the rod (a thick dark-blue bar): one unit-length mesh each,
##   turned and scaled from the anchor to the bob centre every frame (the formula's position),
## - the path of each bob: white dots on its circle of radius L every 5 deg within +-75 deg (built
##   again only when the length changes),
## - the bobs (yarn balls, Task 4g): string bob blue (the web's), rod bob orange (the web's is green, a background colour
##   here: art-direction.md section 2), with an ArtJuice each (shadow, pop, stretch; no landing),
## - reactions: release = stretch; reset = pop.
class_name ConstraintsProps
extends RefCounted

const BOB_SIDES := 7
const CORD_RADIUS := 0.035
const ROD_RADIUS := 0.065
const DOT_SIZE := 0.07
const DOT_STEP_DEG := 5.0
const POST_BACK := 1.1           # m behind the swing plane

var juices: Array[ArtJuice] = []
var links: Array[MeshInstance3D] = []   # [string, rod]
var paths: Array[MeshInstance3D] = []
var _anchors: Array[Vector3] = []
var _path_length := -1.0


## The stands for the anchors (pin at each anchor, post behind it), the board under both.
static func stand_mesh(anchors: Array[Vector3]) -> Mesh:
	var b := ArtKit.builder()
	var left := INF
	var right := -INF
	var back := INF
	var front := -INF
	for a in anchors:
		left = minf(left, a.x)
		right = maxf(right, a.x)
		back = minf(back, a.z - POST_BACK)
		front = maxf(front, a.z)
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3((left + right) * 0.5, -0.028, (back + front) * 0.5 + 0.2)),
		Vector3(right - left + 2.6, 0.06, front - back + 1.6), 0.02, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	for a in anchors:
		var post := Vector3(a.x, 0.0, a.z - POST_BACK)
		var top := a.y + 0.25
		b.ao_min = 0.8
		b.ao_height = 0.6
		b.add_cylinder(Transform3D(Basis(), post), 0.38, 0.32, 0.18, 8, ArtPalette.BLUE_DARK)
		b.add_rounded_box(Transform3D(Basis(), Vector3(post.x, top * 0.5, post.z)), Vector3(0.26, top, 0.26), 0.04, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
		b.ao_min = 1.0
		# The arm forward over the swing plane, a little past the anchor; the pin hangs from it.
		var arm := POST_BACK + 0.35
		b.add_rounded_box(Transform3D(Basis(), Vector3(post.x, top - 0.1, post.z + arm * 0.5 - 0.05)), Vector3(0.24, 0.2, arm + 0.1), 0.04, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
		b.add_cylinder(Transform3D(Basis(), Vector3(a.x, a.y - 0.04, a.z)), 0.07, 0.07, top - 0.2 - a.y + 0.08, 6, ArtPalette.INK)
		b.add_sphere(Transform3D(Basis(), a), 0.09, 3, 6, ArtPalette.WHITE)
	return b.commit()


## The hook on top of a bob (the bob itself is a yarn ball, Task 4g), where the link meets it.
static func hook_mesh(radius: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, radius * 0.85, 0.0)), 0.06, 0.06, 0.12, 6, ArtPalette.INK)
	return b.commit()


## White dots on the circle of radius `length` around the origin in the x-y plane, every
## DOT_STEP_DEG within +-max_deg of straight down.
static func path_mesh(length: float, max_deg: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	var deg := -max_deg
	while deg <= max_deg + 1e-6:
		var a := deg_to_rad(deg)
		var big := is_zero_approx(fmod(absf(deg), 15.0))
		var size := DOT_SIZE * (1.4 if big else 1.0)
		b.add_rounded_box(Transform3D(Basis(Vector3.BACK, a), Vector3(length * sin(a), -length * cos(a), 0.0)), Vector3(size, size, size * 0.5), 0.0, 1, ArtPalette.WHITE)
		deg += DOT_STEP_DEG
	return b.commit()


## Stands, links, paths and bob meshes; `bobs` and `anchors` in the same order (string, rod).
func dress(experiment: Node3D, bobs: Array[RigidBody3D], anchors: Array[Vector3], colors: Array[Color], radius: float) -> void:
	_anchors = anchors
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.6))
	var stand := ArtKit.instance(stand_mesh(anchors))
	stand.name = "Stands"
	experiment.add_child(stand)
	for i in bobs.size():
		var link := ArtKit.instance(ArtKit.link_mesh(CORD_RADIUS if i == 0 else ROD_RADIUS, ArtPalette.WHITE if i == 0 else ArtPalette.BLUE_DARK))
		link.name = "String" if i == 0 else "Rod"
		experiment.add_child(link)
		links.append(link)
		var path := MeshInstance3D.new()
		path.name = "Path%d" % i
		path.position = anchors[i]
		path.material_override = ArtKit.lit_material()
		experiment.add_child(path)
		paths.append(path)
		var visual := Node3D.new()   # the juice squashes this node: a yarn ball (Task 4g) and its hook
		visual.name = "Visual"
		bobs[i].add_child(visual)
		var yarn := ArtKit.yarn_ball(radius, colors[i])
		yarn.name = "Yarn"
		visual.add_child(yarn)
		var hook := ArtKit.instance(hook_mesh(radius))
		hook.name = "Hook"
		visual.add_child(hook)
		var juice := ArtJuice.new()
		juice.name = "BobJuice%d" % i
		juice.round_body = true
		juice.dust_amount = 8
		experiment.add_child(juice)
		juice.setup(bobs[i], visual, radius * 2.0)
		juices.append(juice)


## The paths for the bobs' length (rebuilt only when it changed).
func show_paths(length: float, max_deg: float) -> void:
	if is_equal_approx(length, _path_length):
		return
	_path_length = length
	var mesh := path_mesh(length, max_deg)
	for path in paths:
		path.mesh = mesh


## Link `i` from its anchor to the bob centre `at`.
func stretch_link(i: int, at: Vector3) -> void:
	ArtKit.stretch_link(links[i], _anchors[i], at)


func released() -> void:
	for juice in juices:
		juice.stretch()


func reset() -> void:
	for juice in juices:
		juice.pop()


func status_changed(_previous: String, _current: String) -> void:
	pass
