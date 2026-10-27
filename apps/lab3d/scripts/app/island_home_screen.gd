## The island home (Plan G2): the 3D island seen from above, with the 5 zones and their 11 spots.
## A tap on a spot (its landmark or its name label) makes the bread cat hop over, then the experiment
## opens; when all its stamps (3) are collected a flag stands there. One finger dragged on the map
## turns it like the 3D labs (two fingers turn and zoom, View3D). The settings button sits on the
## map. The stamps are read once when the map opens (refresh_progress), never per frame.
##
## The home is a Control that owns a View3D (top camera, the map's own island: MapIsland, with
## sea, zone ground, paths and one landmark per spot, MapLandmarks) and the bread cat
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
var dugi: DugiActor
var puppy: PuppyActor
var map: MapIsland
var _spots: Array[Dictionary] = []   # {id, definition, at (stage top), top, radius, stand, zone, marker}
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
const LABEL_FULL_DISTANCE := 34.0    # m: a spot name nearer than this is full size
const LABEL_MIN_SCALE := 0.7          # the smallest a far spot name gets

## The 5 zones and their 11 spots. Each spot is an experiment id, where it stands on the island
## (x, z) and its landmark's turn (deg). The zones group the labs by what they need, each its own
## ground (MapIsland): the meadow (throws and falls), the hill (friction: the ramp at its foot,
## the push on its top), the sand yard (springs, rotation, pulley, constraints), the pond
## (buoyancy: the drum in the water, its dock towards the square) and the lookout's headland hill (orbit). Screen up is -z at the default view.
const ZONES := {
	"들판": {"at": [-6.0, 3.6], "ground": "meadow", "radius": 3.6, "spots": [
		["projectile", [-4.7, 6.2], 70.0],
		["collision", [-3.5, 1.5], 0.0],
		["free-fall", [-8.1, 3.3], 0.0],
	]},
	"언덕": {"at": [6.6, 3.1], "ground": "hill", "radius": 3.4, "height": 1.5, "spots": [
		["incline-friction", [3.3, 6.2], -25.0],
		["friction", [6.6, 3.0], 0.0],
	]},
	"놀이터": {"at": [0.3, -5.2], "ground": "yard", "size": [8.8, 4.9], "spots": [
		["spring", [-1.3, -4.0], 0.0],
		["rotation", [1.9, -4.0], 0.0],
		["pulley", [3.2, -6.5], 0.0],
		["constraints", [-2.8, -6.5], 0.0],
	]},
	"연못": {"at": [-7.5, -3.0], "ground": "pond", "radius": 2.0, "spots": [
		["buoyancy", [-6.9, -2.4], -45.0],
	]},
	"전망대": {"at": [8.4, -3.9], "ground": "hill", "radius": 2.4, "height": 1.7, "spots": [
		["orbit", [8.4, -3.9], 0.0],
	]},
}
## The cat's home square (x, z), where the paths meet and the cat waits when the map opens.
const HOME := [0.5, 2.0]
## Dugi and Puppy wait on the square with the cat (2026-10-27 user requests: they were missing
## from the map; then "why an L shape, why facing different ways"): the three in one row across the
## view like a group photo, the cat in the middle, Puppy on its left, Dugi on its right, TRIO_GAP m
## apart, all three facing the same way: the default camera (+z). They stand still when the map
## turns ("don't turn their bodies with the camera"). The signpost stands outside the row's reach
## (MapIsland: 1.3 m from HOME > TRIO_GAP + a body).
const TRIO_GAP := 0.85
const TRIO_YAW := 0.0   # rad about +y from +z: every actor's model faces +z at 0 (BreadCat, labs' cast)
## The dirt paths (x, z polylines, MapIsland smooths them): from the square to every spot.
const PATHS := [
	[[0.5, 2.0], [-1.4, 1.9], [-3.5, 1.5]],
	[[-3.5, 1.5], [-5.8, 2.1], [-8.1, 3.3]],
	[[-1.4, 1.9], [-2.9, 4.3], [-4.7, 6.2]],
	[[0.5, 2.0], [1.9, 3.9], [3.3, 6.2]],
	[[3.3, 6.2], [5.6, 5.6], [6.6, 3.0]],
	[[0.5, 2.0], [0.4, -0.1], [0.3, -2.75]],
	[[0.4, -0.1], [-3.0, -0.4], [-5.6, -1.1]],
	[[0.4, -0.1], [4.0, -0.7], [6.6, -2.2], [8.4, -3.9]],
]


func _ready() -> void:
	# After the CameraRig's _process (priority 0): the names are placed for this frame's camera,
	# not the last one (they trailed the map by a frame while it turned).
	process_priority = 1
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view = View3D.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.single_pointer.connect(_on_pointer)

	# The map's own world: environment + the map island (land, sea, landmarks) + the cat + the spots.
	var world := Node3D.new()
	world.name = "IslandHome"
	view.set_world(world)
	view.viewport.add_child(MapIsland.make_environment())
	map = MapIsland.new(ZONES, PATHS, Vector2(HOME[0], HOME[1]))
	var spots := []
	for zone in ZONES:
		for spot in ZONES[zone].spots:
			spots.append([spot[0], Vector2(spot[1][0], spot[1][1]), spot[2]])
	var built := map.build(world, spots)
	cat = CatActor.new(BreadCat.new())
	world.add_child(cat)
	dugi = DugiActor.new()
	puppy = PuppyActor.new()
	world.add_child(dugi)
	world.add_child(puppy)

	for zone in ZONES:
		for spot in ZONES[zone].spots:
			_add_spot(world, zone, spot[0], built[spot[0]])

	view.rig.configure(_map_camera())
	view.two_finger_pan = true   # one finger turns the map; two move it (and pinch zooms)
	_place_trio(TRIO_YAW)
	refresh_progress()
	_build_top_bar()
	_layout()
	resized.connect(_layout)


## The map's camera definition (CameraRig.configure): a 3/4 view from above by default, then almost
## free (2026-10-27 user decision "거의 제한 없이"): turns all the way round, tilts from straight
## down to almost level (one finger), zooms 6-60 m (pinch) and moves over the ground (two fingers)
## within PAN_RADIUS of the centre, so the island is never lost. The look-at point is TARGET_Y
## above the grass so a close, low camera stays over the hills.
const PITCH_RANGE := [-89.0, -8.0]
const DISTANCE_RANGE := [6.0, 60.0]
const PAN_RADIUS := 15.0
const TARGET_Y := 0.5


func _map_camera() -> Dictionary:
	return {
		"target": [0.0, TARGET_Y, 0.0],
		"distance": 27.0,
		"distance_range": DISTANCE_RANGE,
		"yaw_range_deg": [-180.0, 180.0],
		"pitch_range_deg": PITCH_RANGE,
		"pan_radius": PAN_RADIUS,
		"pan_ground": true,
		"default_mode": "three_quarter",
		"views": {
			"front": {"yaw_deg": 0.0, "pitch_deg": -55.0},
			"three_quarter": {"yaw_deg": 0.0, "pitch_deg": -55.0},
			"top": {"yaw_deg": 0.0, "pitch_deg": -85.0},
			"side": {"yaw_deg": 90.0, "pitch_deg": -40.0},
			"follow": {"yaw_deg": 0.0, "pitch_deg": -55.0},
		},
	}


## A spot: its node at the landmark's stage (the landmark itself is in the map's one landmark
## mesh, MapLandmarks) and the flag on the stage's edge that stands at all its stamps (3). The
## landmark's middle is what a tap measures against; the cat hops to `stand`, beside it.
func _add_spot(world: Node3D, zone: String, id: String, info: Dictionary) -> void:
	var definition := ExperimentRegistry.find(id)
	var root := Node3D.new()
	root.name = "Spot_%s" % id
	root.position = info.at
	world.add_child(root)
	var flag := Node3D.new()
	flag.name = "Flag"
	flag.visible = false
	flag.position = info.flag - info.at
	var fb := ArtKit.builder()
	fb.add_cylinder(Transform3D.IDENTITY, 0.05, 0.05, 2.2, 6, ArtPalette.TRUNK)
	fb.add_cylinder(Transform3D(Basis(), Vector3(0.06, 1.0, 0.0)), 0.02, 0.5, 0.75, 4, ArtPalette.RED)
	flag.add_child(ArtKit.instance(fb.commit()))
	root.add_child(flag)
	_flags[id] = flag
	_spots.append({"id": id, "definition": definition, "at": info.at, "top": info.top, "radius": info.radius,
		"stand": info.stand, "zone": zone, "marker": root})


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


## The trio's row on the square facing `yaw` (the camera's: yaw 0 looks along -z from +z): across
## the view through HOME, Puppy on the left, the cat in the middle, Dugi on the right. The cat
## keeps its own course while it hops to a spot.
func _place_trio(yaw: float) -> void:
	var home := Vector2(HOME[0], HOME[1])
	var right := Vector2(cos(yaw), -sin(yaw))   # screen right, on the ground
	var row := [[puppy, -1.0], [cat, 0.0], [dugi, 1.0]]
	for entry in row:
		var actor: Node3D = entry[0]
		if actor == null or (actor == cat and _walking):
			continue
		var at: Vector2 = home + right * TRIO_GAP * float(entry[1])
		actor.position = Vector3(at.x, map.walk_height(at.x, at.y), at.y)
		actor.rotation.y = yaw


## Where the trio stands now: [Dugi, cat, Puppy] (tests).
func trio() -> Array:
	return [dugi, cat, puppy]


func _step_walk(delta: float) -> void:
	_walk_t += delta
	var k := clampf(_walk_t / _walk_total, 0.0, 1.0)
	var eased := k * k * (3.0 - 2.0 * k)
	var pos := _walk_from.lerp(_walk_to, eased)
	pos.y = map.walk_height(pos.x, pos.z) + HOP_HEIGHT * absf(sin(_walk_t * PI * HOP_HZ))   # up the hills
	cat.position = pos
	if k >= 1.0:
		_walking = false
		cat.position = _walk_to
		var spot: Dictionary = _spots[_walk_spot]
		experiment_chosen.emit(spot.definition)


## One 2D label per spot (its name), its bottom edge just above its landmark (the landmark stays
## visible under it). Created lazily on the first frame the view has a size. The labels take no
## input: a tap on one reaches the map (_spot_at).
var _labels: Dictionary = {}


func _place_labels() -> void:
	if view == null or view.rig == null or view.size.x < 1.0:
		return
	var eye: Vector3 = view.rig.global_position
	var shown: Array = []   # [depth, label]
	for i in _spots.size():
		var spot: Dictionary = _spots[i]
		if not _labels.has(spot.id):
			_labels[spot.id] = _make_label(spot)
		var label: Control = _labels[spot.id]
		var screen_point := label_point(spot)
		label.visible = screen_point != Vector2.INF   # behind a close, low camera: hidden
		if not label.visible:
			continue
		label.position = screen_point - Vector2(label.size.x * 0.5, label.size.y)
		# Pinned at its bottom centre; a far one shrinks a little, like the landmark under it.
		var depth := eye.distance_to(spot.at)
		label.pivot_offset = Vector2(label.size.x * 0.5, label.size.y)
		label.scale = Vector2.ONE * clampf(LABEL_FULL_DISTANCE / maxf(depth, 0.01), LABEL_MIN_SCALE, 1.0)
		shown.append([depth, label])
	# Names that meet stay put: the nearer one is drawn over the farther (no jumping aside).
	shown.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var at := view.get_index() + 1
	for entry in shown:
		move_child(entry[1], at)
		at += 1


## The rect a label covers on screen (its scale about its bottom centre).
func _label_rect(label: Control) -> Rect2:
	return Rect2(label.position + label.pivot_offset * (Vector2.ONE - label.scale), label.size * label.scale)


## Where a spot's label sits on screen (its bottom centre): just above the landmark's top, a fixed
## point of the landmark, so the name rides with it at every camera angle. INF when the map is not
## on screen.
func label_point(spot: Dictionary) -> Vector2:
	return _world_to_screen(spot.at + Vector3.UP * (float(spot.top) + 0.25))


## Where a tap on a spot's landmark is measured from: its middle.
func tap_point(spot: Dictionary) -> Vector3:
	return spot.at + Vector3.UP * (float(spot.top) * 0.5)


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
## nearest landmark within SPOT_RADIUS, or -1.
func _spot_at(position: Vector2) -> int:
	if view == null or view.rig == null:
		return -1
	var hit := -1
	var hit_order := -1
	for i in _spots.size():   # the topmost name (the nearest, drawn last) wins
		var label: Control = _labels.get(_spots[i].id)
		if label != null and label.visible and _label_rect(label).has_point(position) and label.get_index() > hit_order:
			hit = i
			hit_order = label.get_index()
	if hit >= 0:
		return hit
	var best := -1
	var best_d := INF
	for i in _spots.size():
		var screen_point: Vector2 = _world_to_screen(tap_point(_spots[i]))
		if screen_point == Vector2.INF:
			continue
		var d := screen_point.distance_to(position)
		if d <= _screen_radius(tap_point(_spots[i])) and d < best_d:
			best_d = d
			best = i
	return best


## A spot's tap radius, in screen units: its world radius projected at its distance (a minimum of
## TAP_SLOP so a landmark is always tappable).
func _screen_radius(point: Vector3) -> float:
	if view == null or view.rig == null:
		return TAP_SLOP
	var eye: Vector3 = view.rig.global_position
	var dist: float = eye.distance_to(point)
	var world_h := 2.0 * dist * tan(deg_to_rad(view.rig.fov) * 0.5)
	var screen_per_m := view.size.y / world_h
	return maxf(TAP_SLOP, SPOT_RADIUS * 0.5 * screen_per_m)


## A world point on the view, or INF when the map is being swapped out or the point is behind the
## camera (a low, close view: its label hides, a tap cannot pick it).
func _world_to_screen(world: Vector3) -> Vector2:
	if view == null or view.rig == null or not view.rig.is_inside_tree():   # the map being swapped out
		return Vector2.INF
	if view.rig.is_position_behind(world):
		return Vector2.INF
	return view.rig.unproject_position(world) / (Vector2(view.viewport.size) / view.size)


## Starts the cat's hop to the spot (beside its landmark); opens the experiment when it arrives.
func _walk_to_spot(index: int) -> void:
	if index < 0 or _walking:
		return
	_walk_from = cat.position
	_walk_to = _spots[index].stand
	_walk_spot = index
	_walk_total = maxf(0.25, _walk_from.distance_to(_walk_to) / WALK_SPEED)
	_walk_t = 0.0
	_walking = true
	cat.rotation.y = atan2(_walk_to.x - _walk_from.x, _walk_to.z - _walk_from.z)
