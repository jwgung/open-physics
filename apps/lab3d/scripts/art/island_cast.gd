## The island's cast besides the bread cat (Phase 1 Task 4h, art-direction.md section 12): Dugi
## (DugiActor) who explains and Puppy (PuppyActor) with the flag, placed per experiment by its
## definition's `cast` (content/experiments/<id>.json):
##   "cast": {"dugi": {"at": [x, z], "explain_on": [status, ...], "delay_s": s},
##            "puppy": {"at": [x, z]}}
## Both face the experiment's front camera. The shell (ExperimentScreen) adds the cast next to the
## lab under the 3D view, not inside it: the lab's own tree, bodies and physics are the same with or
## without it (tests/island_cast_checks.gd). The cast only reads the lab's status() and
## explain_point(); it never touches a body or a displayed value.
##
## When the lab's status has been one of `explain_on` for `delay_s`, Dugi explains once: he points at
## Experiment.explain_point() and the screen shows the lab's `observe` text (관찰 포인트, the same
## words as the sidebar) in his speech bubble. He explains again only after the status was outside
## `explain_on` for REARM_S (a status that flickers, the buoyancy drum bobbing about its floating
## depth, does not repeat it) or the user changed the run (rearm()).
class_name IslandCast
extends Node3D

const REARM_S := 1.0
const DEFAULT_DELAY_S := 0.6

var experiment: Experiment
var dugi: DugiActor
var puppy: PuppyActor
var explain_on: Array = []
var delay_s := DEFAULT_DELAY_S
## The words of the bubble: the lab's observe text, exactly.
var text := ""
## Times Dugi started an explanation (tests).
var explain_count := 0
var _armed := true
var _inside := 0.0
var _outside := 0.0


## The cast of `definition` for `lab` (null when the definition has no `cast`).
static func create(definition: Dictionary, lab: Experiment) -> IslandCast:
	var spec: Dictionary = definition.get("cast", {})
	if spec.is_empty():
		return null
	var cast := IslandCast.new()
	cast.name = "IslandCast"
	cast.experiment = lab
	cast.text = definition.get("observe", "")
	var eye := front_eye(definition.get("camera", {}))
	if spec.has("dugi"):
		var d: Dictionary = spec.dugi
		cast.dugi = DugiActor.new()
		cast.explain_on = d.get("explain_on", [])
		cast.delay_s = float(d.get("delay_s", DEFAULT_DELAY_S))
		_stand(cast.dugi, d.at, eye)
		cast.add_child(cast.dugi)
	if spec.has("puppy"):
		cast.puppy = PuppyActor.new()
		_stand(cast.puppy, spec.puppy.at, eye)
		cast.add_child(cast.puppy)
	return cast


## On the floor at (x, z), facing the front camera (the model's front is +z).
static func _stand(actor: Node3D, at: Array, eye: Vector3) -> void:
	actor.position = Vector3(at[0], 0.0, at[1])
	actor.rotation.y = atan2(eye.x - at[0], eye.z - at[1])


## Where the camera of the definition's front view is (CameraRig: yaw 0 looks along -z, pitch < 0
## is above the target; the view's own target and distance, else the camera's).
static func front_eye(camera: Dictionary) -> Vector3:
	var view: Dictionary = camera.get("views", {}).get("front", {})
	var t: Array = view.get("target", camera.get("target", [0.0, 0.0, 0.0]))
	var distance: float = view.get("distance", camera.get("distance", 10.0))
	var yaw := deg_to_rad(view.get("yaw_deg", 0.0))
	var pitch := deg_to_rad(view.get("pitch_deg", -10.0))
	return Vector3(t[0], t[1], t[2]) + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance


## World AABB of the meshes under `node` (`skip`: the shadow), for placement checks.
static func drawn_bounds(node: Node, skip: Node = null) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi == skip or not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## The user changed the run (an action, a condition): Dugi stops explaining and may explain the
## new run.
func user_changed() -> void:
	if dugi != null:
		dugi.stop()
	rearm()


## Dugi may explain again (the next time the status is one to explain).
func rearm() -> void:
	_armed = true
	_inside = 0.0


## 처음으로: at once back to rest.
func reset() -> void:
	if dugi != null:
		dugi.stop(true)
	rearm()


func _process(delta: float) -> void:
	watch(delta)


## Follows the lab's status (tests call it with exact steps).
func watch(delta: float) -> void:
	if dugi == null or experiment == null or not is_instance_valid(experiment):
		return
	if experiment.status() in explain_on:
		_outside = 0.0
		_inside += delta
		if _armed and _inside >= delay_s - 1e-6:
			_armed = false
			explain_count += 1
			dugi.explain(experiment.explain_point)
	else:
		_inside = 0.0
		_outside += delta
		if _outside >= REARM_S:
			_armed = true
