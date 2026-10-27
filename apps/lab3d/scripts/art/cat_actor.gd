## A character that acts what the student does, in step with the formula model (Phase 1 Task 4g,
## art-direction.md section 11): it throws the projectile lab's ball, pushes the friction lab's box
## and has a hand in every other lab (holds and lets go, pulls, presses; 2026-10-27). "물리는 모델,
## 고양이는 연기": it never touches the physics (no body, no collision object, no layer); the labs'
## motion and panel values are the same with or without it
## (tests/bread_cat_checks.gd). What it looks like is a CatLook (meshes + the points of its body the
## acting uses: shoulders, reach, neck, ...), so the look can be replaced without touching the sync.
##
## The animation is code (no AnimationPlayer, no Tween): _process advances the clock and poses the
## rig from the mode the lab set:
##   hold(center, r, floor)  the left paw holds a ball of radius r centred at `center` (along the
##                           look's hold_dir from the shoulder, or a given direction: the right paw
##                           when it points to -x); the actor is placed so its arm reaches it,
##                           raised off `floor` when the ball is high (the lab draws a stand of
##                           stand_height) and kept under a `ceiling` (the arm stretches up)
##   throw(dir, on_release)  windup (the ball up and back over the head) and an overhand swing that
##                           reaches the hold pose moving along `dir`, fastest at the release; the ball (`carried`) follows the paw; on the frame the swing
##                           is back at the hold pose (the ball's launch point) on_release runs, then
##                           the arm follows through and rests
##   let_go(dir, retreat)    what the paws held was let go without a throw: the arms follow through
##                           along `dir` and settle, the lean and turn ease back, the actor steps to
##                           `retreat` (if given) and drops to its floor (a hanging pull)
##   push(face_x, ...)       both paws on the plane x = face_x (the box face), the actor behind it (-x),
##                           leaning with the effort
##   grab(root, yaw, pts)    both paws on two points from where the actor stands (on a stand the lab
##                           draws): it leans forward or back until its shoulders reach them (the arms
##                           stretch the rest); `effort` squashes the bread bag a little (pressing)
##   pull(grip, dir, ...)    both paws on a grip (a rope end, a ball) reached along `dir`: the actor
##                           stands where its paws reach it, on its floor or hanging from it when the
##                           grip is high (it jumps up to it), leaning back with the effort
##   cheer(arms)             a small hop (and paws up) when something lands or stops; with the paws
##                           busy (grab, pull, push) only a nod
## The look's hand nodes (under each arm, at the paw centre) show where the paws hold and touch.
class_name CatActor
extends Node3D

## Emitted on the release frame, right after on_release ran (tests).
signal threw

const ARM_R := 0                    # the right paw (-x, facing +z)
const ARM_L := 1                    # left paw (+x): holds and throws the ball
const ARM_HOLD := ARM_L
## Throw timing (s): windup, swing (the release is at its end), follow-through, back to rest.
const WINDUP_S := 0.24
const SWING_S := 0.24
const FOLLOW_S := 0.14
const SETTLE_S := 0.3
const SWING_STRAIGHT := 0.15       # m of straight swing along the throw before the launch point
const SWING_LEAD := 0.2            # m the cubic's last control point lies before that straight part
const SWING_BOW := 0.15             # m the swing curve bows out away from the body
const WINDUP_UP := 0.45            # m the windup point is above the launch point,
const WINDUP_BACK := 0.5           # back against the throw,
const WINDUP_DEPTH := 0.55          # behind it
const WINDUP_OUT := 0.15            # and out away from the body (clear of the head)
const CURVE_SAMPLES := 96
const FOLLOW_DEG := 40.0
const CHEER_S := 0.45
const CHEER_HOP := 0.08
const LEAN_MAX_DEG := 16.0          # push lean at full effort
const SHUFFLE_STEP := 0.3           # m of travel per shuffle hop while pushing
const SHUFFLE_HOP := 0.035
const BLINK_S := 0.13
const HEAD_YAW_MAX := 1.0           # rad the head turns towards what it looks at
const PUSH_HEAD_YAW := -1.05        # rad: a pushing actor (facing +x) looks towards the camera (+z)
const PUSH_LEAN_DEG := 8.0          # a pushing actor leans towards the box this much at rest
## Grab: the most it leans forward / back to reach its points (searched in GRAB_STEP_DEG steps).
const GRAB_LEAN_FWD_DEG := 60.0
const GRAB_LEAN_BACK_DEG := 25.0
const GRAB_STEP_DEG := 2.0
const GRAB_SQUASH := 0.12           # the bag's height shrinks this share at full effort (pressing)
## Pull: lean back at full effort; each paw this far beside the grip (m).
const PULL_LEAN_DEG := 20.0
const PULL_SPREAD := 0.07
const JUMP_SPEED := 6.0             # m/s the actor rises to a grip above its reach
const JUMP_STRETCH_MAX := 1.4       # arm stretch while it rises (the paws reach for the grip)
const FALL_G := 9.81                # m/s^2: let go while hanging, it drops to its floor
const RETREAT_HOP := 0.18           # m: the hop of a step to a retreat point

var look: CatLook
var rig: Node3D
var body: Node3D
var head: Node3D
var eyes: Node3D
var tail: Node3D
var tail2: Node3D
var arms: Array[Node3D] = []
var hands: Array[Node3D] = []
var _arm_rest: Array[Basis] = []    # the arms' rest bases (rig space)
var shadow: MeshInstance3D
## A node the head turns to while not holding or pushing (the flying ball).
var look_target: Node3D
## Called with the world point a carried ball's centre is at, every frame of a throw before the
## release (and once with the launch point on the release frame).
var carried: Callable
## Returns the x of the face being pushed when the actor poses (push mode): read at pose time, so the
## paws follow a box mesh that its reactions moved earlier in the frame. Unset: push()'s face_x.
var push_face: Callable
## Pushing: the paws stay this far (m, along z) from the middle of the face at most.
var push_half_width := 0.2

var mode := "free"                  # free / hold / throw / follow / push / grab / pull
## Height of the base above the floor hold() was given (the lab draws a stand that tall).
var stand_height := 0.0
var _clock := 0.0
var _dt := 0.0                      # the last advance() step (s)
var _next_blink := 1.7
var _blink := -1.0                  # time into a blink, < 0: none
var _cheer := -1.0                  # time into a cheer, < 0: none
var _cheer_arms := true
var _head_yaw := 0.0
# hold / throw / follow
var _held := Vector3.ZERO           # ball centre held (the launch point)
var _held_radius := 0.0
var _floor_y := 0.0
var _hold_arm := ARM_HOLD           # the paw that holds (the right one for a ball at -x)
var _hold_stretch := 1.0            # its stretch (> 1 only under a ceiling)
var _u := Vector3.FORWARD           # unit shoulder -> held ball centre
var _dir := Vector3.RIGHT           # throw direction
var _swing := Vector3.UP            # unit follow-through direction (across _u)
var _t := 0.0                       # time into the throw / follow-through
var _on_release := Callable()
var _arm_dirs: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var _stretch: Array[float] = [1.0, 1.0]   # arm length / its rest length
var _windup := Vector3.ZERO         # windup point of the throw (world)
var _curve_points := PackedVector3Array()   # the swing curve sampled from the windup point (world)
var _curve_length := PackedFloat32Array()   # arc length to each sample
# push
var _face_x := 0.0
var _hand_y := 0.5
var _effort := 0.0                  # -1 (pulling hard) .. 1 (pushing hard)
var _travel := 0.0
var _speed := 0.0
# grab / pull
var _targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # where the right / left paw touches
var _yaw := 0.0                     # rad the rig faces (about +y, from +z)
var _lean := 0.0                    # rad the rig leans now (+ forward)
var _squash := 1.0                  # the bag's height share now
var _grip := Vector3.ZERO
var _pull_dir := Vector3.FORWARD    # shoulders -> grip
var _rising := false                # a pull rises to a high grip (the paws do not reach it yet)
var _grab_fwd := deg_to_rad(GRAB_LEAN_FWD_DEG)
var _pull_ball := 0.0               # radius of a ball the pull's paws are on (0: a grip)
var _grab_key := []                 # the input the lean was last solved for (solved again only on a change)
## Cheers so far (tests).
var cheers := 0
# follow-through after a release (let_go, the throw's release)
var _rel_arms: Array[bool] = [false, false]
var _rel_from: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var _rel_swing: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _rel_end: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]   # arm directions at the swing's end
var _rel_stretch: Array[float] = [1.0, 1.0]
var _rel_yaw := 0.0
var _rel_lean := 0.0
var _rel_squash := 1.0
var _rel_pos := Vector3.ZERO
var _retreat := Vector3.INF
var _fall_v := 0.0
var _falls := false


func _init(cat_look: CatLook) -> void:
	look = cat_look
	name = "CatActor"
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var parts := look.build(rig)
	body = parts.get("body")
	head = parts.get("head")
	eyes = parts.get("eyes")
	tail = parts.get("tail")
	tail2 = parts.get("tail2")
	for i in 2:
		arms.append(parts.arms[i])
		hands.append(parts.hands[i])
		_arm_rest.append((parts.arms[i] as Node3D).basis)
	var s := ArtKit.shadow_builder()
	s.add_soft_rect(Transform3D(Basis(), Vector3(0.0, 0.012, 0.0)), look.footprint * 0.45, 0.22, ArtKit.shadow_alpha(1.1), ArtPalette.SHADOW, 3)
	shadow = ArtKit.instance(s.commit(), ArtKit.shadow_material())
	shadow.name = "Shadow"
	add_child(shadow)
	for i in 2:
		_arm_dirs[i] = _rest_dir(i)
		_aim(i, _arm_dirs[i])


# --- queries --------------------------------------------------------------------------------------

## The rig's transform in the world (or in the parent's space before the actor is in the tree).
func rig_transform() -> Transform3D:
	return (global_transform if is_inside_tree() else transform) * rig.transform


## World position of shoulder `i`.
func shoulder(i: int) -> Vector3:
	return rig_transform() * look.shoulders[i]


## World direction arm `i` points (shoulder -> hand), from its posed transform.
func arm_dir(i: int) -> Vector3:
	return (rig_transform().basis * arms[i].basis * (_arm_rest[i].inverse() * look.hand_rest[i])).normalized()


## World point of paw `i`'s front (what touches the box).
func hand_point(i: int) -> Vector3:
	return shoulder(i) + arm_dir(i) * look.reach * _stretch[i]


## Where the centre of a ball in the holding paw is now (the hand is the grip point: the ball's centre
## is held `reach` + radius from the shoulder, its surface at the paw's front).
func held_point() -> Vector3:
	return shoulder(_hold_arm) + arm_dir(_hold_arm) * (look.reach + _held_radius) * _stretch[_hold_arm]


## The paw that holds a ball (hold, throw).
func hold_arm() -> int:
	return _hold_arm


func throwing() -> bool:
	return mode == "throw"


## The paws are on something (a held ball, a face, grabbed points, a grip).
func attached() -> bool:
	return mode in ["hold", "throw", "push", "grab", "pull"]


## A pull still rises to its grip (the paws reach it once it is up).
func rising() -> bool:
	return mode == "pull" and _rising


## The rig's lean now (rad, + forward): grab and pull solve it each frame.
func lean() -> float:
	return _lean


## Arm `i`'s length / its rest length now.
func stretch(i: int) -> float:
	return _stretch[i]


## World AABB of the actor's drawn meshes (not its shadow; the actor is in the tree): what a
## close-up frames (CameraRig.focus).
func bounds() -> AABB:
	var box := AABB()
	var first := true
	for m in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## The turn (rad about +y, from +z) of an actor at `from` that faces `to` (level).
static func facing(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


## The points where an actor standing at `root` and facing a ball (centre `center`, radius
## `radius`) puts its paws on it: on the ball's side towards the actor, `spread` rad to either side
## of the level line to it and `lift` m above the centre's height; [right paw, left paw].
static func ball_grip(center: Vector3, radius: float, root: Vector3, spread: float, lift := 0.0) -> Array[Vector3]:
	var n := Vector3(root.x - center.x, 0.0, root.z - center.z).normalized()
	var y := clampf(lift / radius, -0.95, 0.95)
	var flat := sqrt(1.0 - y * y)
	# The actor faces -n: its left paw (+x in its own space) is towards -n turned +90 deg = n turned
	# -90 deg about +y.
	var right := n.rotated(Vector3.UP, spread) * flat + Vector3.UP * y
	var left := n.rotated(Vector3.UP, -spread) * flat + Vector3.UP * y
	return [center + right * radius, center + left * radius] as Array[Vector3]


# --- modes ----------------------------------------------------------------------------------------

## Holds a ball of radius `radius` centred at `center` in a paw (gripping) or only stands where it
## would (grip false: a finger holds the ball). Placed so the paw reaches it: the shoulder is
## reach + radius from the centre along `dir` (rig space, the actor facing +z; default the look's
## hold_dir: the left paw, the ball out to +x; a `dir` to -x holds it in the right paw), raised off
## `floor_y` when the ball is high, on the floor when it is low (then the arm points down to it), and
## no higher than `ceiling` (then the arm stretches up to the ball). A throw in progress stops.
func hold(center: Vector3, radius: float, floor_y: float, grip := true, dir := Vector3.ZERO, ceiling := INF) -> void:
	_on_release = Callable()
	_held = center
	_held_radius = radius
	_floor_y = floor_y
	_cheer = -1.0
	var u := (look.hold_dir if dir == Vector3.ZERO else dir).normalized()
	_hold_arm = ARM_R if u.x < 0.0 else ARM_L
	var reach := look.reach + radius
	var sh: Vector3 = look.shoulders[_hold_arm]
	var s := center - u * reach
	var root := s - sh
	_hold_stretch = 1.0
	if root.y < floor_y:
		root.y = floor_y
		s.y = floor_y + sh.y
		var flat := Vector2(u.x, u.z).normalized()
		var across := sqrt(maxf(reach * reach - (center.y - s.y) * (center.y - s.y), 0.0))
		s.x = center.x - flat.x * across
		s.z = center.z - flat.y * across
		root = s - sh
	elif root.y > ceiling:
		root.y = ceiling
		s = root + sh
		_hold_stretch = s.distance_to(center) / reach
	stand_height = root.y - floor_y
	position = root
	rig.transform = Transform3D.IDENTITY
	_yaw = 0.0
	_lean = 0.0
	_squash = 1.0
	_u = (center - s).normalized()
	mode = "hold" if grip else "free"
	if not grip:
		_hold_stretch = 1.0
	_arm_dirs[_hold_arm] = _u if grip else _rest_dir(_hold_arm)
	_arm_dirs[1 - _hold_arm] = _rest_dir(1 - _hold_arm)
	_pose()


## Throws the held ball along the world direction `dir`: windup (WINDUP_S, the ball up over the head)
## and swing (SWING_S, down and in along `dir` to the launch point) of the holding arm around its
## shoulder; the ball's centre follows the paw (`carried`); on the frame the swing is back at the hold
## pose (the ball's centre = the launch point) `on_release` runs, then the arm follows through. Not
## holding: releases at once.
func throw(dir: Vector3, on_release: Callable) -> void:
	if mode != "hold":
		on_release.call()
		return
	_set_swing(dir)
	_windup = _windup_point()
	_build_swing()
	_on_release = on_release
	_t = 0.0
	mode = "throw"


## What the paws held was let go without a throw (a direct release): the holding arms follow through
## along `dir` and settle to rest while the lean, turn and squash ease back; the actor steps to
## `retreat` (a world point on its floor; INF: it stays) and, hanging from a grip, drops to its floor.
func let_go(dir: Vector3, retreat := Vector3.INF) -> void:
	var held: Array[bool] = [false, false]
	match mode:
		"hold":
			held[_hold_arm] = true
		"grab", "pull", "push":
			held = [true, true]
		_:
			return
	_dir = dir.normalized() if dir.length_squared() > 1e-12 else Vector3.ZERO
	_begin_follow(held, retreat)


## Both paws on the plane x = `face_x` at height `hand_y` (the face of the box being pushed, box to
## the actor's +x), `effort` -1 (pulling hard) .. 1 (pushing hard) leans it, `travel` (m) and `speed`
## (m/s) of the box shuffle it along. The root follows so the paws stay on the face. Only stores the
## input: the actor poses once a frame in its own _process (a child of the experiment, so after the
## lab's _process that calls this; tests call advance()).
func push(face_x: float, hand_y: float, effort: float, travel: float, speed: float, z := 0.0, floor_y := 0.0) -> void:
	_face_x = face_x
	_hand_y = hand_y
	_effort = clampf(effort, -1.0, 1.0)
	_travel = travel
	_speed = speed
	mode = "push"
	position = Vector3(position.x, floor_y, z)


## Both paws on the world points `targets` ([right paw, left paw]) from where the actor stands
## (`root`: its base, on a stand the lab draws; facing `yaw` rad about +y from +z): the rig leans
## forward or back (the least that does it, within GRAB_LEAN_FWD_DEG / GRAB_LEAN_BACK_DEG) until the
## shoulders are `reach` from the points, the arms stretch the rest, so the paws' fronts are on the
## points exactly. `effort` 0..1 squashes the bag (pressing hard); `lean_max` (deg) limits the lean
## forward (a head that must stay clear of something in front). Only stores the input (poses in
## _process, like push).
func grab(root: Vector3, yaw: float, targets: Array[Vector3], effort := 0.0, lean_max := GRAB_LEAN_FWD_DEG) -> void:
	position = root
	_grab_fwd = deg_to_rad(lean_max)
	_yaw = yaw
	_targets[0] = targets[0]
	_targets[1] = targets[1]
	_effort = clampf(effort, 0.0, 1.0)
	mode = "grab"


## Both paws on `grip` (PULL_SPREAD to either side), reached along the world direction `dir`
## (shoulders -> grip; the actor faces along it): the actor stands where its shoulders are `reach`
## from the grip, on `floor_y` (its arms point up or down to the grip when that is lower) or above
## it, hanging, when the grip is higher than its paws reach from the floor (it rises at JUMP_SPEED,
## its paws reaching up). `effort` -1..1 leans it back (pulling) or forward (pushing). A `ball`
## radius > 0 puts the paws on that ball (centre `grip` + `dir` * radius) beside the grip. Poses in
## _process.
func pull(grip: Vector3, dir: Vector3, floor_y: float, effort := 0.0, ball := 0.0) -> void:
	_pull_ball = ball
	if mode != "pull":
		_rising = false
	_grip = grip
	_pull_dir = dir.normalized() if dir.length_squared() > 1e-12 else Vector3.FORWARD
	_floor_y = floor_y
	_effort = clampf(effort, -1.0, 1.0)
	mode = "pull"


## A small happy hop (and both paws up, `arms_up`, unless the paws are busy: then only a nod).
func cheer(arms_up := true) -> void:
	_cheer = 0.0
	_cheer_arms = arms_up
	cheers += 1


# --- animation ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta)


## Moves the clock on by `delta` s and poses (tests call it with exact steps).
func advance(delta: float) -> void:
	_dt = delta
	_clock += delta
	if _blink >= 0.0:
		_blink += delta
		if _blink > BLINK_S:
			_blink = -1.0
	elif _clock >= _next_blink:
		_blink = 0.0
		# 2.2-4.0 s apart, a fixed pseudo-random sequence (no RNG state shared with anything).
		_next_blink = _clock + 2.2 + 1.8 * fposmod(sin(_clock * 12.9898) * 43758.5453, 1.0)
	if _cheer >= 0.0:
		_cheer += delta
		if _cheer > CHEER_S:
			_cheer = -1.0
	match mode:
		"throw":
			_t += delta
			if _t >= WINDUP_S + SWING_S:
				# The release frame: the arm exactly at the hold pose, the ball at the launch point.
				_arm_dirs[_hold_arm] = _u
				_stretch[_hold_arm] = 1.0
				_pose()
				if carried.is_valid():
					carried.call(held_point())
				var release := _on_release
				_on_release = Callable()
				var held: Array[bool] = [false, false]
				held[_hold_arm] = true
				_begin_follow(held, Vector3.INF)
				if release.is_valid():
					release.call()
				threw.emit()
				return
			var p := _throw_point(_t)
			var to := p - shoulder(_hold_arm)
			_arm_dirs[_hold_arm] = to.normalized()
			_stretch[_hold_arm] = to.length() / (look.reach + _held_radius)
			_pose()
			if carried.is_valid():
				carried.call(held_point())
			return
		"follow":
			_t += delta
			var follow := deg_to_rad(FOLLOW_DEG)
			if _t < FOLLOW_S:
				var k := _t / FOLLOW_S
				var angle := follow * (1.0 - (1.0 - k) * (1.0 - k))
				for i in 2:
					if _rel_arms[i]:
						_arm_dirs[i] = (_rel_from[i] * cos(angle) + _rel_swing[i] * sin(angle)).normalized()
						_rel_end[i] = _arm_dirs[i]
						_stretch[i] = lerpf(_rel_stretch[i], 1.0, k)
			else:
				var k := clampf((_t - FOLLOW_S) / SETTLE_S, 0.0, 1.0)
				for i in 2:
					if _rel_arms[i]:
						_arm_dirs[i] = _rel_end[i].slerp(_rest_dir_world(i), k * k * (3.0 - 2.0 * k))
						_stretch[i] = 1.0
				if k >= 1.0:
					mode = "free"
			_settle_body()
	_pose()


## The rig after a release: the lean, turn and squash ease back over the follow-through and settle,
## the root steps to the retreat point, and a hanging actor falls to its floor.
func _settle_body() -> void:
	var k := clampf(_t / (FOLLOW_S + SETTLE_S), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	_yaw = lerp_angle(_rel_yaw, 0.0, k)
	_lean = lerpf(_rel_lean, 0.0, k)
	_squash = lerpf(_rel_squash, 1.0, k)
	var at := position
	if is_finite(_retreat.x):
		at = _rel_pos.lerp(_retreat, k)
		at.y += RETREAT_HOP * sin(PI * k) * minf(1.0, _rel_pos.distance_to(_retreat) / 0.3)
	if _falls and at.y > _floor_y:
		_fall_v += FALL_G * _dt
		at.y = maxf(_floor_y, at.y - _fall_v * _dt)
	position = at
	if mode == "free":
		_yaw = 0.0
		_lean = 0.0
		_squash = 1.0


## Starts the follow-through of the arms `held` from where they point now (each swings along the
## release direction _dir, across itself) and the body's settling from its pose now towards
## `retreat` (INF: it stays); only a pull (hanging from its grip) falls to its floor.
func _begin_follow(held: Array[bool], retreat: Vector3) -> void:
	_falls = mode == "pull"
	_retreat = retreat
	for i in 2:
		_rel_arms[i] = held[i]
		_rel_from[i] = _arm_dirs[i]
		_rel_stretch[i] = _stretch[i]
		if i == _hold_arm and mode in ["hold", "throw"]:
			_set_swing(_dir)
			_rel_swing[i] = _swing
		else:
			var across := _dir - _arm_dirs[i] * _dir.dot(_arm_dirs[i])
			_rel_swing[i] = across.normalized() if across.length_squared() > 1e-8 else _arm_dirs[i]
	_rel_yaw = _yaw
	_rel_lean = _lean
	_rel_squash = _squash
	_rel_pos = position
	_fall_v = 0.0
	_t = 0.0
	mode = "follow"


## Where the held ball's centre is `t` s into the throw. Windup (WINDUP_S): from the launch point up
## and back against the throw to the windup point (_windup_point), easing out to rest there. Swing
## (SWING_S): from rest along a curve (_swing_curve) that ends at the launch point moving exactly along
## the throw direction, its distance growing as (t / SWING_S)^2: the paw's speed rises steadily and is
## the largest on the release frame. At WINDUP_S + SWING_S it is the launch point.
func _throw_point(t: float) -> Vector3:
	if t < WINDUP_S:
		var k := t / WINDUP_S
		k = 1.0 - (1.0 - k) * (1.0 - k)
		var lift := _held + Vector3.UP * maxf(_windup.y - _held.y, 0.0)
		return _held.lerp(lift, k).lerp(lift.lerp(_windup, k), k)   # quadratic: up first, then back
	var k := clampf((t - WINDUP_S) / SWING_S, 0.0, 1.0)
	return _curve_at(_curve_length[-1] * k * k)


## Out from the body on the holding paw's side (world).
func _out() -> Vector3:
	return (rig_transform().basis * (Vector3.RIGHT if _hold_arm == ARM_L else Vector3.LEFT)).normalized()


## The windup point: WINDUP_BACK back against the throw from the launch point, up to WINDUP_UP above
## that, WINDUP_DEPTH behind and WINDUP_OUT out (back and up beside the head for a level throw, back
## and down for a steep one; the arm stretches).
func _windup_point() -> Vector3:
	var back := (rig_transform().basis * Vector3.BACK).normalized()
	# Up as much as the throw is level (cos of its elevation): a steep throw winds back under the
	# release, so its swing comes up along it without a loop.
	var level := sqrt(maxf(1.0 - _dir.y * _dir.y, 0.0))
	return _held - _dir * WINDUP_BACK + Vector3.UP * WINDUP_UP * level - back * WINDUP_DEPTH + _out() * WINDUP_OUT


## The swing path: a cubic from the windup point (bowed out away from the body) that runs into a
## straight last SWING_STRAIGHT m along the throw direction ending at the launch point, so the paw
## moves along the throw on the last frames (the last frame's step is shorter than that straight
## part); sampled by arc length (_curve_points / _curve_length) so the swing can run at a chosen
## speed. (With the big head, a low throw's straight part passes close beside the cheek.)
func _build_swing() -> void:
	var out := _out()
	var p := _held
	var a := p - _dir * SWING_STRAIGHT
	a.y = maxf(a.y, _floor_y + _held_radius + 0.05)   # a throw from the floor does not swing through it
	var b2 := a - (p - a).normalized() * SWING_LEAD
	var b1 := _windup + _dir * SWING_LEAD + out * SWING_BOW   # leaves the windup along the throw: no loop
	_curve_points.clear()
	_curve_length.clear()
	var length := 0.0
	var prev := _windup
	for i in CURVE_SAMPLES + 1:
		var u := float(i) / CURVE_SAMPLES
		var q := 1.0 - u
		var c := _windup * (q * q * q) + b1 * (3.0 * q * q * u) + b2 * (3.0 * q * u * u) + a * (u * u * u)
		length += c.distance_to(prev)
		prev = c
		_curve_points.append(c)
		_curve_length.append(length)
	for i in range(1, 5):
		var c := a.lerp(p, i / 4.0)
		length += c.distance_to(prev)
		prev = c
		_curve_points.append(c)
		_curve_length.append(length)


## The swing curve's point `distance` m along it from the windup point.
func _curve_at(distance: float) -> Vector3:
	for i in range(1, _curve_points.size()):
		if _curve_length[i] >= distance:
			var span := _curve_length[i] - _curve_length[i - 1]
			return _curve_points[i - 1].lerp(_curve_points[i], (distance - _curve_length[i - 1]) / span if span > 0.0 else 1.0)
	return _curve_points[-1]


## Throw direction and the follow-through direction across the hold direction.
func _set_swing(dir: Vector3) -> void:
	_dir = dir.normalized() if dir.length_squared() > 1e-12 else Vector3.RIGHT
	var across := _dir - _u * _dir.dot(_u)
	_swing = across.normalized() if across.length_squared() > 1e-8 else Vector3.UP


func _rest_dir(i: int) -> Vector3:
	var d := look.rest_dir.normalized()
	return Vector3(-d.x if i == ARM_L else d.x, d.y, d.z)


## Rest direction of paw `i` in the world (the rig turned).
func _rest_dir_world(i: int) -> Vector3:
	return (rig_transform().basis * _rest_dir(i)).normalized()


## The rig's basis for a turn `yaw`, a lean `lean` (+ forward) and a bag height share `squash` (the
## bag keeps its volume: it widens as it squashes).
static func _body_basis(yaw: float, lean: float, squash: float) -> Basis:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean)
	if squash != 1.0:
		var wide := 1.0 / sqrt(squash)
		b = b * Basis.from_scale(Vector3(wide, squash, wide))
	return b


## Writes the rig, head, eyes, tail and arms from the current mode, clock and reactions.
func _pose() -> void:
	var cheer_k := sin(PI * _cheer / CHEER_S) if _cheer >= 0.0 else 0.0
	var hop := CHEER_HOP * cheer_k
	var yaw := 0.0
	var lean := 0.0
	var squint := 0.0
	if mode == "push":
		yaw = PI * 0.5
		lean = deg_to_rad(PUSH_LEAN_DEG) + deg_to_rad(LEAN_MAX_DEG) * _effort
		hop += SHUFFLE_HOP * clampf(absf(_speed) / 0.6, 0.0, 1.0) * absf(sin(PI * _travel / SHUFFLE_STEP))
		squint = absf(_effort)
	var sway := 0.0
	if mode == "free":
		sway = 0.035 * sin(_clock * 1.1)   # idle: the bag rocks a little
	# The rig is still while a ball is held or thrown (the shoulder must not move under the ball), and
	# while the paws are on grabbed points or a grip (a cheer is a nod).
	if mode in ["hold", "throw", "grab", "pull"]:
		hop = 0.0
	match mode:
		"grab":
			_solve_grab()
			squint = _effort
		"pull":
			_solve_pull()
			squint = absf(_effort)
		"follow":
			rig.transform = Transform3D(_body_basis(_yaw, _lean, _squash), Vector3(0.0, hop, 0.0))
		_:
			rig.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean) * Basis(Vector3.BACK, sway), Vector3(0.0, hop, 0.0))
	var rig_yaw := yaw if mode == "push" else (_yaw if mode in ["grab", "pull", "follow"] else 0.0)
	if head != null:
		# Idle tilt; turned towards the camera while pushing, grabbing or pulling, or towards
		# look_target.
		var want_yaw := PUSH_HEAD_YAW if mode == "push" else clampf(wrapf(-rig_yaw, -PI, PI), -HEAD_YAW_MAX, HEAD_YAW_MAX)
		if mode in ["free", "follow"] and look_target != null and is_inside_tree() and look_target.is_inside_tree():
			var to := look_target.global_position - (rig_transform() * look.neck)
			if Vector2(to.x, to.z).length() > 0.05:
				want_yaw = clampf(wrapf(atan2(to.x, to.z) - rig_yaw, -PI, PI), -HEAD_YAW_MAX, HEAD_YAW_MAX)
		_head_yaw = lerpf(_head_yaw, want_yaw, 0.25) if mode != "push" and mode != "grab" and mode != "pull" else want_yaw
		# Idle: a slow nod and tilt (the model has no separate eyes to blink); a nod on a cheer.
		var nod := 0.05 * sin(_clock * 0.9) + 0.18 * cheer_k + 0.1 * squint
		head.rotation = Vector3(nod, _head_yaw, 0.06 * sin(_clock * 1.3))
	if tail != null:
		tail.rotation = Vector3(0.1 * sin(_clock * 1.7 + 1.0), 0.0, 0.22 * sin(_clock * 2.3) + 0.2 * cheer_k)
	if tail2 != null:
		tail2.rotation = Vector3(0.0, 0.0, 0.35 * sin(_clock * 2.3 - 0.9))
	if eyes != null:
		var blink := 1.0
		if _blink >= 0.0:
			blink = 0.1 + 0.9 * absf(1.0 - 2.0 * _blink / BLINK_S)
		eyes.scale = Vector3(1.0, minf(blink, 1.0 - 0.7 * squint), 1.0)
	match mode:
		"push":
			_pose_push(hop, yaw, lean)
			return
		"grab", "pull":
			for i in 2:
				var to := _targets[i] - shoulder(i)
				_stretch[i] = to.length() / look.reach
				if mode == "pull" and _rising:
					_stretch[i] = minf(_stretch[i], JUMP_STRETCH_MAX)
				_aim(i, to.normalized())
			return
	for i in 2:
		var held := (mode in ["hold", "throw"] and i == _hold_arm) or (mode == "follow" and _rel_arms[i])
		var d := _arm_dirs[i]
		if not held:
			_stretch[i] = 1.0
			d = _rest_dir_world(i)
			if mode == "free" and _cheer >= 0.0 and _cheer_arms:
				var up := (rig_transform().basis * Vector3(0.45 if i == ARM_L else -0.45, 0.9, 0.2)).normalized()
				d = d.slerp(up, cheer_k)
			elif i == ARM_R:
				d = (d + rig_transform().basis * Vector3(0.0, 0.04 * sin(_clock * 2.1), 0.0)).normalized()
		elif mode == "hold":
			_stretch[i] = _hold_stretch
		_aim(i, d)


## Grab: the least lean (forward or back, searched outwards from upright in GRAB_STEP_DEG steps and
## bisected) that puts the shoulders `reach` from their points on average; none in range: the lean
## that comes closest (the arms stretch the rest). Writes the rig transform and _lean.
func _solve_grab() -> void:
	_squash = 1.0 - GRAB_SQUASH * _effort
	var key := [global_position if is_inside_tree() else position, _yaw, _targets[0], _targets[1], _squash, _grab_fwd]
	if key == _grab_key:
		rig.transform = Transform3D(_body_basis(_yaw, _lean, _squash), Vector3.ZERO)
		return
	_grab_key = key
	var step := deg_to_rad(GRAB_STEP_DEG)
	var fwd := _grab_fwd
	var back := deg_to_rad(GRAB_LEAN_BACK_DEG)
	var e0 := _grab_error(0.0)
	var best := 0.0
	var best_err := absf(e0)
	var last: Array[float] = [e0, e0]   # the error at the last angle forward / back
	var k := 1
	var hit := NAN
	while best_err > 1e-6 and is_nan(hit) and (k - 1) * step < maxf(fwd, back):
		for side in 2:
			var limit := fwd if side == 0 else back
			var a := minf(k * step, limit)
			if (k - 1) * step >= limit:
				continue
			var sign := 1.0 if side == 0 else -1.0
			var e := _grab_error(sign * a)
			if absf(e) < best_err:
				best_err = absf(e)
				best = sign * a
			if is_nan(hit) and signf(e) != signf(last[side]):
				var lo := (k - 1) * step
				var hi := a
				for n in 12:
					var mid := (lo + hi) * 0.5
					if signf(_grab_error(sign * mid)) == signf(last[side]):
						lo = mid
					else:
						hi = mid
				hit = sign * (lo + hi) * 0.5
			last[side] = e
		k += 1
	_lean = hit if not is_nan(hit) else best
	rig.transform = Transform3D(_body_basis(_yaw, _lean, _squash), Vector3.ZERO)


## Mean distance (m) of the shoulders from their grab points, less the reach, for a lean `lean`.
func _grab_error(lean: float) -> float:
	var b := _body_basis(_yaw, lean, _squash)
	var xf := global_transform if is_inside_tree() else transform
	var e := 0.0
	for i in 2:
		e += (xf * (b * look.shoulders[i])).distance_to(_targets[i]) - look.reach
	return e * 0.5


## Pull: the turn along the pull direction, the lean back with the effort, the root where the
## shoulders' middle is `reach` from the grip (on the floor, or hanging; rising at JUMP_SPEED towards a
## higher place), the paws' points beside the grip. Writes position, the rig transform and the targets.
func _solve_pull() -> void:
	var flat := Vector2(_pull_dir.x, _pull_dir.z)
	if flat.length_squared() > 1e-10:
		_yaw = atan2(flat.x, flat.y)
		flat = flat.normalized()
	else:
		flat = Vector2(sin(_yaw), cos(_yaw))
	_lean = -deg_to_rad(PULL_LEAN_DEG) * _effort
	_squash = 1.0
	var basis := _body_basis(_yaw, _lean, 1.0)
	var off := basis * ((look.shoulders[0] + look.shoulders[1]) * 0.5)
	var s := _grip - _pull_dir * look.reach
	var root := s - off
	if root.y < _floor_y:
		root.y = _floor_y
		s.y = _floor_y + off.y
		var dy := _grip.y - s.y
		var across := sqrt(maxf(look.reach * look.reach - dy * dy, 0.0))
		s.x = _grip.x - flat.x * across
		s.z = _grip.z - flat.y * across
		root = s - off
	# A grip above where the actor is now: it jumps up (the paws reach for it on the way).
	if root.y > position.y + 1e-4 and (_rising or root.y > position.y + 0.05):
		_rising = true
		root.y = minf(root.y, position.y + JUMP_SPEED * _dt)
	else:
		_rising = false
	position = root
	rig.transform = Transform3D(basis, Vector3.ZERO)
	var side := basis * Vector3.RIGHT
	_targets[0] = _grip - side * PULL_SPREAD
	_targets[1] = _grip + side * PULL_SPREAD
	if _pull_ball > 0.0:
		var centre := _grip + _pull_dir * _pull_ball
		for i in 2:
			_targets[i] = centre + (_targets[i] - centre).normalized() * _pull_ball


## Push pose: the root x so both paws' fronts reach the face plane exactly (the shoulders are mirror images,
## so they share x and y once turned), arms along shoulder -> face point at hand height. (The
## actor's parent is at the world origin, as the labs are.)
func _pose_push(hop: float, yaw: float, lean: float) -> void:
	if push_face.is_valid():
		_face_x = push_face.call()
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean)
	var off := basis * look.shoulders[0] + Vector3(0.0, hop, 0.0)
	# The paws keep within push_half_width of the face's middle (z): a wide look's paws come in.
	var dz := maxf(absf(off.z) - push_half_width, 0.0)
	var dy := _hand_y - (position.y + off.y)
	var dx := sqrt(maxf(look.reach * look.reach - dy * dy - dz * dz, 0.0))
	position.x = _face_x - dx - off.x
	for i in 2:
		_stretch[i] = 1.0
		var s := shoulder(i)
		var z := position.z + clampf(s.z - position.z, -push_half_width, push_half_width)
		_aim(i, (Vector3(_face_x, _hand_y, z) - s).normalized())


## Points arm `i` (shoulder -> hand) along the world direction `d`, turning it at the shoulder only:
## the shortest turn from its rest pose, stretched along `d` by _stretch[i] (in the world: a squashed
## rig would draw it shorter or longer, so the stretch makes up for it).
func _aim(i: int, d: Vector3) -> void:
	_arm_dirs[i] = d
	var rb := rig_transform().basis
	var local := rb.inverse() * d
	var to := local.normalized()   # rig space
	var turn := Basis(Quaternion(look.hand_rest[i].normalized(), to))
	var stretch := Basis.IDENTITY
	var k := _stretch[i] / (rb * to).length() if _squash != 1.0 else _stretch[i]
	if k != 1.0:
		for r in 3:
			for c in 3:
				stretch[c][r] += (k - 1.0) * to[r] * to[c]
	arms[i].transform = Transform3D(stretch * turn * _arm_rest[i], look.shoulders[i])
