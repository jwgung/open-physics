## The hand guide (2026-10-30 user request: young children need a guide to the controls): GuideCoach's timing
## through its own interface, HandGuide's gestures, and on every lab's screen: after the question the
## hand shows that lab's gesture on its own object (a pull, a hold or a drag), a touch stops it, it
## comes once per lab and again after a quiet while during a stage, and it is a picture only (the lab's
## bodies and status do not move). On the map the hand taps the next spot after Puppy's first riddle.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const HOME_SCREEN := "res://scripts/app/island_home_screen.gd"
const TABLET := Vector2(1152, 720)
## The gesture each lab's guide shows (its slingshot, its hold, else a drag).
const GESTURES := {"projectile": "pull", "collision": "pull", "orbit": "pull", "friction": "hold",
	"rotation": "hold", "pulley": "hold", "free-fall": "drag", "spring": "drag", "constraints": "drag",
	"buoyancy": "drag", "incline-friction": "drag"}


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	var store := ProgressStore.path
	ProgressStore.path = ProgressStore.TEST_PATH   # the checks delete the store: never the child's
	check_coach()
	check_gestures()
	var root_size := tree.root.size
	tree.root.size = Vector2i(TABLET)   # the real press in check_lab goes through the window
	for id in GESTURES:
		await check_lab(id)
	tree.root.size = root_size
	await check_once_and_idle()
	await check_slingshot_after_run()
	await check_first_stays_due()
	await check_map_tap()
	await check_map_walk()
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.path = store


# --- GuideCoach ------------------------------------------------------------------------------------

func check_coach() -> void:
	var coach := GuideCoach.new()
	var seen := []
	for i in 5:
		seen.append(coach.step(0.1, true, false, true))
	seen.append(coach.step(0.15, true, false, true))
	expect.call(seen.slice(0, 5).all(func(s: String) -> bool: return s == "") and seen[5] == "first" and coach.seen,
		"hand guide timing: the first guide after FIRST_DELAY_S of quiet", str(seen))
	var noisy := GuideCoach.new()
	var none := []
	for i in 20:
		none.append(noisy.step(0.1, i % 3 != 0, false, true))
	expect.call(none.all(func(s: String) -> bool: return s == ""), "hand guide timing: anything else on screen restarts the wait", str(none))
	var knew := GuideCoach.new()
	knew.step(0.1, true, true, true, true)
	var after := []
	for i in 10:
		after.append(knew.step(0.1, true, false, true))
	var stray := GuideCoach.new()
	stray.step(0.1, true, true, true)   # a tap on the view, not on the object
	var later := []
	for i in 10:
		later.append(stray.step(0.1, true, false, true))
	expect.call(knew.seen and after.all(func(s: String) -> bool: return s == "") and "first" in later,
		"hand guide timing: a child who used the object first gets no first guide; a stray tap only restarts the wait", str(later))
	var idle := GuideCoach.new(true)
	var at := -1.0
	var t := 0.0
	for i in 200:
		t += 0.05
		if idle.step(0.05, true, false, true) == "idle" and at < 0.0:
			at = t
	var closed := GuideCoach.new(true)
	var shut := []
	for i in 200:
		shut.append(closed.step(0.05, true, false, false))
	expect.call(absf(at - GuideCoach.IDLE_S) < 0.06 and shut.all(func(s: String) -> bool: return s == ""),
		"hand guide timing: again after IDLE_S quiet seconds during a stage, never without a stage", "at %.2f" % at)


# --- HandGuide -------------------------------------------------------------------------------------

func check_gestures() -> void:
	var hand := HandGuide.new()
	var from := Vector2(100.0, 200.0)
	var to := Vector2(300.0, 200.0)
	hand.play("drag", func() -> Vector2: return from, func() -> Vector2: return to, 1)
	var cycle := hand.cycle_s()
	var tips := []
	var t := 0.0
	while hand.playing() and t < 10.0:
		hand.step(0.05)
		t += 0.05
		tips.append(hand.tip)
	var reached := tips.any(func(p: Vector2) -> bool: return p.distance_to(to) < 1.0)
	var started := tips.slice(0, 6).all(func(p: Vector2) -> bool: return p.distance_to(from) < 12.0)
	expect.call(started and reached and not hand.playing() and absf(t - cycle) < 0.11,
		"hand guide: a drag presses on the object, carries it to the goal, and one cycle ends the play", "t %.2f" % t)
	hand.play("hold", func() -> Vector2: return from)
	var still := true
	for i in 40:
		hand.step(0.05)
		still = still and hand.tip.distance_to(from) < 12.0
	hand.play("swipe", func() -> Vector2: return from)
	var refused := hand.kind == "hold"
	hand.play("drag", func() -> Vector2: return from)
	refused = refused and hand.kind == "hold"
	expect.call(still and refused and hand.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"hand guide: a hold stays on the object; an unknown gesture or a drag without a goal is ignored; it takes no touch", "")
	hand.stop()
	hand.free()


# --- the lab screens --------------------------------------------------------------------------------

func _open(id: String) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


## Waits `s` seconds of the screen's own clock (process delta): headless frames do not come at 60 Hz.
func _seconds(s: float) -> void:
	var left := s
	while left > 0.0:
		await tree.process_frame
		left -= tree.root.get_process_delta_time()


func _bodies(lab: Experiment) -> Array:
	return lab.find_children("*", "PhysicsBody3D", true, false).map(func(b: Node3D) -> Vector3: return b.global_position)


## The first visit: no hand while Dugi asks; after the answer the lab's gesture on its object, the
## lab untouched by it; a touch stops it; the visit is kept.
func check_lab(id: String) -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _open(id)
	var guide: HandGuide = screen.hand_guide
	var problems := []
	if guide == null:
		expect.call(false, "hand guide (%s): the screen has a hand guide" % id, "")
		await _close(screen)
		return
	await _frames(60)
	if guide.playing() or guide.plays > 0:
		problems.append("shown while Dugi asks")
	# The child answers with a picture button; Dugi's bridge box opens and waits for a tap that a child
	# who cannot read may never make: the hand comes anyway.
	screen._predict_pick_choice(str(MissionRound.predict(screen.definition.raw).get("answer", "")))
	var lab: Experiment = screen.experiment
	var bodies := _bodies(lab)
	var status := lab.status()
	var controls: Array = screen.definition.controls().map(func(c: Dictionary) -> Variant: return lab.control_value(c.id))
	var stamps: int = screen.mission_round.stamps
	await _seconds(GuideCoach.FIRST_DELAY_S + 0.3)
	if not (screen.dialogue != null and screen.dialogue.active):
		problems.append("Dugi's bridge box is not open with the hand (the case under test)")
	var order: Array = [guide.get_index(), screen.dialogue.get_index() if screen.dialogue != null else -1, screen._tip.get_index()]
	if not (order[0] > order[1] and order[1] > order[2]):
		problems.append("overlay order hand %d / box %d / tip %d: the hand over the box, the box over the tip" % order)
	if screen._mission_pill != null and guide.get_index() > screen._mission_pill.get_index():
		problems.append("the hand draws over the mission strip")
	var spec: Dictionary = screen.manipulator.guide()
	if not guide.playing():
		problems.append("no guide after the question")
	elif guide.kind != GESTURES[id] or spec.get("kind") != GESTURES[id]:
		problems.append("gesture %s, want %s" % [guide.kind, GESTURES[id]])
	var pick: Vector2 = screen.view_point(spec.get("from", Vector3.ZERO))
	var view_rect := Rect2(Vector2.ZERO, screen.view.size)
	if not view_rect.has_point(pick):
		problems.append("the object's pick point is off the view: %s" % str(pick))
	var near := true
	var tip_seen := []
	for i in 30:
		await tree.process_frame
		tip_seen.append(guide.tip)
	near = tip_seen.slice(0, 10).any(func(p: Vector2) -> bool: return p.distance_to(pick) < 14.0)
	if not near:
		problems.append("the hand does not start on the object (%s vs %s)" % [str(tip_seen[0]), str(pick)])
	if not ProgressStore.mark(ProgressStore.GUIDES, id):
		problems.append("the first guide is not kept")
	var now: Array = screen.definition.controls().map(func(c: Dictionary) -> Variant: return lab.control_value(c.id))
	if _bodies(lab) != bodies or lab.status() != status or screen.manipulator.mode != "" or now != controls \
			or screen.mission_round.stamps != stamps:
		problems.append("the lab moved under the guide")
	# A real press on the object (through the view, under the hand): the object is taken, the hand goes.
	var press := InputEventScreenTouch.new()
	press.position = screen.view.global_position + screen.view_point(screen.manipulator.guide_point(str(spec.id)))
	press.pressed = true
	tree.root.push_input(press)   # through the GUI: nothing over the object may take it
	await _frames(2)
	if guide.playing() or screen.manipulator.mode == "":
		problems.append("a press under the hand does not take the object and stop the hand (mode '%s')" % screen.manipulator.mode)
	var lift := InputEventScreenTouch.new()
	lift.position = press.position
	lift.canceled = true
	tree.root.push_input(lift)
	await tree.process_frame
	screen.manipulator.cancel()   # put it back before the screen goes
	expect.call(problems.is_empty(), "hand guide (%s): after the question a %s on the lab's object, a picture only, a touch stops it, kept once" % [id, GESTURES[id]],
		"; ".join(problems))
	await _close(screen)


## A second visit has no first guide; a quiet stage brings it back after IDLE_S; a lab without missions
## (the development scene) shows only the first one; a measurement shows none.
func check_once_and_idle() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.GUIDES, "spring", true)
	var screen := await _open("spring")
	screen._predict_pick_choice(str(MissionRound.predict(screen.definition.raw).get("answer", "")))
	var guide: HandGuide = screen.hand_guide
	await _seconds(GuideCoach.FIRST_DELAY_S + 0.3)
	var no_first := not guide.playing() and guide.plays == 0
	await _seconds(GuideCoach.IDLE_S + 0.2)
	var again := guide.playing() and guide.kind == "drag"
	await _close(screen)
	var dev := await _open("manipulation-dev")
	await _seconds(GuideCoach.FIRST_DELAY_S + 0.3)
	var dev_first: bool = dev.hand_guide != null and dev.hand_guide.plays == 1
	await _seconds(GuideCoach.IDLE_S + 4.0)
	var dev_once: bool = dev.hand_guide != null and dev.hand_guide.plays == 1
	await _close(dev)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var measured: Control = load(EXPERIMENT_SCREEN).new()
	measured.measurement = true
	measured.setup(ExperimentRegistry.find("spring"))
	host.add_child(measured)
	await _frames(4)
	var none: bool = measured.hand_guide == null
	await _close(measured)
	expect.call(no_first and again and dev_first and dev_once and none,
		"hand guide: once per lab, again after %d quiet seconds in a stage, a lab without missions only once, none in a measurement" % int(GuideCoach.IDLE_S),
		"no first %s again %s dev %s/%s measurement none %s" % [no_first, again, dev_first, dev_once, none])


## After a throw the slingshot's guide presses the launch point (a press there readies the next shot),
## not the landed ball; the pull ends on the slingshot's surface (a world point).
func check_slingshot_after_run() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _open("projectile")
	screen.mission_round.end_question()
	var lab: Experiment = screen.experiment
	var m: Manipulator = screen.manipulator
	var ready_at: Vector3 = m.guide_point("ball")
	var ready_ok := ready_at.is_equal_approx(lab.manipulation_pick_point("ball"))
	lab.change_from_input(lab.release)
	for i in 240:
		await tree.physics_frame
	var spec: Dictionary = m.guide()
	var launch: Vector3 = m.slingshot_launch.call()
	var at_launch: bool = lab.status() != "ready" and (spec.from as Vector3).is_equal_approx(launch) \
		and not lab.manipulation_pick_point("ball").is_equal_approx(launch)
	var pulled: bool = spec.get("to") is Vector3 and (spec.to as Vector3).distance_to(launch) > 0.1
	var status := lab.status()
	await _close(screen)
	expect.call(ready_ok and at_launch and pulled,
		"hand guide (slingshot): before a throw the hand is on the ball; after it on the launch point; the pull ends on the slingshot's surface",
		"ready %s launch %s pulled %s (status %s)" % [ready_ok, at_launch, pulled, status])


## A first guide with nothing to show (no pull end yet) is not used up: nothing is kept, and it comes
## as soon as the gesture can be shown.
func check_first_stays_due() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var screen := await _open("projectile")
	var m: Manipulator = screen.manipulator
	var surface := m.slingshot_surface
	m.slingshot_surface = null
	screen.mission_round.end_question()
	await _seconds(GuideCoach.FIRST_DELAY_S + 0.5)
	var waited: bool = screen.hand_guide.plays == 0 and not screen._coach.seen and not ProgressStore.mark(ProgressStore.GUIDES, "projectile")
	m.slingshot_surface = surface
	await _frames(3)
	var came: bool = screen.hand_guide.playing() and screen.hand_guide.kind == "pull" and ProgressStore.mark(ProgressStore.GUIDES, "projectile")
	screen.hand_guide.stop()
	await _close(screen)
	expect.call(waited and came, "hand guide: a first guide that cannot be shown stays due (nothing kept) and comes once it can",
		"waited %s came %s" % [waited, came])


# --- the map ---------------------------------------------------------------------------------------

## The map: after Puppy's first riddle closes, the hand taps the next spot (once on this device), and
## again when the hint starts to glint (once per riddle told).
func check_map_tap() -> void:
	var was := Story.enabled
	Story.enabled = true
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var home: IslandHomeScreen = load(HOME_SCREEN).new()
	host.add_child(home)
	await _frames(4)
	var story: StoryDirector = home.story
	story.advance(0.6)
	var told: bool = story.riddle != null and story.riddle.active and story.map_guide == null
	story.riddle.close(true)
	story.advance(0.05)
	var guide: HandGuide = story.map_guide
	var tapping: bool = guide != null and guide.playing() and guide.kind == "tap"
	var spot: Dictionary = {}
	for s in home._spots:
		if s.id == story.next_id:
			spot = s
	var on_spot := false
	if guide != null and not spot.is_empty():
		guide.step(0.3)
		on_spot = guide.tip.distance_to(home._world_to_screen(spot.at + Vector3.UP * float(spot.top))) < 14.0
	var kept := ProgressStore.mark(ProgressStore.GUIDES, "map")
	story.say_riddle()
	story.advance(0.05)
	var stopped: bool = guide != null and not guide.playing()
	# The riddle stays open (no tap): the hint's tap still plays over the open box.
	story.advance(StoryDirector.HINT_DELAY_S + 0.1)
	var hint_tap: bool = guide != null and guide.playing() and story.hinting() and story.riddle.active
	var under_riddle: bool = guide != null and guide.get_index() < story.riddle.get_index()   # his words stay readable
	story.riddle.close(true)
	story.advance(3.0)
	story.advance(0.05)
	var once: bool = guide != null and guide.plays == 2
	Story.enabled = was
	host.queue_free()
	await _frames(3)
	expect.call(told and tapping and on_spot and kept and stopped and hint_tap and under_riddle and once,
		"hand guide (map): after Puppy's first riddle the hand taps the next spot, once on this device; again with the hint, under his box",
		"told %s tapping %s on %s kept %s stopped %s once %s hint %s under %s" % [told, tapping, on_spot, kept, stopped, once, hint_tap, under_riddle])


## The first riddle closes because the child already walks to a spot (hush): no hand, and the map's
## once is not used up.
func check_map_walk() -> void:
	var was := Story.enabled
	Story.enabled = true
	DirAccess.remove_absolute(ProgressStore.path)
	ProgressStore.set_mark(ProgressStore.STORY, "prologue", true)
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var home: IslandHomeScreen = load(HOME_SCREEN).new()
	host.add_child(home)
	await _frames(4)
	var story: StoryDirector = home.story
	story.advance(0.6)
	home._walking = true
	story.hush()
	story.advance(0.05)
	var none: bool = story.map_guide == null or not story.map_guide.playing()
	var kept_free := not ProgressStore.mark(ProgressStore.GUIDES, "map")
	home._walking = false
	Story.enabled = was
	host.queue_free()
	await _frames(3)
	expect.call(none and kept_free, "hand guide (map): a riddle closed by walking to a spot shows no hand and keeps the once",
		"none %s kept free %s" % [none, kept_free])
