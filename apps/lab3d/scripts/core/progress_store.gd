## Game progress (Plan G1): the stamps (도장) per island spot. Spots are named by the experiment
## id; each keeps 0..MAX_STAMPS. Stored in user://progress.cfg (ConfigFile, the app's own storage:
## device only, no account). A missing or corrupt file (a broken section, a non-number stamp, a
## value out of range) reads back as no progress at all: the child starts over, nothing else fails.
## This module never touches physics or display: it only counts a stamp when MissionTracker hands
## one over (Plan: 판정 값은 공식값, 도장은 진행 저장뿐).
class_name ProgressStore
extends RefCounted

const PATH := "user://progress.cfg"
const MAX_STAMPS := 3
## The file in use: PATH in the app. Tests (TEST_PATH) and device measurements (BENCH_PATH) use
## their own file, so they never read or write the child's real progress.
static var path := PATH
const TEST_PATH := "user://progress-test.cfg"
## A device measurement (--auto-drag / --auto-release) keeps its stamps here (ExperimentScreen).
const BENCH_PATH := "user://progress-bench.cfg"
## File reads so far (tests: the map reads the store when it opens, never per frame).
static var load_count := 0
## Sections the store owns (a corrupt one is ignored: a future section name is never read here).
const SECTIONS := ["progress"]
## The control values of the run that cleared each spot's last stage (MissionTracker `change`).
const CLEARED := "cleared"
## The map's flag raise (2026-10-28): a spot whose round is completed now gets `false` here (its
## flag still to be raised on the map); the map raises it once and writes `true`. A missing key
## counts as raised: a save from before this section (a spot already at full stamps) never replays.
const FLAGS := "flags"


static func load() -> Dictionary:
	load_count += 1
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return {}
	var result := {}
	for section in SECTIONS:
		if not config.has_section(section):
			continue
		for id in config.get_section_keys(section):
			var value: Variant = config.get_value(section, id)
			# A stamp is a number; ConfigFile gives a "3" as the string "3" only when the file was
			# hand-edited — accept a numeric string too (a non-numeric one is a corrupt value: drop).
			var number := _as_int(value)
			if number >= 0 and number <= MAX_STAMPS:
				result[id] = number
	return result


## The stamp as a number, or -1 when the stored value is not a number (a corrupt value: dropped).
static func _as_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return -1


## Writes the whole stamp store (atomic enough for a small cfg: ConfigFile.save). The file's other
## sections (the cleared throws) stay; a corrupt file is replaced.
static func save(progress: Dictionary) -> void:
	var config := _read()
	if config.has_section("progress"):
		config.erase_section("progress")
	for id in progress:
		config.set_value("progress", id, int(progress[id]))
	config.save(path)


## The control values of the run that cleared `id`'s last stage ({} when none is stored or the
## stored value is not an object): MissionTracker's `change` compares the next stage's run with it.
static func cleared(id: String) -> Dictionary:
	var value: Variant = _read().get_value(CLEARED, id, {})
	return value if value is Dictionary else {}


## Stores the control values of the run that cleared `id`'s last stage (the stamps stay).
static func save_cleared(id: String, controls: Dictionary) -> void:
	var config := _read()
	config.set_value(CLEARED, id, controls)
	config.save(path)


## The file as it is, or an empty config when it is missing or corrupt.
static func _read() -> ConfigFile:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		config = ConfigFile.new()
	return config


## The stamps of `id` (0 when it has none).
static func stamps(progress: Dictionary, id: String) -> int:
	return int(progress.get(id, 0))


## A spot's round was completed now: its flag waits to be raised on the map (once).
static func mark_flag_pending(id: String) -> void:
	var config := _read()
	config.set_value(FLAGS, id, false)
	config.save(path)


## The map raised `id`'s flag: it just stands from now on.
static func mark_flag_raised(id: String) -> void:
	var config := _read()
	config.set_value(FLAGS, id, true)
	config.save(path)


## The spots whose flag waits to be raised (explicitly `false`; a missing key or any other value is
## raised: an old save, a hand-edited file).
static func pending_flags() -> Array:
	var config := _read()
	var out := []
	if config.has_section(FLAGS):
		for id in config.get_section_keys(FLAGS):
			if config.get_value(FLAGS, id) is bool and config.get_value(FLAGS, id) == false:
				out.append(id)
	return out
