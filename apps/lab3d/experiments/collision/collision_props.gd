## Grass island props of the collision lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the floor, ball and knob bodies are built and moved by collision.gd; nothing here
## touches a body (the balls' rolling turns a child mesh, the squash is ArtJuice's mesh transform).
## - the rail: a yellow lane (14 x 1.4 m) between two white guide rails, white metre ticks, a white
##   middle mark between the two start halves and blue bumpers at both walls (visual: the walls are
##   the formula's),
## - ball A blue, ball B orange (the web's object colours, from the palette), yarn balls (Task 4g;
##   until then each with a white band)
##   that shows it rolling, its ArtJuice (shadow, dust, squash) and a yellow knob above it,
## - one arrow per ball above it: the purple velocity arrow to the knob while waiting (the web's
##   purple arrow), the momentum arrow p = mv in the ball's colour while it moves (the web's
##   momentum arrows; length 0.25 m per kg m/s),
## - the force pair at the contact for 0.5 s after a hit: two equal arrows pointing apart (red on A,
##   green on B; the web's "충돌 순간의 힘" overlay),
## - reactions: a hit = both balls squash along the rail (ArtJuice.bump) with dust; release = stretch;
##   reset = pop.
## - the bread cat (CatActor wearing the BreadCat look, 2026-10-27) on the lane behind the blue ball A
##   (on the side A will go away from), both paws on the ball; "출발" pushes (the arms follow through
##   along the start velocity) and it hops off the lane to behind the rail (a ball may come back);
##   next to a bumper it stands behind the rail and reaches over it. It cheers after the first
##   collision. Only meshes: the balls move as the formula model says from the release on.
class_name CollisionProps
extends RefCounted

const LANE_WIDTH := 1.4
const MOMENTUM_SCALE := 0.25     # m of arrow per kg m/s
const MOMENTUM_MAX := 3.0        # m
const ARROW_LIFT := 0.35         # m from a ball's top to its arrow and knob
const LENGTH_STEP := 0.02        # m: arrow lengths are rounded to this (the mesh is rebuilt rarely)
const FORCE_LENGTH := 0.9        # m, each arrow of the force pair
const FORCE_SHOW_S := 0.5
## The cat's base: CAT_BEHIND m from ball A's centre against its start velocity, on the lane; after
## the push (or next to a bumper) behind the rail at z = CAT_OFF_Z.
const CAT_BEHIND := 0.7
const CAT_OFF_Z := -1.1
const CAT_OFF_LEAN := 15.0       # deg: the most it leans over the rail
const CAT_HALF := 0.42           # m: the cat's half width with a margin (it stays off the bumpers)
const CAT_SPREAD := 0.55         # rad: the paws either side of the ball's side facing the cat
const CAT_PAW_LIFT := 0.12       # m above the ball's centre

var juice_a: ArtJuice
var juice_b: ArtJuice
var spin_a: MeshInstance3D
var spin_b: MeshInstance3D
var arrow_a: VelocityArrow
var arrow_b: VelocityArrow
var force_pair: MeshInstance3D
var knob_visual_a: MeshInstance3D
var knob_visual_b: MeshInstance3D
var _radius_a := 0.4
var _radius_b := 0.5
var _force_tween: Tween
var _host: Node3D
var cat: CatActor
var _cheered := false
var _wall := 7.0


func track_mesh(wall: float) -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, -0.028, 0.0)), Vector3(wall * 2.0, 0.06, LANE_WIDTH), 0.02, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	b.ao_min = 1.0
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.03, side * (LANE_WIDTH * 0.5 - 0.04))), Vector3(wall * 2.0, 0.06, 0.08), 0.0, 1, ArtPalette.WHITE)
	var half := int(floorf(wall))
	for i in range(-half + 1, half):
		b.add_rounded_box(Transform3D(Basis(), Vector3(i, 0.006, LANE_WIDTH * 0.5 - 0.25)), Vector3(0.05, 0.02, 0.26), 0.0, 1, ArtPalette.WHITE)
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.006, 0.0)), Vector3(0.07, 0.02, LANE_WIDTH - 0.3), 0.0, 1, ArtPalette.WHITE)
	b.ao_min = 0.85
	b.ao_height = 0.4
	for side in [-1.0, 1.0]:
		b.add_rounded_box(Transform3D(Basis(), Vector3(side * (wall + 0.15), 0.3, 0.0)), Vector3(0.3, 0.6, LANE_WIDTH + 0.2), 0.05, 1, ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	return b.commit()


## The force pair: two arrows from the contact (the origin) pointing apart along x.
static func force_pair_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	VelocityArrow.add_arrow(b, Transform3D(Basis(Vector3.UP, PI), Vector3(-0.06, 0.0, 0.0)), FORCE_LENGTH, ArtPalette.RED, ArtPalette.RED_TOP)
	VelocityArrow.add_arrow(b, Transform3D(Basis(), Vector3(0.06, 0.0, 0.0)), FORCE_LENGTH, ArtPalette.LEAF, ArtPalette.LEAF_LIGHT)
	return b.commit()


func dress(experiment: Node3D, ball_a: RigidBody3D, radius_a: float, ball_b: RigidBody3D, radius_b: float,
		knob_a: Node3D, knob_b: Node3D, wall: float) -> void:
	_host = experiment
	_wall = wall
	_radius_a = radius_a
	_radius_b = radius_b
	ArtKit.add_world(experiment, Vector3(0.0, 0.0, -0.8))
	var track := ArtKit.instance(track_mesh(wall))
	track.name = "Rail"
	experiment.add_child(track)
	var a := _dress_ball(experiment, ball_a, radius_a, ArtPalette.BLUE)
	juice_a = a[0]
	spin_a = a[1]
	var b := _dress_ball(experiment, ball_b, radius_b, ArtPalette.ORANGE)
	juice_b = b[0]
	spin_b = b[1]
	knob_visual_a = knob_a.get_node("Visual")   # built with the knob (Experiment._make_knob)
	knob_visual_b = knob_b.get_node("Visual")
	arrow_a = VelocityArrow.new()
	arrow_a.name = "ArrowA"
	experiment.add_child(arrow_a)
	arrow_b = VelocityArrow.new()
	arrow_b.name = "ArrowB"
	experiment.add_child(arrow_b)
	force_pair = ArtKit.instance(force_pair_mesh())
	force_pair.name = "ForcePair"
	force_pair.visible = false
	experiment.add_child(force_pair)
	cat = CatActor.new(BreadCat.new())
	cat.look_target = ball_a
	experiment.add_child(cat)


## Where the cat stands for ball A at `at` that will start with `velocity` (m/s) on a rail with its
## bumper faces at +-`wall`: behind the ball on the lane, or behind the rail when that is too close
## to a bumper.
static func cat_root(at: Vector3, velocity: float, wall: float) -> Vector3:
	var side := -1.0 if velocity < 0.0 else 1.0
	var x := at.x - side * CAT_BEHIND
	if absf(x) + CAT_HALF > wall:
		return Vector3(at.x + side * 0.1, 0.0, CAT_OFF_Z)
	return Vector3(x, 0.0, 0.0)


## Waiting (not released): the cat's paws on ball A at `at` (radius `radius`, start `velocity`).
func update_cat(at: Vector3, radius: float, velocity: float, released_now: bool) -> void:
	if cat == null or released_now:
		return
	var root := cat_root(at, velocity, _wall)
	# Behind the rail it reaches over it, its head kept off the ball (the arms reach the rest).
	cat.grab(root, CatActor.facing(root, at), CatActor.ball_grip(at, radius, root, CAT_SPREAD, CAT_PAW_LIFT), 0.0,
		CatActor.GRAB_LEAN_FWD_DEG if root.z == 0.0 else CAT_OFF_LEAN)


## Visual node (squashed by the juice) with the spinning ball mesh under it; [juice, spin mesh].
func _dress_ball(experiment: Node3D, ball: RigidBody3D, radius: float, color: Color) -> Array:
	var visual := Node3D.new()
	visual.name = "Visual"
	ball.add_child(visual)
	var spin := ArtKit.yarn_ball(radius, color)   # a yarn ball (Task 4g); it turns with the rolling
	spin.name = "Spin"
	visual.add_child(spin)
	var juice := ArtJuice.new()
	juice.name = ball.name + "Juice"
	juice.round_body = true
	juice.dust_amount = 10   # two balls: at most 20 grains at once
	experiment.add_child(juice)
	juice.setup(ball, visual, radius * 2.0)
	return [juice, spin]


## Rolling: each ball's mesh turned by its distance from the start over its radius (about z).
func spin(moved_a: float, moved_b: float) -> void:
	if spin_a == null:
		return
	spin_a.rotation.z = -moved_a / _radius_a
	spin_b.rotation.z = -moved_b / _radius_b


## Waiting: purple velocity arrows from above each ball to its knob, signed lengths `la` / `lb` (m,
## up to the knob's near face; 0 = hidden, any other length is drawn at least VelocityArrow.MIN_LENGTH long).
func show_velocity(at_a: Vector3, radius_a: float, la: float, at_b: Vector3, radius_b: float, lb: float) -> void:
	arrow_a.set_colors(ArtPalette.PURPLE, ArtPalette.PURPLE_TOP)
	arrow_b.set_colors(ArtPalette.PURPLE, ArtPalette.PURPLE_TOP)
	_place(arrow_a, at_a, radius_a, la)
	_place(arrow_b, at_b, radius_b, lb)


## Running: momentum arrows in the balls' colours (length 0.25 m per kg m/s, at most 3 m).
func show_momentum(at_a: Vector3, radius_a: float, pa: float, at_b: Vector3, radius_b: float, pb: float) -> void:
	arrow_a.set_colors(ArtPalette.BLUE, ArtPalette.BLUE_DARK)
	arrow_b.set_colors(ArtPalette.ORANGE, ArtPalette.ORANGE_TOP)
	_place(arrow_a, at_a, radius_a, clampf(pa * MOMENTUM_SCALE, -MOMENTUM_MAX, MOMENTUM_MAX))
	_place(arrow_b, at_b, radius_b, clampf(pb * MOMENTUM_SCALE, -MOMENTUM_MAX, MOMENTUM_MAX))


## Height of a ball's arrow and knob centre above the floor.
static func arrow_height(radius: float) -> float:
	return 2.0 * radius + ARROW_LIFT


## An arrow above the ball at `at` with signed length `length` (+ = to the right). Hidden only when
## the length rounds to 0; a short one is drawn at VelocityArrow.MIN_LENGTH (a slow ball or a small
## momentum still shows its direction).
func _place(arrow: VelocityArrow, at: Vector3, radius: float, length: float) -> void:
	var l := snappedf(absf(length), LENGTH_STEP)
	arrow.visible = l > 0.0
	if arrow.visible:
		arrow.point(Vector3(at.x, arrow_height(radius), 0.0), 0.0 if length > 0.0 else 180.0, l)


## A hit at x = `contact_x` with strength 0..1: both balls squash along the rail, the force pair shows.
func hit(contact_x: float, strength: float) -> void:
	if juice_a == null:
		return
	juice_a.bump(Vector3.RIGHT, strength)
	juice_b.bump(Vector3.RIGHT, strength)
	force_pair.position = Vector3(contact_x, 2.0 * maxf(_radius_a, _radius_b) + 0.75, 0.0)
	force_pair.visible = true
	if _force_tween != null and _force_tween.is_valid():
		_force_tween.kill()
	_force_tween = _host.create_tween()
	_force_tween.tween_interval(FORCE_SHOW_S)
	_force_tween.tween_callback(force_pair.hide)


## "출발": `velocity_a` is ball A's start velocity (the cat's push follows it through).
func released(velocity_a := 0.0) -> void:
	knob_visual_a.visible = false
	knob_visual_b.visible = false
	juice_a.stretch()
	juice_b.stretch()
	_cheered = false
	if cat != null:
		cat.let_go(Vector3(signf(velocity_a), 0.0, 0.0), Vector3(cat.position.x, 0.0, CAT_OFF_Z))


func reset() -> void:
	if juice_a == null:
		return
	knob_visual_a.visible = true
	knob_visual_b.visible = true
	force_pair.visible = false
	juice_a.pop()
	juice_b.pop()


## Coming to rest: a small settle of both balls.
func status_changed(_previous: String, current: String) -> void:
	if current == "rest" and juice_a != null:
		juice_a.wobble()
		juice_b.wobble()
	# The first collision of the run (its result): the cat cheers.
	if current == "collided" and cat != null and not _cheered:
		_cheered = true
		cat.cheer()
