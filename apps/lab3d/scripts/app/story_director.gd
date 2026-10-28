## The story on the island map (the story "별 조각 찾기", 2026-10-28; the words and saved marks: Story).
## It plays three things over the map, each with its own camera moves:
## - the prologue (first launch, or 이야기 다시 보기 in the settings): 8 pages in the dialogue box, the
##   camera gliding from the far sea of 퍼피랜드 to 과학섬, night falling, the guiding star breaking into
##   11 pieces that land at the 11 spots, the dark sea and the lost boats' lanterns, a sweep over the
##   island, then the bread cat on the square as the day comes back. A tap turns the page; 건너뛰기
##   skips it all. Afterwards the map is as it was (no piece on it, the day, the child's camera).
## - a found piece's flight (a round completed in a lab): after the spot's flag rises, a star piece
##   flies from the spot to the lookout (전망대) and the corner emblem (StarEmblem) fills a wedge.
## - the finale (the 11th piece at the lookout, once): the pieces gather into the whole star, Puppy and
##   Dugi speak, the bread cat lifts the star and it rises to the sky; the sea sparkles, the boats light
##   their lanterns and sail. The star then stays in the map's sky.
##
## The camera: while a prologue or the finale plays the director draws the rig itself (the rig's own
## easing is paused; the child's view, goal_* and pan, is never touched) with eased moves between
## shots, and at the end it eases back to the child's view and hands the rig back exactly there
## (CameraRig.snap). A flight uses the rig's own timed close-up (CameraRig.focus), like the flag raise.
## The night is a global multiplier on the map's shaders (story_tint) and the map's sea colour, put
## back to the day at the end (and when the map goes away).
##
## Pictures and words only: the director never opens a lab, sets a control or reads a body. Its 3D
## nodes are outside the map's default view or gone after the story (the map stays clean), apart from
## the sky star after the finale.
class_name StoryDirector
extends Node

signal ended(part: String)

const NIGHT_TINT := Vector3(0.42, 0.5, 0.82)
const DARK_TINT := Vector3(0.26, 0.31, 0.6)
const NIGHT_SEA := Color("1b4478")
const DARK_SEA := Color("0e2649")
## The guiding star in the prologue's night sky, above and behind the island (default view: -z).
const STAR_AT := Vector3(0.0, 24.0, -16.0)
const STAR_SIZE := 2.4
## Where the star rests in the map's sky after the finale: high over the island's middle, inside the
## map's default view (tests), and where it first rises to.
const SKY_STAR_AT := Vector3(2.5, 8.5, -3.0)
const SKY_STAR_SIZE := 0.9
const SKY_HIGH := Vector3(3.0, 21.0, -6.0)
const PIECE_SIZE := 0.42
const FLIGHT_IN_S := 0.6
const FLIGHT_S := 1.3
const FLIGHT_OUT_S := 0.6
const RETURN_S := 1.4
const FIRST_SHOT := {"yaw": 0.0, "pitch": -8.0, "dist": 150.0, "target": Vector3(0.0, 6.0, -55.0)}
const DIALOGUE_MARGIN := 12.0
const DIALOGUE_SHARE := 0.8        # of the view width the box may take (the scene stays in view)

var home: IslandHomeScreen
var part := ""                     # "", "prologue", "flight", "finale"
var page := -1                     # the prologue / finale page now (-1: none)
var sea: MapSea
var emblem: StarEmblem
var sky_star: Node3D
var dialogue: DialogueBox
var shield: Control
var skip_button: Button
## Night: 0 day, 1 night, 2 the darker night after the star broke. The tint it puts on (tests).
var night := 0.0
var tint := Vector3.ONE
var placed_count := 0              # pieces at the lookout shown on the emblem
var flights_played := 0            # (tests)
var _night_from := 0.0
var _night_to := 0.0
var _night_t := 0.0
var _night_s := 0.0
var _day_sea := Color.BLACK
var _can_tint := false
## The camera while the director draws it: an eased move from one shot to another.
var _driving := false
var _cam_from: Dictionary = {}
var _cam_to: Dictionary = {}
var _cam_t := 0.0
var _cam_s := 0.0
var _returning := false
## Timed beats of the current page: [[seconds left, Callable], ...].
var _beats: Array = []
var _clock := 0.0
var _star: Node3D = null           # the guiding star while it is whole in a story
var _star_motion: Dictionary = {}  # {from, to, t, s} a move of _star
var _pieces: Array = []            # [{node, from, ctrl, to, t, s, spin}]
var _sparkles: Array = []          # [node, phase]
var _cat_hop: Dictionary = {}      # {from, to, t, s, height}
var _boats_wander := false
var _boats_sail := -1.0
var _flight_queue: Array = []
var _flight: Dictionary = {}       # {id, node, from, to, t}
var _lift := false                 # the finale's star rides above the cat's paws
var _finale_due := false           # all pieces found, the finale not played: after the flights


func _init(screen: IslandHomeScreen) -> void:
	name = "StoryDirector"
	home = screen


func _ready() -> void:
	_can_tint = DisplayServer.get_name() != "headless"
	_day_sea = home.env.environment.background_color if home.env != null else MapIsland.sea_color()
	sea = MapSea.new()
	sea.build(home.world)
	sea.set_lanterns(Story.finale_seen())
	emblem = StarEmblem.new(Story.spots().size())
	home.add_child(emblem)
	placed_count = Story.placed(ProgressStore.load()).size()
	emblem.set_filled(placed_count)
	if Story.finale_seen():
		_place_sky_star()
	_layout()
	home.resized.connect(_layout)


func _exit_tree() -> void:
	_set_night(0.0)   # never leave the night on (the map is swapped out mid-story)


# --- state -------------------------------------------------------------------------------------

## A prologue or the finale plays: the director has the camera and the screen (the map's labels,
## top bar and taps wait).
func cinematic() -> bool:
	return part == "prologue" or part == "finale"


## Anything of the story plays (a flight too).
func busy() -> bool:
	return part != ""


func flying() -> bool:
	return part == "flight"


## After the map's progress is read (and its flag raises queued): queue the found pieces' flights;
## the finale follows the last one. Nothing starts while the prologue or a flag raise plays.
func refresh() -> void:
	var progress := ProgressStore.load()
	_flight_queue = Story.to_fly(progress)
	_finale_due = Story.found(progress).size() >= Story.spots().size() and not Story.finale_seen()


# --- the prologue -------------------------------------------------------------------------------

func play_prologue() -> void:
	if cinematic():
		return
	_begin("prologue")
	_set_camera(FIRST_SHOT)
	_open_page(0)


## The page `i` of the current part: its words (if any) and its camera, night and beats.
func _open_page(i: int) -> void:
	page = i
	_beats.clear()
	var pages := Story.pages(part)
	if part == "prologue":
		_prologue_page(i)
	else:
		_finale_page(i)
	if i < pages.size():
		var entry: Dictionary = pages[i]
		dialogue.set_speaker(str(entry.get("who", "dugi")))
		dialogue.open(str(entry.get("text", "")))
		_layout()


func _prologue_page(i: int) -> void:
	var home_at := Vector3(MapIsland.HOME[0], 0.0, MapIsland.HOME[1])
	match i:
		0:   # the far sea of 퍼피랜드: islands, boats; a slow drift
			_move({"yaw": 6.0, "pitch": -9.0, "dist": 138.0, "target": FIRST_SHOT.target}, 7.0)
		1:   # gliding in towards 과학섬
			_move({"yaw": 0.0, "pitch": -32.0, "dist": 36.0, "target": Vector3(0.0, 0.5, 0.0)}, 3.4)
		2:   # night falls; the guiding star; the camera tilts up to it
			_night(1.0, 1.8)
			sea.set_lanterns(true)
			_beat(0.7, _show_star)
			_move({"yaw": 0.0, "pitch": 24.0, "dist": 34.0, "target": STAR_AT}, 3.0)
		3:   # it cracks and breaks; the pieces fall to the spots; the camera pulls back to see them land
			_beat(0.0, func() -> void: _shake_star(0.6))
			_beat(0.6, _break_star)
			_move({"yaw": 0.0, "pitch": -12.0, "dist": 58.0, "target": Vector3(0.0, 9.0, -5.0)}, 2.4)
		4:   # the sea goes darker, the lost boats' lanterns wander
			_night(2.0, 1.5)
			_boats_wander = true
			_move({"yaw": 40.0, "pitch": -13.0, "dist": 52.0, "target": Vector3.ZERO}, 3.0)
		5:   # a sweep over the island: the pieces glint at the spots
			_move({"yaw": -30.0, "pitch": -42.0, "dist": 25.0, "target": Vector3(0.0, 0.5, 0.0)}, 5.0, true)
		6:   # the sweep goes on
			_move({"yaw": -110.0, "pitch": -45.0, "dist": 23.0, "target": Vector3(0.0, 0.5, 0.0)}, 6.0, true)
		7:   # the square: the bread cat hops out and lifts a paw; the day comes back
			_move({"yaw": 0.0, "pitch": -24.0, "dist": 8.5, "target": home_at + Vector3(0.0, 0.7, 0.0)}, 2.2)
			_beat(1.0, func() -> void:
				_night(0.0, 2.0)
				_boats_wander = false)
			_beat(1.5, func() -> void:
				_hop_cat(home.cat.position, home.cat.position, 0.6, 0.8)
				SoundBoard.play(&"hop"))
			_beat(2.1, func() -> void: home.cat.cheer(true, 2))
			_beat(2.0, _fade_pieces)


## The words of the page closed (a tap past it, or its read timer): the next page, or the end.
func _on_dialogue_closed() -> void:
	if not cinematic() or _returning:
		return
	var pages := Story.pages(part)
	if part == "prologue":
		if page < pages.size() - 1:
			_open_page(page + 1)
		else:
			_end_cinematic()
	elif part == "finale":
		if page < pages.size() - 1:
			_open_page(page + 1)
		else:
			_open_page(pages.size())   # the last part has no words


# --- the finale ---------------------------------------------------------------------------------

func play_finale() -> void:
	if cinematic():
		return
	ProgressStore.set_mark(ProgressStore.STORY, "finale", true)   # once, even if the app closes during it
	_begin("finale")
	_finale_intro()


func _lookout() -> Dictionary:
	for spot in home._spots:
		if spot.id == "orbit":
			return spot
	return home._spots[0]


func _lookout_point() -> Vector3:
	var spot := _lookout()
	return spot.at + Vector3.UP * (float(spot.top) + 1.6)


## Before the words: the camera goes to the lookout, the pieces gather into the whole star there.
func _finale_intro() -> void:
	page = -1
	var at := _lookout_point()
	_move({"yaw": -25.0, "pitch": -20.0, "dist": 10.5, "target": at}, 1.8)
	_beat(0.6, _gather_pieces)
	_beat(2.9, func() -> void: _open_page(0))


func _finale_page(i: int) -> void:
	var at := _lookout_point()
	match i:
		0:
			_move({"yaw": -15.0, "pitch": -16.0, "dist": 9.0, "target": at}, 2.0)
		1:
			_move({"yaw": -35.0, "pitch": -18.0, "dist": 10.0, "target": at}, 2.5)
		2:   # no words: the cat hops over and lifts the star; it rises; the sea sparkles, the boats sail
			var spot := _lookout()
			_hop_cat(home.cat.position, spot.stand, 1.1, 1.2)
			SoundBoard.play(&"hop")
			_move({"yaw": -25.0, "pitch": -12.0, "dist": 11.0, "target": at + Vector3.DOWN * 0.8}, 1.4)
			_beat(1.1, func() -> void:
				home.cat.cheer(true, 3)
				_lift = true)
			_beat(2.1, func() -> void:
				_lift = false
				_move_star(SKY_HIGH, 2.2)
				SoundBoard.play(&"piece_fly")
				_move({"yaw": -10.0, "pitch": 18.0, "dist": 30.0, "target": SKY_HIGH}, 2.4))
			_beat(4.3, func() -> void:
				SoundBoard.play(&"finale")
				_sparkle_sea()
				sea.set_lanterns(true)
				_boats_sail = 0.0
				_move({"yaw": 15.0, "pitch": -14.0, "dist": 62.0, "target": Vector3(0.0, 4.0, -4.0)}, 2.6))
			_beat(8.0, func() -> void:
				_move_star(SKY_STAR_AT, RETURN_S)
				_hop_cat(home.cat.position, home.trio_spot(home.cat), 1.0, 1.0)
				_end_cinematic())


# --- flights -----------------------------------------------------------------------------------

## Starts the next found piece's flight (after the flag raises): the camera frames the spot and the
## lookout, the piece arcs over, the emblem fills a wedge. The store says "flown" at once (it never
## replays). After the last one, the finale when all are found (advance).
func _next_flight() -> void:
	if not _flight_queue.is_empty():
		var id: String = _flight_queue.pop_front()
		ProgressStore.set_mark(ProgressStore.PIECES, id, true)
		var spot: Dictionary = {}
		for s in home._spots:
			if s.id == id:
				spot = s
		if spot.is_empty():
			return
		part = "flight"
		var from: Vector3 = spot.at + Vector3.UP * (float(spot.top) + 0.6)
		var to := _lookout_point()
		var node := StarArt.make(true, PIECE_SIZE)
		home.world.add_child(node)
		node.position = from
		_flight = {"id": id, "node": node, "from": from, "to": to, "t": -FLIGHT_IN_S}
		var box := AABB(from, Vector3.ZERO).expand(to).expand(spot.at).grow(1.5)
		home.view.rig.focus({"box": box, "fill": 0.55, "anchor": Vector2(0.5, 0.55),
			"in_s": FLIGHT_IN_S, "hold_s": FLIGHT_S + 0.2, "out_s": FLIGHT_OUT_S})
		flights_played += 1
		SoundBoard.play(&"glint")


func _step_flight(delta: float) -> void:
	if _flight.is_empty():
		if part == "flight" and not home.view.rig.is_framing():
			part = ""
			ended.emit("flight")
		return
	var before: float = _flight.t
	_flight.t += delta
	if before < 0.0 and _flight.t >= 0.0:
		SoundBoard.play(&"piece_fly")
	var k := clampf(_flight.t / FLIGHT_S, 0.0, 1.0)
	var node: Node3D = _flight.node
	node.position = _arc(_flight.from, _flight.to, 4.0, k * k * (3.0 - 2.0 * k))
	node.rotation.y += delta * 6.0
	if k >= 1.0:
		node.queue_free()
		_flight = {}
		placed_count += 1
		emblem.set_filled(placed_count, true)
		SoundBoard.play(&"glint")


## Ends every flight now (a tap): the pieces at the lookout, the camera the child's at once.
func skip_flights() -> void:
	var any := not _flight.is_empty() or not _flight_queue.is_empty()
	for id in _flight_queue:
		ProgressStore.set_mark(ProgressStore.PIECES, id, true)
	_flight_queue.clear()
	if not _flight.is_empty():
		(_flight.node as Node3D).queue_free()
		_flight = {}
	if any or part == "flight":
		placed_count = Story.placed(ProgressStore.load()).size()
		emblem.set_filled(placed_count)
		home.view.rig.cut_focus()
		part = ""


# --- the frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance(minf(delta, 0.05))


## Moves the story on by `delta` s (tests step it).
func advance(delta: float) -> void:
	_clock += delta
	if part == "flight":
		_step_flight(delta)
	if part == "" and not home.raising():
		if not _flight_queue.is_empty():
			_next_flight()
		elif _finale_due:
			_finale_due = false
			play_finale()
	for b in _beats.duplicate():
		b[0] -= delta
		if b[0] <= 0.0:
			_beats.erase(b)
			(b[1] as Callable).call()
	_step_night(delta)
	_step_star(delta)
	_step_pieces(delta)
	_step_cat(delta)
	_step_boats(delta)
	_step_sparkles(delta)
	if _driving:
		_step_camera(delta)
	if sky_star != null:
		sky_star.rotation.y += delta * 0.8


# --- cinematic plumbing -------------------------------------------------------------------------

## A prologue or the finale starts: the director takes the camera and the screen.
func _begin(which: String) -> void:
	skip_flights()
	part = which
	_returning = false
	_beats.clear()
	var rig := home.view.rig
	rig.cut_focus()
	rig.set_process(false)
	_driving = true
	_cam_t = 0.0
	_cam_s = 0.0
	_cam_from = _pose_now()
	_cam_to = _cam_from
	home.set_cinematic(true)
	emblem.visible = which == "finale"
	if dialogue == null:
		shield = Control.new()
		shield.name = "StoryShield"
		shield.mouse_filter = Control.MOUSE_FILTER_STOP
		shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shield.gui_input.connect(_on_shield_input)
		home.add_child(shield)
		dialogue = DialogueBox.new("")
		home.add_child(dialogue)
		dialogue.closed.connect(_on_dialogue_closed)
		skip_button = Ui.button("건너뛰기", "", 56)
		skip_button.name = "SkipButton"
		skip_button.pressed.connect(skip)
		home.add_child(skip_button)
	shield.visible = true
	skip_button.visible = true
	_layout()


## The last page is over: the camera eases back to the child's view, then everything is the map's
## again.
func _end_cinematic() -> void:
	if _returning:
		return
	_returning = true
	if dialogue.active:
		dialogue.close(true)
	dialogue.visible = false
	_move(_child_pose(), RETURN_S)
	_beat(RETURN_S, _finish)


## Skips the prologue or the finale now: its end state at once (day, the map clean, the child's
## camera exactly).
func skip() -> void:
	if not cinematic():
		return
	_beats.clear()
	_finish()


func _finish() -> void:
	var which := part
	_beats.clear()
	_returning = false
	if dialogue != null:
		if dialogue.active:
			dialogue.close(true)
		dialogue.visible = false
		shield.visible = false
		skip_button.visible = false
	_set_night(0.0)
	_night_s = 0.0
	_clear_pieces()
	if _star != null:
		_star.queue_free()
		_star = null
	_star_motion = {}
	_lift = false
	for s in _sparkles:
		(s[0] as Node3D).queue_free()
	_sparkles.clear()
	_boats_wander = false
	_boats_sail = -1.0
	sea.rest_boats()
	_cat_hop = {}
	home.reset_trio()
	if which == "prologue":
		ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
		sea.set_lanterns(Story.finale_seen())
	else:
		sea.set_lanterns(true)
		_place_sky_star()
	var rig := home.view.rig
	_driving = false
	rig.set_process(true)
	rig.snap()   # exactly the child's view (its goal was never touched)
	part = ""
	page = -1
	emblem.visible = true
	home.set_cinematic(false)
	ended.emit(which)


## A tap anywhere but the box and 건너뛰기: the same as a tap on the box (the whole page, the next).
func _on_shield_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if tap:
		tap_page()
		shield.accept_event()


func tap_page() -> void:
	if dialogue != null and dialogue.active:
		dialogue.advance()


func _layout() -> void:
	var view_size := home.view.size if home.view != null else home.size
	if emblem != null:
		emblem.position = Vector2(DIALOGUE_MARGIN + 6.0, view_size.y - StarEmblem.SIZE - DIALOGUE_MARGIN - 6.0)
	if skip_button != null:
		skip_button.size = skip_button.get_combined_minimum_size()
		skip_button.position = Vector2(view_size.x - skip_button.size.x - DIALOGUE_MARGIN, DIALOGUE_MARGIN)
	if dialogue != null and dialogue.active:
		var right := maxf(view_size.x * DIALOGUE_SHARE, minf(view_size.x - DIALOGUE_MARGIN, 900.0))
		dialogue.visible = dialogue.layout(Rect2(Vector2.ZERO, view_size), right, DIALOGUE_MARGIN)


# --- camera ------------------------------------------------------------------------------------

func _pose_now() -> Dictionary:
	var rig := home.view.rig
	return {"yaw": rad_to_deg(rig.cur_yaw), "pitch": rad_to_deg(rig.cur_pitch), "dist": rig.cur_distance, "target": rig.cur_target}


## The child's own view (the rig's goal: never changed by the story).
func _child_pose() -> Dictionary:
	var rig := home.view.rig
	return {"yaw": rad_to_deg(rig.goal_yaw), "pitch": rad_to_deg(rig.goal_pitch), "dist": rig.goal_distance, "target": rig._view_goal_target()}


func _set_camera(shot: Dictionary) -> void:
	_cam_from = shot.duplicate()
	_cam_to = shot.duplicate()
	_cam_t = 0.0
	_cam_s = 0.0
	_draw_camera(shot)


## Eases from the drawn view to `shot` over `seconds` (smoothstep). A sweep turns the long way the
## yaw says; any other move turns the short way.
func _move(shot: Dictionary, seconds: float, sweep := false) -> void:
	_cam_from = _pose_now()
	_cam_to = shot.duplicate()
	if not sweep:
		_cam_to.yaw = _cam_from.yaw + wrapf(float(shot.yaw) - float(_cam_from.yaw), -180.0, 180.0)
	_cam_t = 0.0
	_cam_s = maxf(seconds, 0.01)


func _step_camera(delta: float) -> void:
	if _cam_s <= 0.0:
		return
	_cam_t = minf(_cam_t + delta, _cam_s)
	var k := _cam_t / _cam_s
	k = k * k * (3.0 - 2.0 * k)
	_draw_camera({"yaw": lerpf(_cam_from.yaw, _cam_to.yaw, k), "pitch": lerpf(_cam_from.pitch, _cam_to.pitch, k),
		"dist": lerpf(_cam_from.dist, _cam_to.dist, k), "target": (_cam_from.target as Vector3).lerp(_cam_to.target, k)})


func _draw_camera(pose: Dictionary) -> void:
	var rig := home.view.rig
	rig.cur_yaw = deg_to_rad(float(pose.yaw))
	rig.cur_pitch = deg_to_rad(float(pose.pitch))
	rig.cur_distance = float(pose.dist)
	rig.cur_target = pose.target
	rig._apply()


func _beat(after: float, what: Callable) -> void:
	_beats.append([after, what])


# --- night -------------------------------------------------------------------------------------

func _night(to: float, seconds: float) -> void:
	_night_from = night
	_night_to = to
	_night_t = 0.0
	_night_s = seconds


func _step_night(delta: float) -> void:
	if _night_s <= 0.0:
		return
	_night_t = minf(_night_t + delta, _night_s)
	var k := _night_t / _night_s
	_set_night(lerpf(_night_from, _night_to, k * k * (3.0 - 2.0 * k)))
	if _night_t >= _night_s:
		_night_s = 0.0


## The night level: the shaders' global tint and the sea (the clear colour).
func _set_night(level: float) -> void:
	night = level
	var sea_color: Color
	if level <= 1.0:
		tint = Vector3.ONE.lerp(NIGHT_TINT, level)
		sea_color = _day_sea.lerp(NIGHT_SEA, level)
	else:
		tint = NIGHT_TINT.lerp(DARK_TINT, level - 1.0)
		sea_color = NIGHT_SEA.lerp(DARK_SEA, level - 1.0)
	if _can_tint:
		RenderingServer.global_shader_parameter_set(&"story_tint", tint)
	if home != null and home.env != null and _day_sea != Color.BLACK:
		home.env.environment.background_color = sea_color


# --- the star, its pieces, the sparkles ----------------------------------------------------------

func _show_star() -> void:
	_star = StarArt.make(false, STAR_SIZE)
	_star.position = STAR_AT
	_star.scale = Vector3.ONE * 0.01
	home.world.add_child(_star)
	_star_motion = {"pop": 0.0}
	SoundBoard.play(&"glint")


func _shake_star(seconds: float) -> void:
	if _star != null:
		_star_motion = {"shake": 0.0, "s": seconds}


## The star cracks: it is gone, one piece per spot arcs down to the spot (staggered).
func _break_star() -> void:
	var from := STAR_AT
	if _star != null:
		from = _star.position
		_star.queue_free()
		_star = null
	_star_motion = {}
	SoundBoard.play(&"star_break")
	var i := 0
	for spot in home._spots:
		var to: Vector3 = spot.at + Vector3.UP * (float(spot.top) + 0.6)
		var ctrl := Vector3(to.x * 1.3, from.y + 3.0, to.z * 1.3).lerp(from, 0.3)
		_add_piece(from, ctrl, to, 1.7 + 0.08 * i, -0.06 * i)
		i += 1


func _add_piece(from: Vector3, ctrl: Vector3, to: Vector3, seconds: float, start: float) -> void:
	var node := StarArt.make(true, PIECE_SIZE)
	node.position = from
	node.visible = start >= 0.0
	home.world.add_child(node)
	_pieces.append({"node": node, "from": from, "ctrl": ctrl, "to": to, "t": start, "s": seconds, "spin": 3.0 + randf() * 2.0,
		"landed": false})


func _step_pieces(delta: float) -> void:
	for p in _pieces:
		var node: Node3D = p.node
		p.t += delta
		node.visible = p.t >= 0.0 and not p.get("gone", false)
		var k := clampf(p.t / p.s, 0.0, 1.0)
		var eased: float = k * k if p.get("fall", true) else k * k * (3.0 - 2.0 * k)
		var a: Vector3 = (p.from as Vector3).lerp(p.ctrl, eased)
		var b: Vector3 = (p.ctrl as Vector3).lerp(p.to, eased)
		node.position = a.lerp(b, eased)
		node.rotation.y += delta * float(p.spin)
		if k >= 1.0:
			if not p.landed:
				p.landed = true
				SoundBoard.play(&"glint")
			# Glint where it landed: a gentle pulse.
			var pulse := 1.0 + 0.18 * sin(_clock * 6.0 + float(p.spin))
			node.scale = Vector3.ONE * pulse * float(p.get("fade", 1.0))


## The prologue's pieces shrink away as the day comes back (the map is clean after the story).
func _fade_pieces() -> void:
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		for p in _pieces:
			p["fade"] = v, 1.0, 0.0, 1.0)


func _clear_pieces() -> void:
	for p in _pieces:
		(p.node as Node3D).queue_free()
	_pieces.clear()


## The finale: the 11 pieces appear round the lookout and spiral into the whole star.
func _gather_pieces() -> void:
	var at := _lookout_point()
	var n := Story.spots().size()
	for i in n:
		var a := TAU * i / n
		var from := at + Vector3(cos(a) * 2.6, sin(a * 2.0) * 0.4, sin(a) * 2.6)
		var ctrl := at + Vector3(cos(a + 1.2) * 1.6, 0.6, sin(a + 1.2) * 1.6)
		_add_piece(from, ctrl, at, 1.8, -0.04 * i)
		_pieces[-1]["fall"] = false
	SoundBoard.play(&"piece_fly")
	_beat(2.3, func() -> void:
		_clear_pieces()
		_star = StarArt.make(false, 1.0)
		_star.position = at
		_star.scale = Vector3.ONE * 0.01
		home.world.add_child(_star)
		_star_motion = {"pop": 0.0}
		SoundBoard.play(&"glint"))


func _move_star(to: Vector3, seconds: float) -> void:
	if _star != null:
		_star_motion = {"from": _star.position, "to": to, "t": 0.0, "s": seconds, "from_scale": _star.scale.x,
			"to_scale": SKY_STAR_SIZE if to == SKY_STAR_AT else _star.scale.x}


func _step_star(delta: float) -> void:
	if _star == null:
		return
	_star.rotation.y += delta * 1.2
	if _lift and home.cat != null:
		var top := home.cat.position + Vector3.UP * 2.0
		_star.position = _star.position.lerp(top, 1.0 - exp(-8.0 * delta))
	if _star_motion.has("pop"):
		_star_motion.pop += delta
		var k := clampf(float(_star_motion.pop) / 0.5, 0.0, 1.0)
		_star.scale = Vector3.ONE * maxf(0.01, 1.0 + 0.3 * sin(PI * k) - (1.0 - k) * (1.0 - k))
		if k >= 1.0:
			_star.scale = Vector3.ONE
			_star_motion = {}
	elif _star_motion.has("shake"):
		_star_motion.shake += delta
		_star.rotation.z = sin(float(_star_motion.shake) * 60.0) * 0.12
	elif _star_motion.has("to"):
		_star_motion.t += delta
		var k := clampf(float(_star_motion.t) / float(_star_motion.s), 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		_star.position = (_star_motion.from as Vector3).lerp(_star_motion.to, e)
		_star.scale = Vector3.ONE * lerpf(_star_motion.from_scale, _star_motion.to_scale, e)
		if k >= 1.0:
			_star_motion = {}


## The star in the map's sky after the finale (it stays: small, bright, turning slowly).
func _place_sky_star() -> void:
	if sky_star == null:
		sky_star = StarArt.make(false, 1.0)
		sky_star.name = "SkyStar"
		home.world.add_child(sky_star)
	sky_star.position = SKY_STAR_AT
	sky_star.scale = Vector3.ONE * SKY_STAR_SIZE


## The sea sparkles again: little stars twinkle on the water round the island for a few seconds.
func _sparkle_sea() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(15.0, 34.0)
		var node := StarArt.make(false, 0.32)
		node.position = Vector3(cos(a) * r, MapIsland.SEA_Y + 0.35, sin(a) * r)
		node.scale = Vector3.ONE * 0.01
		home.world.add_child(node)
		_sparkles.append([node, rng.randf() * TAU, 0.0])


func _step_sparkles(delta: float) -> void:
	for s in _sparkles:
		s[2] += delta
		var life := clampf((5.0 - float(s[2])) / 1.0, 0.0, 1.0)
		var twinkle := 0.5 + 0.5 * sin(float(s[2]) * 7.0 + float(s[1]))
		(s[0] as Node3D).scale = Vector3.ONE * maxf(0.01, twinkle * life * minf(1.0, float(s[2]) * 3.0))


# --- the cat and the boats -----------------------------------------------------------------------

func _hop_cat(from: Vector3, to: Vector3, seconds: float, height: float) -> void:
	_cat_hop = {"from": from, "to": to, "t": 0.0, "s": seconds, "h": height}
	if from.distance_to(to) > 0.05:
		home.cat.rotation.y = atan2(to.x - from.x, to.z - from.z)


func _step_cat(delta: float) -> void:
	if _cat_hop.is_empty():
		return
	_cat_hop.t += delta
	var k := clampf(float(_cat_hop.t) / float(_cat_hop.s), 0.0, 1.0)
	var p := (_cat_hop.from as Vector3).lerp(_cat_hop.to, k)
	p.y = lerpf((_cat_hop.from as Vector3).y, (_cat_hop.to as Vector3).y, k) + float(_cat_hop.h) * sin(PI * k)
	home.cat.position = p
	if k >= 1.0:
		home.cat.rotation.y = 0.0
		_cat_hop = {}


func _step_boats(delta: float) -> void:
	if _boats_wander:
		for i in sea.boats.size():
			var t := _clock * 0.45 + i * 2.1
			var home_at: Vector3 = sea.boat_homes[i]
			sea.boats[i].position = home_at + Vector3(sin(t) * 3.0, 0.0, cos(t * 0.8) * 3.0)
			sea.boats[i].rotation.y = t + PI * 0.5
	elif _boats_sail >= 0.0:
		_boats_sail += delta
		for i in sea.boats.size():
			var boat := sea.boats[i]
			boat.position += boat.global_basis.z * delta * 2.5


## A point on an arc from `from` to `to` at k (0..1), `height` m above the straight line at its middle.
static func _arc(from: Vector3, to: Vector3, height: float, k: float) -> Vector3:
	return from.lerp(to, k) + Vector3.UP * height * 4.0 * k * (1.0 - k)
