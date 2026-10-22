## Grass island props of the collision lab (apps/lab3d/docs/art-direction.md, section 9). Meshes and
## reactions only: the floor, ball and knob bodies are built and moved by collision.gd; nothing here
## touches a body (the balls' rolling turns a child mesh, the squash is ArtJuice's mesh transform).
## - the rail: a yellow lane (14 x 1.4 m) between two white guide rails, white metre ticks, a white
##   middle mark between the two start halves and blue bumpers at both walls (visual: the walls are
##   the formula's),
## - ball A blue, ball B orange (the web's object colours, from the palette), each with a white band
##   that shows it rolling, its ArtJuice (shadow, dust, squash) and a yellow knob above it,
## - one arrow per ball above it: the purple velocity arrow to the knob while waiting (the web's
##   purple arrow), the momentum arrow p = mv in the ball's colour while it moves (the web's
##   momentum arrows; length 0.25 m per kg m/s),
## - the force pair at the contact for 0.5 s after a hit: two equal arrows pointing apart (red on A,
##   green on B; the web's "충돌 순간의 힘" overlay),
## - reactions: a hit = both balls squash along the rail (ArtJuice.bump) with dust; release = stretch;
##   reset = pop.
class_name CollisionProps
extends RefCounted

const LANE_WIDTH := 1.4
const MOMENTUM_SCALE := 0.25     # m of arrow per kg m/s
const MOMENTUM_MAX := 3.0        # m
const ARROW_LIFT := 0.35         # m from a ball's top to its arrow and knob
const LENGTH_STEP := 0.02        # m: arrow lengths are rounded to this (the mesh is rebuilt rarely)
const FORCE_LENGTH := 0.9        # m, each arrow of the force pair
const FORCE_SHOW_S := 0.5

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


## A low-poly ball with a white band around its x axis (turns with the rolling).
static func ball_mesh(radius: float, color: Color) -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = radius * 1.2
	b.add_sphere(Transform3D.IDENTITY, radius, 4, 7, color)
	b.ao_min = 1.0
	var along_x := Basis(Vector3.BACK, -PI * 0.5)
	b.add_cylinder(Transform3D(along_x, Vector3(-radius * 0.1, 0.0, 0.0)), radius * 1.02, radius * 1.02, radius * 0.2, 7, ArtPalette.WHITE, false)
	return b.commit()


## The force pair: two arrows from the contact (the origin) pointing apart along x.
static func force_pair_mesh() -> Mesh:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	VelocityArrow.add_arrow(b, Transform3D(Basis(Vector3.UP, PI), Vector3(-0.06, 0.0, 0.0)), FORCE_LENGTH, ArtPalette.RED, ArtPalette.RED_TOP)
	VelocityArrow.add_arrow(b, Transform3D(Basis(), Vector3(0.06, 0.0, 0.0)), FORCE_LENGTH, ArtPalette.LEAF, ArtPalette.LEAF_LIGHT)
	return b.commit()


func dress(experiment: Node3D, ball_a: RigidBody3D, radius_a: float, ball_b: RigidBody3D, radius_b: float,
		knob_a: Node3D, knob_b: Node3D, knob_size: float, wall: float) -> void:
	_host = experiment
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
	var knob := VelocityArrow.knob_mesh(knob_size)
	knob_visual_a = ArtKit.instance(knob)
	knob_visual_a.name = "Visual"
	knob_a.add_child(knob_visual_a)
	knob_visual_b = ArtKit.instance(knob)
	knob_visual_b.name = "Visual"
	knob_b.add_child(knob_visual_b)
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


## Visual node (squashed by the juice) with the spinning ball mesh under it; [juice, spin mesh].
func _dress_ball(experiment: Node3D, ball: RigidBody3D, radius: float, color: Color) -> Array:
	var visual := Node3D.new()
	visual.name = "Visual"
	ball.add_child(visual)
	var spin := ArtKit.instance(ball_mesh(radius, color))
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
## up to the knob's near face; too short = hidden, the knob covers it).
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


## An arrow above the ball at `at` with signed length `length` (+ = to the right; too short = hidden).
func _place(arrow: VelocityArrow, at: Vector3, radius: float, length: float) -> void:
	var l := snappedf(absf(length), LENGTH_STEP)
	arrow.visible = l >= VelocityArrow.MIN_LENGTH
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


func released() -> void:
	knob_visual_a.visible = false
	knob_visual_b.visible = false
	juice_a.stretch()
	juice_b.stretch()


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
