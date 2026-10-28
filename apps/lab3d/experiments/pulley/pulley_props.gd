## Grass island props of the pulley lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the load and the handle are bodies built and posed by pulley.gd; nothing here
## moves a body.
## - the gantry (one mesh): a yellow board, two blue posts and the top beam with the guide wheel over
##   the pull side,
## - the load (a parcel box) looks as heavy as it is (set_look, 2026-10-28: one stuff, the cube root
##   of its mass against the 20 kg load's 0.8 m, grown from its bottom; the moving block on its top),
## - the fixed pulley block under the beam and the moving block on the load, each with its wheels
##   (n = 1: one fixed wheel; 2: one fixed + one moving; 4: two + two), rebuilt when n changes,
## - the rope (white): the n supporting strands from the fixed block down to the moving block (one
##   mesh, stretched each frame), the run over to the guide wheel (in the fixed block's mesh) and the
##   pull strand down to the red grip (a link posed each frame); the rope pulled in earlier strokes lies coiled on the ground (its height grows
##   with the length),
## - arrows: the orange weight of the load and the red pull of the hand (down), FORCE_SCALE m per N,
## - reactions: lifting off = stretch; set down (reset) = pop.
## - the bread cat (CatActor wearing the BreadCat look, 2026-10-27) under the grip, behind the pull
##   strand: while the finger pulls the grip the cat holds it with both paws and pulls it down with
##   it (it jumps up to the grip and hangs from it while the grip is above its reach, stands and
##   leans back once it is low); letting go it drops back to its spot, cheering when the stroke
##   lifted the load. Only meshes: the rope, the grip and the load are the formula model's.
class_name PulleyProps
extends RefCounted

const WHEEL_RADIUS := 0.2
const WHEEL_DEPTH := 0.12
const ROPE_RADIUS := 0.03
const FORCE_SCALE := 0.006
const ARROW_MAX := 2.4
const BLOCK_DEPTH := 0.3
## The cat's reach to the grip's back face (shoulders -> grip: from below and behind), how hard it
## leans back pulling, and its spot under the grip (x offset, z) when it does not hold it.
const CAT_DIR := Vector3(0.0, 0.45, 0.89)
const CAT_EFFORT := 0.6
const CAT_SPOT_Z := -0.45
const CAT_SPOT_X := -0.15       # m beside the grip (clear of the gantry's post)

var juice: ArtJuice
var fixed_block: MeshInstance3D
var moving_block: MeshInstance3D
var strands: MeshInstance3D               # the n supporting strands: one mesh, 1 m long, scaled to the gap
var pull_link: MeshInstance3D              # guide wheel -> grip
var pile: MeshInstance3D
var weight_arrow: VelocityArrow
var pull_arrow: VelocityArrow
var cat: CatActor
var _n := -1
var _guide := Vector3.ZERO
var _load_x := 0.0
var _top_y := 0.0
## The load look's size against its body's (set_look) and the hook above the body's centre for it.
var look := 1.0
var hook_up := 0.62
var _hook_base := 0.62
var _load_size := 0.8


static func gantry_mesh(left: float, right: float, beam_y: float, guide: Vector3) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3((left + right) * 0.5, -0.028, 0.0)), Vector3(right - left + 1.6, 0.06, 2.4), 0.02, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	b.ao_min = 0.8
	b.ao_height = 0.6
	for x in [left, right]:
		b.add_cylinder(Transform3D(Basis(), Vector3(x, 0.0, -0.5)), 0.4, 0.34, 0.16, 8, ArtPalette.BLUE_DARK)
		b.add_rounded_box(Transform3D(Basis(), Vector3(x, beam_y * 0.5, -0.5)), Vector3(0.3, beam_y, 0.3), 0.05, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D(Basis(), Vector3((left + right) * 0.5, beam_y + 0.15, -0.25)), Vector3(right - left + 0.5, 0.3, 0.8), 0.05, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	# The guide wheel over the pull side, hanging from the beam.
	b.add_rounded_box(Transform3D(Basis(), Vector3(guide.x, (guide.y + beam_y) * 0.5, 0.0)), Vector3(0.12, beam_y - guide.y, 0.1), 0.0, 1, ArtPalette.BLUE_DARK)
	add_wheel(b, guide)
	return b.commit()


## A wheel turning about z at `at` (white rim, dark hub).
static func add_wheel(b: ArtMeshBuilder, at: Vector3) -> void:
	var turn := Basis(Vector3.RIGHT, PI * 0.5)
	b.add_cylinder(Transform3D(turn, at - Vector3(0.0, 0.0, WHEEL_DEPTH * 0.5)), WHEEL_RADIUS, WHEEL_RADIUS, WHEEL_DEPTH, 10, ArtPalette.WHITE)
	b.add_cylinder(Transform3D(turn, at - Vector3(0.0, 0.0, WHEEL_DEPTH * 0.5 + 0.01)), WHEEL_RADIUS * 0.4, WHEEL_RADIUS * 0.4, WHEEL_DEPTH + 0.02, 6, ArtPalette.BLUE_DARK)


## A pulley block of `count` wheels side by side around its origin; `hang` = +1 hangs the block
## below the origin (fixed block), -1 stands it above (moving block on the load). `run_to` (block
## local, fixed block only) draws the rope's run from the last strand over to the guide wheel.
static func block_mesh(count: int, hang: float, run_from := 0.0, run_to: Variant = null) -> Mesh:
	var b := ArtKit.builder()
	if count <= 0:
		return b.commit()
	b.ao_min = 1.0
	var width := count * WHEEL_RADIUS * 2.6
	var centre := -hang * (WHEEL_RADIUS + 0.06)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, centre, -BLOCK_DEPTH * 0.5 - 0.02)), Vector3(width, WHEEL_RADIUS * 2.0 + 0.2, 0.06), 0.02, 1, ArtPalette.BLUE_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, centre + hang * (WHEEL_RADIUS + 0.16), -BLOCK_DEPTH * 0.25)), Vector3(0.1, 0.2, 0.1), 0.0, 1, ArtPalette.INK)
	for i in count:
		add_wheel(b, Vector3((i - (count - 1) * 0.5) * WHEEL_RADIUS * 2.6, centre, 0.0))
	if run_to != null:
		var to: Vector3 = run_to
		var y := centre + WHEEL_RADIUS
		b.add_cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(run_from, y, 0.0)), ROPE_RADIUS, ROPE_RADIUS, to.x - run_from, 6, ArtPalette.WHITE)
	return b.commit()


## n strands of 1 m down from the origin at their x offsets (scaled along y to the gap).
static func strands_mesh(n: int) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	for i in n:
		b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(strand_x(0.0, i, n), 0.0, 0.0)), ROPE_RADIUS, ROPE_RADIUS, 1.0, 6, ArtPalette.WHITE)
	return b.commit()


static func grip_mesh(size: Vector3) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D.IDENTITY, size, 0.08, 1, ArtPalette.RED, ArtPalette.RED_TOP)
	return b.commit()


static func pile_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.85
	b.ao_height = 0.3
	b.add_cylinder(Transform3D.IDENTITY, 0.32, 0.28, 1.0, 10, ArtPalette.WHITE)
	return b.commit()


func dress(experiment: Node3D, load_body: RigidBody3D, handle: StaticBody3D, sizes: Dictionary) -> void:
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.6))
	var gantry := ArtKit.instance(gantry_mesh(sizes.left, sizes.right, sizes.beam_y, sizes.guide))
	gantry.name = "Gantry"
	experiment.add_child(gantry)
	fixed_block = MeshInstance3D.new()
	fixed_block.name = "FixedBlock"
	fixed_block.material_override = ArtKit.lit_material()
	fixed_block.position = Vector3(sizes.load_x, sizes.top_y, 0.0)
	experiment.add_child(fixed_block)
	moving_block = MeshInstance3D.new()
	moving_block.name = "MovingBlock"
	moving_block.material_override = ArtKit.lit_material()
	moving_block.position = Vector3(0.0, sizes.hook_up, 0.0)
	_hook_base = sizes.hook_up
	hook_up = sizes.hook_up
	_load_size = sizes.load_size
	load_body.add_child(moving_block)
	var load_visual := ArtKit.parcel_box(sizes.load_size)   # a parcel box (Task 4g)
	load_visual.name = "Visual"
	load_body.add_child(load_visual)
	juice = ArtJuice.new()
	juice.name = "LoadJuice"
	juice.dust_amount = 12
	experiment.add_child(juice)
	juice.setup(load_body, load_visual, sizes.load_size)
	var grip := ArtKit.instance(grip_mesh(sizes.handle))
	grip.name = "Visual"
	handle.add_child(grip)
	strands = MeshInstance3D.new()
	strands.name = "Strands"
	strands.material_override = ArtKit.lit_material()
	strands.position = Vector3(sizes.load_x, sizes.top_y, 0.0)
	experiment.add_child(strands)
	_guide = sizes.guide
	_load_x = sizes.load_x
	_top_y = sizes.top_y
	pull_link = ArtKit.instance(ArtKit.link_mesh(ROPE_RADIUS, ArtPalette.WHITE))
	pull_link.name = "PullStrand"
	experiment.add_child(pull_link)
	pile = ArtKit.instance(pile_mesh())
	pile.name = "RopePile"
	pile.position = Vector3(sizes.guide.x + 0.75, 0.0, 0.3)
	experiment.add_child(pile)
	weight_arrow = VelocityArrow.new(ArtPalette.ORANGE, ArtPalette.ORANGE_TOP)
	weight_arrow.name = "WeightArrow"
	experiment.add_child(weight_arrow)
	pull_arrow = VelocityArrow.new(ArtPalette.RED, ArtPalette.RED_TOP)
	pull_arrow.name = "PullArrow"
	experiment.add_child(pull_arrow)
	cat = CatActor.new(BreadCat.new())
	cat.look_target = handle
	cat.position = cat_spot(handle.global_position)
	experiment.add_child(cat)


## The load looks `k` times its body's size (from its bottom); the moving block stays on its top.
func set_look(k: float) -> void:
	look = k
	juice.set_look_scale(k)
	hook_up = _hook_base + (k - 1.0) * _load_size
	moving_block.position.y = hook_up


## Centre of the load's look on the load body `load` ((k - 1) half sides above the body's centre).
func look_centre(load: Node3D) -> Vector3:
	return load.global_position + Vector3.UP * (look - 1.0) * _load_size * 0.5


## The cat's spot on the floor under the grip at `grip` (when it does not hold it).
static func cat_spot(grip: Vector3) -> Vector3:
	return Vector3(grip.x + CAT_SPOT_X, 0.0, CAT_SPOT_Z)


## The finger holds the grip (centre `grip`, `size`): the cat's paws on its back face, pulling.
func update_cat(grip: Vector3, size: Vector3) -> void:
	if cat != null:
		cat.pull(grip - Vector3(0.0, 0.0, size.z * 0.5), CAT_DIR.normalized(), 0.0, CAT_EFFORT)


## The finger let the grip go: the cat lets go and drops back to its spot (a cheer when the load is
## off the ground).
func cat_let_go(grip_rest: Vector3, lifted: bool) -> void:
	if cat == null:
		return
	cat.let_go(Vector3.UP, cat_spot(grip_rest))
	if lifted:
		cat.cheer()


## The blocks for n strands (n / 2 moving wheels, max(1, n / 2) fixed ones), rebuilt when n changed.
func show_strands(n: int) -> void:
	if n == _n:
		return
	_n = n
	var fixed := maxi(1, n / 2)
	# The fixed block's run starts above its last wheel and ends over the guide wheel.
	fixed_block.mesh = block_mesh(fixed, 1.0, (fixed - 1) * 0.5 * WHEEL_RADIUS * 2.6, _guide - Vector3(_load_x, _top_y, 0.0))
	moving_block.mesh = block_mesh(n / 2, -1.0)
	strands.mesh = strands_mesh(n)


## x of supporting strand `i` of `n` around the load's x.
static func strand_x(load_x: float, i: int, n: int) -> float:
	return load_x + (i - (n - 1) * 0.5) * WHEEL_RADIUS * 1.3


## The n strands between the fixed block (top_y) and the hook (hook_y), the pull strand from the
## guide wheel to the grip top; the pile for `piled` m of rope; the arrows.
func show_rope(top_y: float, hook_y: float, guide: Vector3, grip_top: Vector3, piled: float,
		load_centre: Vector3, load_half: float, weight: float, pull: float) -> void:
	strands.scale = Vector3(1.0, maxf(0.01, top_y - hook_y), 1.0)
	ArtKit.stretch_link(pull_link, guide + Vector3(WHEEL_RADIUS, 0.0, 0.0), grip_top)
	pile.visible = piled > 0.001
	pile.scale = Vector3(1.0, 0.04 + minf(piled, 10.0) * 0.03, 1.0)
	var w := minf(ARROW_MAX, snappedf(weight * FORCE_SCALE, 0.02))
	weight_arrow.point(load_centre + Vector3(0.0, 0.0, load_half + 0.12), -90.0, w)
	pull_arrow.visible = pull >= 0.5
	if pull_arrow.visible:
		pull_arrow.point(grip_top + Vector3(0.0, -0.2, 0.35), -90.0, minf(ARROW_MAX, snappedf(pull * FORCE_SCALE, 0.02)))


func lifted_off() -> void:
	if juice != null:
		juice.stretch()


func reset() -> void:
	if juice != null:
		juice.pop()
