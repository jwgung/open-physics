## Dugi's dialogue (Phase 1 Task 4h, art-direction.md section 12): an old-school game dialogue box in
## the app's storybook look. A cream, slightly see-through rounded box with the characters' brown
## outline runs along the bottom of the 3D view from the left margin up to the action buttons (or to
## Dugi on the view, whichever is nearer); a bust portrait of Dugi always stands on its left end and
## overlaps the top edge (assets/characters/portraits, rendered from the model by
## art_src/characters/dugi_portrait.py), the name tag "두기두기" sits on the top edge beside it,
## and a blinking ▼ shows when the page is fully shown. The portrait's expression follows the line
## (2026-10-29 user request "대화시 표정을 좀 더 다양하게": Story.FACES, set_speaker / open with a face,
## the content tags each line); it never changes within one line (2026-10-27: a face changing every
## page was too busy), a line with the same face keeps the picture as it is (no re-pop), and a new face
## swaps in with a short soft pop (SWAP_S) that changes neither the box nor the portrait's rect.
##
## The words are the lab's observe text exactly (or, for one open, other words of Dugi's: the
## mission's question or the prediction's reason — Plan G4), only split into pages of at most
## LINES lines at the spaces (joined() is the text again). Each page types out at
## CHARS_PER_S; a tap shows the whole page, the next tap turns the page, and after the last page
## it closes. Pages never turn by themselves (2026-10-28 user: only a tap turns a page; before, an
## untouched page turned after READ_S + READ_PER_CHAR_S per character — `auto_turn` keeps that for
## anyone who sets it); a box that holds (`hold`: a question waiting for its answer) stays on its
## last page. UI only:
## no full-screen layer; it takes taps only on the box and the bust (_has_point), the rest of its
## rect passes them to the 3D view.
class_name DialogueBox
extends Control

## Closed (by a tap past the last page, the read timer, or close()).
signal closed

const LINES := 2
const CHARS_PER_S := 28.0
const READ_S := 3.0
const READ_PER_CHAR_S := 0.06
## Whether an untouched page turns after its read time (off: only a tap turns a page).
static var auto_turn := false
const BLINK_HZ := 2.0
const BOX_PAD := Vector2(22.0, 14.0)        # inner padding (x, y)
const NAME_LIFT := 18.0                     # the name tag rises this far above the box
const PORTRAIT_SIZE := 236.0
const PORTRAIT_INSET := 6.0                 # from the box's left end
const PORTRAIT_SHARE := 0.94                # of the portrait's width the words keep clear of (the stick)
const MIN_TEXT_WIDTH := 300.0
const MORE_ROOM := 30.0                     # right of the text: the ▼
## A new face settles in over SWAP_S s: the portrait grows from SWAP_SCALE and fades in from
## SWAP_ALPHA about its bottom middle (drawing only: its rect and the box stay where they are).
const SWAP_S := 0.16
const SWAP_SCALE := 0.94
const SWAP_ALPHA := 0.55
static var _textures := {}

var text := ""
## Who speaks now (Story.SPEAKERS: "dugi" by default, "puppy" for his clues and story lines).
var speaker := "dugi"
## The face shown now (Story.FACES) and the face of the box's own words (set_words).
var face := Story.DEFAULT_FACE
var words_face := ""
## Portrait pictures swapped in (a new speaker or face; tests: a same-face line swaps nothing).
var swaps := 0
var _swap_t := -1.0
## The box's own words (the lab's observe text): every open without other words shows these.
var words := ""
## A question is waiting for its answer: the last page stays (no read timer, a tap does not close).
var hold := false
var box: PanelContainer
var name_tag: PanelContainer
var name_label: Label
var label: Label
var more: Label
var portrait: TextureRect
var active := false
var page := 0
## [page text, separator before the next page] for the current width.
var _pages: Array = []
var _shown := 0.0                           # characters of the page shown (typewriter)
var _read_left := 0.0
var _clock := 0.0
var _text_width := 0.0


func _init(own_words: String) -> void:
	name = "DialogueBox"
	words = own_words
	text = own_words
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	box = Ui.panel("DialogueBox")
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	label = Ui.label("", "DialogueLabel")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(label)
	more = Ui.label("▼", "DialogueMoreLabel")
	more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(more)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = portrait_texture(speaker, face)
	add_child(portrait)
	name_tag = Ui.panel("DialogueNameTag")
	name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_tag)
	name_label = Ui.label("두기두기", "DialogueNameLabel")
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_tag.add_child(name_label)


# --- pages ----------------------------------------------------------------------------------------

## The lines of `words` at most `width` wide in `font` / `size`, broken at spaces (a word wider than
## the line is broken between characters): [[line, separator after it], ...].
static func wrap_lines(words: String, font: Font, size: int, width: float) -> Array:
	var out := []
	var line := ""
	var tokens := words.split(" ")
	for t in tokens:
		var candidate := t if line == "" else line + " " + t
		if line != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			out.append([line, " "])
			line = t
		else:
			line = candidate
		# A single word wider than the line: break it between characters.
		while font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and line.length() > 1:
			var cut := line.length() - 1
			while cut > 1 and font.get_string_size(line.substr(0, cut), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				cut -= 1
			out.append([line.substr(0, cut), ""])
			line = line.substr(cut)
	if line != "":
		out.append([line, ""])
	return out


## Pages of at most LINES lines: [{"lines": [...], "seps": [separator after each line]}, ...].
static func paginate(words: String, font: Font, size: int, width: float) -> Array:
	var lines := wrap_lines(words, font, size, width)
	var out := []
	for k in range(0, lines.size(), LINES):
		var chunk: Array = lines.slice(k, k + LINES)
		out.append({"lines": chunk.map(func(l: Array) -> String: return l[0]), "seps": chunk.map(func(l: Array) -> String: return l[1])})
	return out


## The pages for the current layout (tests).
func pages() -> Array:
	return _pages


## A page as shown (its lines one under the other).
func page_text(k: int) -> String:
	return "\n".join(PackedStringArray(_pages[k].lines))


## The pages joined back with the separators they were split at (tests: == text).
func joined() -> String:
	var s := ""
	for p in _pages:
		for j in p.lines.size():
			s += p.lines[j] + p.seps[j]
	return s


# --- layout -----------------------------------------------------------------------------------

## Lays the box out inside `view` (local units): from the left margin to `right` (the action buttons'
## or Dugi's left edge), bottom-aligned, the portrait always on its left end. What Dugi points at is
## kept uncovered by the experiments' placements (the target stays above the box: tests check it
## over a whole run in every experiment), not by moving the box. Returns false when the room is too
## narrow (then it hides).
func layout(view: Rect2, right: float, margin: float) -> bool:
	var font := label.get_theme_font("font")
	var size_px := label.get_theme_font_size("font_size")
	var line_h := font.get_height(size_px) + label.get_theme_constant("line_spacing")
	var box_style := box.get_theme_stylebox("panel")
	var height := BOX_PAD.y * 2.0 + line_h * LINES + box_style.get_minimum_size().y
	var left := view.position.x + margin
	var width := right - margin - left
	var text_width := width - BOX_PAD.x * 2.0 - PORTRAIT_SIZE * PORTRAIT_SHARE - box_style.get_minimum_size().x - MORE_ROOM
	if text_width < MIN_TEXT_WIDTH:
		return false
	var top := view.end.y - margin - height
	var origin := Vector2(left, top - (PORTRAIT_SIZE - height))
	box.position = Vector2(0.0, PORTRAIT_SIZE - height)
	box.size = Vector2(width, height)
	position = origin
	size = Vector2(width, PORTRAIT_SIZE)
	portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	var inset := BOX_PAD.x + box_style.get_margin(SIDE_LEFT)
	portrait.position = Vector2(PORTRAIT_INSET, 0.0)
	var text_left := PORTRAIT_INSET + PORTRAIT_SIZE * PORTRAIT_SHARE + BOX_PAD.x
	label.position = box.position + Vector2(text_left, BOX_PAD.y + box_style.get_margin(SIDE_TOP))
	more.position = Vector2(label.position.x + text_width + 6.0, box.position.y + height - BOX_PAD.y - more.get_minimum_size().y)
	name_tag.position = Vector2(text_left - 4.0, box.position.y - NAME_LIFT)
	label.size = Vector2(text_width, line_h * LINES)
	name_tag.size = name_tag.get_combined_minimum_size()
	if not is_equal_approx(text_width, _text_width):
		_text_width = text_width
		_pages = paginate(text, font, size_px, text_width)
		page = mini(page, maxi(0, _pages.size() - 1))
		_show_page(false)
	return true


## The box's and the portrait's rects in the parent (the view), for the overlap rules (tests).
func rects() -> Array[Rect2]:
	return [Rect2(position + box.position, box.size), Rect2(position + portrait.position, portrait.size)]


# --- acting -----------------------------------------------------------------------------------

## The portrait picture of `who` with `face` (loaded once).
static func portrait_texture(who: String, with_face: String) -> Texture2D:
	var path := Story.portrait_path(who, with_face)
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


## Who speaks (Story.SPEAKERS id) and with which face (Story.FACES; "" or unknown = the default): the
## portrait and the name tag change, the box stays where it is (the story "별 조각 찾기", 2026-10-28:
## Puppy tells his clues in the same box). The same speaker and face change nothing.
func set_speaker(who: String, new_face := "") -> void:
	if not Story.SPEAKERS.has(who):
		return
	var f := Story.face_or_default(new_face)
	if who == speaker and f == face:
		return
	speaker = who
	face = f
	name_label.text = Story.SPEAKERS[who][0]
	portrait.texture = portrait_texture(who, f)
	name_tag.size = name_tag.get_combined_minimum_size()
	swaps += 1
	if active:
		_swap_t = 0.0   # the soft pop (a closed box just shows the new face when it opens)
		_draw_swap()


## Replaces the box's own words (the words of every later open without other words) and their face.
func set_words(new_words: String, new_face := "") -> void:
	words = new_words
	words_face = new_face
	_set_text(new_words)


## Opens at the first page (laid out by the caller first). `once` (optional): other words for this
## open only (the prediction's question or reason, Plan G4), with `once_face` (optional: else the
## face set before, set_speaker); the next open shows the box's own words (and their face) again.
func open(once := "", once_face := "") -> void:
	if once == "":
		set_speaker(speaker, words_face)
	elif once_face != "":
		set_speaker(speaker, once_face)
	_set_text(once if once != "" else words)
	active = true
	page = 0
	_show_page(true)


func _set_text(new_text: String) -> void:
	if new_text == text and not _pages.is_empty():
		return
	text = new_text
	_pages = paginate(text, label.get_theme_font("font"), label.get_theme_font_size("font_size"),
		_text_width if _text_width > 0.0 else MIN_TEXT_WIDTH)
	page = 0


## Closes (instant: no `closed` signal, the caller is closing it).
func close(quiet := false) -> void:
	if not active:
		return
	active = false
	visible = false
	_swap_t = -1.0
	_draw_swap()   # a pop cut short ends on the whole picture
	if not quiet:
		closed.emit()


## The page is fully shown (the ▼ blinks).
func typed() -> bool:
	return _pages.is_empty() or _shown >= page_text(page).length()


## A tap: the whole page, else the next page, else close.
func advance() -> void:
	if not active:
		return
	if not typed():
		_shown = page_text(page).length()
		_read_left = _read_time()
	elif page < _pages.size() - 1:
		page += 1
		_show_page(true)
	elif not hold:
		close()
	_refresh()


func _show_page(restart: bool) -> void:
	if restart:
		_shown = 0.0
	_read_left = _read_time()
	_refresh()


func _read_time() -> float:
	return READ_S + READ_PER_CHAR_S * (page_text(page).length() if not _pages.is_empty() else 0)


func _refresh() -> void:
	if _pages.is_empty():
		return
	label.text = page_text(page)
	label.visible_characters = int(_shown) if not typed() else -1
	# A held question's last page waits for an answer, not a tap: no ▼ there.
	var waits := hold and page == _pages.size() - 1
	more.visible = typed() and not waits and fmod(_clock * BLINK_HZ, 1.0) < 0.6


func _process(delta: float) -> void:
	step(delta)


## Moves the typewriter and the read timer on by `delta` s (tests call it with exact steps).
func step(delta: float) -> void:
	if not active:
		return
	_clock += delta
	if _swap_t >= 0.0:
		_swap_t += delta
		_draw_swap()
	if not typed():
		_shown += CHARS_PER_S * delta
	elif auto_turn and (not hold or page < _pages.size() - 1):
		_read_left -= delta
		if _read_left <= 0.0:
			advance()
			return
	_refresh()


## The swap's pop now (the portrait's scale and alpha only).
func _draw_swap() -> void:
	var k := clampf(_swap_t / SWAP_S, 0.0, 1.0) if _swap_t >= 0.0 else 1.0
	if k >= 1.0:
		_swap_t = -1.0
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	portrait.pivot_offset = Vector2(PORTRAIT_SIZE * 0.5, PORTRAIT_SIZE)
	portrait.scale = Vector2.ONE * lerpf(SWAP_SCALE, 1.0, e)
	portrait.modulate.a = lerpf(SWAP_ALPHA, 1.0, e)


## Takes input only where it is drawn: the box and the portrait's lower two thirds (the bust; the
## ears and the empty corners above the box let taps and gestures through to the 3D view).
func _has_point(point: Vector2) -> bool:
	if not active:
		return false
	if Rect2(box.position, box.size).has_point(point):
		return true
	var bust := Rect2(portrait.position + Vector2(PORTRAIT_SIZE * 0.2, PORTRAIT_SIZE * 0.35), Vector2(PORTRAIT_SIZE * 0.6, PORTRAIT_SIZE * 0.65))
	return bust.has_point(point)


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
			and event.device != InputEvent.DEVICE_ID_EMULATION)   # a touch's emulated click: one tap, one page
	if tap and active:
		advance()
		accept_event()
