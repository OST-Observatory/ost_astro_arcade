## Touch keyboard for names (no OS keyboard on the kiosk). Layout follows the UI
## language (QWERTZ with umlauts for German, Ñ for Spanish). Words are capitalised
## automatically, so there is no shift key. In sentence_mode (set before adding it) only
## the start of a sentence is capitalised, a shift key capitalises the next letter (German
## nouns) and there are punctuation keys.
class_name OnscreenKeyboard
extends VBoxContainer

signal text_changed(text: String)
signal submitted(text: String)

const LAYOUTS := {
	"de": ["1234567890", "QWERTZUIOPÜ", "ASDFGHJKLÖÄ", "YXCVBNMß-"],
	"en": ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM-"],
	"es": ["1234567890", "QWERTYUIOP", "ASDFGHJKLÑ", "ZXCVBNM-"],
}
const KEY_SIZE := Vector2(132, 116)

var text := ""
var max_length := 20
var sentence_mode := false
var key_size := KEY_SIZE
var _shift := false
var _shift_key: Button


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var layout: Array = (LAYOUTS.get(I18n.locale, LAYOUTS.en) as Array).duplicate()
	if sentence_mode:
		layout[layout.size() - 1] += ",.?!"
	for row_chars in layout:
		var row := _row()
		for ch in row_chars:
			row.add_child(_key(ch, ch, key_size))
	var last := _row()
	last.add_child(_key(Icons.get_char("backspace"), "BACK", Vector2(260, key_size.y), true))
	if sentence_mode:
		_shift_key = _key(Icons.get_char("arrow_upward"), "SHIFT", Vector2(200, key_size.y), true)
		last.add_child(_shift_key)
	last.add_child(_key(" ", "SPACE", Vector2(640, key_size.y)))
	var ok := _key(Icons.get_char("check"), "OK", Vector2(260, key_size.y), true)
	ok.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.ACCENT, 0.9), UiTheme.ACCENT_HI, 2, 20))
	ok.add_theme_color_override("font_color", UiTheme.BG)
	last.add_child(ok)


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	return h


func _key(label: String, id: String, size_px: Vector2, icon := false) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = size_px
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.add_theme_font_size_override("font_size", 46)
	if icon:
		b.add_theme_font_override("font", UiTheme.font("icons"))
		b.add_theme_font_size_override("font_size", 56)
	b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SURFACE, UiTheme.LINE, 2, 20))
	b.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.ACCENT, UiTheme.ACCENT_HI, 2, 20))
	b.pressed.connect(_press.bind(id))
	return b


func _press(id: String) -> void:
	Audio.play("tick")
	match id:
		"BACK":
			text = text.substr(0, text.length() - 1)
		"SPACE":
			if text != "" and not text.ends_with(" ") and text.length() < max_length:
				text += " "
		"OK":
			submitted.emit(text.strip_edges())
			return
		"SHIFT":
			_set_shift(not _shift)
			return
		_:
			if text.length() < max_length:
				var capital: bool
				if sentence_mode:
					var t := text.strip_edges(false, true)
					capital = t == "" or t.ends_with(".") or t.ends_with("?") or t.ends_with("!")
				else:
					capital = text == "" or text.ends_with(" ") or text.ends_with("-")
				text += id if capital or _shift else id.to_lower()
				_set_shift(false)
	text_changed.emit(text)


func _set_shift(on: bool) -> void:
	_shift = on
	if _shift_key:
		_shift_key.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.ACCENT if on else UiTheme.SURFACE,
			UiTheme.ACCENT_HI if on else UiTheme.LINE, 2, 20))


func set_text(t: String) -> void:
	text = t.substr(0, max_length)
	text_changed.emit(text)
