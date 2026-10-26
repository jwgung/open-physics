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
## The file in use: PATH in the app. Tests point it at their own file (TEST_PATH) so a run never
## reads or writes the child's real progress.
static var path := PATH
const TEST_PATH := "user://progress-test.cfg"
## File reads so far (tests: the map reads the store when it opens, never per frame).
static var load_count := 0
## Sections the store owns (a corrupt one is ignored: a future section name is never read here).
const SECTIONS := ["progress"]


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


## Writes the whole store (atomic enough for a small cfg: ConfigFile.save).
static func save(progress: Dictionary) -> void:
	var config := ConfigFile.new()
	for id in progress:
		config.set_value("progress", id, int(progress[id]))
	config.save(path)


## The stamps of `id` (0 when it has none).
static func stamps(progress: Dictionary, id: String) -> int:
	return int(progress.get(id, 0))


## `stamps + 1`, capped at MAX_STAMPS.
static func award(progress: Dictionary, id: String, stamps: int) -> int:
	return mini(stamps + 1, MAX_STAMPS)
