## A character that acts what the student does, in step with the formula model (Phase 1 Task 4g,
## art-direction.md section 11): it throws the projectile lab's ball and pushes the friction lab's
## box. "물리는 모델, 고양이는 연기": it never touches the physics (no body, no collision object, no
## layer); the labs' motion and panel values are the same with or without it
## (tests/bread_cat_checks.gd). What it looks like is a CatLook (meshes + the points of its body the
## acting uses: shoulders, reach, neck, ...), so the look can be replaced without touching the sync.
##
## The animation is code (no AnimationPlayer, no Tween): _process advances the clock and poses the
## rig from the mode the lab set:
##   hold(center, r, floor)  the left paw holds a ball of radius r centred at `center` (along the
##                           look's hold_dir from the shoulder); the actor is placed so its arm
##                           reaches it, raised off `floor` when the ball is high (the lab draws a
##                           stand of stand_height)
##   throw(dir, on_release)  windup (the ball up and back over the head) and an overhand swing that
##                           reaches the hold pose moving along `dir`, fastest at the release; the ball (`carried`) follows the paw; on the frame the swing
##                           is back at the hold pose (the ball's launch point) on_release runs, then
##                           the arm follows through and rests
##   let_go(dir)             the ball was let go without a throw (the arm follows through)
##   push(face_x, ...)       both paws on the plane x = face_x (the box face), the actor behind it (-x),
##                           leaning with the effort
##   cheer(arms)             a small hop (and paws up) when something lands or stops
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

var mode := "free"                  # free / hold / throw / follow / push
## Height of the base above the floor hold() was given (the lab draws a stand that tall).
var stand_height := 0.0
var _clock := 0.0
var _next_blink := 1.7
var _blink := -1.0                  # time into a blink, < 0: none
var _cheer := -1.0                  # time into a cheer, < 0: none
var _cheer_arms := true
var _head_yaw := 0.0
# hold / throw / follow
var _held := Vector3.ZERO           # ball centre held (the launch point)
var _held_radius := 0.0
var _floor_y := 0.0
var _u := Vector3.FORWARD           # unit shoulder -> held ball centre
var _dir := Vector3.RIGHT           # throw direction
var _swing := Vector3.UP            # unit follow-through direction (across _u)
var _t := 0.0                       # time into the throw / follow-through
var _on_release := Callable()
var _arm_dirs: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var _stretch: Array[float] = [1.0, 1.0]   # arm length / its rest length
var _follow_from := Vector3.DOWN    # arm direction at the end of the follow-through swing
var _windup := Vector3.ZERO         # windup point of the throw (world)
var _curve_points := PackedVector3Array()   # the swing curve sampled from the windup point (world)
var _curve_length := PackedFloat32Array()   # arc length to each sample
# push
var _face_x := 0.0
var _hand_y := 0.5
var _effort := 0.0                  # -1 (pulling hard) .. 1 (pushing hard)
var _travel := 0.0
var _speed := 0.0


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
	return shoulder(ARM_HOLD) + arm_dir(ARM_HOLD) * (look.reach + _held_radius) * _stretch[ARM_HOLD]


func throwing() -> bool:
	return mode == "throw"


# --- modes ----------------------------------------------------------------------------------------

## Holds a ball of radius `radius` centred at `center` in the left paw (gripping) or only stands
## where it would (grip false: a finger holds the ball). Placed so the paw reaches it: the shoulder
## is reach + radius from the centre along the look's hold_dir, raised off `floor_y` when the ball is
## high, on the floor when it is low (then the arm points down to it). A throw in progress stops.
func hold(center: Vector3, radius: float, floor_y: float, grip := true) -> void:
	_on_release = Callable()
	_held = center
	_held_radius = radius
	_floor_y = floor_y
	_cheer = -1.0
	var reach := look.reach + radius
	var sh: Vector3 = look.shoulders[ARM_HOLD]
	var u := look.hold_dir.normalized()
	var s := center - u * reach
	var root := s - sh
	if root.y < floor_y:
		root.y = floor_y
		s.y = floor_y + sh.y
		var flat := Vector2(look.hold_dir.x, look.hold_dir.z).normalized()
		var across := sqrt(maxf(reach * reach - (center.y - s.y) * (center.y - s.y), 0.0))
		s.x = center.x - flat.x * across
		s.z = center.z - flat.y * across
		root = s - sh
	stand_height = root.y - floor_y
	position = root
	rig.transform = Transform3D.IDENTITY
	_u = (center - s).normalized()
	mode = "hold" if grip else "free"
	_arm_dirs[ARM_HOLD] = _u if grip else _rest_dir(ARM_HOLD)
	_arm_dirs[ARM_R] = _rest_dir(ARM_R)
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


## The ball left without a throw (a direct release): the arm follows through along `dir`.
func let_go(dir: Vector3) -> void:
	if mode == "hold":
		_set_swing(dir)
		_t = 0.0
		mode = "follow"


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


## A small happy hop (and both paws up, `arms_up`, unless the paws are busy).
func cheer(arms_up := true) -> void:
	_cheer = 0.0
	_cheer_arms = arms_up


# --- animation ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta)


## Moves the clock on by `delta` s and poses (tests call it with exact steps).
func advance(delta: float) -> void:
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
				_arm_dirs[ARM_HOLD] = _u
				_stretch[ARM_HOLD] = 1.0
				_pose()
				if carried.is_valid():
					carried.call(held_point())
				var release := _on_release
				_on_release = Callable()
				_t = 0.0
				mode = "follow"
				if release.is_valid():
					release.call()
				threw.emit()
				return
			var p := _throw_point(_t)
			var to := p - shoulder(ARM_HOLD)
			_arm_dirs[ARM_HOLD] = to.normalized()
			_stretch[ARM_HOLD] = to.length() / (look.reach + _held_radius)
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
				_arm_dirs[ARM_HOLD] = (_u * cos(angle) + _swing * sin(angle)).normalized()
				_follow_from = _arm_dirs[ARM_HOLD]
			else:
				var k := clampf((_t - FOLLOW_S) / SETTLE_S, 0.0, 1.0)
				_arm_dirs[ARM_HOLD] = _follow_from.slerp(_rest_dir_world(ARM_HOLD), k * k * (3.0 - 2.0 * k))
				if k >= 1.0:
					mode = "free"
	_pose()


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


## The windup point: WINDUP_BACK back against the throw from the launch point, up to WINDUP_UP above
## that, WINDUP_DEPTH behind and WINDUP_OUT out (back and up beside the head for a level throw, back
## and down for a steep one; the arm stretches).
func _windup_point() -> Vector3:
	var back := (rig_transform().basis * Vector3.BACK).normalized()
	# Up as much as the throw is level (cos of its elevation): a steep throw winds back under the
	# release, so its swing comes up along it without a loop.
	var level := sqrt(maxf(1.0 - _dir.y * _dir.y, 0.0))
	var out := (rig_transform().basis * Vector3.RIGHT).normalized()
	return _held - _dir * WINDUP_BACK + Vector3.UP * WINDUP_UP * level - back * WINDUP_DEPTH + out * WINDUP_OUT


## The swing path: a cubic from the windup point (bowed out away from the body) that runs into a
## straight last SWING_STRAIGHT m along the throw direction ending at the launch point, so the paw
## moves along the throw on the last frames (the last frame's step is shorter than that straight
## part); sampled by arc length (_curve_points / _curve_length) so the swing can run at a chosen
## speed. (With the big head, a low throw's straight part passes close beside the cheek.)
func _build_swing() -> void:
	var out := (rig_transform().basis * Vector3.RIGHT).normalized()
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
	# The rig is still while a ball is held or thrown (the shoulder must not move under the ball).
	if mode == "hold" or mode == "throw":
		hop = 0.0
	rig.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean) * Basis(Vector3.BACK, sway), Vector3(0.0, hop, 0.0))
	if head != null:
		# Idle tilt, turned towards the camera while pushing or towards look_target.
		var want_yaw := PUSH_HEAD_YAW if mode == "push" else 0.0
		if mode in ["free", "follow"] and look_target != null and is_inside_tree() and look_target.is_inside_tree():
			var to := look_target.global_position - (rig_transform() * look.neck)
			if Vector2(to.x, to.z).length() > 0.05:
				want_yaw = clampf(atan2(to.x, to.z), -HEAD_YAW_MAX, HEAD_YAW_MAX)
		_head_yaw = lerpf(_head_yaw, want_yaw, 0.25) if mode != "push" else want_yaw
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
	if mode == "push":
		_pose_push(hop, yaw, lean)
		return
	for i in 2:
		var d := _arm_dirs[i]
		if not (i == ARM_HOLD and mode == "throw"):
			_stretch[i] = 1.0
		if i != ARM_HOLD or mode == "free":
			d = _rest_dir_world(i)
			if mode == "free" and _cheer >= 0.0 and _cheer_arms:
				var up := (rig_transform().basis * Vector3(0.45 if i == ARM_L else -0.45, 0.9, 0.2)).normalized()
				d = d.slerp(up, cheer_k)
			elif i == ARM_R:
				d = (d + rig_transform().basis * Vector3(0.0, 0.04 * sin(_clock * 2.1), 0.0)).normalized()
		_aim(i, d)


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
## the shortest turn from its rest pose, stretched along `d` by _stretch[i].
func _aim(i: int, d: Vector3) -> void:
	_arm_dirs[i] = d
	var to := (rig_transform().basis.inverse() * d).normalized()   # rig space
	var turn := Basis(Quaternion(look.hand_rest[i].normalized(), to))
	var stretch := Basis.IDENTITY
	if _stretch[i] != 1.0:
		for r in 3:
			for c in 3:
				stretch[c][r] += (_stretch[i] - 1.0) * to[r] * to[c]
	arms[i].transform = Transform3D(stretch * turn * _arm_rest[i], look.shoulders[i])
