## The island home (Plan G2): the 3D island seen from above, with the 5 zones and their 11 spots.
## A tap on a spot (its marker or its name label) makes the bread cat hop over, then the experiment
## opens; when all its stamps (3) are collected a flag stands there. One finger dragged on the map
## turns it like the 3D labs (two fingers turn and zoom, View3D). The settings button sits on the
## map. The stamps are read once when the map opens (refresh_progress), never per frame.
##
## The home is a Control that owns a View3D (top camera, ArtKit's island) and the bread cat
## (CatActor) who hops between spots. Spot names are 2D labels projected onto the map
## (the key-card / dialogue pattern: the 3D view under, UI on top). It never touches an
## experiment's physics: the map is its own little world. App.gd builds it the way it built the
## ListScreen (same signals).
class_name IslandHomeScreen
extends Control

signal experiment_chosen(definition: Dictionary)
signal settings_requested

var definitions: Array[Dictionary] = []
var view: View3D
var cat: CatActor
var _island_center := Vector3.ZERO
var _spots: Array[Dictionary] = []   # {id, definition, at, zone, marker}
var _flags: Dictionary = {}          # spot id -> flag root (visible at 3 stamps)
var _walking := false
var _walk_from := Vector3.ZERO
var _walk_to := Vector3.ZERO
var _walk_t := 0.0
var _walk_total := 0.0
var _walk_spot := -1
var _down := [Vector2.INF, false]    # screen point of the press, cancelled (a drag)
var _last := Vector2.INF             # the pointer's last point while it turns the map
var _progress: Dictionary = {}       # ProgressStore.load(), read on open (refresh_progress)
var _labels_for := Vector2.ZERO      # the view size the spot labels were placed for
var _labels_camera := Transform3D()  # the camera they were placed for
var _label_frames := 0               # frames the labels are placed again (their sizes settle)

const TAP_SLOP := 14.0               # UI units a press may move and still count as a tap
const WALK_SPEED := 6.0              # m/s the cat hops
const HOP_HEIGHT := 0.35             # m the cat rises on a hop
const HOP_HZ := 4.0                  # hops per second while walking
const SPOT_RADIUS := 2.2             # m: how far a tap may be from a spot and still hit it

## The 5 zones and their 11 spots. Each spot is an experiment id and where it stands on the island
## (x, z). The zones group the labs by what they need: the field (throws and falls), the slope
## (friction), the playground (springs, rotation, pulley, constraints), the pond (buoyancy) and the
## lookout (orbit).
const ZONES := {
	"들판": {"at": [-5.5, 3.5], "color": "5fd04a", "spots": [
		["projectile", [-8.0, 1.5]],
		["collision", [-4.0, 0.0]],
		["free-fall", [-6.5, 5.5]],
	]},
	"언덕": {"at": [6.0, 4.5], "color": "c98a4b", "spots": [
		["incline-friction", [4.5, 3.0]],
		["friction", [8.0, 6.0]],
	]},
	"놀이터": {"at": [0.5, -5.5], "color": "ffd84a", "spots": [
		["spring", [-2.0, -4.0]],
		["rotation", [3.0, -4.0]],
		["pulley", [1.0, -8.0]],
		["constraints", [-4.0, -8.0]],
	]},
	"연못": {"at": [-9.0, -3.5], "color": "8fd3ff", "spots": [
		["buoyancy", [-9.0, -4.0]],
	]},
	"전망대": {"at": [9.0, -3.5], "color": "9479ff", "spots": [
		["orbit", [9.5, -3.0]],
	]},
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view = View3D.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.single_pointer.connect(_on_pointer)

	# The island's own world: environment + island (ArtKit's) + the cat + the spot markers.
	var world := Node3D.new()
	world.name = "IslandHome"
	view.set_world(world)
	view.viewport.add_child(ArtKit.make_environment())
	var island_root := Node3D.new()
	world.add_child(island_root)
	_island_center = Vector3(0.0, 0.0, 0.0)
	ArtKit.build_island(island_root, _island_center)
	cat = CatActor.new(BreadCat.new())
	world.add_child(cat)
	cat.position = Vector3(_island_center.x, 0.0, _island_center.z + 7.0)
	cat.rotation.y = deg_to_rad(180.0)   # face the top camera ("up" on screen)

	for zone in ZONES:
		_build_zone(zone, world)

	view.rig.configure(_map_camera())
	refresh_progress()
	_build_top_bar()
	_layout()
	resized.connect(_layout)


## The map's camera definition (CameraRig.configure): a 3/4 view from above that turns all the way
## round and tilts between steep and low (one finger or two), zooms with a pinch, no panning.
func _map_camera() -> Dictionary:
	return {
		"target": [0.0, 0.0, 0.0],
		"distance": 27.0,
		"distance_range": [16.0, 34.0],
		"yaw_range_deg": [-180.0, 180.0],
		"pitch_range_deg": [-85.0, -30.0],
		"pan_radius": 0.0,
		"default_mode": "three_quarter",
		"views": {
			"front": {"yaw_deg": 0.0, "pitch_deg": -55.0},
			"three_quarter": {"yaw_deg": 0.0, "pitch_deg": -55.0},
			"top": {"yaw_deg": 0.0, "pitch_deg": -85.0},
			"side": {"yaw_deg": 90.0, "pitch_deg": -40.0},
			"follow": {"yaw_deg": 0.0, "pitch_deg": -55.0},
		},
	}


func _build_zone(zone: String, world: Node3D) -> void:
	var spec: Dictionary = ZONES[zone]
	_zone_pad(world, zone, spec)
	for spot in spec.spots:
		var id: String = spot[0]
		var at: Vector3 = Vector3(float(spot[1][0]), 0.0, float(spot[1][1]))
		var definition := ExperimentRegistry.find(id)
		var marker := _spot_marker(world, definition, at, spec)
		_spots.append({"id": id, "definition": definition, "at": at, "zone": zone, "marker": marker})


## A flat coloured disc under a zone's spots (the zone's territory on the grass).
func _zone_pad(world: Node3D, zone: String, spec: Dictionary) -> void:
	var b := ArtKit.builder()
	var at: Vector3 = Vector3(float(spec.at[0]), 0.03, float(spec.at[1]))
	b.add_cylinder(_at(at, 0.0), 3.4, 3.4, 0.05, 20, _zone_color(spec))
	var mi := ArtKit.instance(b.commit())
	mi.name = "ZonePad_%s" % zone
	world.add_child(mi)


func _zone_color(spec: Dictionary) -> Color:
	return Color(spec.color)


func _at(pos: Vector3, y: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(pos.x, y, pos.z))


## A spot's marker: a coloured post on the grass, and a flag that stands when the spot has all its
## stamps (3). The post's world position is what a tap measures against.
func _spot_marker(world: Node3D, definition: Dictionary, at: Vector3, spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Spot_%s" % definition.id
	root.position = at
	world.add_child(root)
	var b := ArtKit.builder()
	b.add_cylinder(_at(Vector3.ZERO, 0.0), 0.14, 0.14, 1.2, 8, _zone_color(spec))
	b.add_sphere(_at(Vector3(0.0, 1.25, 0.0), 0.0), 0.16, 5, 6, ArtPalette.WHITE)
	root.add_child(ArtKit.instance(b.commit()))
	var flag := Node3D.new()
	flag.name = "Flag"
	flag.visible = false
	var fb := ArtKit.builder()
	fb.add_cylinder(_at(Vector3.ZERO, 0.0), 0.05, 0.05, 2.0, 6, ArtPalette.TRUNK)
	fb.add_cylinder(_at(Vector3(0.06, 0.9, 0.0), 0.0), 0.02, 0.4, 0.6, 4, ArtPalette.RED)
	flag.add_child(ArtKit.instance(fb.commit()))
	root.add_child(flag)
	_flags[definition.id] = flag
	return root


## The top bar: the brand and the settings button (the home's own chrome, over the map).
func _build_top_bar() -> void:
	var bar := Ui.panel("TopBar")
	bar.name = "TopBar"
	add_child(bar)
	var row := Ui.hbox(12)
	bar.add_child(row)
	var brand := Ui.vbox(0)
	brand.add_child(Ui.label("빵고양이 과학섬", "HeadingLabel"))
	brand.add_child(Ui.label("가고 싶은 곳을 눌러 봐요", "EyebrowLabel"))
	row.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var settings := Ui.button("설정", "", 60)
	settings.name = "SettingsButton"
	settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings.pressed.connect(settings_requested.emit)
	row.add_child(settings)


func _layout() -> void:
	var bar: PanelContainer = find_child("TopBar", true, false)
	if bar == null:
		return
	var top: HBoxContainer = bar.get_child(0)
	bar.position = Vector2(0.0, 0.0)
	bar.size = Vector2(size.x, top.get_combined_minimum_size().y)


## The stamps of every spot from the store (one file read), and the flags they stand.
func refresh_progress() -> void:
	_progress = ProgressStore.load()
	for spot in _spots:
		_refresh_flag(spot)


## The cat's hop, and the 2D spot labels placed over the map when the view size or the camera changed.
func _process(delta: float) -> void:
	if _walking:
		_step_walk(delta)
	if view != null and view.rig != null and (view.size != _labels_for or view.rig.global_transform != _labels_camera):
		_labels_for = view.size
		_labels_camera = view.rig.global_transform
		_label_frames = 3
	if _label_frames > 0:
		_label_frames -= 1
		_place_labels()


func _step_walk(delta: float) -> void:
	_walk_t += delta
	var k := clampf(_walk_t / _walk_total, 0.0, 1.0)
	var eased := k * k * (3.0 - 2.0 * k)
	var pos := _walk_from.lerp(_walk_to, eased)
	pos.y = HOP_HEIGHT * absf(sin(_walk_t * PI * HOP_HZ))
	cat.position = pos
	if k >= 1.0:
		_walking = false
		cat.position = Vector3(_walk_to.x, 0.0, _walk_to.z)
		var spot: Dictionary = _spots[_walk_spot]
		experiment_chosen.emit(spot.definition)


## One 2D label per spot (its name), placed over its marker. Created lazily on the first frame the
## view has a size. The labels take no input: a tap on one reaches the map (_spot_at).
var _labels: Dictionary = {}


func _place_labels() -> void:
	if view == null or view.rig == null or view.size.x < 1.0:
		return
	for i in _spots.size():
		var spot: Dictionary = _spots[i]
		if not _labels.has(spot.id):
			_labels[spot.id] = _make_label(spot)
		var label: Control = _labels[spot.id]
		var screen_point := _world_to_screen(spot.at + Vector3.UP * 1.4)
		label.position = screen_point - label.size * 0.5
		label.visible = screen_point != Vector2.INF


## Stands the spot's flag when it has all its stamps (3), otherwise lowers it.
func _refresh_flag(spot: Dictionary) -> void:
	var flag: Node3D = _flags.get(spot.id)
	if flag == null:
		return
	var stages: Array = MissionTracker.missions(spot.definition).get("stages", [])
	if stages.is_empty():
		flag.visible = false
		return
	var stamps := ProgressStore.stamps(_progress, str(spot.id))
	flag.visible = stamps >= stages.size()


func _make_label(spot: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.name = "SpotLabel_%s" % spot.id
	box.theme_type_variation = "SpotPanel"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Ui.label(_spot_name(spot.definition), "SpotLabel")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	add_child(box)
	move_child(box, view.get_index() + 1)   # under the top bar
	return box


## A short name for the spot (the labs' own titles are long questions): the experiment's kid
## `place` ("공 던지기", ExperimentRegistry.kid_text), else its title.
func _spot_name(definition: Dictionary) -> String:
	return ExperimentRegistry.kid_text(definition, "place")


func _on_pointer(kind: String, position: Vector2) -> void:
	match kind:
		"press":
			_down[0] = position
			_down[1] = false
			_last = position
		"move":
			if _down[0] != Vector2.INF and position.distance_to(_down[0]) > TAP_SLOP:
				_down[1] = true   # a drag, not a tap: it turns the map
			if _down[1] and _last != Vector2.INF:
				view.rig.orbit(position - _last)
			_last = position
		"release":
			if _down[0] != Vector2.INF and not _down[1]:
				_walk_to_spot(_spot_at(position))
			_down[0] = Vector2.INF
			_down[1] = false
			_last = Vector2.INF
		"cancel":
			_down[0] = Vector2.INF
			_down[1] = false
			_last = Vector2.INF


## The index of the spot under the screen point: the spot whose name label holds it, else the
## nearest marker within SPOT_RADIUS, or -1.
func _spot_at(position: Vector2) -> int:
	if view == null or view.rig == null:
		return -1
	for i in _spots.size():
		var label: Control = _labels.get(_spots[i].id)
		if label != null and label.visible and Rect2(label.position, label.size).has_point(position):
			return i
	var best := -1
	var best_d := INF
	for i in _spots.size():
		var screen_point: Vector2 = _world_to_screen(_spots[i].at + Vector3.UP * 1.0)
		if screen_point == Vector2.INF:
			continue
		var d := screen_point.distance_to(position)
		if d <= _screen_radius(_spots[i].at) and d < best_d:
			best_d = d
			best = i
	return best


## A spot's tap radius, in screen units: its world radius projected at its distance (a minimum of
## TAP_SLOP so a marker is always tappable).
func _screen_radius(at: Vector3) -> float:
	if view == null or view.rig == null:
		return TAP_SLOP
	var eye: Vector3 = view.rig.global_position
	var dist: float = eye.distance_to(at + Vector3.UP * 1.0)
	var world_h := 2.0 * dist * tan(deg_to_rad(view.rig.fov) * 0.5)
	var screen_per_m := view.size.y / world_h
	return maxf(TAP_SLOP, SPOT_RADIUS * 0.5 * screen_per_m)


func _world_to_screen(world: Vector3) -> Vector2:
	if view == null or view.rig == null or not view.rig.is_inside_tree():   # the map being swapped out
		return Vector2.INF
	return view.rig.unproject_position(world) / (Vector2(view.viewport.size) / view.size)


## Starts the cat's hop to the spot; opens the experiment when it arrives.
func _walk_to_spot(index: int) -> void:
	if index < 0 or _walking:
		return
	_walk_from = cat.position
	_walk_to = _spots[index].at
	_walk_spot = index
	_walk_total = maxf(0.25, _walk_from.distance_to(_walk_to) / WALK_SPEED)
	_walk_t = 0.0
	_walking = true
	cat.rotation.y = atan2(_walk_to.x - _walk_from.x, _walk_to.z - _walk_from.z)
