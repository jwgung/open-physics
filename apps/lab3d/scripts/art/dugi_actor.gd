## Dugi (두기두기), the science rabbit who explains the experiments (Phase 1 Task 4h,
## art-direction.md section 12): the user's model assets/characters/dugi.glb (art_src/characters/
## dugi.py, no armature: each node's origin is its pivot). He stands on the island facing the camera
## and, when the lab has something to show, raises his right arm so the red tip of his pointer stick
## (PointerTip) aims at it. "물리는 모델, 캐릭터는 연기": he has no body, no collision object and no
## layer, and never reads or writes the lab's bodies; what he points at is a point the lab answers
## (Experiment.explain_point).
##
## Draw nodes under Rig (the node that turns and bobs): Static (Body + ArmL in one mesh), Head (nod,
## look) > EarL, EarR (sway), ArmR (turned at the shoulder) > Pointer (the stick: hidden while the arm
## rests, it would hang into the ground) > PointerTip. Plus a blob shadow. One storybook material
## (ArtKit.toon_material) on the atlas.
##
## The animation is code (no AnimationPlayer, no Tween): _process -> advance(delta).
##   rest   idle: a slight bob, the ears sway, the head nods a little
##   raise  explain(): the arm swings from the rest pose to the target over RAISE_S
##   point  the tip stays on the line shoulder -> target (it follows a moving target) for POINT_S
##   lower  stop() or the time is up: back to the rest pose over LOWER_S
class_name DugiActor
extends Node3D

const SCENE := preload("res://assets/characters/dugi.glb")
const RAISE_S := 0.45
const LOWER_S := 0.45
## How long he keeps pointing once the arm is up when nothing holds him (hold_on(): the screen's
## dialogue keeps him pointing while it is open).
const POINT_S := 6.0
## Arm blend (0 rest .. 1 pointing) from which the stick shows: by then its tip is well above the
## ground (tests/island_cast_checks.gd).
const POINTER_SHOW := 0.5
## While pointing he turns his body towards the target by this share of its bearing (at most
## TURN_MAX_DEG): a 3/4 "presenting" pose instead of an arm across the chest.
const TURN_SHARE := 0.35
const TURN_MAX_DEG := 25.0
const HEAD_YAW_MAX := 0.5           # rad the head turns to look at the target
const HEAD_PITCH_MAX := 0.3
const BOB_M := 0.012                # idle bob (m) and its rate
const BOB_HZ := 0.5
const NOD_DEG := 2.0
const EAR_DEG := 5.0                # ear sway (deg) and its rate; the two ears are out of phase
const EAR_HZ := 0.37

var rig: Node3D
var static_mesh: MeshInstance3D
var head: Node3D
var ears: Array[Node3D] = []
var arm: Node3D                     # ArmR
var pointer: Node3D
var pointer_tip: Node3D
var shadow: MeshInstance3D
## ArmR's pivot (rig space) and the shoulder -> PointerTip offset of the rest pose.
var shoulder := Vector3.ZERO
var tip_rest := Vector3.ZERO
var state := "rest"                 # rest / raise / point / lower
## Returns the world point to aim at (called every frame while the arm is up).
var target := Callable()
var _blend := 0.0
var _left := 0.0
var _clock := 0.0
var _point := Vector3.ZERO          # the last target point
var _has_point := false
var _head_rest := Transform3D()
var _ear_rest: Array[Transform3D] = []
## The celebration (2026-10-28: a whole round done): for CELEBRATE_S he hops CELEBRATE_HOPS times
## and waves his free arm over his head (the stick stays hidden).
var _celebrate_left := 0.0
const CELEBRATE_S := 2.0
const CELEBRATE_HOPS := 4
const CELEBRATE_HOP := 0.3
const CELEBRATE_WAVE_HZ := 2.5


func _init() -> void:
	name = "Dugi"
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var model: Node3D = SCENE.instantiate()
	var body := model.get_node("Dugi/Body") as MeshInstance3D
	var material := ArtKit.toon_material((body.mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture)
	# Body and the resting left arm never move against each other: one mesh (one draw call).
	var arm_l := body.get_node("ArmL") as MeshInstance3D
	var st := SurfaceTool.new()
	st.append_from(body.mesh, 0, body.transform)
	st.append_from(arm_l.mesh, 0, body.transform * arm_l.transform)
	static_mesh = MeshInstance3D.new()
	static_mesh.name = "Static"
	static_mesh.mesh = st.commit()
	rig.add_child(static_mesh)
	for node_name in ["Head", "ArmR"]:
		var node := body.get_node(node_name) as Node3D
		var rig_xf := body.transform * node.transform
		body.remove_child(node)
		for n in [node] + node.find_children("*", "", true, false):
			n.owner = null   # it leaves the model scene
		node.transform = rig_xf
		rig.add_child(node)
	model.free()
	head = rig.get_node("Head")
	arm = rig.get_node("ArmR")
	pointer = arm.get_node("Pointer")
	pointer_tip = pointer.get_node("PointerTip")
	for ear_name in ["EarL", "EarR"]:
		ears.append(head.get_node(ear_name))
		_ear_rest.append((head.get_node(ear_name) as Node3D).transform)
	_head_rest = head.transform
	shoulder = arm.position
	tip_rest = arm.basis * (pointer.transform * pointer_tip.position)
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = material
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s := ArtKit.shadow_builder()
	s.add_blob(Transform3D(Basis(), Vector3(0.0, 0.012, 0.0)), 0.45, ArtKit.shadow_alpha(1.0))
	shadow = ArtKit.instance(s.commit(), ArtKit.shadow_material())
	shadow.name = "Shadow"
	add_child(shadow)
	_pose()


# --- queries --------------------------------------------------------------------------------------

func rig_transform() -> Transform3D:
	return (global_transform if is_inside_tree() else transform) * rig.transform


## World position of the right shoulder (the arm's pivot).
func shoulder_point() -> Vector3:
	return rig_transform() * shoulder


## World position of the stick's red tip.
func tip_point() -> Vector3:
	return rig_transform() * (arm.transform * (pointer.transform * pointer_tip.position))


## Explaining: raising the arm or pointing.
func speaking() -> bool:
	return state == "raise" or state == "point"


## World AABB of the drawn meshes (not the shadow; the actor is in the tree).
func bounds() -> AABB:
	return IslandCast.drawn_bounds(rig, shadow)


# --- acting ---------------------------------------------------------------------------------------

## Points at what `point` returns (a world point, asked every frame) for POINT_S once the arm is up.
## Called again while pointing: the new target, the time starts over.
func explain(point: Callable) -> void:
	target = point
	_left = POINT_S
	if state == "rest" or state == "lower":
		state = "raise"


## Keeps pointing for another POINT_S (called every frame while the dialogue is open).
func hold_on() -> void:
	if state == "point" or state == "raise":
		_left = POINT_S


## Back to rest: the arm comes down over LOWER_S, or at once (`instant`: 처음으로).
func stop(instant := false) -> void:
	if instant:
		state = "rest"
		_blend = 0.0
		target = Callable()
		_has_point = false
		_pose()
	elif state != "rest":
		state = "lower"


## He hops and waves (a cleared round): any explanation stops at once first.
func celebrate() -> void:
	stop(true)
	_celebrate_left = CELEBRATE_S


func celebrating() -> bool:
	return _celebrate_left > 0.0


func _process(delta: float) -> void:
	advance(delta)


## Moves the clock on by `delta` s and poses (tests call it with exact steps).
func advance(delta: float) -> void:
	_clock += delta
	_celebrate_left = maxf(0.0, _celebrate_left - delta)
	match state:
		"raise":
			_blend = minf(1.0, _blend + delta / RAISE_S)
			if _blend >= 1.0:
				state = "point"
		"point":
			_left -= delta
			if _left <= 0.0:
				state = "lower"
		"lower":
			_blend = maxf(0.0, _blend - delta / LOWER_S)
			if _blend <= 0.0:
				state = "rest"
				target = Callable()
				_has_point = false
	_pose()


func _pose() -> void:
	var k := smoothstep(0.0, 1.0, _blend)
	if k > 0.0 and target.is_valid():
		var p: Variant = target.call()
		if p is Vector3 and (p as Vector3).is_finite():
			_point = p
			_has_point = true
	var aiming := k > 0.0 and _has_point
	var turn := 0.0
	if aiming:
		var own := (global_transform if is_inside_tree() else transform).affine_inverse() * _point
		var bearing := atan2(own.x, own.z)
		turn = clampf(bearing * TURN_SHARE, -deg_to_rad(TURN_MAX_DEG), deg_to_rad(TURN_MAX_DEG)) * k
	var bob := 0.5 + 0.5 * sin(_clock * TAU * BOB_HZ)
	var hop := 0.0
	if celebrating():
		var c := 1.0 - _celebrate_left / CELEBRATE_S   # whole hops, back down at the end
		hop = CELEBRATE_HOP * absf(sin(c * PI * CELEBRATE_HOPS))
	rig.transform = Transform3D(Basis(Vector3.UP, turn), Vector3(0.0, BOB_M * bob + hop, 0.0))
	var look_yaw := 0.0
	var look_pitch := 0.0
	if aiming:
		var local := rig_transform().affine_inverse() * _point
		var d := (local - shoulder).normalized()
		var aim := Quaternion(tip_rest.normalized(), d)
		arm.basis = Basis(Quaternion.IDENTITY.slerp(aim, k))
		var h := local - _head_rest.origin
		look_yaw = clampf(atan2(h.x, h.z), -HEAD_YAW_MAX, HEAD_YAW_MAX) * k
		look_pitch = clampf(-atan2(h.y, Vector2(h.x, h.z).length()), -HEAD_PITCH_MAX, HEAD_PITCH_MAX) * k
	elif celebrating():
		# The arm up and out over his head, swaying: the shortest turn from rest (as when pointing).
		var w := sin(_clock * TAU * CELEBRATE_WAVE_HZ) * 0.35
		var up := Vector3(-0.55 + w, 0.85, 0.15).normalized()
		var lift := minf(1.0, minf(_celebrate_left, CELEBRATE_S - _celebrate_left) / 0.2)
		arm.basis = Basis(Quaternion.IDENTITY.slerp(Quaternion(tip_rest.normalized(), up), smoothstep(0.0, 1.0, lift)))
	else:
		arm.basis = Basis()
	var nod := deg_to_rad(NOD_DEG) * sin(_clock * TAU * BOB_HZ * 0.5)
	head.transform = Transform3D(_head_rest.basis * Basis.from_euler(Vector3(look_pitch + nod, look_yaw, 0.0)), _head_rest.origin)
	for i in ears.size():
		var sway := deg_to_rad(EAR_DEG) * sin(_clock * TAU * EAR_HZ + i * 1.7)
		var side := 1.0 if i == 0 else -1.0   # EarL (+x) sways out to +x, EarR mirrored
		ears[i].transform = Transform3D(_ear_rest[i].basis * Basis(Vector3.BACK, -side * sway) * Basis(Vector3.RIGHT, sway * 0.5), _ear_rest[i].origin)
	pointer.visible = _blend >= POINTER_SHOW
