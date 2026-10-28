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
var world: Node3D
var env: WorldEnvironment
## The story "별 조각 찾기" (StoryDirector, only when Story.enabled): the prologue, the found pieces'
## flights to the lookout, the finale, the corner emblem. null in measurements and plain tests.
var story: StoryDirector = null
## App: play the prologue when the map opens (first launch, or 이야기 다시 보기).
var play_prologue_on_open := false
var _cinematic := false
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
## The flag raise (2026-10-28): a spot whose round was completed since the map last showed it
## (ProgressStore.pending_flags) gets its flag raised once: the camera eases over to frame the spot
## (a timed close-up that ends exactly on the child's view), the flag grows out of the ground with a
## bounce, then the camera is the child's again. A tap during it skips it (and opens nothing).
var _raise_queue: Array = []         # spot ids still to raise
var _raising: Dictionary = {}        # {id, flag, t} of the raise playing now
var raised_count := 0                # flag raises played (tests)
## Screenshots (--demo-flag=<id>): that spot's round counts as just completed, in the bench store only.
static var _demo_flag_done := false

const RAISE_DELAY_S := 0.5           # the map is on screen first (its slide-in, the first heavy frames)
const RAISE_IN_S := 0.8              # the camera eases to the spot
const RAISE_HOLD_S := 1.5            # it stays while the flag rises
const RAISE_OUT_S := 0.8             # and eases back to the child's view
const RAISE_START_S := 0.6           # the flag starts to grow (into the ease-in)
const RAISE_GROW_S := 1.0            # the grow with its bounce
const RAISE_FILL := 0.42             # share of the view height the spot (landmark + flag) takes

const TAP_SLOP := 14.0               # UI units a press may move and still count as a tap
const WALK_SPEED := 6.0              # m/s the cat hops
const HOP_HEIGHT := 0.35             # m the cat rises on a hop
const HOP_HZ := 4.0                  # hops per second while walking
const SPOT_RADIUS := 2.2             # m: how far a tap may be from a spot and still hit it
const LABEL_FULL_DISTANCE := 34.0    # m: a spot name nearer than this is full size
const LABEL_MIN_SCALE := 0.7          # the smallest a far spot name gets

## The map's layout (MapIsland.ZONES, HOME, PATHS: the labs' worlds read it too, LabWorld).
const ZONES := MapIsland.ZONES
const HOME := MapIsland.HOME
const PATHS := MapIsland.PATHS
## Dugi and Puppy wait on the square with the cat (2026-10-27 user requests: they were missing
## from the map; then "why an L shape, why facing different ways"): the three in one row across the
## view like a group photo, the cat in the middle, Puppy on its left, Dugi on its right, TRIO_GAP m
## apart, all three facing the same way: the default camera (+z). They stand still when the map
## turns ("don't turn their bodies with the camera"). The signpost stands outside the row's reach
## (MapIsland: 1.3 m from HOME > TRIO_GAP + a body).
const TRIO_GAP := 0.85
const TRIO_YAW := 0.0   # rad about +y from +z: every actor's model faces +z at 0 (BreadCat, labs' cast)


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
	world = Node3D.new()
	world.name = "IslandHome"
	view.set_world(world)
	env = MapIsland.make_environment()
	view.viewport.add_child(env)
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
	view.rig.focus_modes = ["three_quarter", "orbit", "front", "top", "side"]   # the flag raise frames the spot from any view
	_demo_flag()
	view.two_finger_pan = true   # one finger turns the map; two move it (and pinch zooms)
	_place_trio(TRIO_YAW)
	refresh_progress()
	_build_top_bar()
	_layout()
	resized.connect(_layout)
	if Story.enabled:
		story = StoryDirector.new(self)
		add_child(story)
		story.refresh()
		if play_prologue_on_open:
			story.play_prologue()


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
	MapFlag.build(fb)
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
	_raise_queue.clear()
	if story != null:
		story.refresh()
	for id in ProgressStore.pending_flags():
		var flag: Node3D = _flags.get(id)
		if flag != null and flag.visible:   # all its stamps: raise it once (else it stays pending)
			flag.visible = false
			_raise_queue.append(id)
	_next_raise()


## Starts the next queued flag raise: the store says "raised" at once (it never replays, even when
## the app is closed during it).
func _next_raise() -> void:
	if not _raising.is_empty() or _raise_queue.is_empty():
		return
	var id: String = _raise_queue.pop_front()
	var spot: Dictionary = {}
	for s in _spots:
		if s.id == id:
			spot = s
	ProgressStore.mark_flag_raised(id)
	var flag: Node3D = _flags[id]
	flag.visible = true
	flag.scale = Vector3(1.0, 0.01, 1.0)
	_raising = {"id": id, "flag": flag, "t": -RAISE_DELAY_S, "framed": false, "spot": spot}
	raised_count += 1


## The camera's timed close-up on the raising spot (ends exactly on the child's view).
func _frame_raise(spot: Dictionary, flag: Node3D) -> void:
	var top: Vector3 = spot.at + Vector3.UP * maxf(float(spot.top), 2.4)
	var box := AABB(spot.at, Vector3.ZERO).expand(flag.global_position + Vector3.UP * 2.4).expand(top)
	box = box.grow(1.0)
	view.rig.focus({"box": box, "fill": RAISE_FILL, "anchor": Vector2(0.5, 0.55),
		"in_s": RAISE_IN_S, "hold_s": RAISE_HOLD_S, "out_s": RAISE_OUT_S})


## The flag's height share at `t` s into its grow: 0 -> past 1 (a bounce) -> 1.
static func raise_height(t: float) -> float:
	var k := clampf(t / RAISE_GROW_S, 0.0, 1.0)
	if k >= 1.0:
		return 1.0
	return maxf(0.01, 1.0 - exp(-5.0 * k) * cos(2.5 * PI * k))


func _step_raise(delta: float) -> void:
	if _raising.is_empty() or _cinematic:   # the prologue first
		return
	var before: float = _raising.t
	_raising.t += minf(delta, 0.05)   # a long frame never skips the grow
	if before < RAISE_START_S and _raising.t >= RAISE_START_S:
		SoundBoard.play(&"flag")   # the flag starts to grow
	var flag: Node3D = _raising.flag
	if _raising.t >= 0.0 and not _raising.framed:
		_raising.framed = true
		_frame_raise(_raising.spot, flag)
	var h := raise_height(_raising.t - RAISE_START_S)
	flag.scale = Vector3(1.0, h, 1.0)   # grows up with its bounce; no sideways squash (it bent the banner)
	if _raising.t >= RAISE_IN_S + RAISE_HOLD_S + RAISE_OUT_S and _raising.framed and not view.rig.is_framing():
		flag.scale = Vector3.ONE
		_raising = {}
		_next_raise()


## Ends every raise now (a tap): flags up, the camera at once on the child's view.
func skip_raise() -> void:
	if _raising.is_empty():
		return
	for id in [_raising.id] + _raise_queue:
		ProgressStore.mark_flag_raised(id)
		var flag: Node3D = _flags[id]
		flag.visible = true
		flag.scale = Vector3.ONE
	_raise_queue.clear()
	_raising = {}
	view.rig.cut_focus()


func raising() -> bool:
	return not _raising.is_empty()


## --demo-flag=<id> (screenshots): the bench store, that spot at all its stamps and its flag pending.
func _demo_flag() -> void:
	var id := Quality.cmdline_value("demo-flag")
	if id == "" or _demo_flag_done or ExperimentRegistry.find(id).is_empty():
		return
	_demo_flag_done = true
	ProgressStore.path = ProgressStore.BENCH_PATH   # never the child's progress
	var store := ProgressStore.load()
	store[id] = MissionTracker.missions(ExperimentRegistry.find(id)).get("stages", []).size()
	ProgressStore.save(store)
	ProgressStore.mark_flag_pending(id)


## The cat's hop, and the 2D spot labels placed over the map when the view size or the camera changed.
func _process(delta: float) -> void:
	if _walking:
		_step_walk(delta)
	_step_raise(delta)
	if _cinematic:
		return
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


## The story's prologue or finale has the screen: the top bar and the spot names hide (the labels are
## placed again when it ends), taps go to the story.
func set_cinematic(on: bool) -> void:
	_cinematic = on
	var bar: Control = find_child("TopBar", true, false)
	if bar != null:
		bar.visible = not on
	for id in _labels:
		(_labels[id] as Control).visible = not on
	if not on:
		_label_frames = 3


## The trio back on the square (after the story moved the cat).
func reset_trio() -> void:
	_place_trio(TRIO_YAW)


## Where `actor` stands in the trio's row on the square.
func trio_spot(actor: Node3D) -> Vector3:
	var home := Vector2(HOME[0], HOME[1])
	var right := Vector2(cos(TRIO_YAW), -sin(TRIO_YAW))
	var place := {puppy: -1.0, cat: 0.0, dugi: 1.0}
	var at: Vector2 = home + right * TRIO_GAP * float(place.get(actor, 0.0))
	return Vector3(at.x, map.walk_height(at.x, at.y), at.y)


## Where the trio stands now: [Dugi, cat, Puppy] (tests).
func trio() -> Array:
	return [dugi, cat, puppy]


func _step_walk(delta: float) -> void:
	var hops := floori(_walk_t * HOP_HZ)
	_walk_t += delta
	if floori(_walk_t * HOP_HZ) > hops:
		SoundBoard.play(&"hop")   # each hop's landing (HOP_HZ a second while it walks)
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
			if _cinematic:
				return   # the story's shield takes the taps
			if raising() or (story != null and story.flying()):
				skip_raise()   # the tap only skips (it opens nothing): the flag and the pieces' flights
				if story != null:
					story.skip_flights()
				_down[0] = Vector2.INF
				return
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
	SoundBoard.play(&"spot")
	cat.rotation.y = atan2(_walk_to.x - _walk_from.x, _walk_to.z - _walk_from.z)
