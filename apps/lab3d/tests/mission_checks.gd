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
	expect.call(predict.reason.contains("v0") and predict.reason.contains("R"),
		"predict: the reason is matched to the formula (R = v0²·sin2θ/g)", predict.reason)
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
	DirAccess.remove_absolute(ProgressStore.PATH)
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
	DirAccess.remove_absolute(ProgressStore.PATH)
	var path := ProjectSettings.globalize_path(ProgressStore.PATH)
	var backup := ""
	if FileAccess.file_exists(ProgressStore.PATH):
		backup = FileAccess.get_file_as_string(ProgressStore.PATH)
	DirAccess.remove_absolute(ProgressStore.PATH)
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
	DirAccess.remove_absolute(ProgressStore.PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ProgressStore.PATH).get_base_dir())
	var file := FileAccess.open(ProgressStore.PATH, FileAccess.WRITE)
	file.store_string("this is { not a config file ]\n")
	file.close()
	expect.call(ProgressStore.load().is_empty(), "a corrupt file reads back as no progress (start over)", "")
	# A cfg with a section whose stamp is not a number or out of range is dropped. ConfigFile reads
	# a "99" as the string "99" (a hand-written cfg): the numeric-string path of the loader.
	file = FileAccess.open(ProgressStore.PATH, FileAccess.WRITE)
	file.store_string("[progress]\nprojectile=99\norbit=2\nbuoyancy=1\n")
	file.close()
	var loaded := ProgressStore.load()
	expect.call(loaded == {"orbit": 2, "buoyancy": 1} and ProgressStore.load().get("projectile") == null,
		"a stamp out of range (99) is dropped, a valid one stays", str(loaded))
	# The store is the app's own file: a save after a corrupt read replaces it.
	ProgressStore.save({"projectile": 1})
	expect.call(ProgressStore.load() == {"projectile": 1}, "a save after a corrupt read replaces the file", str(ProgressStore.load()))
	DirAccess.remove_absolute(ProgressStore.PATH)
	if backup != "":
		file = FileAccess.open(ProgressStore.PATH, FileAccess.WRITE)
		file.store_string(backup)
		file.close()


# --- physics unchanged -----------------------------------------------------------------------------


## With and without the mission tracker running on every status change, the projectile's engine
## ball (every step) and the panel values are the same: the mission only reads.
func _record(tracker: MissionTracker = null) -> Array:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = TABLET
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("projectile"))
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	var lab: Experiment = screen.experiment
	# The default throw (earth, 45 deg, 9 m/s, 0.5 m high) flies ~8.7 m: it clears the first stage.
	var out := []
	var statuses := []
	var previous := lab.status()
	for k in 600:
		await tree.physics_frame
		if k == 30:
			lab.run_action("release")
		if lab.status() != previous:
			statuses.append(lab.status())
			if tracker != null:
				tracker.on_run_ended(lab.status(), lab, lab.observations())
		previous = lab.status()
		if k % 5 == 0:
			out.append([lab.status(), str(lab.observations()), lab.ball.global_transform])
	# The ball's last pose, read while the tree is alive (it would be freed with the host below).
	var last_ball: Transform3D = lab.ball.global_transform
	var values: Dictionary = lab.observations()
	host.queue_free()
	await tree.process_frame
	return [out, statuses, values, last_ball]


func check_physics_unchanged() -> void:
	# Clean slate: the unit checks and the store checks wrote and removed the store's file.
	DirAccess.remove_absolute(ProgressStore.PATH)
	# The run without the mission (the physics baseline).
	var without: Array = await _record()
	# The same run with the tracker judging every status change: one throw, one settled landing.
	var tracker := MissionTracker.new()
	tracker.definition = ExperimentRegistry.find("projectile")
	var awarded := []
	tracker.progress = func(id: String, stamps: int) -> void: awarded.append([id, stamps])
	var with_mission: Array = await _record(tracker)
	# Compare step by step: status, the panel values, the engine ball's transform.
	var rows := mini(without[0].size(), with_mission[0].size())
	var first := -1
	var same := true
	for k in rows:
		var a: Array = without[0][k]
		var b: Array = with_mission[0][k]
		if a.size() != b.size():
			same = false
			break
		for j in a.size():
			if a[j] != b[j]:
				same = false
				first = k
				break
		if not same:
			break
	var values: Dictionary = with_mission[2]
	expect.call(without[0].size() == with_mission[0].size() and same,
		"projectile: the trajectory and the displayed values are the same at every step, with or without the mission",
		"first difference at row %d of %d" % [first, rows])
	expect.call(values.range is float and float(values.range) > 3.0 and tracker.stamps == 1 and tracker.stage() == 1,
		"the default throw lands past 3 m (formula range %s) and earns the first stamp (one throw, one stage)" % str(values.range),
		"stamps %d" % tracker.stamps)
	expect.call(awarded == [["projectile", 1]] and ProgressStore.load() == {"projectile": 1},
		"the cleared stage saved its stamp (1 stored after the run)", "awarded %s, stored %s" % [str(awarded), str(ProgressStore.load())])
	expect.call(with_mission[1].has("landed"), "the run ends landed, when the tracker judges", str(with_mission[1]))
	DirAccess.remove_absolute(ProgressStore.PATH)
