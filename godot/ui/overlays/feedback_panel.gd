## Feedback from testers: what kind (bug, idea, other), an optional sentence typed on the
## touch keyboard, and the screenshot taken just before the panel opened. Saved with
## FeedbackStore; the app is paused while the panel is open. Closes by itself after a while
## without touches (a visitor walked away).
class_name FeedbackPanel
extends Control

signal closed

const IDLE_CLOSE_SEC := 90.0
const KIND_LABELS := {"bug": ["FB_KIND_BUG", "bug_report"], "idea": ["FB_KIND_IDEA", "lightbulb"],
	"other": ["FB_KIND_OTHER", "edit"]}

var shot: Image
var _kind := ""
var _kind_buttons := {}
var _text: Label
var _message: Label
var _kb: OnscreenKeyboard
var _idle := 0.0
var _sent := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.97)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 160
	v.offset_right = -160
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 24)
	add_child(v)
	v.add_child(UiTheme.label("FB_TITLE", UiTheme.SIZE_H2 + 8, "serif"))
	var intro := UiTheme.label("FB_INTRO", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)

	# Screenshot and the three kinds.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	v.add_child(row)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(320, 180)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if shot != null:
		thumb.texture = ImageTexture.create_from_image(shot)
	row.add_child(thumb)
	var kinds := VBoxContainer.new()
	kinds.alignment = BoxContainer.ALIGNMENT_CENTER
	kinds.add_theme_constant_override("separation", 12)
	row.add_child(kinds)
	kinds.add_child(UiTheme.label("FB_WHAT", UiTheme.SIZE_BODY, "semibold"))
	var kind_row := HBoxContainer.new()
	kind_row.add_theme_constant_override("separation", 20)
	kinds.add_child(kind_row)
	for k in FeedbackStore.KINDS:
		var b := BigButton.make(KIND_LABELS[k][0], KIND_LABELS[k][1], false, 330)
		b.pressed.connect(_choose.bind(k))
		kind_row.add_child(b)
		_kind_buttons[k] = b

	# The text, with cancel and send beside it.
	var text_row := HBoxContainer.new()
	text_row.add_theme_constant_override("separation", 24)
	v.add_child(text_row)
	_text = UiTheme.label("", UiTheme.SIZE_BODY + 4, "medium")
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1500, 120)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_stylebox_override("normal", UiTheme.box(Color(0, 0, 0, 0.5), Color(UiTheme.ACCENT, 0.6), 3))
	text_row.add_child(_text)
	var cancel := BigButton.make("FB_CANCEL", "close", false, 300)
	cancel.pressed.connect(_close)
	text_row.add_child(cancel)
	var send := BigButton.make("FB_SEND", "send", true, 300)
	send.pressed.connect(_send)
	text_row.add_child(send)
	_message = UiTheme.label("", UiTheme.SIZE_BODY, "semibold", UiTheme.DANGER)
	_message.custom_minimum_size = Vector2(0, 44)
	v.add_child(_message)

	_kb = OnscreenKeyboard.new()
	_kb.sentence_mode = true
	_kb.max_length = 300
	_kb.key_size = Vector2(118, 92)
	_kb.text_changed.connect(_on_text)
	_kb.submitted.connect(func(_t): _send())
	v.add_child(_kb)
	_on_text("")


func _process(delta: float) -> void:
	_idle += delta
	if _idle > IDLE_CLOSE_SEC and not _sent:
		_close()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		_idle = 0.0


func _choose(kind: String) -> void:
	_kind = kind
	_message.text = ""
	for k in _kind_buttons:
		var b: BigButton = _kind_buttons[k]
		if k == kind:
			b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.ACCENT, 0.9), UiTheme.ACCENT_HI))
		else:
			b.remove_theme_stylebox_override("normal")


func _on_text(t: String) -> void:
	if t == "":
		_text.text = tr("FB_TEXT_HINT")
		_text.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	else:
		_text.text = t + "|"
		_text.remove_theme_color_override("font_color")


func _send() -> void:
	if _sent:
		return
	if _kind == "":
		_message.text = tr("FB_CHOOSE_KIND")
		Audio.play("fail", "SFX", 0.5)
		return
	_sent = true
	var store := FeedbackStore.new(Settings.data_path("feedback"))
	store.save({
		"kind": _kind,
		"text": _kb.text.strip_edges(),
		"game": Router.current.get("id", "hub"),
		"step": Router.last_step,
		"difficulty": Session.difficulty_name(),
		"locale": I18n.locale,
		"version": FeedbackStore.app_version(),
	}, shot)
	Audio.play("success")
	_message.add_theme_color_override("font_color", UiTheme.SUCCESS)
	_message.text = tr("FB_THANKS")
	await get_tree().create_timer(1.6, true, false, true).timeout
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
