## Godot Theme carrying the web 2D app's look (src/app/style.css tokens: ink, muted, line, accent,
## orange, green; white cards on #eef2f7 with 1 px #dce3ed borders and 10-14 px radii).
## Sizes are UI units: the shorter screen side is 720 units (project.godot), so 22 units on a
## 1200 px wide SM-P200 are 37 px.
class_name UiTheme
extends RefCounted

const INK := Color("1d2940")
const INK_STRONG := Color("17243b")
const MUTED := Color("718099")
const SUBTLE := Color("536078")
const LINE := Color("dce3ed")
const ACCENT := Color("365eea")
const ACCENT_SOFT := Color("eef3ff")
const ACCENT_LINE := Color("5575e8")
const ORANGE := Color("ef7754")
const GREEN := Color("209a71")
const GREEN_SOFT := Color("e7f7f0")
const GREEN_TEXT := Color("3e6f60")
const BACKGROUND := Color("eef2f7")
const SURFACE := Color("fbfcff")
const WHITE := Color("ffffff")
const CODE_BG := Color("eef2fa")
const CODE_TEXT := Color("405fc5")

const FONT_REGULAR := "res://assets/fonts/NotoSansKR-Lab3dSubset-Regular.otf"
const FONT_BOLD := "res://assets/fonts/NotoSansKR-Lab3dSubset-Bold.otf"

const SIZE_BODY := 22
const SIZE_SMALL := 19
const SIZE_TITLE := 32
const SIZE_HEADING := 26


static func bold_font() -> Font:
	return load(FONT_BOLD)


static func build() -> Theme:
	var theme := Theme.new()
	var regular: Font = load(FONT_REGULAR)
	var bold := bold_font()
	theme.default_font = regular
	theme.default_font_size = SIZE_BODY

	# Labels
	theme.set_color("font_color", "Label", INK)
	_label_variation(theme, "MutedLabel", regular, SIZE_SMALL, MUTED)
	_label_variation(theme, "EyebrowLabel", bold, 17, ACCENT)
	_label_variation(theme, "TitleLabel", bold, SIZE_TITLE, INK_STRONG)
	_label_variation(theme, "HeadingLabel", bold, SIZE_HEADING, INK_STRONG)
	_label_variation(theme, "SectionLabel", bold, SIZE_SMALL, SUBTLE)
	_label_variation(theme, "ValueLabel", bold, 25, INK_STRONG)
	_label_variation(theme, "ObserveLabel", regular, SIZE_SMALL, GREEN_TEXT)
	_label_variation(theme, "ObserveTitleLabel", bold, 17, Color("167657"))
	_label_variation(theme, "EquationLabel", bold, 20, CODE_TEXT)
	theme.set_stylebox("normal", "EquationLabel", _box(CODE_BG, Color.TRANSPARENT, 8, 10, 6))
	_label_variation(theme, "StepNumberLabel", bold, 17, ACCENT)
	theme.set_stylebox("normal", "StepNumberLabel", _box(Color("e8eeff"), Color.TRANSPARENT, 8, 9, 2))
	_label_variation(theme, "HintLabel", bold, 18, Color("4c5c73"))
	theme.set_stylebox("normal", "HintLabel", _box(Color(1, 1, 1, 0.92), Color("d9e1ee"), 10, 12, 8))
	_label_variation(theme, "FpsLabel", bold, 18, WHITE)
	theme.set_stylebox("normal", "FpsLabel", _box(Color(0.09, 0.14, 0.23, 0.78), Color.TRANSPARENT, 8, 10, 4))

	# Panels
	theme.set_stylebox("panel", "PanelContainer", _box(WHITE, LINE, 14, 18, 16))

	_panel_variation(theme, "SoftCard", _box(Color("fafbfd"), Color("dfe5ef"), 12, 16, 14))
	_panel_variation(theme, "ObserveCard", _box(GREEN_SOFT, Color.TRANSPARENT, 12, 16, 12))
	_panel_variation(theme, "Tile", _box(Color("f8faff"), Color("e3e8f0"), 10, 12, 10))
	# No fill: the clear color shows through (each full-screen layer costs fill rate on low-end GPUs).
	_panel_variation(theme, "SideSheet", StyleBoxEmpty.new())
	_panel_variation(theme, "TopBar", _box(WHITE, Color.TRANSPARENT, 0, 16, 8, Color("dfe5ee")))
	_panel_variation(theme, "IconBadge", _box(Color("e8efff"), Color.TRANSPARENT, 12, 12, 6))
	_panel_variation(theme, "ViewOverlay", _box(Color(1, 1, 1, 0.88), Color("d6dedf"), 12, 6, 6))

	# Buttons
	theme.set_font_size("font_size", "Button", 21)
	theme.set_font("font", "Button", bold)
	theme.set_color("font_color", "Button", Color("354259"))
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_hover_pressed_color", "Button", ACCENT)
	theme.set_color("font_focus_color", "Button", Color("354259"))
	theme.set_color("font_disabled_color", "Button", Color(0.21, 0.26, 0.35, 0.45))
	theme.set_stylebox("normal", "Button", _box(WHITE, Color("d6deea"), 10, 16, 10))
	theme.set_stylebox("hover", "Button", _box(Color("f5f7fb"), Color("b8c5d8"), 10, 16, 10))
	theme.set_stylebox("pressed", "Button", _box(ACCENT_SOFT, ACCENT_LINE, 10, 16, 10, Color.TRANSPARENT, 2))
	theme.set_stylebox("hover_pressed", "Button", _box(ACCENT_SOFT, ACCENT_LINE, 10, 16, 10, Color.TRANSPARENT, 2))
	theme.set_stylebox("disabled", "Button", _box(Color("f5f7fb"), Color("e1e7f0"), 10, 16, 10))
	theme.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, Color("91a8ff"), 10, 16, 10, Color.TRANSPARENT, 2))

	theme.set_type_variation("PrimaryButton", "Button")
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, "PrimaryButton", WHITE)
	theme.set_stylebox("normal", "PrimaryButton", _box(ACCENT, ACCENT, 10, 18, 10))
	theme.set_stylebox("hover", "PrimaryButton", _box(Color("2749c8"), Color("2749c8"), 10, 18, 10))
	theme.set_stylebox("pressed", "PrimaryButton", _box(Color("2749c8"), Color("2749c8"), 10, 18, 10))
	theme.set_stylebox("hover_pressed", "PrimaryButton", _box(Color("2749c8"), Color("2749c8"), 10, 18, 10))

	theme.set_type_variation("ChipButton", "Button")
	theme.set_font_size("font_size", "ChipButton", 19)
	theme.set_stylebox("normal", "ChipButton", _box(WHITE, Color("d4ddeb"), 9, 12, 8))
	theme.set_stylebox("hover", "ChipButton", _box(Color("f5f7fb"), Color("b8c5d8"), 9, 12, 8))
	theme.set_stylebox("pressed", "ChipButton", _box(ACCENT_SOFT, ACCENT_LINE, 9, 12, 8, Color.TRANSPARENT, 2))
	theme.set_stylebox("hover_pressed", "ChipButton", _box(ACCENT_SOFT, ACCENT_LINE, 9, 12, 8, Color.TRANSPARENT, 2))

	theme.set_type_variation("FlatButton", "Button")
	theme.set_color("font_color", "FlatButton", ACCENT)
	var flat := _box(Color.TRANSPARENT, Color.TRANSPARENT, 10, 12, 8)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		theme.set_stylebox(state, "FlatButton", flat)

	# Slider: 10-unit track, 40-unit round grabber (touch friendly).
	theme.set_stylebox("slider", "HSlider", _box(Color("e1e7f0"), Color.TRANSPARENT, 5, 0, 5))
	theme.set_stylebox("grabber_area", "HSlider", _box(Color("8ca5ff"), Color.TRANSPARENT, 5, 0, 5))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, Color.TRANSPARENT, 5, 0, 5))
	theme.set_icon("grabber", "HSlider", _circle_texture(40, ACCENT, WHITE))
	theme.set_icon("grabber_highlight", "HSlider", _circle_texture(40, Color("2749c8"), WHITE))
	theme.set_constant("center_grabber", "HSlider", 1)

	# Scroll bars: thin, like the web panels.
	theme.set_stylebox("scroll", "VScrollBar", _box(Color.TRANSPARENT, Color.TRANSPARENT, 4, 0, 0))
	theme.set_stylebox("grabber", "VScrollBar", _box(Color("b8c3d3"), Color.TRANSPARENT, 4, 4, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(Color("9aa7ba"), Color.TRANSPARENT, 4, 4, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _box(Color("8793a5"), Color.TRANSPARENT, 4, 4, 0))
	theme.set_font_size("font_size", "CheckButton", SIZE_BODY)
	return theme


static func _label_variation(theme: Theme, name: String, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)


static func _panel_variation(theme: Theme, name: String, box: StyleBox) -> void:
	theme.set_type_variation(name, "PanelContainer")
	theme.set_stylebox("panel", name, box)


## Rounded box. `bottom_line` draws only a bottom border (top bars); `border` overrides width.
static func _box(bg: Color, line: Color, radius: int, margin_x: float, margin_y: float,
		bottom_line := Color.TRANSPARENT, border := 1) -> StyleBoxFlat:
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
	return box


static func _circle_texture(size: int, fill: Color, ring: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var outer := size * 0.5 - 1.0
	var inner := outer - 4.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var color := ring if d > inner else fill
			color.a *= clampf(outer - d + 0.5, 0.0, 1.0)  # 1 px anti-aliased edge
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
