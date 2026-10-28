## Grass island props of the lever lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the beam, the load and the fulcrum stand are bodies built and posed by
## rotation.gd; nothing here moves a body.
## - the static base (one mesh): a yellow board on the grass and the blue rest block under the beam's
##   left end (the load side rests on it until the lever lifts),
## - the beam (yellow, white ticks every 0.5 m) under the beam body; the three effort points on it
##   (white pegs, the chosen one red, rebuilt when the fulcrum or the choice changes),
## - the fulcrum stand: a blue triangular prism with its blob shadow, under the stand body,
## - the orange load box (the web's load colour) with its ArtJuice; it looks as heavy as it is
##   (set_look, 2026-10-28: one stuff, the cube root of its mass against the 20 kg load's 0.7 m, grown
##   from its bottom on the beam; the body, its place on the beam and the model stay). The red
##   handle and its rod went on 2026-10-28: the child presses and holds the chosen (red) effort
##   point itself and the lab's gauge (ForceGauge) beside it fills,
## - arrows: the red force on the beam at the effort point (down) and the orange weight of the load,
##   FORCE_SCALE m per N (at most ARROW_MAX m),
## - reactions: lifted = the load stretches; back down = a small squash; reset = pop.
## - the bread cat (CatActor wearing the BreadCat look, 2026-10-27) on a stack of bread crates behind
##   the beam just right of the effort point (left of it near the beam's end): both paws on the
##   beam's top there, pressing it down with the held press (the bag squashes a little with the force's
##   share of the required force; as the effort side goes down it leans after it, at most
##   CAT_LEAN_MAX, and its arms reach the rest); a nod when the load lifts. Only meshes: the beam
##   turns as the lever model says.
class_name RotationProps
extends RefCounted

const BEAM_COLOR := ArtPalette.YELLOW
const FORCE_SCALE := 0.006        # m of arrow per N
const ARROW_MAX := 2.4
## The cat: its base right of the effort point (CAT_RIGHT along the beam) and behind the beam
## (CAT_Z), its paws' z on the beam top and their distance either side of that point, its
## shoulders' height above the level beam's top, its lean limit (deg).
const CAT_RIGHT := 0.55
const CAT_Z := -0.84
const CAT_PAW_Z := -0.25
const CAT_PAW_HALF := 0.15
const CAT_ABOVE := 0.08
const CAT_LEAN_MAX := 20.0

var juice: ArtJuice
## The load look's size against its body's (set_look).
var look := 1.0
var _load_size := 0.7
var markers: MeshInstance3D
var force_arrow: VelocityArrow
var weight_arrow: VelocityArrow
var _marker_key := Vector4(INF, INF, INF, INF)   # the three points and the chosen one
var cat: CatActor
var cat_stand: CatCrates


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
	var load_visual := ArtKit.parcel_box(sizes.load_size)   # a parcel box (Task 4g)
	load_visual.name = "Visual"
	parts.load.add_child(load_visual)
	juice = ArtJuice.new()
	juice.name = "LoadJuice"
	juice.dust_amount = 10
	experiment.add_child(juice)
	juice.setup(parts.load, load_visual, sizes.load_size)
	_load_size = sizes.load_size
	force_arrow = VelocityArrow.new(ArtPalette.RED, ArtPalette.RED_TOP)
	force_arrow.name = "ForceArrow"
	experiment.add_child(force_arrow)
	weight_arrow = VelocityArrow.new(ArtPalette.ORANGE, ArtPalette.ORANGE_TOP)
	weight_arrow.name = "WeightArrow"
	experiment.add_child(weight_arrow)
	cat = CatActor.new(BreadCat.new())
	cat_stand = CatCrates.new(cat.look.footprint)
	experiment.add_child(cat_stand)
	experiment.add_child(cat)


## The load looks `k` times its body's size (from its bottom on the beam).
func set_look(k: float) -> void:
	look = k
	juice.set_look_scale(k)


## Centre of the load's look on the load body `load`: (k - 1) half sides above the body's centre
## along the body's up (it turns with the beam).
func look_centre(load: Node3D) -> Vector3:
	return load.global_transform * Vector3(0.0, (look - 1.0) * _load_size * 0.5, 0.0)


## The cat's paws on the beam body `beam` (`thick` m; its centre is x = 0 of the level beam) of
## `model` at the effort point, pressing with `effort` 0..1 (the force's share of the required
## force); its crates under it. The paws follow the posed beam itself.
func update_cat(model: LeverLabModel, beam: Node3D, thick: float, effort: float) -> void:
	if cat == null:
		return
	# Right of the effort point, or left of it when the beam ends too soon (the far point).
	var ex := model.effort_x() + CAT_RIGHT
	if ex + CAT_PAW_HALF > model.beam_half - 0.05:
		ex = model.effort_x() - CAT_RIGHT
	var top := thick * 0.5
	var targets: Array[Vector3] = []
	for along in [ex - CAT_PAW_HALF, ex + CAT_PAW_HALF]:
		targets.append(beam.global_transform * Vector3(along, top, CAT_PAW_Z))
	var shoulder_y: float = cat.look.shoulders[0].y
	cat.grab(Vector3(ex, model.pivot_y + top + CAT_ABOVE - shoulder_y, CAT_Z), 0.0, targets, effort, CAT_LEAN_MAX)
	cat_stand.fit(cat, 0.0)


## The effort pegs for beam-local points `points` (rebuilt only when they or the choice changed).
func show_markers(points: Array[float], chosen: int, thick: float, depth: float) -> void:
	var key := Vector4(points[0], points[1], points[2], chosen)
	if key == _marker_key:
		return
	_marker_key = key
	markers.mesh = marker_mesh(points, chosen, thick, depth)


## The force arrow above the effort point `effort` (`force` N, down) and the weight arrow below the
## load centre (`weight` N).
func show_forces(effort: Vector3, force: float, load_centre: Vector3, load_half: float, weight: float) -> void:
	force_arrow.visible = force >= 0.5
	if force_arrow.visible:
		var l := minf(ARROW_MAX, snappedf(force * FORCE_SCALE, 0.02))
		force_arrow.point(effort + Vector3(0.0, l + 0.08, 0.35), -90.0, l)
	var w := minf(ARROW_MAX, snappedf(weight * FORCE_SCALE, 0.02))
	weight_arrow.point(load_centre + Vector3(0.0, 0.0, load_half + 0.12), -90.0, w)


func lifted() -> void:
	if juice != null:
		juice.stretch()
	if cat != null:
		cat.cheer(false)


func lowered() -> void:
	if juice != null:
		juice.settle()


func reset() -> void:
	if juice != null:
		juice.pop()
