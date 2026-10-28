## The story "별 조각 찾기" (2026-10-28 user-approved): 과학섬 is one island of the sea country 퍼피랜드.
## Its guiding star (길잡이 별) lights the night sea for the boats; it breaks and 11 pieces fall, one
## at each lab spot. A spot's round completed (all its stamps) is its piece found; the pieces fly to
## the lookout (전망대) on the map and, all 11 there, the star goes back to the sky.
##
## Roles (fixed): 퍼피 the detective finds clues (what, where), 두기두기 the scientist gives the reason
## (why), the bread cat acts and never speaks. The story is pictures and words only: it never sets a
## control, runs an action or reads a body (the labs' physics, missions, controls and numbers are
## the same with or without it).
##
## This is the story's data and saved state: the words (content/story.json, each lab's story.clue),
## the marks in the ProgressStore (prologue / finale played, clue told, piece flown) and whether the
## story runs at all (`enabled`: App turns it on for the child's app, never for a measurement or a
## test that does not ask for it). The map's StoryDirector and the lab screen play it.
class_name Story
extends RefCounted

const CONTENT_PATH := "res://content/story.json"
## Who speaks: [name tag, portrait] (DialogueBox.set_speaker).
const SPEAKERS := {
	"dugi": ["두기두기", "res://assets/characters/portraits/dugi_point.webp"],
	"puppy": ["퍼피", "res://assets/characters/portraits/puppy_talk.webp"],
}

## The story plays (App: the child's app; off for measurements, screenshots without --demo-story
## and tests that build screens directly).
static var enabled := false
## App may turn the story on (false: the headless tests' App instances never do; story_checks sets
## `enabled` itself).
static var app_may_enable := true
static var _content: Dictionary = {}


## The story's pages: "prologue" or "finale" -> [{who, text}, ...].
static func pages(part: String) -> Array:
	return _load().get(part, [])


static func _load() -> Dictionary:
	if _content.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
		_content = parsed if parsed is Dictionary else {}
	return _content


## The map plays the prologue when it opens: the story is on and it was never played, or the child
## asked for it again (`replay`, settings 이야기 다시 보기).
static func should_play_prologue(replay := false) -> bool:
	return enabled and (replay or not prologue_seen())


## Puppy's clue for a lab ("" when it has none).
static func clue(definition: Dictionary) -> String:
	return _story_text(definition, "clue")


## Puppy's riddle on the night map while this spot is the next to find ("" when it has none).
static func map_clue(definition: Dictionary) -> String:
	return _story_text(definition, "map_clue")


static func _story_text(definition: Dictionary, key: String) -> String:
	var story: Variant = definition.get("story")
	return str(story.get(key, "")) if story is Dictionary else ""


# --- the night map's exploration (2026-10-28 user-approved: explore the night map in a fixed order) --
# The spots are found one by one in a fixed order (content/story.json `order`). Only the next spot
# (the first in the order whose piece is not found) and the found spots open; Puppy says the next
# one's riddle on the map. Nothing new is saved: all of it follows from the found pieces (stamps), so
# an old save (some spots complete, out of order) works: its found spots are open and lit, the next is
# the first unfound one in the order.

## The fixed order the spots are found in (all 11 spots, each once).
static func order() -> Array:
	var raw: Variant = _load().get("order", [])
	return raw.filter(func(id: Variant) -> bool: return id is String) if raw is Array else []


## The next spot to find: the first in the order whose piece is not found ("" when all are found).
static func next_spot(progress: Dictionary) -> String:
	var done := found(progress)
	for id in order():
		if id not in done:
			return id
	return ""


## The spot opens from the map: its piece is found, or it is the next one.
static func enterable(progress: Dictionary, id: String) -> bool:
	return id in found(progress) or id == next_spot(progress)


## Puppy's line when a locked spot is tapped.
static func wrong_line() -> String:
	return str(_load().get("map_wrong", ""))


## The map's night (StoryDirector: 2 = the dark night after the star broke, 1 = the story's night,
## 0 = day) with `count` pieces at the lookout: the night lifts a step per piece, slowly at first
## (2026-10-28 user: the map should really be dark; with the linear 1 -> 0 the grass read as day and
## 7 pieces as almost day), so the island stays a night island until the last pieces. The last step
## (day) comes with the finale (`finale_done`: day from then on).
const NIGHT_CURVE := 0.7
static func night_level(count: int, finale_done: bool) -> float:
	if finale_done:
		return 0.0
	var total := spots().size()
	var left := 1.0 - float(clampi(count, 0, total - 1)) / total
	return 2.0 * pow(left, NIGHT_CURVE)


## The 11 spots, in the map's order (MapIsland.ZONES).
static func spots() -> Array:
	var out := []
	for zone in MapIsland.ZONES:
		for spot in MapIsland.ZONES[zone].spots:
			out.append(spot[0])
	return out


## The spots whose piece is found: every stage stamped (an old save counts too).
static func found(progress: Dictionary) -> Array:
	return spots().filter(func(id: String) -> bool:
		var stages: Array = MissionTracker.missions(ExperimentRegistry.find(id)).get("stages", [])
		return not stages.is_empty() and ProgressStore.stamps(progress, id) >= stages.size())


## The found pieces already at the lookout (their flight played, or an old save: no flight).
static func placed(progress: Dictionary) -> Array:
	var flying := ProgressStore.pending(ProgressStore.PIECES)
	return found(progress).filter(func(id: String) -> bool: return id not in flying)


## The found pieces whose flight to the lookout is still to play (in the map's order).
static func to_fly(progress: Dictionary) -> Array:
	var flying := ProgressStore.pending(ProgressStore.PIECES)
	return found(progress).filter(func(id: String) -> bool: return id in flying)


static func prologue_seen() -> bool:
	return ProgressStore.mark(ProgressStore.STORY, "prologue")


static func finale_seen() -> bool:
	return ProgressStore.mark(ProgressStore.STORY, "finale")


static func clue_seen(id: String) -> bool:
	return ProgressStore.mark(ProgressStore.CLUES, id)


## A measurement or a device check (the launch args): no story, ever (--progress=bench, --auto-drag,
## --auto-release, --demo-celebrate, --demo-flag, --sound=0). --demo-story turns it on in the bench
## store (App).
static func measurement_run(args: PackedStringArray) -> bool:
	for arg in args:
		for prefix in ["--progress=bench", "--auto-drag=", "--auto-release=", "--demo-celebrate=", "--demo-flag=", "--sound=0"]:
			if arg.begins_with(prefix):
				return true
	return false
