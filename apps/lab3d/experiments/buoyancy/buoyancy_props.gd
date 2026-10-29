## Grass island props of the buoyancy lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the drum and floor bodies are built and posed by buoyancy.gd.
## - the tank, drawn as a cutaway (no large translucent surface, section 8): a blue base, water-blue
##   floor, back and side walls up to the waterline and white glass walls above it, white corner posts
##   and rim at the open front, light-blue waterline strips along the walls and across the front,
##   white depth ticks on the back wall every 0.1 m (long every 0.5 m) from the tank floor,
## - the orange drum (the web's ball colour) with a white band, its ArtJuice (shadow, splash dust,
##   squash) and a light-blue water ring around it at the waterline while it is partly under water,
## - its mass (set_mass, 2026-10-28 user request: the look follows the weight): the drum's size is its
##   volume (큰 통 / 작은 통), so the mass is an iron weight on its lid, its width the cube root of the
##   mass (WEIGHT_WIDTH for 150 kg, the slider's top, like the picture button's weight). (2026-10-29
##   user: no number on the kid screen — the "80킬로그램" tag over the drum is gone; the kilograms are
##   in 자세히 only.) Visual only: the drum body and the model do not see it,
## - two force arrows beside the drum: the weight m g (red, down) and the buoyant force rho g V_sub
##   (blue, up), both ARROW_PER_FULL m for the buoyant force of the whole drum,
## - reactions: entering the water fast = splash (dust) and squash; hitting the tank floor = bump;
##   settling = wobble; release = stretch; reset = pop.
## - the bread cat (CatActor wearing the BreadCat look, 2026-10-27) on a stack of bread crates
##   standing in the tank's back left corner (clear of the drum's way down and of the depth ticks):
##   while the drum waits above the water it holds it with both paws on its side, leaning over to it;
##   "놓기" lets go (the paws follow down); a finger holding the drum, or a drum put under the water:
##   it only watches. It cheers when the drum floats, stays or sinks. Only meshes: the drum moves as
##   the formula model says.
class_name BuoyancyProps
extends RefCounted

const HALF_X := 1.3              # inner half width of the tank (x) and depth (z)
const HALF_Z := 0.8
const WALL := 0.08
const ARROW_PER_FULL := 1.2      # m of arrow for the buoyant force of the fully submerged drum
const ARROW_GAP := 0.2           # m between the drum's side and an arrow
## The cat's crates in the tank (x, z of the stack, its top: the cat's base) and its paws' spread
## (rad either side of the drum's side facing it).
const CAT_AT := Vector2(-0.66, -0.4)
const CAT_TOP := 1.7
const CAT_SPREAD := 0.45
const WEIGHT_MASS := 150.0       # kg: the weight that is WEIGHT_WIDTH wide (the mass slider's top)
const WEIGHT_WIDTH := 0.34       # m (fits on the small drum's 0.4 m lid)
const WEIGHT_TALL := 0.85       # the weight mesh's height per metre of its width

var juice: ArtJuice
var drum_visual: Node3D
var ring: MeshInstance3D
var weight_arrow: VelocityArrow
var buoyant_arrow: VelocityArrow
var _radius := 0.25
var _height := 0.5
var _waterline := 1.5
var cat: CatActor
var cat_stand: CatCrates
## The iron weight on the lid (a 1 m wide mesh scaled to the mass).
var weight: MeshInstance3D
var _mass := 70.0


## The tank around x = 0, z = 0: base under `floor_y`, water to `waterline`, walls to `top`.
func tank_mesh(floor_y: float, waterline: float, top: float) -> Mesh:
	var b := ArtKit.builder()
	var outer_x := HALF_X + WALL
	var outer_z := HALF_Z + WALL
	b.ao_min = 0.85
	b.ao_height = 0.3
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, floor_y * 0.5, 0.0)), Vector3(outer_x * 2.0 + 0.2, floor_y, outer_z * 2.0 + 0.2), 0.04, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, floor_y + 0.005, 0.0)), Vector3(HALF_X * 2.0, 0.01, HALF_Z * 2.0), 0.0, 1, ArtPalette.WATER)
	var water_h := waterline - floor_y
	var dry_h := top - waterline
	# Back wall: water below the waterline, white glass above.
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, floor_y + water_h * 0.5, -HALF_Z - WALL * 0.5)), Vector3(outer_x * 2.0, water_h, WALL), 0.0, 1, ArtPalette.WATER)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, waterline + dry_h * 0.5, -HALF_Z - WALL * 0.5)), Vector3(outer_x * 2.0, dry_h, WALL), 0.0, 1, ArtPalette.WHITE)
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (HALF_X + WALL * 0.5), floor_y + water_h * 0.5, 0.0)), Vector3(WALL, water_h, HALF_Z * 2.0), 0.0, 1, ArtPalette.WATER)
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (HALF_X + WALL * 0.5), waterline + dry_h * 0.5, 0.0)), Vector3(WALL, dry_h, HALF_Z * 2.0), 0.0, 1, ArtPalette.WHITE)
		# Front corner posts.
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (HALF_X + WALL * 0.5), (floor_y + top) * 0.5, HALF_Z + WALL * 0.5)), Vector3(WALL, top - floor_y, WALL), 0.0, 1, ArtPalette.WHITE)
	# Top rim at the front, waterline strips along the walls and across the open front.
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, top - 0.03, HALF_Z + WALL * 0.5)), Vector3(outer_x * 2.0, 0.06, WALL), 0.0, 1, ArtPalette.WHITE)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, waterline, HALF_Z + 0.02)), Vector3(HALF_X * 2.0, 0.04, 0.04), 0.0, 1, ArtPalette.WATER_TOP)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, waterline, -HALF_Z + 0.02)), Vector3(HALF_X * 2.0, 0.04, 0.04), 0.0, 1, ArtPalette.WATER_TOP)
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (HALF_X - 0.02), waterline, 0.0)), Vector3(0.04, 0.04, HALF_Z * 2.0), 0.0, 1, ArtPalette.WATER_TOP)
	# Depth ticks on the back wall (from the tank floor), right of the drum.
	var tick_x := HALF_X - 0.35
	var steps := int(roundf((top - floor_y - 0.05) * 10.0))
	for i in range(1, steps + 1):
		var long := i % 5 == 0
		b.add_rounded_box(Transform3D(Basis(), Vector3(tick_x, floor_y + i * 0.1, -HALF_Z + 0.006)), Vector3(0.34 if long else 0.18, 0.025, 0.012), 0.0, 1, ArtPalette.WHITE)
	return b.commit()


## An upright drum of `radius` x `height` centred on the origin, with a white band.
static func drum_mesh(radius: float, height: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = height
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, -height * 0.5, 0.0)), radius, radius, height, 10, ArtPalette.ORANGE, true, ArtPalette.ORANGE_TOP)
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, -height * 0.08, 0.0)), radius * 1.02, radius * 1.02, height * 0.16, 10, ArtPalette.WHITE, false)
	return b.commit()


## An iron weight 1 m wide on its bottom face (the origin): a square block narrowing upwards with a
## bar handle, like the picture button's weight.
static func weight_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = 0.75
	var turn := Basis(Vector3.UP, PI * 0.25)   # 4 sides: a square, faces along x and z
	b.add_cylinder(Transform3D(turn, Vector3.ZERO), 0.5 * sqrt(2.0), 0.36 * sqrt(2.0), 0.6, 4, ArtPalette.IRON, true, ArtPalette.IRON_TOP)
	b.ao_min = 1.0
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * 0.2, 0.68, 0.0)), Vector3(0.1, 0.18, 0.12), 0.0, 1, ArtPalette.IRON)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.8, 0.0)), Vector3(0.5, 0.1, 0.14), 0.03, 1, ArtPalette.IRON, ArtPalette.IRON_TOP)
	return b.commit()


## The water ring: a thin level disk a little wider than the drum (the drum hides its middle).
static func ring_mesh(radius: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_cylinder(Transform3D(Basis(), Vector3(0.0, -0.015, 0.0)), radius + 0.12, radius + 0.12, 0.03, 12, ArtPalette.WATER_TOP)
	return b.commit()


func dress(experiment: Node3D, drum: RigidBody3D, radius: float, height: float, floor_y: float, waterline: float, top: float) -> void:
	_waterline = waterline
	ArtKit.add_world(experiment, Vector3(-0.5, 0.0, -0.8), Vector3.ZERO, HALF_X + 0.6)
	var tank := ArtKit.instance(tank_mesh(floor_y, waterline, top))
	tank.name = "Tank"
	experiment.add_child(tank)
	drum_visual = Node3D.new()
	drum_visual.name = "Visual"
	drum.add_child(drum_visual)
	juice = ArtJuice.new()
	juice.name = "DrumJuice"
	juice.dust_amount = 12
	experiment.add_child(juice)
	ring = MeshInstance3D.new()
	ring.name = "WaterRing"
	ring.material_override = ArtKit.lit_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	experiment.add_child(ring)
	weight_arrow = VelocityArrow.new(ArtPalette.RED, ArtPalette.RED_TOP)
	weight_arrow.name = "WeightArrow"
	experiment.add_child(weight_arrow)
	buoyant_arrow = VelocityArrow.new(ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	buoyant_arrow.name = "BuoyantArrow"
	experiment.add_child(buoyant_arrow)
	var mesh := MeshInstance3D.new()
	mesh.name = "Drum"
	mesh.material_override = ArtKit.lit_material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drum_visual.add_child(mesh)
	juice.setup(drum, drum_visual, height, floor_y)
	weight = ArtKit.instance(weight_mesh())
	weight.name = "Weight"
	drum_visual.add_child(weight)   # on the lid: squashed with the drum
	set_drum(radius, height)
	cat = CatActor.new(BreadCat.new())
	cat.look_target = drum
	cat.position = Vector3(CAT_AT.x, CAT_TOP, CAT_AT.y)
	cat_stand = CatCrates.new(cat.look.footprint)
	experiment.add_child(cat_stand)
	experiment.add_child(cat)
	cat_stand.fit(cat, floor_y)


## The drum (centre `at`) waits for the release (`waiting`): the cat holds it while it is above the
## water; otherwise a cat still holding it lets go.
func update_cat(at: Vector3, waiting: bool) -> void:
	if cat == null:
		return
	var bottom := at.y - _height * 0.5
	if waiting and bottom >= _waterline - 1e-6:
		var root := Vector3(CAT_AT.x, CAT_TOP, CAT_AT.y)
		var y := clampf(root.y + cat.look.shoulders[0].y - 0.1, bottom + 0.06, bottom + _height - 0.04)
		cat.grab(root, CatActor.facing(root, at), CatActor.ball_grip(Vector3(at.x, y, at.z), _radius, root, CAT_SPREAD))
	elif cat.mode == "grab":
		cat.let_go(Vector3.DOWN)


## The drum's size (a new volume): its mesh, the juice's size, the ring and the weight on its lid.
func set_drum(radius: float, height: float) -> void:
	_radius = radius
	_height = height
	(drum_visual.get_node("Drum") as MeshInstance3D).mesh = drum_mesh(radius, height)
	juice.size = height
	ring.mesh = ring_mesh(radius)
	set_mass(_mass)


## The drum's mass `mass` (kg): the weight's width (cube root of the mass against WEIGHT_MASS).
func set_mass(mass: float) -> void:
	_mass = mass
	var w := weight_width(mass)
	weight.scale = Vector3.ONE * w
	weight.position = Vector3(0.0, _height * 0.5, 0.0)


## Width (m) of the weight for `mass` kg: one stuff, the cube root of the mass against WEIGHT_MASS.
static func weight_width(mass: float) -> float:
	return WEIGHT_WIDTH * MassLook.factor(mass, WEIGHT_MASS)


## The ring at the waterline while the drum crosses it; the two force arrows (N) beside the drum
## at `at`, against the buoyant force of the whole drum `full` (N).
func show_forces(at: Vector3, weight: float, buoyant: float, full: float) -> void:
	if ring == null:
		return
	var bottom := at.y - _height * 0.5
	ring.visible = bottom < _waterline and bottom + _height > _waterline
	if ring.visible:
		ring.position = Vector3(at.x, _waterline, at.z)
	_arrow(weight_arrow, Vector3(at.x + _radius + ARROW_GAP, at.y, at.z), -90.0, weight / full)
	_arrow(buoyant_arrow, Vector3(at.x - _radius - ARROW_GAP, at.y, at.z), 90.0, buoyant / full)


func _arrow(arrow: VelocityArrow, origin: Vector3, angle: float, share: float) -> void:
	arrow.visible = share > 0.005
	if arrow.visible:
		arrow.point(origin, angle, snappedf(share * ARROW_PER_FULL, 0.02))


func hide_forces() -> void:
	if ring == null:
		return
	ring.visible = false
	weight_arrow.visible = false
	buoyant_arrow.visible = false


## The drum entered the water at `speed` (m/s): splash and squash.
func splash(speed: float) -> void:
	if juice == null:
		return
	var s := clampf(speed / 4.0, 0.25, 1.0)
	juice.puff(s)
	juice.bump(Vector3.UP, s * 0.6)


## The drum hit the tank floor at `speed`.
func hit_floor(speed: float) -> void:
	if juice != null:
		juice.bump(Vector3.UP, clampf(speed / 3.0, 0.2, 1.0))


func released() -> void:
	if juice != null:
		juice.stretch()
	if cat != null and cat.mode == "grab":
		cat.let_go(Vector3.DOWN)


func reset() -> void:
	if juice != null:
		juice.pop()


func status_changed(_previous: String, current: String) -> void:
	if juice != null and current in ["floating", "staying", "sunk"]:
		juice.wobble()
		if cat != null:
			cat.cheer()
