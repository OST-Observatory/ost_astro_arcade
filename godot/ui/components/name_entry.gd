## Full-screen name entry with the on-screen keyboard. Validates with WordFilter
## (via Session.set_custom_name). Emits done(true) on success, done(false) on cancel.
class_name NameEntry
extends Control

signal done(accepted: bool)

var _display: Label
var _error: Label
var _kb: OnscreenKeyboard


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 28)
	add_child(v)

	var title := UiTheme.label("NAME_TITLE", UiTheme.SIZE_H2 + 8, "serif")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	_display = UiTheme.label("", 84, "semibold", UiTheme.ACCENT_HI)
	_display.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.custom_minimum_size = Vector2(1400, 140)
	_display.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_display.add_theme_stylebox_override("normal", UiTheme.box(Color(0, 0, 0, 0.5), Color(UiTheme.ACCENT, 0.6), 3))
	v.add_child(_display)

	_error = UiTheme.label("", UiTheme.SIZE_BODY, "semibold", UiTheme.DANGER)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.custom_minimum_size = Vector2(0, 48)
	v.add_child(_error)

	_kb = OnscreenKeyboard.new()
	_kb.max_length = 20
	_kb.text_changed.connect(_on_text)
	_kb.submitted.connect(_on_submit)
	v.add_child(_kb)

	var cancel := BigButton.make("BACK", "arrow_back", false, 420)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func(): done.emit(false))
	v.add_child(cancel)
	_on_text("")


func _on_text(t: String) -> void:
	_display.text = t + "|"
	_error.text = ""


func _on_submit(t: String) -> void:
	if t.length() < 2:
		_error.text = tr("NAME_TOO_SHORT")
		Audio.play("fail")
	elif Session.set_custom_name(t):
		done.emit(true)
	else:
		_error.text = tr("NAME_REJECTED")
		Audio.play("fail")
		_kb.set_text("")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.02, 0.95))
