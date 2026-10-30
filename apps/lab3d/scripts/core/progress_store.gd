## Game progress (Plan G1): the stamps (도장) per island spot. Spots are named by the experiment
## id; each keeps 0..MAX_STAMPS. Stored in user://progress.cfg (ConfigFile, the app's own storage:
## device only, no account). A missing or corrupt file (a broken section, a non-number stamp, a
## value out of range) reads back as no progress at all: the child starts over, nothing else fails.
## This module never touches physics or display: it only counts a stamp when MissionRound hands
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
## The control values of the run that cleared each spot's last stage (MissionRound `change`).
const CLEARED := "cleared"
## The map's flag raise (2026-10-28): a spot whose round is completed now gets `false` here (its
## flag still to be raised on the map); the map raises it once and writes `true`. A missing key
## counts as raised: a save from before this section (a spot already at full stamps) never replays.
const FLAGS := "flags"
## The story "별 조각 찾기" (2026-10-28, Story): its own sections, never read as stamps.
##   [story]  prologue / finale = true once played (a missing key: not played yet)
##   [clues]  <spot id> = true once Puppy's clue was told in that lab
##   [pieces] <spot id> = false: the star piece was found in the lab (the round completed), its
##            flight to the lookout still to play on the map; true: flown. A missing key counts as
##            flown: a save from before the story (a spot already at full stamps) never replays.
const STORY := "story"
const CLUES := "clues"
const PIECES := "pieces"
## The map (2026-10-29): [map] last_spot = the spot id the trio last walked to (they stand there when
## the map opens again; none: the square).
const MAP := "map"


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
## stored value is not an object): MissionRound's `change` compares the next stage's run with it.
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
	return pending(FLAGS)


## The keys of `section` that are explicitly `false` (flags still to raise, pieces still to fly).
static func pending(section: String) -> Array:
	var config := _read()
	var out := []
	if config.has_section(section):
		for id in config.get_section_keys(section):
			if config.get_value(section, id) is bool and config.get_value(section, id) == false:
				out.append(id)
	return out


## A yes/no mark of the story sections (true only when stored as true; a missing or odd value: false).
static func mark(section: String, key: String) -> bool:
	var value: Variant = _read().get_value(section, key, false)
	return value is bool and value


static func set_mark(section: String, key: String, value: bool) -> void:
	var config := _read()
	config.set_value(section, key, value)
	config.save(path)


## Removes a story section (a replay, the screenshot demos' bench store).
static func clear_section(section: String) -> void:
	var config := _read()
	if config.has_section(section):
		config.erase_section(section)
		config.save(path)


## The spot the trio last walked to on the map ("" when none: they stand on the square).
static func last_spot() -> String:
	var value: Variant = _read().get_value(MAP, "last_spot", "")
	return value if value is String else ""


static func set_last_spot(id: String) -> void:
	var config := _read()
	if id == "":
		if config.has_section_key(MAP, "last_spot"):
			config.erase_section_key(MAP, "last_spot")
	else:
		config.set_value(MAP, "last_spot", id)
	config.save(path)


## 처음부터 다시 하기 (settings, confirmed): every section of the store in use is gone — the stamps,
## the cleared runs, the flags, the story (prologue, clues, pieces, finale) and the map's last spot.
## Only the file at `path` (the bench or test store in measurements and tests). The sound and the
## other settings live in user://settings.cfg and stay.
static func reset_all() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
