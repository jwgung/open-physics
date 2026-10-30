## 2026-10-29 user requests (round 3), on the real screens and the content:
## 1. no action buttons: a game lab has only "다시"; every run starts from the hand (free fall: a ball
##    let go after its drag drops both balls, a new drag starts a fresh run; the slide: the box let go
##    on the slide slides; the drum, the spring ball and the bob let go swing / float); the --auto-drag
##    demo and --auto-release still run.
## 2. Puppy's result line per stage (win / miss): 66 short lines without science words; after an
##    attempt the bubble shows near Puppy, clear of the overlays, for ResultBubble.SHOW_S; one line per
##    attempt; a control change drops it.
## 3. the bridge from the answer to the first mission (Dugi's line, the strip's pulse), the reason only
##    after the first result, and every lab's question answered by its first stage (the formula).
## 4. the orbit shown 2.5x faster: 2, 3, 2, 3 ... model steps per frame, the same model values as at
##    1x after the same steps, the lap stamp, the note's line.
## 5. the play yard spread out: its four spots apart, inside the fence, the walk clear of the other
##    stages, the names clear of the other landmarks (phone, tablet).
## 6. the pulley's rope round the wheels' rims (n = 1, 2, 4), following the load.
extends RefCounted

var tree: SceneTree
var expect: Callable
const UI_THEME := "res://scripts/app/ui_theme.gd"
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const HOME_SCREEN := "res://scripts/app/island_home_screen.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)
const OLD_BUTTONS := ["공 놓기", "출발", "발사", "놓기", "상자 놓기", "동그랗게 돌게"]
const LINE_MAX := 24             # characters of a result line (one short line)
const LANDMARK_COVER := 0.15     # the share of another yard landmark a spot name may cover (its stage's near edge)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	await check_no_action_buttons()
	await check_release_on_lift()
	await check_demo_and_auto_release()
	check_result_lines()
	await check_result_bubbles()
	await check_bridge_and_reason()
	check_stage1_answers()
	await check_orbit_pace()
	await check_yard_spread()
	await check_pulley_rope()
	DirAccess.remove_absolute(ProgressStore.path)


# --- 1. no action buttons -------------------------------------------------------------------------

func check_no_action_buttons() -> void:
	var problems := []
	for definition in ExperimentRegistry.load_all():
		if MissionRound.missions(definition).is_empty():
			continue
		var screen := await _open(definition, TABLET)
		var row: Array = screen._action_row.get_children()
		if row.size() != 1 or (row[0] as Button).text != ExperimentScreen.RESET_SHORT or screen._action_buttons.keys() != ["reset"]:
			problems.append("%s: the row is %s" % [definition.id, str(row.map(func(b: Button) -> String: return b.text))])
		for button: Button in screen.find_children("*", "Button", true, false):
			if button.text in OLD_BUTTONS:
				problems.append("%s: a %s button" % [definition.id, button.text])
		if not screen._extra_actions.is_empty():
			problems.append("%s: actions in 자세히" % definition.id)
		await _free(screen)
	expect.call(problems.is_empty(), "no action buttons: every game lab shows only 다시 (no 공 놓기 / 출발 / 발사 / 놓기 / 상자 놓기 / 동그랗게 돌게, also not in 자세히)", "; ".join(problems))


## The real touch path: press on the object, drag, lift.
func check_release_on_lift() -> void:
	var problems := []
	# Free fall: the red ball up to 8 m and let go: both balls drop together from their own heights.
	var screen := await _open(ExperimentRegistry.find("free-fall"), TABLET)
	screen.mission_round.end_question()
	var lab: Experiment = screen.experiment
	var r: float = lab.BALL_RADIUS
	await _drag_to(screen, lab.balls.red.global_position, Vector3(lab.starts.red.x, 8.0 + r, lab.starts.red.z))
	for i in 3:
		await tree.physics_frame
	if not (lab.released and lab.status() == "falling" and is_equal_approx(lab.starts.red.y, 8.0) and is_equal_approx(lab.starts.yellow.y, 3.0)):
		problems.append("free fall: let go at 8 m: released %s, %s, red %.1f, yellow %.1f" % [lab.released, lab.status(), lab.starts.red.y, lab.starts.yellow.y])
	for i in 120:
		await tree.physics_frame
	var landed: bool = lab.status() == "landed"
	# A new drag after the drop: the press starts a fresh run (the balls wait), the lift drops both again.
	_touch(screen, _at(screen, lab.balls.yellow.global_position), true)
	await tree.physics_frame
	var fresh: bool = lab.status() == "ready" and not lab.released
	_touch(screen, _at(screen, lab.balls.yellow.global_position), false)   # a tap: let go at its start, both drop
	await tree.physics_frame
	var tapped: bool = lab.released and is_equal_approx(lab.starts.yellow.y, 3.0)
	for i in 120:
		await tree.physics_frame
	await _drop_drag(screen, "yellow", 8.0)
	await tree.physics_frame
	var together: bool = lab.released and is_equal_approx(lab.starts.yellow.y, 8.0) and is_equal_approx(lab.starts.red.y, 8.0)
	if not (landed and fresh and tapped and together):
		problems.append("free fall: landed %s, a new press waits %s, a tap drops both %s, the yellow lifted to 8 m drops both %s" % [landed, fresh, tapped, together])
	await _free(screen)
	# The slide: the box dragged up the slide and let go slides from there.
	screen = await _open(ExperimentRegistry.find("incline-friction"), TABLET)
	screen.mission_round.end_question()
	lab = screen.experiment
	screen._set_control("material", "steel")
	var box_to: Vector3 = lab._pivot.global_transform * Vector3(6.0 - lab.INCLINE_LENGTH * 0.5, lab.BOX * 0.5, 0.0)
	await _drag_to(screen, lab.box.global_position, box_to)
	for i in 20:
		await tree.physics_frame
	if not (lab.released and absf(lab.run_length() - 6.0) < 1e-6 and lab.status() in ["sliding", "left"]):
		problems.append("slide: let go at 6 m: released %s, run %.2f, %s" % [lab.released, lab.run_length(), lab.status()])
	await _free(screen)
	# The drum, the spring ball, the bob: let go = released (already so before; kept).
	screen = await _open(ExperimentRegistry.find("buoyancy"), TABLET)
	screen.mission_round.end_question()
	lab = screen.experiment
	await _drag_to(screen, lab.drum.global_position, lab.drum.global_position + Vector3(0.0, -0.6, 0.0))
	await tree.physics_frame
	if not lab.released:
		problems.append("drum: not released on the lift")
	await _free(screen)
	screen = await _open(ExperimentRegistry.find("spring"), TABLET)
	screen.mission_round.end_question()
	lab = screen.experiment
	await _drag_to(screen, lab.manipulation_body("ball").global_position, Vector3(lab.ANCHOR_X + lab.REST_LENGTH + 0.6, lab.ROD_Y, 0.0))
	await tree.physics_frame
	if not (lab.released and absf(lab.pull - 0.6) < 1e-6):
		problems.append("spring: released %s at %.2f" % [lab.released, lab.pull])
	await _free(screen)
	screen = await _open(ExperimentRegistry.find("constraints"), TABLET)
	screen.mission_round.end_question()
	lab = screen.experiment
	var bob: Vector3 = lab.manipulation_body("rope").global_position
	var a := deg_to_rad(30.0)
	await _drag_to(screen, bob, lab.anchor(0) + Vector3(sin(a), -cos(a), 0.0) * lab.length)
	await tree.physics_frame
	if not lab.released:
		problems.append("bob: not released on the lift")
	await _free(screen)
	expect.call(problems.is_empty(), "release on the lift: free fall drops both balls (a new drag starts over), the slide's box slides, the drum, the spring ball and the bob go", "; ".join(problems))


## --auto-drag (bench_device.sh) on the labs that lost their action: the demo's let-go is the run (no
## follow-up action), and --auto-release still re-releases through the lab's own action.
func check_demo_and_auto_release() -> void:
	var problems := []
	for id in ["free-fall", "incline-friction"]:
		var screen := await _open(ExperimentRegistry.find(id), TABLET)
		screen.mission_round.end_question()
		var lab: Experiment = screen.experiment
		var m: Manipulator = screen.manipulator
		if m.demo_action != "":
			problems.append("%s: demo action %s" % [id, m.demo_action])
		m.start_demo(100.0)
		m._demo_left = 0.0
		var released := false
		for i in 150:
			await tree.process_frame
			released = released or lab.released
		if not released or screen._demo_release_left >= 0.0:
			problems.append("%s: the demo's let-go released %s, a follow-up %.2f" % [id, released, screen._demo_release_left])
		screen.experiment_action("reset")
		screen._run_measured_action("release")
		await tree.physics_frame
		if not lab.released:
			problems.append("%s: --auto-release does not release" % id)
		await _free(screen)
	expect.call(problems.is_empty(), "measurements: the --auto-drag demo's let-go is the run (free fall, slide: no 0.4 s follow-up action), --auto-release still releases", "; ".join(problems))


# --- 2. Puppy's result lines ------------------------------------------------------------------------

func check_result_lines() -> void:
	var problems := []
	var count := 0
	for definition in ExperimentRegistry.load_all():
		var stages: Array = MissionRound.missions(definition).get("stages", [])
		if stages.is_empty():
			continue
		if MissionRound.missions(definition).get("miss_on", []).is_empty():
			problems.append("%s: no miss_on" % definition.id)
		for i in stages.size():
			for won in [true, false]:
				var line := MissionRound.result_line(definition, i, won)
				var text := str(line[0])
				count += 1 if text != "" else 0
				if text == "" or text.length() > LINE_MAX or text == str(stages[i].text) or not str(line[1]) in Story.FACES:
					problems.append("%s %d %s: '%s' (%d)" % [definition.id, i + 1, "win" if won else "miss", text, text.length()])
				for word in Story.SCIENCE_WORDS:
					if text.contains(word):
						problems.append("%s %d: '%s' has %s" % [definition.id, i + 1, text, word])
				if _kid_symbols(text):
					problems.append("%s %d: '%s' has a symbol or a number" % [definition.id, i + 1, text])
	expect.call(problems.is_empty() and count == 66, "result lines: 11 labs x 3 stages have a win and a miss line (66), short (<= %d), no science words or symbols, a known face" % LINE_MAX, "%d lines; %s" % [count, "; ".join(problems)])


func _kid_symbols(text: String) -> bool:
	return RegEx.create_from_string("[A-Za-z0-9√θ₀²³μ=°]").search(text) != null


func check_result_bubbles() -> void:
	var problems := []
	# Free fall: different heights miss stage 1 (the buttons apart), the same height wins it.
	var screen := await _open(ExperimentRegistry.find("free-fall"), TABLET)
	screen.mission_round.end_question()
	var lab: Experiment = screen.experiment
	var r: float = lab.BALL_RADIUS
	await _drag_to(screen, lab.balls.red.global_position, Vector3(lab.starts.red.x, 6.0 + r, lab.starts.red.z))
	var bubble: ResultBubble = await _wait_bubble(screen, 300)
	var stage0: Dictionary = MissionRound.missions(lab.definition.raw).stages[0]
	if bubble == null or bubble.text != str(stage0.miss) or bubble.won or screen.result_count.miss != 1:
		problems.append("free fall: the miss line after the first drop (%s)" % (bubble.text if bubble != null else "none"))
	else:
		problems.append_array(_bubble_place(screen, bubble, "free fall miss"))
	# It goes after SHOW_S; the same attempt never gets a second line.
	for i in roundi(ResultBubble.SHOW_S * 60.0) + 10:
		await tree.process_frame
	if screen.result_bubble() != null or screen.result_count.miss != 1:
		problems.append("free fall: the bubble stays or a second line came (%s)" % str(screen.result_count))
	await _drop_drag(screen, "yellow", 6.0)
	bubble = await _wait_bubble(screen, 300, true)
	if bubble == null or bubble.text != str(stage0.win) or not bubble.won or screen.mission_round.stamps != 1:
		problems.append("free fall: the win line with the stamp (%s, %d stamps)" % [bubble.text if bubble != null else "none", screen.mission_round.stamps])
	else:
		problems.append_array(_bubble_place(screen, bubble, "free fall win"))
	for i in 60:
		await tree.process_frame
	if screen.result_count.miss != 1 or screen.result_count.win != 1:
		problems.append("free fall: after the win %s" % str(screen.result_count))
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	# The spring: let go short of the near bell -> the miss after the half swing (its number), then the win.
	screen = await _open(ExperimentRegistry.find("spring"), TABLET)
	screen.mission_round.end_question()
	lab = screen.experiment
	var spring_stage: Dictionary = MissionRound.missions(lab.definition.raw).stages[0]
	await _drag_to(screen, lab.manipulation_body("ball").global_position, Vector3(lab.ANCHOR_X + lab.REST_LENGTH + 0.4, lab.ROD_Y, 0.0))
	var early := screen.result_bubble() != null
	bubble = await _wait_bubble(screen, 300)
	if early or bubble == null or bubble.text != str(spring_stage.miss):
		problems.append("spring: the miss after the half swing (early %s, %s)" % [early, bubble.text if bubble != null else "none"])
	await _drag_to(screen, lab.manipulation_body("ball").global_position, Vector3(lab.ANCHOR_X + lab.REST_LENGTH + 0.6, lab.ROD_Y, 0.0))
	bubble = await _wait_bubble(screen, 300, true)
	if bubble == null or bubble.text != str(spring_stage.win):
		problems.append("spring: the win at 0.6 m (%s)" % (bubble.text if bubble != null else "none"))
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	# The push: a short press and lift leaves the box where it is -> "꿈쩍 안 해" (the hold's miss).
	screen = await _open(ExperimentRegistry.find("friction"), TABLET)
	screen.mission_round.end_question()
	lab = screen.experiment
	screen._set_control("mass", "light")
	var at := _at(screen, lab.manipulation_pick_point("box"))
	_touch(screen, at, true)
	for i in 6:
		await tree.physics_frame
	var pressing := screen.result_bubble() == null
	_touch(screen, at, false)
	bubble = await _wait_bubble(screen, 120)
	if not pressing or bubble == null or bubble.text != str(MissionRound.missions(lab.definition.raw).stages[0].miss):
		problems.append("push: a tap's miss (%s)" % (bubble.text if bubble != null else "none"))
	# A control change before the result drops the attempt (no line).
	await _free(screen)
	screen = await _open(ExperimentRegistry.find("free-fall"), TABLET)
	screen.mission_round.end_question()
	lab = screen.experiment
	await _drag_to(screen, lab.balls.red.global_position, Vector3(lab.starts.red.x, 7.0 + r, lab.starts.red.z))
	screen._set_control("gravity", "moon")
	for i in 240:
		await tree.process_frame
	if screen.result_count.miss + screen.result_count.win != 0:
		problems.append("a control change before the result still got a line")
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(), "result lines: Puppy's miss after a missed run (free fall, the spring after its half swing, a short push), the win with its stamp, one per attempt, gone after %.1f s, near Puppy inside the view and clear of the overlays; none after a control change" % ResultBubble.SHOW_S,
		"; ".join(problems))


## Frames until a bubble shows (`fresh`: one that appeared after this call), null when none came.
func _wait_bubble(screen: Control, frames: int, fresh := false) -> ResultBubble:
	var before: ResultBubble = screen.result_bubble()
	for i in frames:
		await tree.process_frame
		var now: ResultBubble = screen.result_bubble()
		if now != null and (not fresh or now != before):
			await tree.process_frame
			return now
	return null


## The bubble is inside the view, clear of the overlays, and its tail points at Puppy.
func _bubble_place(screen: Control, bubble: ResultBubble, what: String) -> Array:
	var out := []
	var rect := bubble.bubble_rect()
	if not Rect2(Vector2.ZERO, screen.view.size).grow(0.5).encloses(rect):
		out.append("%s: outside the view %s" % [what, str(rect)])
	var others: Array = screen.overlay_rects()
	others.append(screen._mission_pill.get_rect())
	for other: Rect2 in others:
		if other.intersects(rect):
			out.append("%s: over an overlay %s" % [what, str(other)])
	var puppy: Rect2 = screen.view_rect_of(screen.cast.puppy.bounds())
	if puppy.grow(6.0).has_point(bubble.anchor) == false:
		out.append("%s: the tail points at %s, Puppy is %s" % [what, str(bubble.anchor), str(puppy)])
	if bubble.mouse_filter != Control.MOUSE_FILTER_IGNORE or bubble.panel.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		out.append("%s: the bubble takes touches" % what)
	return out


# --- 3. the bridge, the reason, stage 1 answers the question ------------------------------------------

func check_bridge_and_reason() -> void:
	var problems := []
	var definition := ExperimentRegistry.find("free-fall")
	var predict := MissionRound.predict(definition)
	var screen := await _open(definition, TABLET)
	var lab: Experiment = screen.experiment
	var box: DialogueBox = screen.dialogue
	screen._predict_pick_choice(str(predict.answer))
	var grew := false
	var said := ""
	for i in 30:
		await tree.process_frame
		grew = grew or screen._mission_pill.scale.x > 1.05
		if box.active and box.visible and said == "":
			said = box.text
	var want := "%s %s" % [predict.bridge, MissionRound.BRIDGE_FIRST]
	if said != want or box.speaker != "dugi" or box.face != str(predict.bridge_face) or screen.strip_pulses != 1 or not grew:
		problems.append("bridge: said '%s' (want '%s'), %s %s, pulses %d, grew %s" % [said, want, box.speaker, box.face, screen.strip_pulses, grew])
	for i in roundi(ExperimentScreen.PULSE_S * 60.0) + 5:
		await tree.process_frame
	if screen._mission_pill.scale != Vector2.ONE or screen._mission_pill.self_modulate != Color.WHITE:
		problems.append("bridge: the strip did not settle after its pulse")
	screen.handle_back()   # Dugi's bridge closes
	# The first drop: nothing tells the reason before Puppy's line; right after it Dugi does.
	var r: float = lab.BALL_RADIUS
	await _drag_to(screen, lab.balls.red.global_position, Vector3(lab.starts.red.x, 6.0 + r, lab.starts.red.z))
	var early := false
	var told_after := false
	for i in 400:
		await tree.process_frame
		var told: bool = box.active and box.text == str(predict.reason)
		if screen.result_bubble() == null:
			early = early or told
		elif told:
			told_after = true
			break
	if early or not told_after or box.face != Story.REASON_FACE[true]:
		problems.append("reason: before the first line %s, after it %s (%s)" % [early, told_after, box.face])
	await _free(screen)
	# A spot with a stamp already: the bridge says the next mission.
	var store := ProgressStore.load()
	store["free-fall"] = 1
	ProgressStore.save(store)
	screen = await _open(definition, TABLET)
	screen._predict_pick_choice(str(predict.answer))
	if screen.mission_round.bridge_line() != "%s %s" % [predict.bridge, MissionRound.BRIDGE_NEXT]:
		problems.append("bridge at stage 2: '%s'" % screen.mission_round.bridge_line())
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(), "bridge: after the answer Dugi says the lab's bridge (첫 번째 미션 / 다음 미션) and the strip pulses once; the prediction's reason only after the first attempt's line", "; ".join(problems))


## Every lab's prediction is answered by its first stage: the formula of a run that clears stage 1
## gives the answer's choice (2026-10-29: the questions stage 1 did not answer were changed).
func check_stage1_answers() -> void:
	var problems := []
	var g := 9.81
	var answers := {}
	for definition in ExperimentRegistry.load_all():
		answers[definition.id] = str(MissionRound.predict(definition).get("answer", ""))
	var stage := func(id: String) -> Dictionary: return MissionRound.missions(ExperimentRegistry.find(id)).stages[0]
	# The throw: stage 1's low throws (0-20 deg, 8 m/s) land nearer than the slanted 45 deg one.
	var v := 8.0
	var low := v * v * sin(2.0 * deg_to_rad(15.0)) / g
	var slant := v * v * sin(2.0 * deg_to_rad(45.0)) / g
	_answer(problems, answers, "projectile", "near" if low < slant else "far")
	# The fall: the same height lands together whatever the mass (t = sqrt(2h/g)).
	_answer(problems, answers, "free-fall", "together" if is_equal_approx(sqrt(2.0 * 5.0 / g), sqrt(2.0 * 5.0 / g)) else "heavy")
	# The hit: equal masses (stage 1: 1 kg + 1 kg, rubber e 0.88): B goes on, A nearly stops.
	var c: Dictionary = stage.call("collision").conditions
	var ma := float(c.mass_a)
	var mb := float(c.mass_b)
	var e := 0.88
	var u := 6.5
	var vb := (1.0 + e) * ma / (ma + mb) * u
	var va := (ma - e * mb) / (ma + mb) * u
	_answer(problems, answers, "collision", "flies" if vb > 0.5 * u and absf(va) < 0.1 * u else "stop")
	# The spring: no damping by default, the swing reaches as far as the pull (x0 e^0).
	var spring := ExperimentRegistry.find("spring")
	var damping := ""
	for control in spring.controls:
		if control.id == "damping":
			damping = str(control.default)
	_answer(problems, answers, "spring", "full" if damping == "none" else "short")
	# The push: the light box (stage 1) on wood stays until the push passes mu_s m g > 0.
	var friction := ExperimentRegistry.find("friction")
	var mu_s := 0.0
	var kg := 0.0
	for control in friction.controls:
		for option in control.get("options", []):
			if control.id == "material" and option.id == control.default:
				mu_s = float(option.mu_s)
			if control.id == "mass" and option.id == stage.call("friction").conditions.mass:
				kg = float(option.kg)
	_answer(problems, answers, "friction", "wait" if mu_s * kg * g > 0.5 else "now")
	# The lever: stage 1 near point needs more than the chest's own weight (its threshold over mg).
	var rotation_stage: Dictionary = stage.call("rotation")
	_answer(problems, answers, "rotation", "hard" if float(rotation_stage.threshold) > float(rotation_stage.conditions.mass) * g else "easy")
	# The orbit: from 4 m the circular speed sqrt(GM / r) is under the escape speed: it goes round.
	var radius := float(stage.call("orbit").conditions.radius)
	_answer(problems, answers, "orbit", "stay" if sqrt(OrbitModel.DEFAULT_MU / radius) < sqrt(2.0 * OrbitModel.DEFAULT_MU / radius) else "leave")
	# The drum: the big drum displaces more than every load's mass: it floats with any of them.
	var buoyancy := ExperimentRegistry.find("buoyancy")
	var litres := 0.0
	var heaviest := 0.0
	for control in buoyancy.controls:
		if control.id == "volume":
			for option in control.options:
				if option.id == stage.call("buoyancy").conditions.volume:
					litres = float(option.volume) * 1000.0
	for pick in buoyancy.kid.picks.get("mass", []):
		heaviest = maxf(heaviest, float(pick.value))
	_answer(problems, answers, "buoyancy", "floats" if heaviest < litres else "sinks")
	# The swing: stage 1's long rope (>= 2.25 m) swings slower than the 2 m start rope.
	var long_rope := float(stage.call("constraints").conditions.length.min)
	_answer(problems, answers, "constraints", "slower" if TAU * sqrt(long_rope / g) > TAU * sqrt(2.0 / g) else "same")
	# The pulley: one strand carries the whole weight (mg / 1), four would carry a quarter.
	var pulley_stage: Dictionary = stage.call("pulley")
	_answer(problems, answers, "pulley", "hard" if float(pulley_stage.conditions.mass) * g / 1.0 > float(pulley_stage.conditions.mass) * g / 4.0 else "easy")
	# The slide: steel at the start angle (20 deg) slides (tan 20 deg > mu_s of steel).
	var incline := ExperimentRegistry.find("incline-friction")
	var steel_mu := 1.0
	var angle := 0.0
	for control in incline.controls:
		if control.id == "angle":
			angle = float(control.default)
		for option in control.get("options", []):
			if option.id == "steel":
				steel_mu = float(option.mu_s)
	_answer(problems, answers, "incline-friction", "slides" if tan(deg_to_rad(angle)) > steel_mu else "stays")
	expect.call(problems.is_empty() and answers.size() >= 11, "every lab's question is answered by doing its first stage (the formula of a stage-1 run gives the answer)", "; ".join(problems))


func _answer(problems: Array, answers: Dictionary, id: String, want: String) -> void:
	if answers.get(id, "") != want:
		problems.append("%s: answer %s, stage 1 shows %s" % [id, answers.get(id, ""), want])


# --- 4. the orbit's pace ---------------------------------------------------------------------------

func check_orbit_pace() -> void:
	var problems := []
	var definition := ExperimentRegistry.find("orbit")
	var screen := await _open(definition, TABLET)
	screen.mission_round.end_question()
	var lab: Experiment = screen.experiment
	screen._set_control("radius", 4.0)
	screen.experiment.run_action("circular")
	screen.experiment_action("launch")
	await tree.physics_frame   # the frame of the launch (its signal comes before the lab's step)
	var steps := []
	var last: int = lab.model.steps
	for i in 40:
		await tree.physics_frame
		steps.append(lab.model.steps - last)
		last = lab.model.steps
	var total: int = lab.model.steps
	var paced: bool = steps.all(func(n: int) -> bool: return n == 2 or n == 3) and steps.reduce(func(a: int, n: int) -> int: return a + n, 0) == 100
	var at := [lab.model.x, lab.model.z, lab.model.vx, lab.model.vz, str(lab.observations())]
	var posed: bool = lab.planet.global_position.distance_to(lab.model.position()) < 1e-4
	# The same launch at 1x, stepped as often: the same model, the same numbers.
	var plain: Experiment = ExperimentRegistry.instantiate(definition)
	tree.root.add_child(plain)
	await tree.process_frame
	plain.set_control("radius", 4.0)
	plain.run_action("circular")
	plain.run_action("launch")
	var guard := 0
	while plain.model.steps < total and guard < 1000:
		await tree.physics_frame
		guard += 1
	var same: bool = plain.model.steps == total and [plain.model.x, plain.model.z, plain.model.vx, plain.model.vz, str(plain.observations())] == at
	plain.queue_free()
	if not (paced and same and posed):
		problems.append("steps per frame %s (total %d), same model %s, planet on it %s" % [str(steps.slice(0, 6)), total, same, posed])
	# The first stage's lap is judged on the model's lap (stamp), sooner on the clock.
	var frames := 0
	while screen.mission_round.stamps == 0 and frames < 600:
		await tree.physics_frame
		await tree.process_frame
		frames += 1
	var lap: Variant = lab.observations().lap
	if screen.mission_round.stamps != 1 or not (lap is float and lap > 9.0) or frames > 300:
		problems.append("the lap stamp after %d frames (lap %s s, stamps %d)" % [frames, str(lap), screen.mission_round.stamps])
	var note: Label = screen.find_child("TimeScaleNote", true, false)
	if note == null or not note.text.contains("2.5배"):
		problems.append("the note has no 2.5x line")
	await _free(screen)
	DirAccess.remove_absolute(ProgressStore.path)
	expect.call(problems.is_empty(), "orbit pace: 2.5 model steps a frame (2, 3, 2, 3), the model and its numbers = the 1x run after the same steps, the lap stamp (model seconds) on time, 자세히 says 시간을 2.5배", "; ".join(problems))


# --- 5. the play yard -------------------------------------------------------------------------------

func check_yard_spread() -> void:
	var problems := []
	var spec: Dictionary = MapIsland.ZONES["놀이터"]
	var spots: Array = spec.spots
	var fence := PackedVector2Array(MapIsland.yard_outline(spec, 0.15))
	for a in spots.size():
		var pa := Vector2(spots[a][1][0], spots[a][1][1])
		var ra := MapLandmarks.stage_radius(spots[a][0])
		for k in 12:
			var p := pa + Vector2.from_angle(TAU * k / 12.0) * (ra + 0.1)
			if not Geometry2D.is_point_in_polygon(p, fence):
				problems.append("%s reaches the fence" % spots[a][0])
				break
		for b in range(a + 1, spots.size()):
			var pb := Vector2(spots[b][1][0], spots[b][1][1])
			var gap := pa.distance_to(pb) - ra - MapLandmarks.stage_radius(spots[b][0])
			if gap < 1.1:   # (before 2026-10-29: 0.75 m, rotation - pulley)
				problems.append("%s - %s stages %.2f m apart" % [spots[a][0], spots[b][0], gap])
	for setup in [[PHONE, "phone"], [TABLET, "tablet"]]:
		var home := await _home(setup[0])
		await tree.process_frame
		await tree.process_frame
		var yard := spots.map(func(s: Array) -> String: return str(s[0]))
		for spot: Dictionary in home._spots:
			if spot.id not in yard:
				continue
			# The walk from the square to the spot keeps off every other stage.
			var stand := Vector2(spot.stand.x, spot.stand.z)
			for p in home.route(Vector2(home.HOME[0], home.HOME[1]), stand):
				for other: Dictionary in home._spots:
					if other.id != spot.id and p.distance_to(Vector2(other.at.x, other.at.z)) < float(other.radius) + 0.1:
						problems.append("%s: the walk crosses the %s stage" % [spot.id, other.id])
						break
			# Its name: clear of every other yard landmark and of the other yard names.
			var label: Control = home._labels[spot.id]
			var rect := Rect2(label.position, label.size)
			for other: Dictionary in home._spots:
				if other.id == spot.id or other.id not in yard:
					continue
				# A name may lie over the edge of a farther landmark's stage, never over its model's top (where
				# its own name stands) and never over more than LANDMARK_COVER of it.
				var marker := _landmark_rect(home, other)
				var top: Vector2 = home._world_to_screen(other.at + Vector3.UP * float(other.top))
				var head := Rect2(top - Vector2(14.0, 0.0), Vector2(28.0, 28.0))
				var covered := rect.intersection(marker).get_area() / maxf(1.0, marker.get_area()) if rect.intersects(marker) else 0.0
				if rect.intersects(head) or covered > LANDMARK_COVER:
					problems.append("%s (%s): the name covers %d %% of the %s landmark" % [spot.id, setup[1], roundi(covered * 100.0), other.id])
				var other_label: Control = home._labels[other.id]
				if rect.grow(6.0).intersects(Rect2(other_label.position, other_label.size)):
					problems.append("%s (%s): the name touches %s's" % [spot.id, setup[1], other.id])
		await _free(home)
	expect.call(problems.is_empty(), "play yard: its four spots inside the fence, stages 1.1 m or more apart (before: 0.75 m), the walk to each clear of the others, the names 6 units apart and off the other landmarks' tops, covering at most 15 % of one (phone, tablet)", "; ".join(problems))


## A spot's landmark on the map screen: its stage and model (up to its top), projected.
func _landmark_rect(home: Control, spot: Dictionary) -> Rect2:
	var r := float(spot.radius)
	var base: Vector3 = spot.at
	var box := AABB(base - Vector3(r, 0.0, r), Vector3(r * 2.0, float(spot.top), r * 2.0))
	var rect := Rect2(home._world_to_screen(box.position), Vector2.ZERO)
	for i in 8:
		rect = rect.expand(home._world_to_screen(box.get_endpoint(i)))
	return rect


# --- 6. the pulley's rope ---------------------------------------------------------------------------

func check_pulley_rope() -> void:
	var problems := []
	var lab: Experiment = ExperimentRegistry.instantiate(ExperimentRegistry.find("pulley"))
	tree.root.add_child(lab)
	await tree.process_frame
	var props: PulleyProps = lab.props
	var R := PulleyProps.RIM
	var yf: float = lab.TOP_Y - PulleyProps.FIXED_DOWN
	for n in [1, 2, 4]:
		lab.set_control("strands", {1: "one", 2: "two", 4: "four"}[n])
		for top in [false, true]:
			lab.set_stroke(lab.model.stroke_limit() if top else 0, false)
			lab.let_go()
			await tree.physics_frame
			await tree.physics_frame
			lab._show()
			var what := "%d strands, %s" % [n, "top" if top else "ground"]
			var plan := PulleyProps.layout(n, lab.LOAD_X)
			var hook: float = lab.load_body.global_position.y + props.hook_up
			var ym := hook + PulleyProps.MOVING_UP
			var bottom := hook if n == 1 else ym
			var wheels := []
			for x in plan.fixed:
				wheels.append(Vector2(x, yf))
			for x in plan.moving:
				wheels.append(Vector2(x, ym))
			var xs: Array = plan.strands
			for k in xs.size():
				var x: float = xs[k]
				# Top: on a fixed wheel's rim (its side at its centre height), or the dead end tied to the block.
				var on_top: bool = plan.fixed.any(func(c: float) -> bool: return absf(absf(x - c) - R) < 1e-6)
				if not on_top and not (n > 1 and k == 0):
					problems.append("%s: strand %d's top is on no fixed wheel" % [what, k])
				# Bottom: on a moving wheel's rim, or the hook over the load's centre for one strand.
				if n == 1:
					if absf(x - lab.LOAD_X) > 1e-6:
						problems.append("%s: the strand is not over the hook" % what)
				elif not plan.moving.any(func(c: float) -> bool: return absf(absf(x - c) - R) < 1e-6):
					problems.append("%s: strand %d's bottom is on no moving wheel" % [what, k])
				# Never through a wheel.
				for w: Vector2 in wheels:
					var near := Geometry2D.get_closest_point_to_segment(w, Vector2(x, yf), Vector2(x, bottom))
					if near.distance_to(w) < R - 1e-6:
						problems.append("%s: strand %d passes %.3f m from a wheel's centre" % [what, k, near.distance_to(w)])
			# The drawn strands: n of them at those xs, from the fixed wheels down to `bottom` (follows the load).
			var strands: MeshInstance3D = props.strands
			var low := INF
			var high := -INF
			for vtx in strands.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = strands.global_transform * vtx
				low = minf(low, p.y)
				high = maxf(high, p.y)
			if absf(low - bottom) > 1e-4 or absf(high - yf) > 1e-4:
				problems.append("%s: strands drawn %.3f..%.3f, want %.3f..%.3f" % [what, low, high, bottom, yf])
			# The run to the guide: tangent to the last fixed wheel and to the guide wheel; the pull strand
			# leaves the guide's right rim.
			var paths := PulleyProps.fixed_rope(n, lab.LOAD_X, lab.TOP_Y, lab.GUIDE)
			var last: PackedVector2Array = paths[-1]
			var origin := Vector2(lab.LOAD_X, lab.TOP_Y)
			var guide := Vector2(lab.GUIDE.x, lab.GUIDE.y)
			var centre := Vector2(plan.fixed[-1], yf)
			for i in last.size():
				var p: Vector2 = last[i] + origin
				if absf(minf(p.distance_to(centre), p.distance_to(guide)) - R) > 1e-6:
					problems.append("%s: a rope point off the rims" % what)
					break
			if not paths.all(func(path: PackedVector2Array) -> bool: return (path[0] + origin).distance_to(Vector2(plan.fixed[0] - R, yf)) < 1e-6 or n > 1):
				problems.append("%s: the rope does not come up the first wheel's left rim" % what)
			var link: Node3D = props.pull_link
			if link.global_position.distance_to(lab.GUIDE + Vector3(R, 0.0, 0.0)) > 1e-4 or absf(lab.rope_end.global_position.x - (lab.GUIDE.x + R)) > 1e-6:
				problems.append("%s: the pull strand leaves %s, the rope end at x %.3f" % [what, str(link.global_position), lab.rope_end.global_position.x])
		if PulleyProps.run_normal(Vector2(plan_last_fixed(n, lab.LOAD_X), yf), Vector2(lab.GUIDE.x, lab.GUIDE.y)).y <= 0.0:
			problems.append("%d strands: the run goes under the wheels" % n)
	lab.queue_free()
	await tree.process_frame
	expect.call(problems.is_empty(), "pulley rope (n = 1, 2, 4, load down and up): every strand hangs from a fixed wheel's rim (or its tied end) to a moving wheel's rim (or the hook), never through a wheel, drawn to follow the load; the run touches both wheels; the pull strand leaves the guide's rim", "; ".join(problems.slice(0, 8)))


static func plan_last_fixed(n: int, load_x: float) -> float:
	return PulleyProps.layout(n, load_x).fixed[-1]


# --- helpers ---------------------------------------------------------------------------------------

func _open(definition: Dictionary, size: Vector2) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _home(size: Vector2) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(HOME_SCREEN).new()
	host.add_child(screen)
	for i in 4:
		await tree.process_frame
	return screen


func _free(screen: Control) -> void:
	screen.get_parent().queue_free()
	for i in 3:
		await tree.process_frame


func _at(screen: Control, world: Vector3) -> Vector2:
	return screen.view_point(world)


func _touch(screen: Control, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	screen.view._gui_input(event)


func _drag(screen: Control, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	screen.view._gui_input(event)


## A finger presses free-fall ball `id` where it lies (after a drop: on the floor; the press starts a
## fresh run and the ball waits at its start again), drags it to the height `h` (m) on its drop line
## (the finger moves as far as the ball must) and lifts there.
func _drop_drag(screen: Control, id: String, h: float) -> void:
	var lab: Experiment = screen.experiment
	var a := _at(screen, lab.balls[id].global_position)
	_touch(screen, a, true)
	await tree.process_frame
	var start: Vector3 = lab.starts[id] + Vector3.UP * lab.BALL_RADIUS
	var d := _at(screen, Vector3(start.x, h + lab.BALL_RADIUS, start.z)) - _at(screen, start)
	for i in range(1, 9):
		_drag(screen, a + d * (i / 8.0))
		await tree.process_frame
	_touch(screen, a + d, false)
	await tree.process_frame


## A finger presses `from` (world), drags to `to` in 8 moves over 8 frames and lifts there.
func _drag_to(screen: Control, from: Vector3, to: Vector3) -> void:
	var a := _at(screen, from)
	var b := _at(screen, to)
	_touch(screen, a, true)
	await tree.process_frame
	for i in range(1, 9):
		_drag(screen, a.lerp(b, i / 8.0))
		await tree.process_frame
	_touch(screen, b, false)
	await tree.process_frame
