## Design tokens and the global Theme. Derived from the OST logo: black night sky, thin
## white lines, serif titles (CMU Serif), amber for actions, cyan for science/data.
class_name UiTheme
extends RefCounted

const BG := Color("05060c")
const SURFACE := Color(0.06, 0.07, 0.13, 0.88)
const SURFACE_HI := Color(0.11, 0.12, 0.2, 0.95)
const LINE := Color(1, 1, 1, 0.16)
const TEXT := Color("f4f1ea")
const TEXT_DIM := Color("a8adbd")
const ACCENT := Color("ffb347")
const ACCENT_HI := Color("ffcf86")
const SCIENCE := Color("4dd0e1")
const SUCCESS := Color("7ee08a")
const DANGER := Color("ff6b6b")

const RADIUS := 28
const TOUCH_MIN := 96
const SIZE_SMALL := 28
const SIZE_BODY := 34
const SIZE_BUTTON := 38
const SIZE_H2 := 56
const SIZE_TITLE := 104

const FONT_DIR := "res://assets/fonts/"

static var _fonts := {}


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var file: String = {
		"regular": "inter/Inter_18pt-Regular.ttf",
		"medium": "inter/Inter_18pt-Medium.ttf",
		"semibold": "inter/Inter_18pt-SemiBold.ttf",
		"bold": "inter/Inter_24pt-Bold.ttf",
		"serif": "cmu/cmunrm.otf",
		"serif_bold": "cmu/cmunbx.otf",
		"serif_italic": "cmu/cmunti.otf",
		"icons": "icons/MaterialIcons-Regular.ttf",
	}[kind]
	var f: Font = load(FONT_DIR + file)
	if kind != "icons":
		# Icon glyphs (private use area) fall back to Material Icons, so " Home" works.
		f.fallbacks = [font("icons")]
	_fonts[kind] = f
	return f


static func box(bg: Color, border := LINE, border_w := 2, radius := RADIUS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(24)
	s.anti_aliasing = true
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = SIZE_BODY

	t.set_color("font_color", "Label", TEXT)

	t.set_font("font", "Button", font("semibold"))
	t.set_font_size("font_size", "Button", SIZE_BUTTON)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", BG)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_constant("h_separation", "Button", 18)
	t.set_stylebox("normal", "Button", box(SURFACE))
	t.set_stylebox("hover", "Button", box(SURFACE_HI, Color(ACCENT, 0.6)))
	t.set_stylebox("pressed", "Button", box(ACCENT, ACCENT_HI))
	t.set_stylebox("disabled", "Button", box(Color(SURFACE, 0.5), Color(LINE, 0.08)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	t.set_stylebox("panel", "PanelContainer", box(SURFACE))
	t.set_stylebox("panel", "Panel", box(SURFACE))

	t.set_font("font", "LineEdit", font("medium"))
	t.set_font_size("font_size", "LineEdit", SIZE_H2)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.5), Color(ACCENT, 0.7)))
	t.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())

	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, ACCENT, 0, 8))
	t.set_stylebox("slider", "HSlider", box(LINE, LINE, 0, 8))
	return t


## Label helpers so every screen uses the same typography.
static func label(text: String, size := SIZE_BODY, kind := "regular", color := TEXT) -> Label:
	var l := Label.new()
	# Explicit, because labels inside buttons would inherit the button's "disabled".
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func icon(icon_name: String, size := 64, color := TEXT) -> Label:
	var l := label(Icons.get_char(icon_name), size, "icons", color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
