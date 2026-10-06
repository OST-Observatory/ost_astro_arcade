## Touch keyboard for names (no OS keyboard on the kiosk). Layout follows the UI
## language (QWERTZ with umlauts for German, Ñ for Spanish). Words are capitalised
## automatically, so there is no shift key.
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


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var layout: Array = LAYOUTS.get(I18n.locale, LAYOUTS.en)
	for row_chars in layout:
		var row := _row()
		for ch in row_chars:
			row.add_child(_key(ch, ch, KEY_SIZE))
	var last := _row()
	last.add_child(_key(Icons.get_char("backspace"), "BACK", Vector2(260, KEY_SIZE.y), true))
	last.add_child(_key(" ", "SPACE", Vector2(640, KEY_SIZE.y)))
	var ok := _key(Icons.get_char("check"), "OK", Vector2(260, KEY_SIZE.y), true)
	ok.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.ACCENT, 0.9), UiTheme.ACCENT_HI, 2, 20))
	ok.add_theme_color_override("font_color", UiTheme.BG)
	last.add_child(ok)


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	return h


func _key(label: String, id: String, key_size: Vector2, icon := false) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = key_size
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
		_:
			if text.length() < max_length:
				var at_word_start := text == "" or text.ends_with(" ") or text.ends_with("-")
				text += id if at_word_start else id.to_lower()
	text_changed.emit(text)


func set_text(t: String) -> void:
	text = t.substr(0, max_length)
	text_changed.emit(text)
