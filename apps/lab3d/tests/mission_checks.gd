## Plan G1: the mission and progress model — the missions / predict blocks of the content, the
## MissionTracker (a landed run is judged by the formula value; a throw that falls short changes
## nothing), the ProgressStore (user://progress.cfg, 0..3 stamps per spot, a corrupt file starts
## over), and the physics invariant: with and without the tracker on, the projectile's trajectory
## and displayed values are the same at every step.
extends RefCounted

var tree: SceneTree
var expect: Callable
const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const TABLET := Vector2(1152, 720)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_content()
	check_registry_validation()
	await check_mission_tracker()
	check_progress_store()
	await check_physics_unchanged()


# --- content --------------------------------------------------------------------------------------

## The projectile's mission and predict blocks (Plan: one predict question, two pictures, the
## reason matched to R = v0^2 sin2θ / g; the three thresholds inside the earth default-height
## maximum of ~8.7 m).
func check_content() -> void:
	var definition := ExperimentRegistry.find("projectile")
	expect.call(definition.has("missions") and definition.has("predict"), "projectile: has the missions and predict blocks", "")
	var missions: Dictionary = definition.missions
	expect.call(missions.observe == "range" and (missions.stages as Array).size() == 3,
		"missions: judged by the formula range, three stages", str(missions.get("observe")))
	var thresholds := (missions.stages as Array).map(func(s: Dictionary) -> Variant: return s.threshold)
	expect.call(thresholds == [3.0, 5.0, 7.0] and thresholds.all(func(t: Variant) -> bool: return t <= 8.7),
		"missions: 3 m -> 5 m -> 7 m, all inside the earth default-height maximum (~8.7 m)", str(thresholds))
	for stage in missions.stages:
		expect.call(stage.text != "", "missions: every stage has its text", str(stage.get("threshold")))
	var predict: Dictionary = definition.predict
	expect.call(predict.question == "공을 더 세게 던지면 더 멀리 갈까?" and (predict.choices as Array).size() == 2,
		"predict: the one question, two pictures", str(predict.get("question")))
	var ids := (predict.choices as Array).map(func(c: Dictionary) -> Variant: return c.id)
	expect.call(ids == ["farther", "same"], "predict: the two pictures are 멀리 and 똑같이", str(ids))
	expect.call(predict.reason.contains("v₀") and predict.reason.contains("R") and predict.reason.contains("같은 각도")
		and predict.reason.contains("높이 없이"),
		"predict: the reason says R grows with v₀ at the same angle, and gives R = v₀²·sin2θ/g only for a launch without height", predict.reason)
	# The other experiments have no missions or predict yet (next Plan).
	for other in ExperimentRegistry.load_all():
		if other.id != "projectile":
			expect.call(not other.has("missions") and not other.has("predict"),
				"%s: no missions or predict yet" % other.id, "")


# --- registry validation ---------------------------------------------------------------------------

## Malformed missions / predict are rejected (like the other blocks).
func check_registry_validation() -> void:
	var base := ExperimentRegistry.find("incline-friction").duplicate(true)
	# The base file has no observations list in its raw form: use a defined one.
	var defined := ExperimentRegistry.find("projectile").duplicate(true)
	var problems := ExperimentRegistry.validate(defined)
	expect.call(problems.is_empty(), "projectile (with its missions) is a valid definition", ", ".join(problems))
	var broken := defined.duplicate(true)
	broken.missions.observe = "no-such-observation"
	var found := ExperimentRegistry.validate(broken)
	expect.call(found.size() == 1 and "missions.observe" in found[0],
		"registry rejects a mission judged by an unknown observation id", ", ".join(found))
	var four := defined.duplicate(true)
	four.missions.stages = four.missions.stages.duplicate(true)
	four.missions.stages.append({"threshold": 9.0, "text": "네 번째"})
	found = ExperimentRegistry.validate(four)
	expect.call(found.size() == 1 and "missions.stages" in found[0],
		"registry rejects four stages (the stamp cap is 3)", ", ".join(found))
	var nontext := defined.duplicate(true)
	nontext.missions.stages = defined.missions.stages.duplicate(true)
	nontext.missions.stages[0].text = ""
	found = ExperimentRegistry.validate(nontext)
	expect.call(found.size() == 1 and "text" in found[0], "registry rejects an empty stage text", ", ".join(found))
	var nethreshold := defined.duplicate(true)
	nethreshold.missions.stages = defined.missions.stages.duplicate(true)
	nethreshold.missions.stages[0].threshold = 0.0
	found = ExperimentRegistry.validate(nethreshold)
	expect.call(found.size() == 1 and "threshold" in found[0], "registry rejects a non-positive threshold", ", ".join(found))
	# A file without `missions` still validates (optional block).
	var none := defined.duplicate(true)
	none.erase("missions")
	expect.call(ExperimentRegistry.validate(none).is_empty(), "missions is an optional block", "")


# --- the tracker -----------------------------------------------------------------------------------

## A landed run judged by the formula value: clears the stage, awards the stamp; a short throw,
## a run without a number and a not-yet-settled landing change nothing; all three stages -> done.
func check_mission_tracker() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var definition := ExperimentRegistry.find("projectile").duplicate(true)
	var awarded := []
	var tracker := MissionTracker.new()
	tracker.definition = definition
	tracker.progress = func(id: String, stamps: int) -> void:
		awarded.append([id, stamps])
		var store := ProgressStore.load()
		store["projectile"] = stamps
		ProgressStore.save(store)
	var stubs := [
		["settled", "extends Experiment\nvar stamps := 0\nfunc status() -> String:\n\treturn \"landed\"\nfunc settled() -> bool:\n\treturn true\n"],
		["not_settled", "extends Experiment\nvar stamps := 0\nfunc status() -> String:\n\treturn \"landed\"\nfunc settled() -> bool:\n\treturn false\n"],
	]
	var labs := {}
	for stub in stubs:
		var script := GDScript.new()
		script.source_code = stub[1]
		script.reload()
		var lab = script.new()
		tree.root.add_child(lab)
		labs[stub[0]] = lab
	expect.call(tracker.stage() == 0 and tracker.text() == "3 m보다 멀리 보내기!", "the first stage is 3 m", tracker.text())
	tracker.on_run_ended("flying", labs.settled, {"range": 4.0})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a throw in flight is not judged", str(awarded))
	tracker.on_run_ended("landed", labs.settled, {"range": 2.9})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a throw that falls short (2.9 m < 3 m) changes nothing", str(awarded))
	tracker.on_run_ended("landed", labs.settled, {"range": "닿지 않아요"})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a run with no number is not judged", str(awarded))
	tracker.on_run_ended("out", labs.settled, {"range": 9.0})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a flight out of the island is not a stage clear", str(awarded))
	tracker.on_run_ended("landed", labs.not_settled, {"range": 9.0})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "a landing the engine has not finished is not judged yet", str(awarded))
	tracker.on_run_ended("landed", labs.settled, {"range": 3.0})
	expect.call(tracker.stage() == 0 and awarded.is_empty(), "exactly at the threshold is not farther", str(awarded))
	tracker.on_run_ended("landed", labs.settled, {"range": 3.42})
	await tree.process_frame
	expect.call(tracker.stage() == 1 and tracker.text() == "5 m보다 멀리 보내기!" and awarded == [["projectile", 1]],
		"farther than 3 m clears the first stage (one stamp)", "%d stage, %s" % [tracker.stage(), str(awarded)])
	tracker.on_run_ended("landed", labs.settled, {"range": 6.1})
	await tree.process_frame
	tracker.on_run_ended("landed", labs.settled, {"range": 7.71})
	await tree.process_frame
	expect.call(tracker.stage() == -1 and tracker.text() == "" and awarded == [["projectile", 1], ["projectile", 2], ["projectile", 3]],
		"5 m and 7 m clear the rest; all three stamps, done", "stage %d, %s" % [tracker.stage(), str(awarded)])
	# A lab without missions: nothing to track.
	var plain := ExperimentRegistry.find("free-fall").duplicate(true)
	var bare := MissionTracker.new()
	bare.definition = plain
	expect.call(bare.stage() == -1 and bare.text() == "", "a lab without missions has no stage", "")
	bare.on_run_ended("landed", labs.settled, {"range": 99.0})
	expect.call(bare.stage() == -1, "a lab without missions is never judged", "")
	for lab in labs.values():
		lab.queue_free()
	await tree.process_frame


# --- the store -------------------------------------------------------------------------------------

## user://progress.cfg: 0..3 stamps per spot, saved and reloaded; a corrupt file starts over.
func check_progress_store() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var path := ProjectSettings.globalize_path(ProgressStore.path)
	var backup := ""
	if FileAccess.file_exists(ProgressStore.path):
		backup = FileAccess.get_file_as_string(ProgressStore.path)
	DirAccess.remove_absolute(ProgressStore.path)
	# A missing file is no progress.
	expect.call(ProgressStore.load().is_empty(), "a missing file is no progress", "")
	# Award, save, reload.
	var progress := ProgressStore.load()
	progress["projectile"] = ProgressStore.award(progress, "projectile", ProgressStore.stamps(progress, "projectile"))
	progress["projectile"] = ProgressStore.award(progress, "projectile", ProgressStore.stamps(progress, "projectile"))
	ProgressStore.save(progress)
	var reloaded := ProgressStore.load()
	expect.call(reloaded == {"projectile": 2} and ProgressStore.stamps(reloaded, "projectile") == 2 \
		and ProgressStore.stamps(reloaded, "orbit") == 0, "stamps are saved and reloaded (2 for projectile, 0 for the rest)", str(reloaded))
	# The cap is 3.
	progress["projectile"] = ProgressStore.award(progress, "projectile", 3)
	expect.call(progress["projectile"] == 3, "the stamp cap is 3", str(progress["projectile"]))
	# A corrupt file (broken cfg) is no progress, not an error.
	DirAccess.remove_absolute(ProgressStore.path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ProgressStore.path).get_base_dir())
	var file := FileAccess.open(ProgressStore.path, FileAccess.WRITE)
	file.store_string("this is { not a config file ]\n")
	file.close()
	expect.call(ProgressStore.load().is_empty(), "a corrupt file reads back as no progress (start over)", "")
	# A cfg with a section whose stamp is not a number or out of range is dropped. ConfigFile reads
	# a "99" as the string "99" (a hand-written cfg): the numeric-string path of the loader.
	file = FileAccess.open(ProgressStore.path, FileAccess.WRITE)
	file.store_string("[progress]\nprojectile=99\norbit=2\nbuoyancy=1\n")
	file.close()
	var loaded := ProgressStore.load()
	expect.call(loaded == {"orbit": 2, "buoyancy": 1} and ProgressStore.load().get("projectile") == null,
		"a stamp out of range (99) is dropped, a valid one stays", str(loaded))
	# The store is the app's own file: a save after a corrupt read replaces it.
	ProgressStore.save({"projectile": 1})
	expect.call(ProgressStore.load() == {"projectile": 1}, "a save after a corrupt read replaces the file", str(ProgressStore.load()))
	DirAccess.remove_absolute(ProgressStore.path)
	if backup != "":
		file = FileAccess.open(ProgressStore.path, FileAccess.WRITE)
		file.store_string(backup)
		file.close()


# --- physics unchanged -----------------------------------------------------------------------------


## One recorded throw of 40 deg, 8.5 m/s on the projectile screen (earth, 0.5 m): from the frame of
## the throw on, every 5th physics step the status, the panel's values and the engine ball's
## transform. `missions`: the screen with its mission round (the tracker judging, the strip, Dugi's
## question) or a definition without the missions / predict blocks (no tracker at all).
## `slingshot`: the throw is a real pull on the ball through the view's touch input, else the two
## sliders and "공 놓기" (the same frame either way).
func _record(missions: bool, slingshot: bool) -> Array:
	var definition := ExperimentRegistry.find("projectile").duplicate(true)
	if not missions:
		definition.erase("missions")
		definition.erase("predict")
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(definition)
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	var lab: Experiment = screen.experiment
	var tracked: bool = screen._missions != null
	var out := []
	var statuses := []
	var previous := lab.status()
	for k in 600:
		await tree.physics_frame
		if k == 30:
			if slingshot:
				_pull(screen, lab, 40.0, 8.5)
			else:
				screen._set_control("angle", 40.0)
				screen._set_control("speed", 8.5)
				screen.experiment_action("release")
		if lab.status() != previous:
			statuses.append(lab.status())
		previous = lab.status()
		if k >= 30 and k % 5 == 0:
			out.append([lab.status(), str(lab.observations()), lab.ball.global_transform])
	var values: Dictionary = lab.observations()
	host.queue_free()
	await tree.process_frame
	return [out, statuses, values, tracked]


## A slingshot pull to (angle, speed) and the release, all in this frame (press, moves, release).
func _pull(screen: Control, lab: Experiment, angle: float, speed: float) -> void:
	var surface: PolarArrowSurface = screen.manipulator.slingshot_surface
	var press: Vector2 = screen.view_point(lab.ball_center())
	var launch := PolarArrowSurface.tip_point(angle, speed, 0.0, surface.arrow_scale)
	var finger: Vector2 = screen.view_point(surface.pose(surface.to_plane(lab.ball_center()) - launch, 0.0).origin)
	for step in [[press, true], [press.lerp(finger, 0.5), null], [finger, null], [finger, false]]:
		var event: InputEvent
		if step[1] == null:
			event = InputEventScreenDrag.new()
		else:
			event = InputEventScreenTouch.new()
			event.pressed = step[1]
		event.position = step[0]
		screen.view._gui_input(event)


## The first row where two recordings differ (-1: none), and whether they have the same length.
static func _first_difference(a: Array, b: Array) -> int:
	for k in mini(a.size(), b.size()):
		if a[k] != b[k]:
			return k
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


func check_physics_unchanged() -> void:
	DirAccess.remove_absolute(ProgressStore.path)
	var plain: Array = await _record(false, false)
	var game: Array = await _record(true, false)
	var pulled: Array = await _record(true, true)
	expect.call(not plain[3] and game[3] and pulled[3], "physics check: the plain screen has no tracker, the game screens have one", "")
	var with_round := _first_difference(plain[0], game[0])
	expect.call(with_round == -1 and plain[0].size() > 100,
		"projectile: with or without the mission round, the trajectory and the displayed values are the same at every step",
		"first difference at row %d of %d" % [with_round, plain[0].size()])
	var by_pull := _first_difference(game[0], pulled[0])
	expect.call(by_pull == -1,
		"projectile: a slingshot throw and the sliders + 공 놓기 at the same angle and speed fly the same, step by step",
		"first difference at row %d of %d" % [by_pull, game[0].size()])
	var values: Dictionary = pulled[2]
	expect.call(values.range is float and float(values.range) > 7.0 and pulled[1].has("landed"),
		"the 40° 8.5 m/s throw lands past 7 m (formula range %s)" % str(values.range), str(pulled[1]))
	# Each game screen judged its own landing (one throw, one stage): two stamps; the plain one none.
	expect.call(ProgressStore.load().get("projectile", 0) == 2,
		"the game screens' landings earned one stamp each; the plain screen judged nothing",
		"stored %s" % str(ProgressStore.load()))
	DirAccess.remove_absolute(ProgressStore.path)
