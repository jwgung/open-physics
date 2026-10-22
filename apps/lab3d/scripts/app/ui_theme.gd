## Godot Theme for the grass island style (Phase 1 Task 2c, apps/lab3d/docs/art-direction.md
## section 7): the web 2D app's layout and widget set (src/app/style.css: cards, chips, tiles, primary
## button) in the island palette (ArtPalette): navy ink, sky-tinted paper, blue primary buttons with
## a darker bottom lip (a chunky toy button), yellow selection, rounder corners (14-18 units).
## Sizes are UI units: the shorter screen side is 720 units (project.godot), so 22 units on a
## 1200 px wide SM-P200 are 37 px.
class_name UiTheme
extends RefCounted

const INK := ArtPalette.INK
const MUTED := ArtPalette.MUTED
const SUBTLE := ArtPalette.INK_SOFT
const LINE := ArtPalette.LINE
const ACCENT := ArtPalette.BLUE
const ACCENT_DARK := ArtPalette.BLUE_DARK
const SELECT := ArtPalette.YELLOW
const SELECT_LINE := ArtPalette.YELLOW_DARK
const GREEN := ArtPalette.GRASS
const GREEN_SOFT := ArtPalette.GREEN_SOFT
const GREEN_TEXT := ArtPalette.GREEN_TEXT
const BACKGROUND := ArtPalette.PAPER
const SURFACE := Color("fbfdff")
const WHITE := Color("ffffff")
const CODE_BG := Color("e8f1ff")
const CODE_TEXT := ArtPalette.BLUE_DARK
## Bottom "lip" of buttons and cards (units): the darker edge that makes them look pressable.
const LIP := 5
const CARD_LIP := 3

const FONT_REGULAR := "res://assets/fonts/NotoSansKR-Lab3dSubset-Regular.otf"
const FONT_BOLD := "res://assets/fonts/NotoSansKR-Lab3dSubset-Bold.otf"
## Symbols Noto Sans CJK lacks (x₀, ⚖ …): DejaVu Sans subsets, the fallback of each face (Task 4a).
const FONT_SYMBOLS_REGULAR := "res://assets/fonts/Lab3dSymbols-Regular.ttf"
const FONT_SYMBOLS_BOLD := "res://assets/fonts/Lab3dSymbols-Bold.ttf"

const SIZE_BODY := 22
const SIZE_SMALL := 19
const SIZE_TITLE := 32
const SIZE_HEADING := 26


static func bold_font() -> Font:
	return _with_symbols(FONT_BOLD, FONT_SYMBOLS_BOLD)


static func regular_font() -> Font:
	return _with_symbols(FONT_REGULAR, FONT_SYMBOLS_REGULAR)


## The Hangul face with the symbol subset as its fallback (set once on the cached resource).
static func _with_symbols(path: String, symbols: String) -> Font:
	var font: Font = load(path)
	if font.fallbacks.is_empty():
		font.fallbacks = [load(symbols)]
	return font


static func build() -> Theme:
	var theme := Theme.new()
	var regular := regular_font()
	var bold := bold_font()
	theme.default_font = regular
	theme.default_font_size = SIZE_BODY

	# Labels
	theme.set_color("font_color", "Label", INK)
	_label_variation(theme, "MutedLabel", regular, SIZE_SMALL, MUTED)
	_label_variation(theme, "EyebrowLabel", bold, 17, ACCENT)
	_label_variation(theme, "TitleLabel", bold, SIZE_TITLE, INK)
	_label_variation(theme, "HeadingLabel", bold, SIZE_HEADING, INK)
	_label_variation(theme, "SectionLabel", bold, SIZE_SMALL, SUBTLE)
	_label_variation(theme, "ValueLabel", bold, 25, INK)
	_label_variation(theme, "ObserveLabel", regular, SIZE_SMALL, GREEN_TEXT)
	_label_variation(theme, "ObserveTitleLabel", bold, 17, GREEN_TEXT)
	_label_variation(theme, "EquationLabel", bold, 20, CODE_TEXT)
	theme.set_stylebox("normal", "EquationLabel", _box(CODE_BG, Color.TRANSPARENT, 10, 12, 6))
	_label_variation(theme, "StepNumberLabel", bold, 17, INK)
	theme.set_stylebox("normal", "StepNumberLabel", _box(SELECT, Color.TRANSPARENT, 10, 10, 2))
	_label_variation(theme, "HintLabel", bold, 18, SUBTLE)
	theme.set_stylebox("normal", "HintLabel", _box(Color(1, 1, 1, 0.92), Color.TRANSPARENT, 14, 12, 8))
	_label_variation(theme, "FpsLabel", bold, 18, WHITE)
	theme.set_stylebox("normal", "FpsLabel", _box(Color(0.09, 0.14, 0.23, 0.78), Color.TRANSPARENT, 8, 10, 4))
	_label_variation(theme, "BadgeLabel", bold, 26, WHITE)

	# Panels: white cards with a soft blue lip.
	theme.set_stylebox("panel", "PanelContainer", _box(WHITE, LINE, 18, 18, 16, Color.TRANSPARENT, 2, CARD_LIP))

	_panel_variation(theme, "SoftCard", _box(SURFACE, Color("dbe7f3"), 14, 16, 14))
	_panel_variation(theme, "ObserveCard", _box(GREEN_SOFT, Color.TRANSPARENT, 14, 16, 12))
	_panel_variation(theme, "Tile", _box(Color("f5faff"), Color("dfeaf5"), 12, 12, 10))
	# No fill: the clear color shows through (each full-screen layer costs fill rate on low-end GPUs).
	_panel_variation(theme, "SideSheet", StyleBoxEmpty.new())
	_panel_variation(theme, "TopBar", _box(WHITE, Color.TRANSPARENT, 0, 16, 8, LINE))
	_panel_variation(theme, "IconBadge", _box(ACCENT, Color.TRANSPARENT, 16, 12, 8, Color.TRANSPARENT, 0, LIP, ACCENT_DARK))
	_panel_variation(theme, "ViewOverlay", _box(Color(1, 1, 1, 0.9), Color.TRANSPARENT, 16, 6, 6))

	# Buttons: white with a grey-blue lip; pressed = the lip shrinks (the button sinks).
	theme.set_font_size("font_size", "Button", 21)
	theme.set_font("font", "Button", bold)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_hover_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color(0.11, 0.16, 0.29, 0.4))
	_button_states(theme, "Button", WHITE, Color("f4f9ff"), Color("eef5ff"), LINE, Color("b9cde2"), 14, 16, 10)
	theme.set_stylebox("disabled", "Button", _box(Color("f2f6fa"), Color("e1e9f2"), 14, 16, 10, Color.TRANSPARENT, 2, LIP))
	theme.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, Color("8fb6ff"), 14, 16, 10, Color.TRANSPARENT, 2))

	theme.set_type_variation("PrimaryButton", "Button")
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, "PrimaryButton", WHITE)
	_button_states(theme, "PrimaryButton", ACCENT, Color("3a87ff"), Color("2a72e6"), ACCENT_DARK, ACCENT_DARK, 14, 18, 10)
	theme.set_stylebox("disabled", "PrimaryButton", _box(Color("a9c6f5"), Color("8fb0e8"), 14, 18, 10, Color.TRANSPARENT, 2, LIP))

	# Chips: the selected one turns yellow (the style's selection colour).
	theme.set_type_variation("ChipButton", "Button")
	theme.set_font_size("font_size", "ChipButton", 19)
	theme.set_color("font_pressed_color", "ChipButton", INK)
	theme.set_color("font_hover_pressed_color", "ChipButton", INK)
	theme.set_stylebox("normal", "ChipButton", _box(WHITE, LINE, 12, 12, 8, Color.TRANSPARENT, 2, 4))
	theme.set_stylebox("hover", "ChipButton", _box(Color("f4f9ff"), Color("b9cde2"), 12, 12, 8, Color.TRANSPARENT, 2, 4))
	var chip_on := _box(SELECT, SELECT_LINE, 12, 12, 8, Color.TRANSPARENT, 2, 4)
	theme.set_stylebox("pressed", "ChipButton", chip_on)
	theme.set_stylebox("hover_pressed", "ChipButton", chip_on)
	theme.set_stylebox("disabled", "ChipButton", _box(Color("f2f6fa"), Color("e1e9f2"), 12, 12, 8, Color.TRANSPARENT, 2, 4))

	theme.set_type_variation("FlatButton", "Button")
	theme.set_color("font_color", "FlatButton", ACCENT)
	theme.set_color("font_pressed_color", "FlatButton", ACCENT_DARK)
	theme.set_color("font_hover_color", "FlatButton", ACCENT_DARK)
	var flat := _box(Color.TRANSPARENT, Color.TRANSPARENT, 12, 12, 8)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		theme.set_stylebox(state, "FlatButton", flat)
	theme.set_stylebox("disabled", "FlatButton", flat)   # same margins as the others; only the font fades
	theme.set_color("font_disabled_color", "FlatButton", Color(ACCENT, 0.4))

	# Slider: 12-unit blue track, 42-unit yellow grabber with a white ring (touch friendly).
	theme.set_stylebox("slider", "HSlider", _box(Color("dce8f4"), Color.TRANSPARENT, 6, 0, 6))
	theme.set_stylebox("grabber_area", "HSlider", _box(ACCENT, Color.TRANSPARENT, 6, 0, 6))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, Color.TRANSPARENT, 6, 0, 6))
	theme.set_icon("grabber", "HSlider", _circle_texture(42, SELECT, WHITE, ACCENT_DARK))
	theme.set_icon("grabber_highlight", "HSlider", _circle_texture(42, ArtPalette.YELLOW_TOP, WHITE, ACCENT_DARK))
	theme.set_constant("center_grabber", "HSlider", 1)

	# Scroll bars: thin, like the web panels.
	theme.set_stylebox("scroll", "VScrollBar", _box(Color.TRANSPARENT, Color.TRANSPARENT, 4, 0, 0))
	theme.set_stylebox("grabber", "VScrollBar", _box(Color("b5c7da"), Color.TRANSPARENT, 4, 4, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(Color("97abc1"), Color.TRANSPARENT, 4, 4, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _box(Color("8399b1"), Color.TRANSPARENT, 4, 4, 0))
	theme.set_font_size("font_size", "CheckButton", SIZE_BODY)
	return theme


## normal / hover / pressed / hover_pressed of a lipped button (border = lip colour). Pressed: the
## whole face (fill, top edge and content) moves down by the lip it gives up, so the button looks
## pushed in and its size does not change. The disabled boxes keep the same vertical margins as the
## normal one (same lip height) so the text does not move when a button is enabled or disabled.
static func _button_states(theme: Theme, type: String, normal: Color, hover: Color, pressed: Color,
		line: Color, hover_line: Color, radius: int, margin_x: float, margin_y: float) -> void:
	theme.set_stylebox("normal", type, _box(normal, line, radius, margin_x, margin_y, Color.TRANSPARENT, 2, LIP))
	theme.set_stylebox("hover", type, _box(hover, hover_line, radius, margin_x, margin_y, Color.TRANSPARENT, 2, LIP))
	var down := _box(pressed, hover_line, radius, margin_x, margin_y, Color.TRANSPARENT, 2, 2)
	down.content_margin_top += LIP - 2
	down.expand_margin_top = -(LIP - 2)
	theme.set_stylebox("pressed", type, down)
	theme.set_stylebox("hover_pressed", type, down)


static func _label_variation(theme: Theme, name: String, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)


static func _panel_variation(theme: Theme, name: String, box: StyleBox) -> void:
	theme.set_type_variation(name, "PanelContainer")
	theme.set_stylebox("panel", name, box)


## Rounded box. `bottom_line` draws only a bottom border (top bars); `border` overrides width.
## `lip` > 0 makes the bottom border that thick: the toy-button edge. Without a `line`, the lip
## alone is drawn in `lip_color`. The bottom content margin grows by the lip so the text stays
## centred on the face.
static func _box(bg: Color, line: Color, radius: int, margin_x: float, margin_y: float,
		bottom_line := Color.TRANSPARENT, border := 1, lip := 0, lip_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	box.anti_aliasing = true
	if line.a > 0.0:
		box.border_color = line
		box.set_border_width_all(border)
	elif bottom_line.a > 0.0:
		box.border_color = bottom_line
		box.border_width_bottom = 1
	if lip > 0:
		if line.a <= 0.0:
			box.border_color = lip_color
		box.border_width_bottom = lip
		box.content_margin_bottom = margin_y + lip - (border if line.a > 0.0 else 0)
	return box


static func _circle_texture(size: int, fill: Color, ring: Color, edge := Color.TRANSPARENT) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var outer := size * 0.5 - 1.0
	var inner := outer - 4.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var color := ring if d > inner else fill
			if edge.a > 0.0 and d > outer - 1.5:
				color = edge
			color.a *= clampf(outer - d + 0.5, 0.0, 1.0)  # 1 px anti-aliased edge
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
