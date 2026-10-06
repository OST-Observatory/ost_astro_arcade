## Row of language pills ("Deutsch", "English", "Español"); the active one is highlighted.
## Uses language names instead of flags (English is not only the UK, Spanish not only Spain).
class_name LanguageBar
extends HBoxContainer

var _buttons := {}


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	for code in I18n.available():
		var b := Button.new()
		b.text = I18n.NAMES.get(code, code)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(220, UiTheme.TOUCH_MIN)
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
		b.pressed.connect(func():
			Audio.play("tap")
			I18n.set_locale(code))
		add_child(b)
		_buttons[code] = b
	I18n.locale_changed.connect(func(_c): _update())
	_update()


func _update() -> void:
	for code in _buttons:
		var b: Button = _buttons[code]
		var active: bool = code == I18n.locale
		b.add_theme_stylebox_override("normal",
			UiTheme.box(Color(UiTheme.ACCENT, 0.9), UiTheme.ACCENT_HI, 2, 48) if active
			else UiTheme.box(Color(UiTheme.SURFACE, 0.6), UiTheme.LINE, 2, 48))
		b.add_theme_color_override("font_color", UiTheme.BG if active else UiTheme.TEXT)
		b.add_theme_color_override("font_hover_color", UiTheme.BG if active else UiTheme.TEXT)
