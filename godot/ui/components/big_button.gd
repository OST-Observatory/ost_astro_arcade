## Large touch button: optional icon + translated text, press animation and tap sound.
## Icon and text are separate labels (the text font must not be relied on for icon
## code points: Inter defines some private-use glyphs itself).
class_name BigButton
extends Button

const PAD := 36

var text_key := ""
var icon_name := ""
var sound := "tap"
var icon_size := 0  # 0 = derived from the font size

var _row: HBoxContainer
var _icon: Label
var _label: Label
var _min_width := 0


static func make(key: String, icon := "", accent := false, min_width := 0) -> BigButton:
	var b := BigButton.new()
	b.text_key = key
	b.icon_name = icon
	b._min_width = min_width
	if accent:
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.ACCENT, 0.9), UiTheme.ACCENT_HI))
		b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.ACCENT_HI, UiTheme.ACCENT_HI))
		b.add_theme_color_override("font_color", UiTheme.BG)
		b.add_theme_color_override("font_hover_color", UiTheme.BG)
	return b


func _ready() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	focus_mode = Control.FOCUS_NONE
	text = ""
	var fsize := get_theme_font_size("font_size")
	var col := get_theme_color("font_color")
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 18)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)
	if icon_name != "":
		_icon = UiTheme.icon(icon_name, icon_size if icon_size > 0 else int(fsize * 1.25), col)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(_icon)
	_label = UiTheme.label("", fsize, "semibold", col)
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_label)
	_refresh_text()
	resized.connect(func(): pivot_offset = size / 2.0)
	button_down.connect(func(): _bounce(0.95))
	button_up.connect(func(): _bounce(1.0))
	pressed.connect(func(): Audio.play(sound))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _label != null:
		_refresh_text()


func set_key(key: String) -> void:
	text_key = key
	_refresh_text()


func _refresh_text() -> void:
	_label.text = tr(text_key) if text_key != "" else ""
	_label.visible = _label.text != ""
	var w := maxf(_row.get_combined_minimum_size().x + 2 * PAD, _min_width)
	custom_minimum_size = Vector2(w, maxf(custom_minimum_size.y, UiTheme.TOUCH_MIN))


func _bounce(target: float) -> void:
	create_tween().tween_property(self, "scale", Vector2.ONE * target, 0.08)
