## Grass island props of the pulley lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the load and the rope end are bodies built and posed by pulley.gd; nothing here
## moves a body.
## - the gantry (one mesh): a yellow board, two blue posts and the top beam with the guide wheel over
##   the pull side,
## - the load (a parcel box) looks as heavy as it is (set_look, 2026-10-28: one stuff, the cube root
##   of its mass against the 20 kg load's 0.8 m, grown from its bottom; the moving block on its top),
## - the fixed pulley block under the beam and the moving block on the load, each with its wheels
##   (n = 1: one fixed wheel; 2: one fixed + one moving; 4: two + two), rebuilt when n changes,
## - the rope (white), one path round the wheels' rims (2026-10-29 user: "도르래 줄 위치가 이상해", the
##   strands used to start at the block's top and pass through the wheels' centres): the n supporting
##   strands hang straight at the wheels' rims (layout(): strand k and the wheels between them), from
##   the fixed wheels' centre height down to the moving wheels' centre height (one mesh, stretched each
##   frame, so it follows the load); under every moving wheel and over every fixed wheel a half turn
##   (the moving ones in the moving block's mesh, the fixed ones in the fixed block's); for even n the
##   rope's dead end is tied to the fixed block, for n = 1 to the hook on the load; from the last fixed
##   wheel the run to the guide wheel is their common upper tangent, round the guide to its right rim,
##   then the pull strand down to its end, a white knot the child presses and holds (2026-10-28: the
##   red grip went; a link posed each frame); the rope pulled in earlier strokes lies coiled on the
##   ground (its height grows with the length),
## - arrows: the orange weight of the load and the red pull of the hand (down), FORCE_SCALE m per N,
## - reactions: lifting off = stretch; set down (reset) = pop.
## - the bread cat (CatActor wearing the BreadCat look, 2026-10-27) under the rope end, behind the
##   pull strand: while the finger holds the rope the cat holds its end with both paws and pulls it
##   down with it (it jumps up to the end and hangs from it while it is above its reach, stands and
##   leans back once it is low); letting go it drops back to its spot, cheering when the stroke
##   lifted the load. Only meshes: the rope, its end and the load are the formula model's.
class_name PulleyProps
extends RefCounted

const WHEEL_RADIUS := 0.2
const WHEEL_DEPTH := 0.12
const ROPE_RADIUS := 0.03
const FORCE_SCALE := 0.006
const ARROW_MAX := 2.4
const BLOCK_DEPTH := 0.3
const KNOT_RADIUS := 0.13       # m, the rope end's knot
## The rope's path round a wheel: its centre line on the rim (the rope sits in the groove).
const RIM := WHEEL_RADIUS
## The wheels' centres: the fixed ones this far below the block's top (top_y), the moving ones this
## far above the load's hook.
const FIXED_DOWN := WHEEL_RADIUS + 0.06
const MOVING_UP := WHEEL_RADIUS + 0.06
const ARC_STEPS := 8            # straight pieces per half turn of rope round a wheel
## The cat's reach to the rope end's back face (shoulders -> grip: from below and behind), how hard it
## leans back pulling, and its spot under the grip (x offset, z) when it does not hold it.
const CAT_DIR := Vector3(0.0, 0.45, 0.89)
const CAT_EFFORT := 0.6
const CAT_SPOT_Z := -0.45
const CAT_SPOT_X := -0.15       # m beside the grip (clear of the gantry's post)

var juice: ArtJuice
var fixed_block: MeshInstance3D
var moving_block: MeshInstance3D
var strands: MeshInstance3D               # the n supporting strands: one mesh, 1 m long, scaled to the gap
var pull_link: MeshInstance3D              # guide wheel -> rope end
var pile: MeshInstance3D
var weight_arrow: VelocityArrow
var pull_arrow: VelocityArrow
var cat: CatActor
var _n := -1
var _guide := Vector3.ZERO
var _load_x := 0.0
var _top_y := 0.0
var _beam_y := 0.0
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
	# The guide wheel over the pull side, hanging from the beam by a strap behind it (clear of the rope
	# that runs over its top).
	var behind := -WHEEL_DEPTH * 0.5 - 0.05
	b.add_rounded_box(Transform3D(Basis(), Vector3(guide.x, (guide.y + beam_y) * 0.5, behind)), Vector3(0.12, beam_y - guide.y, 0.06), 0.0, 1, ArtPalette.BLUE_DARK)
	add_wheel(b, guide)
	return b.commit()


## A wheel turning about z at `at` (white rim, dark hub).
static func add_wheel(b: ArtMeshBuilder, at: Vector3) -> void:
	var turn := Basis(Vector3.RIGHT, PI * 0.5)
	b.add_cylinder(Transform3D(turn, at - Vector3(0.0, 0.0, WHEEL_DEPTH * 0.5)), WHEEL_RADIUS, WHEEL_RADIUS, WHEEL_DEPTH, 10, ArtPalette.WHITE)
	b.add_cylinder(Transform3D(turn, at - Vector3(0.0, 0.0, WHEEL_DEPTH * 0.5 + 0.01)), WHEEL_RADIUS * 0.4, WHEEL_RADIUS * 0.4, WHEEL_DEPTH + 0.02, 6, ArtPalette.BLUE_DARK)


## The rope's layout for `n` strands round the load at `load_x` (x only; the rope lies in z = 0):
## "strands" the n strand xs (2 RIM apart, centred on the load), "fixed" the fixed wheels' centre xs,
## "moving" the moving wheels'. Strand 2j and 2j + 1 wrap moving wheel j from below; strand 2j + 1 and
## 2j + 2 wrap fixed wheel j from above; the last strand goes up to the last fixed wheel, which turns
## the rope towards the guide wheel. n = 1: the one strand from the hook to the one fixed wheel's left
## rim. For even n the first strand's end is tied to the fixed block.
static func layout(n: int, load_x: float) -> Dictionary:
	var xs: Array[float] = []
	for k in n:
		xs.append(load_x + (2 * k - (n - 1)) * RIM)
	var fixed: Array[float] = []
	var moving: Array[float] = []
	if n == 1:
		fixed.append(xs[0] + RIM)
	else:
		for j in n / 2:
			moving.append(xs[2 * j] + RIM)
			fixed.append(xs[2 * j + 1] + RIM)
	return {"strands": xs, "fixed": fixed, "moving": moving}


## The rope's path round the fixed wheels and on to the guide (x-y points, block-local to (load_x,
## top_y)): [the over-turns of the fixed wheels before the last, ..., the last wheel's turn + the run +
## the guide's turn to its right rim]. Every point of a turn is on a rim (RIM from its centre).
static func fixed_rope(n: int, load_x: float, top_y: float, guide: Vector3) -> Array:
	var plan := layout(n, load_x)
	var fixed: Array = plan.fixed
	var y := -FIXED_DOWN
	var paths: Array = []
	for j in fixed.size() - 1:
		paths.append(arc(Vector2(fixed[j] - load_x, y), PI, 0.0))
	var last := Vector2(fixed[-1] - load_x, y)
	var to := Vector2(guide.x - load_x, guide.y - top_y)
	var up := run_normal(last, to)
	var leave := atan2(up.y, up.x)
	var path := arc(last, PI, leave)
	path.append_array(arc(to, leave, 0.0))
	paths.append(path)
	return paths


## The common upper tangent's normal of two equal wheels at `a` and `b` (pointing up): the run between
## them touches each at centre + normal * RIM.
static func run_normal(a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x) if d.x >= 0.0 else Vector2(d.y, -d.x)


## Points on the rim round `centre` from angle `from` to `to` (radians, x right, y up), ARC_STEPS
## pieces per half turn (at least 2).
static func arc(centre: Vector2, from: float, to: float) -> PackedVector2Array:
	var steps := maxi(2, ceili(absf(to - from) / PI * ARC_STEPS))
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		out.append(centre + Vector2(cos(a), sin(a)) * RIM)
	return out


## The fixed block for `n` strands at its origin (load_x, top_y): a dark plate behind its wheels, the
## strap up to the beam (`beam_y`), the wheels (layout()), the rope's turns over them and the run to
## the guide wheel (fixed_rope()), and for even n the rope's dead end tied to the plate over strand 0.
static func fixed_block_mesh(n: int, load_x: float, top_y: float, beam_y: float, guide: Vector3) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	var plan := layout(n, load_x)
	var y := -FIXED_DOWN
	var lo: float = minf(plan.strands[0], plan.fixed[0] - RIM) - load_x - 0.12
	var hi: float = plan.fixed[-1] + RIM - load_x + 0.12
	b.add_rounded_box(Transform3D(Basis(), Vector3((lo + hi) * 0.5, y, -BLOCK_DEPTH * 0.5 - 0.02)), Vector3(hi - lo, WHEEL_RADIUS * 2.0 + 0.2, 0.06), 0.02, 1, ArtPalette.BLUE_DARK)
	var strap_bottom := y + WHEEL_RADIUS + 0.1
	b.add_rounded_box(Transform3D(Basis(), Vector3((lo + hi) * 0.5, (strap_bottom + beam_y - top_y) * 0.5, -BLOCK_DEPTH * 0.5 - 0.02)), Vector3(0.12, beam_y - top_y - strap_bottom, 0.06), 0.0, 1, ArtPalette.INK)
	for x in plan.fixed:
		add_wheel(b, Vector3(x - load_x, y, 0.0))
	for path in fixed_rope(n, load_x, top_y, guide):
		_rope_path(b, path)
	if n > 1:
		b.add_rounded_box(Transform3D(Basis(), Vector3(plan.strands[0] - load_x, y, -0.02)), Vector3(0.1, 0.1, 0.1), 0.0, 1, ArtPalette.INK)
	return b.commit()


## The moving block for `n` strands at the hook (its origin, on the load's top): the plate, the wheels
## (layout(), MOVING_UP above the hook) and the rope's half turn under each; n = 1 has no block, only
## the hook's eye the strand is tied to.
static func moving_block_mesh(n: int) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	var plan := layout(n, 0.0)
	if plan.moving.is_empty():
		b.add_cylinder(Transform3D(Basis(), Vector3(0.0, -0.06, 0.0)), 0.07, 0.07, 0.08, 6, ArtPalette.INK)
		b.add_sphere(Transform3D(Basis(), Vector3.ZERO), ROPE_RADIUS * 2.2, 3, 6, ArtPalette.WHITE)
		return b.commit()
	var lo: float = plan.moving[0] - RIM - 0.12
	var hi: float = plan.moving[-1] + RIM + 0.12
	b.add_rounded_box(Transform3D(Basis(), Vector3((lo + hi) * 0.5, MOVING_UP, -BLOCK_DEPTH * 0.5 - 0.02)), Vector3(hi - lo, WHEEL_RADIUS * 2.0 + 0.2, 0.06), 0.02, 1, ArtPalette.BLUE_DARK)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.0, -BLOCK_DEPTH * 0.25)), Vector3(0.12, 0.12, 0.1), 0.0, 1, ArtPalette.INK)
	for x in plan.moving:
		add_wheel(b, Vector3(x, MOVING_UP, 0.0))
		_rope_path(b, arc(Vector2(x, MOVING_UP), PI, TAU))
	return b.commit()


## A rope along `points` (x-y, z = 0): one thin cylinder per piece, overlapping a little at the joints.
static func _rope_path(b: ArtMeshBuilder, points: PackedVector2Array) -> void:
	for i in points.size() - 1:
		var a := Vector3(points[i].x, points[i].y, 0.0)
		var c := Vector3(points[i + 1].x, points[i + 1].y, 0.0)
		var d := c - a
		if d.length() < 1e-5:
			continue
		var y := d.normalized()
		var x := y.cross(Vector3.BACK).normalized()
		b.add_cylinder(Transform3D(Basis(x, y, x.cross(y)), a - y * ROPE_RADIUS * 0.5), ROPE_RADIUS, ROPE_RADIUS, d.length() + ROPE_RADIUS, 5, ArtPalette.WHITE, false)


## n strands of 1 m down from the origin (the fixed wheels' centre height over the load) at their x
## offsets from the load (layout()), scaled along y to reach the moving wheels' centre height (or the hook).
static func strands_mesh(n: int) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	for x in layout(n, 0.0).strands:
		b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(x, 0.0, 0.0)), ROPE_RADIUS, ROPE_RADIUS, 1.0, 6, ArtPalette.WHITE)
	return b.commit()


## The rope end: a white knot (a ball of rope) with a short tail under it.
static func knot_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_sphere(Transform3D.IDENTITY, KNOT_RADIUS, 4, 8, ArtPalette.WHITE)
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, -KNOT_RADIUS - 0.12, 0.0)), ROPE_RADIUS, ROPE_RADIUS, 0.16, 6, ArtPalette.WHITE)
	return b.commit()


static func pile_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.85
	b.ao_height = 0.3
	b.add_cylinder(Transform3D.IDENTITY, 0.32, 0.28, 1.0, 10, ArtPalette.WHITE)
	return b.commit()


func dress(experiment: Node3D, load_body: RigidBody3D, rope_end: StaticBody3D, sizes: Dictionary) -> void:
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
	var knot := ArtKit.instance(knot_mesh())
	knot.name = "Visual"
	rope_end.add_child(knot)
	strands = MeshInstance3D.new()
	strands.name = "Strands"
	strands.material_override = ArtKit.lit_material()
	strands.position = Vector3(sizes.load_x, sizes.top_y - FIXED_DOWN, 0.0)
	experiment.add_child(strands)
	_guide = sizes.guide
	_load_x = sizes.load_x
	_top_y = sizes.top_y
	_beam_y = sizes.beam_y
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
	cat.look_target = rope_end
	cat.position = cat_spot(rope_end.global_position)
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


## The cat's spot on the floor under the rope end at `grip` (when it does not hold it).
static func cat_spot(grip: Vector3) -> Vector3:
	return Vector3(grip.x + CAT_SPOT_X, 0.0, CAT_SPOT_Z)


## The finger holds the rope (its end's centre `grip`, pick box `size`): the cat's paws on its back, pulling.
func update_cat(grip: Vector3, size: Vector3) -> void:
	if cat != null:
		cat.pull(grip - Vector3(0.0, 0.0, size.z * 0.5), CAT_DIR.normalized(), 0.0, CAT_EFFORT)


## The finger let the rope go: the cat lets go and drops back to its spot (a cheer when the load is
## off the ground).
func cat_let_go(grip_rest: Vector3, lifted: bool) -> void:
	if cat == null:
		return
	cat.let_go(Vector3.UP, cat_spot(grip_rest))
	if lifted:
		cat.cheer()


## The blocks and the rope's turns for n strands, rebuilt when n changed.
func show_strands(n: int) -> void:
	if n == _n:
		return
	_n = n
	fixed_block.mesh = fixed_block_mesh(n, _load_x, _top_y, _beam_y, _guide)
	moving_block.mesh = moving_block_mesh(n)
	strands.mesh = strands_mesh(n)


## Where the strands end below (y): the moving wheels' centre height over the hook at `hook_y` (the
## rope turns under them), or the hook itself for one strand.
func strand_bottom(hook_y: float) -> float:
	return hook_y + (MOVING_UP if _n > 1 else 0.0)


## The n strands between the fixed wheels (FIXED_DOWN under top_y) and the moving wheels over the hook
## (hook_y; strand_bottom), the pull strand from the guide wheel's right rim to the rope end's top; the
## pile for `piled` m of rope; the arrows.
func show_rope(top_y: float, hook_y: float, guide: Vector3, grip_top: Vector3, piled: float,
		load_centre: Vector3, load_half: float, weight: float, pull: float) -> void:
	strands.scale = Vector3(1.0, maxf(0.01, top_y - FIXED_DOWN - strand_bottom(hook_y)), 1.0)
	ArtKit.stretch_link(pull_link, guide + Vector3(RIM, 0.0, 0.0), grip_top)
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
