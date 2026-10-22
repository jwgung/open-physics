## Shell object manipulation (Phase 1 Task 2b): one finger (or the left mouse button) picks up an
## object, drags it on its surface, and puts it down on the surface's grid. Fed by
## View3D.single_pointer; the experiment says which objects can be picked and on which surface
## (definition.manipulation + Experiment.manipulation_*), see apps/lab3d/README.md "조작".
##
## - Pick: one ray from the finger (only manipulable bodies count); when it misses, the object whose
##   centre is within PICK_RADIUS UI units on screen (a 0.4 m box is ~36 units wide at the default
##   distance, smaller than a child's fingertip).
## - Drag: the finger ray is projected on the surface (ManipSurface.project_ray) at the object's
##   centre height, keeping the offset between finger and object from the pick-up (an offset on
##   the surface, so a turning camera does not change it; the object follows the finger on screen
##   while the assist turns the view, see _follow_camera). A grazing ray
##   leaves the object where it is; the object never leaves the region by more than SOFT_MARGIN.
##   The object is frozen while held and follows the finger unsnapped; the footprint marker shows
##   the grid point it will land on (white) or that it cannot be placed there (dark + wobble).
## - Height: an object whose rule allows it shows a vertical handle beside it when selected; the
##   knob drags the height along the surface normal only (snapped to its step).
## - Put down: a valid target places the object there (Experiment.manipulation_placed); an invalid
##   one, a second finger, or a system cancel puts it back where it was picked up.
## - The camera turns to show the surface while dragging if the view is too flat (CameraRig.begin_assist).
## Work per input event: at most one ray (pick) and one shape query (only when the grid target or
## the height changes). _process allocates nothing; a pointer event makes a few small values (the
## finger ray, one projected point).
class_name Manipulator
extends Node3D

## An object was put down or put back (the panel should refresh).
signal changed
## The auto-drag demo (start_demo) put its object down.
signal demo_placed

const PICK_RADIUS := 44.0        # UI units
const HANDLE_RADIUS := 52.0      # UI units around the height knob
const SOFT_MARGIN := 0.6         # m
const MARKER_LIFT := 0.012       # m above the surface (no z-fighting)
const MARKER_WIDTH := 0.05       # m, footprint ring bar
const HANDLE_GAP := 0.3          # m between the object's side and the handle rod
const KNOB_SIZE := 0.32          # m
const ROD_RADIUS := 0.045
const DEMO_DRAG_S := 1.0
const DEMO_NEAR_FRACTION := 0.4  # the demo's near stop: this far along the region (the far stop is its end)
const RAY_LENGTH := 200.0        # m, pick ray
const ON_SURFACE_TOL := 0.05     # m, how far off its surface an object still counts as resting on it
const REGION_EPS := 0.001        # m, "inside the drag region" tolerance
const MARKER_MARGIN := 0.06      # m, footprint ring beyond the object's extent on every side
const MARKER_THICKNESS := 0.02   # m

var view: View3D
var experiment: Experiment
## id -> {"surface": String, "snap": float, "height_max": float, "height_step": float}
## (height_max 0 = no height handle).
var rules: Dictionary = {}

var mode := ""                   # "", "drag", "height"
var active_id := ""
var selected_id := ""
var valid := true
var target := Vector2.ZERO       # grid point (plane coordinates) the held object would land on
var height := 0.0                # chosen height of the object's base above the surface (m)

var _surface: ManipSurface
var _body: PhysicsBody3D
var _lift := 0.0                 # object centre above its base (half extent along the normal)
var _start_xf := Transform3D.IDENTITY
var _start_freeze := false
var _grab := Vector2.ZERO        # object centre minus the finger's surface point at pick-up (plane coordinates: independent of the camera)
var _grab_height := 0.0          # knob point minus the finger's point on the knob line (height mode; set again when the camera turns)
var _finger := Vector2.ZERO      # last finger position (view UI units)
var _finger_camera := Transform3D()   # camera the held object was last placed for
var _placed_last := false        # the last release put the object down (not back)
var _held := Vector2.ZERO        # unsnapped plane point of the held object
var _target_set := false
var _ray := PhysicsRayQueryParameters3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _query_shapes: Dictionary = {}   # id -> shrunk Shape3D for overlap checks
var _markers: Dictionary = {}        # id -> [ok MeshInstance3D, blocked MeshInstance3D]
var _rods: Dictionary = {}           # id -> MeshInstance3D (handle rod sized to the height range)
var _knob: MeshInstance3D
var _handle_body := Transform3D()    # body and camera transforms the handle was placed for
var _handle_camera := Transform3D()
var _handle_offset := Vector3.ZERO   # from the object's base point to the handle rod (camera right * reach)
var _handle_surface: ManipSurface    # surface of the selected object, built once per selection / state change
var _demo_every := 0.0
var _demo_left := 0.0
var _demo_flip := false
var _demo_from := Vector2.ZERO
var _demo_to := Vector2.ZERO
var _demo_t := -1.0


func setup(target_view: View3D, target_experiment: Experiment) -> void:
	view = target_view
	experiment = target_experiment
	rules.clear()
	for object in experiment.definition.get("manipulation", {}).get("objects", []):
		var h: Variant = object.get("height", false)
		var height_rule: Dictionary = h if h is Dictionary else {}
		rules[object.id] = {
			"surface": str(object.surface),
			"snap": float(object.get("snap", 0.0)),
			"height_max": float(height_rule.get("max", 0.0)),
			"height_step": float(height_rule.get("step", 0.0)),
		}
	_ray.collide_with_areas = false
	_query.collide_with_areas = false
	experiment.state_changed.connect(_forget_handle_surface)
	var knob := ArtKit.builder()
	knob.ao_min = 0.9
	knob.add_rounded_box(Transform3D.IDENTITY, Vector3.ONE * KNOB_SIZE, 0.06, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	var arrow := KNOB_SIZE * 0.5
	knob.add_cylinder(Transform3D(Basis(), Vector3(0.0, arrow, 0.0)), 0.1, 0.0, 0.14, 4, ArtPalette.WHITE)
	knob.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, -arrow, 0.0)), 0.1, 0.0, 0.14, 4, ArtPalette.WHITE)
	_knob = ArtKit.instance(knob.commit())
	_knob.name = "HeightKnob"
	_knob.visible = false
	add_child(_knob)


## View3D.single_pointer handler (positions in the view's UI units).
func handle_pointer(kind: String, position: Vector2) -> void:
	match kind:
		"press":
			_press(position)
		"move":
			_move(position)
		"release":
			_release()
		"cancel":
			cancel()


## Puts a held object back where it was picked up (also called before a control or action changes
## the experiment under the finger).
func cancel(shake := false) -> void:
	if mode == "":
		return
	var id := active_id
	_body.global_transform = _start_xf
	if _body is RigidBody3D:
		(_body as RigidBody3D).freeze = _start_freeze
	var juice := experiment.manipulation_juice(id)
	_finish()
	experiment.manipulation_cancelled(id)
	if juice:
		juice.hold(false)
		if shake:
			juice.wobble()
	changed.emit()


func select(id: String) -> void:
	selected_id = id
	_handle_body = Transform3D()
	_handle_surface = null
	_update_handle()


# --- input ------------------------------------------------------------------------------------

func _press(position: Vector2) -> void:
	if mode != "":
		cancel()
	if selected_id != "" and _knob.visible and _screen_distance(_knob.global_position, position) <= HANDLE_RADIUS:
		_begin(selected_id, "height", position)
		return
	var id := _pick(position)
	if id == "":
		select("")
		return
	_begin(id, "drag", position)


func _move(position: Vector2) -> void:
	if mode == "height" and view.rig.global_transform != _finger_camera:
		_follow_camera()   # the camera turned since the last event: measure from the finger where it was
	_finger = position
	if mode == "drag":
		_drag_to(position)
	elif mode == "height":
		var s: Variant = _knob_line_point(position)
		if s == null:
			return
		var rule: Dictionary = rules[active_id]
		var h := _snap_height(rule, s - _grab_height - _lift)
		if not is_equal_approx(h, height):
			height = h
			_body.global_transform = _surface.pose(_held, _lift + height)
			_target_set = false
			_update_target()
			_update_handle()


## Places the dragged object under a finger at `position` (the finger point on the surface plus the
## offset from the pick-up).
func _drag_to(position: Vector2) -> void:
	var ray := _finger_ray(position)
	var finger: Variant = _surface.project_ray(ray[0], ray[1], _lift + height)
	if finger == null:
		return   # grazing ray: keep the object where it is
	_held = _surface.clamp_soft(finger + _grab, SOFT_MARGIN)
	_body.global_transform = _surface.pose(_held, _lift + height)
	_update_target()


## The camera turned while an object is held (the assist, or a mode button): a drag puts the object
## under the unmoved finger again; a height drag measures the finger from the new view, so the
## height stays the same until the finger moves.
func _follow_camera() -> void:
	_finger_camera = view.rig.global_transform
	if mode == "drag":
		_drag_to(_finger)
	elif mode == "height":
		var s: Variant = _knob_line_point(_finger)
		if s != null:
			_grab_height = s - (_lift + height)


func _release() -> void:
	_placed_last = false
	if mode == "":
		return
	if not valid:
		cancel(true)
		return
	var id := active_id
	var was_drag := mode == "drag"
	var xf := _surface.pose(target, _lift + height)
	_body.global_transform = xf
	var juice := experiment.manipulation_juice(id)
	_finish()
	experiment.manipulation_placed(id, xf)
	_placed_last = true
	if juice:
		if was_drag:
			juice.settle()
		else:
			juice.hold(false)
	select(id if rules[id].height_max > 0.0 else "")
	changed.emit()


func _begin(id: String, kind: String, position: Vector2) -> void:
	var rule: Dictionary = rules[id]
	var body := experiment.manipulation_body(id)
	var surface := experiment.manipulation_surface(rule.surface)
	if body == null or surface == null:
		return
	if surface.snap == Vector2.ZERO and rule.snap > 0.0:
		surface.snap = Vector2(rule.snap, rule.snap)
	_body = body
	_surface = surface
	active_id = id
	mode = kind
	_start_xf = body.global_transform
	_start_freeze = (body as RigidBody3D).freeze if body is RigidBody3D else false
	experiment.manipulation_started(id)
	if body is RigidBody3D:
		var rigid := body as RigidBody3D
		rigid.freeze = true
		rigid.linear_velocity = Vector3.ZERO
		rigid.angular_velocity = Vector3.ZERO
	_lift = _half_extents(id).y
	var p := surface.to_plane(body.global_position)
	var above := surface.height_of(body.global_position) - _lift
	# Resting on (or held above) its surface, within the drag area: keep the finger's offset.
	var on_surface: bool = above > -ON_SURFACE_TOL and above <= rule.height_max + ON_SURFACE_TOL \
		and surface.clamp_soft(p, SOFT_MARGIN).distance_to(p) < REGION_EPS
	height = 0.0
	if rule.height_max > 0.0 and on_surface:
		height = _snap_height(rule, above)
	_finger = position
	_finger_camera = view.rig.global_transform
	var ray := _finger_ray(position)
	if kind == "drag":
		var finger: Variant = surface.project_ray(ray[0], ray[1], _lift + height)
		if on_surface:
			_held = p
			_grab = p - finger if finger != null else Vector2.ZERO
		else:
			# Picked up off its surface (e.g. the box lying on the floor): it jumps under the finger.
			_held = surface.clamp_soft(finger if finger != null else surface.nearest_inside(p), SOFT_MARGIN)
			_grab = Vector2.ZERO
		_body.global_transform = surface.pose(_held, _lift + height)
		select("")   # the handle (of this or another object) hides while dragging
		var juice := experiment.manipulation_juice(id)
		if juice:
			juice.hold(true)
		# The surface must face the camera enough to show the footprint (and a line must not run
		# along the view, or the finger could not move the object along it).
		view.rig.begin_assist(surface.normal(), surface.frame.basis.x if surface.is_line() else Vector3.ZERO)
	else:
		_held = surface.nearest_inside(p)
		var s: Variant = _knob_line_point(position)
		_grab_height = (s - (_lift + height)) if s != null else 0.0
		view.rig.begin_assist(Vector3.ZERO, surface.normal())
	_target_set = false
	_update_target()


func _finish() -> void:
	view.rig.end_assist()
	if _markers.has(active_id):
		for marker in _markers[active_id]:
			marker.visible = false
	mode = ""
	active_id = ""
	_target_set = false


## `h` kept in 0..height_max and rounded to the rule's height step (never above height_max, also
## when the maximum is not a multiple of the step).
func _snap_height(rule: Dictionary, h: float) -> float:
	h = clampf(h, 0.0, rule.height_max)
	if rule.height_step > 0.0:
		h = minf(roundf(h / rule.height_step) * rule.height_step, rule.height_max)
	return h


## Recomputes the landing point and whether it is free; only when the grid point (or height) changed.
func _update_target() -> void:
	var t := _surface.nearest_inside(_held) if _surface.contains(_held) else _surface.snap_point(_held)
	if _target_set and t == target:
		return
	var was_valid := valid or not _target_set
	_target_set = true
	target = t
	var xf := _surface.pose(t, _lift + height)
	valid = _surface.contains(t) and _is_free(active_id, xf) and experiment.placement_allowed(active_id, xf)
	if was_valid and not valid:
		var juice := experiment.manipulation_juice(active_id)
		if juice:
			juice.wobble()
	var markers: Array = _marker_pair(active_id)
	var marker_xf := _surface.pose(t, MARKER_LIFT)
	markers[0].global_transform = marker_xf
	markers[1].global_transform = marker_xf
	markers[0].visible = valid
	markers[1].visible = not valid


# --- queries ----------------------------------------------------------------------------------

## [origin, direction] of the camera ray through a point of the view (UI units).
func _finger_ray(position: Vector2) -> Array:
	var pixels := position * _pixels_per_unit()
	return [view.rig.project_ray_origin(pixels), view.rig.project_ray_normal(pixels)]


func _pixels_per_unit() -> Vector2:
	var size := view.size
	if size.x < 1.0 or size.y < 1.0:
		return Vector2.ONE
	return Vector2(view.viewport.size) / size


## Distance in UI units between a world point drawn on the view and a view position (INF if behind).
func _screen_distance(world: Vector3, position: Vector2) -> float:
	if view.rig.is_position_behind(world):
		return INF
	return (view.rig.unproject_position(world) / _pixels_per_unit()).distance_to(position)


func _pick(position: Vector2) -> String:
	var ray := _finger_ray(position)
	_ray.from = ray[0]
	_ray.to = ray[0] + ray[1] * RAY_LENGTH
	var hit := experiment.get_world_3d().direct_space_state.intersect_ray(_ray)
	var best := ""
	var best_distance := PICK_RADIUS
	for id in rules:
		var body := experiment.manipulation_body(id)
		if body == null:
			continue
		if not hit.is_empty() and hit.collider == body:
			return id
		# Near the object on screen counts, unless something else stands between the camera and it
		# (a ray to its centre; the floor or surface it rests on is below that line of sight).
		var d := _screen_distance(body.global_position, position)
		if d <= best_distance and _in_sight(ray[0], body):
			best_distance = d
			best = id
	return best


func _in_sight(eye: Vector3, body: PhysicsBody3D) -> bool:
	_ray.from = eye
	_ray.to = body.global_position
	var hit := experiment.get_world_3d().direct_space_state.intersect_ray(_ray)
	return hit.is_empty() or hit.collider == body


## Height-handle drag: the point of the knob's vertical line (the rod beside the object, where the
## handle is drawn) closest to the finger ray, as the distance above the surface (null when the ray
## runs along the line).
func _knob_line_point(position: Vector2) -> Variant:
	var ray := _finger_ray(position)
	var base := _surface.pose(_held, 0.0).origin + _handle_offset
	return ManipSurface.closest_on_line(base, _surface.normal(), ray[0], ray[1])


func _is_free(id: String, xf: Transform3D) -> bool:
	_query.shape = _query_shape(id)
	_query.transform = xf
	var exclude: Array[RID] = [_body.get_rid()]
	exclude.append_array(_surface.exclude)
	_query.exclude = exclude
	return experiment.get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()


## The object's collision shape shrunk by 1 cm per side, so resting contact is not an overlap.
func _query_shape(id: String) -> Shape3D:
	if _query_shapes.has(id):
		return _query_shapes[id]
	var shape := _collision_shape(id)
	var shrunk: Shape3D = shape
	if shape is BoxShape3D:
		shrunk = BoxShape3D.new()
		shrunk.size = (shape as BoxShape3D).size - Vector3.ONE * 0.02
	elif shape is SphereShape3D:
		shrunk = SphereShape3D.new()
		shrunk.radius = (shape as SphereShape3D).radius - 0.01
	elif shape is CylinderShape3D:
		shrunk = CylinderShape3D.new()
		shrunk.radius = (shape as CylinderShape3D).radius - 0.01
		shrunk.height = (shape as CylinderShape3D).height - 0.02
	_query_shapes[id] = shrunk
	return shrunk


func _collision_shape(id: String) -> Shape3D:
	var body := experiment.manipulation_body(id)
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null:
			return child.shape
	return BoxShape3D.new()


## Half extents of the object's collision shape (x, y = along the surface normal, z).
func _half_extents(id: String) -> Vector3:
	var shape := _collision_shape(id)
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size * 0.5
	if shape is SphereShape3D:
		return Vector3.ONE * (shape as SphereShape3D).radius
	if shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		return Vector3(c.radius, c.height * 0.5, c.radius)
	if shape is CapsuleShape3D:
		var k := shape as CapsuleShape3D
		return Vector3(k.radius, k.height * 0.5, k.radius)
	return Vector3.ONE * 0.5


# --- visuals ------------------------------------------------------------------------------------

## Footprint rings for one object: white = can land here, dark ink with a cross = cannot. Built
## once per object; flat bars without bevels (36 vertices each).
func _marker_pair(id: String) -> Array:
	if _markers.has(id):
		return _markers[id]
	var e := _half_extents(id)
	var pair := []
	for color in [ArtPalette.WHITE, ArtPalette.INK]:
		var b := ArtKit.builder()
		b.ao_min = 1.0
		var hx := e.x + MARKER_MARGIN
		var hz := e.z + MARKER_MARGIN
		var w := MARKER_WIDTH
		for side in [-1.0, 1.0]:
			b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.0, side * hz)), Vector3(hx * 2.0 + w, MARKER_THICKNESS, w), 0.0, 1, color)
			b.add_rounded_box(Transform3D(Basis(), Vector3(side * hx, 0.0, 0.0)), Vector3(w, MARKER_THICKNESS, hz * 2.0 - w), 0.0, 1, color)
			if color == ArtPalette.INK:
				# Blocked: a cross inside the ring as well as the dark colour.
				var diagonal := Vector2(hx, hz).length() * 2.0
				b.add_rounded_box(Transform3D(Basis(Vector3.UP, side * atan2(hz, hx)), Vector3.ZERO), Vector3(diagonal - w, MARKER_THICKNESS, w), 0.0, 1, color)
		var marker := ArtKit.instance(b.commit())
		marker.name = "Footprint%s" % ("Ok" if color == ArtPalette.WHITE else "Blocked")
		marker.visible = false
		add_child(marker)
		pair.append(marker)
	_markers[id] = pair
	return pair


func _rod(id: String) -> MeshInstance3D:
	if _rods.has(id):
		return _rods[id]
	var length: float = rules[id].height_max + _half_extents(id).y * 2.0 + KNOB_SIZE
	var b := ArtKit.builder()
	b.ao_min = 0.8
	b.ao_height = 0.2
	b.add_cylinder(Transform3D.IDENTITY, ROD_RADIUS * 2.2, ROD_RADIUS * 2.2, 0.05, 6, ArtPalette.BLUE_DARK)
	b.add_cylinder(Transform3D.IDENTITY, ROD_RADIUS, ROD_RADIUS, length, 6, ArtPalette.BLUE)
	var rod := ArtKit.instance(b.commit())
	rod.name = "HeightRod"
	rod.visible = false
	add_child(rod)
	_rods[id] = rod
	return rod


## Places the height handle beside the selected object, on the camera's right (moved only when the
## object or the camera moved).
func _update_handle() -> void:
	if selected_id == "" or rules[selected_id].height_max <= 0.0:
		_knob.visible = false
		for id in _rods:
			_rods[id].visible = false
		return
	for id in _rods:
		_rods[id].visible = _rods[id].visible and id == selected_id
	var body := experiment.manipulation_body(selected_id)
	var surface := _surface if mode == "height" else _selected_surface()
	if body == null or surface == null:
		_knob.visible = false
		return
	var rod := _rod(selected_id)
	var n := surface.normal()
	var right := view.rig.global_basis.x
	right = (right - n * right.dot(n)).normalized()
	var e := _half_extents(selected_id)
	var reach := absf(right.dot(surface.frame.basis.x)) * e.x + absf(right.dot(surface.frame.basis.z)) * e.z + HANDLE_GAP
	var center := body.global_position
	if mode != "height":
		_handle_offset = right * reach   # fixed while the knob is held
	var base := center - n * surface.height_of(center) + _handle_offset
	rod.global_transform = Transform3D(surface.frame.basis, base)
	_knob.global_transform = Transform3D(surface.frame.basis, base + n * surface.height_of(center))
	rod.visible = mode != "drag"
	_knob.visible = mode != "drag"
	_handle_body = body.global_transform
	_handle_camera = view.rig.global_transform


## The selected object's surface (built again only after select() or an experiment state change).
func _selected_surface() -> ManipSurface:
	if _handle_surface == null:
		_handle_surface = experiment.manipulation_surface(rules[selected_id].surface)
	return _handle_surface


func _forget_handle_surface() -> void:
	_handle_surface = null
	_handle_body = Transform3D()   # place the handle again on the next frame


func _process(delta: float) -> void:
	if mode != "" and view.rig.global_transform != _finger_camera:
		_follow_camera()
	if selected_id != "" and mode != "drag":
		var body := experiment.manipulation_body(selected_id)
		if body != null and (body.global_transform != _handle_body or view.rig.global_transform != _handle_camera):
			_update_handle()
	if _demo_every > 0.0:
		_demo_tick(delta)


# --- measurement demo -----------------------------------------------------------------------------

## Drags the first manipulable object back and forth every `every` seconds through the same input
## path as a finger (press, moves over DEMO_DRAG_S, release), alternating between the far end of
## its region and DEMO_NEAR_FRACTION along it (--auto-drag, bench_device.sh).
func start_demo(every: float) -> void:
	_demo_every = every
	_demo_left = 1.0


func _demo_tick(delta: float) -> void:
	if _demo_t >= 0.0:
		_demo_t = minf(_demo_t + delta / DEMO_DRAG_S, 1.0)
		handle_pointer("move", _demo_from.lerp(_demo_to, _demo_t))
		if _demo_t >= 1.0:
			_demo_t = -1.0
			handle_pointer("release", _demo_to)
			if _placed_last:
				demo_placed.emit()
		return
	_demo_left -= delta
	if _demo_left > 0.0 or rules.is_empty():
		return
	_demo_left = _demo_every
	var id: String = rules.keys()[0]
	var body := experiment.manipulation_body(id)
	var surface := experiment.manipulation_surface(rules[id].surface)
	if body == null or surface == null or view.rig.is_position_behind(body.global_position):
		return
	_demo_flip = not _demo_flip
	var goal := surface.nearest_inside(surface.region_min.lerp(surface.region_max, 1.0 if _demo_flip else DEMO_NEAR_FRACTION))
	var lift := _half_extents(id).y
	_demo_from = view.rig.unproject_position(body.global_position) / _pixels_per_unit()
	_demo_to = view.rig.unproject_position(surface.pose(goal, lift).origin) / _pixels_per_unit()
	handle_pointer("press", _demo_from)
	_demo_t = 0.0 if mode == "drag" else -1.0
