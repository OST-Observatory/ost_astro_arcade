## Bonus round after the asteroid hunt: a real comet in real data. Six frames of comet
## 67P/Churyumov-Gerasimenko taken at the OST on 2015-08-13 are blinked; tap the comet.
## Data: tools/comet/build_67p.py (OST gallery, CC BY-NC-SA 3.0).
class_name CometBonus
extends Control

signal closed

const DATA := "res://assets/data/comet/67p.json"
const VIEW := Rect2(60, 190, 1840, 1150)
const FRAME_SEC := 0.45
const TOL_PX := 70.0         # in image pixels

var _data: Dictionary
var _textures: Array[Texture2D] = []
var _scale := 1.0
var _origin := Vector2.ZERO
var _image: TextureRect
var _marks: Control
var _frame := 0
var _t := 0.0
var _playing := true
var _wrong := 0
var _found := false
var _status: Label
var _side: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for f in _data.frames:
		_textures.append(load(f.image))
	var size := Vector2(_data.size[0], _data.size[1])
	_scale = minf(VIEW.size.x / size.x, VIEW.size.y / size.y)
	_origin = VIEW.position + (VIEW.size - size * _scale) / 2.0

	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.position = _origin
	_image.size = size * _scale
	_image.texture = _textures[0]
	_image.mouse_filter = Control.MOUSE_FILTER_STOP
	_image.gui_input.connect(_on_input)
	add_child(_image)
	_marks = Control.new()
	_marks.position = _origin
	_marks.size = size * _scale
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	add_child(_marks)

	var title := UiTheme.label("COMET_TITLE", UiTheme.SIZE_H2, "serif", UiTheme.ACCENT_HI)
	title.position = Vector2(200, 52)
	add_child(title)
	_side = VBoxContainer.new()
	_side.position = Vector2(1960, 190)
	_side.custom_minimum_size = Vector2(540, 0)
	_side.add_theme_constant_override("separation", 24)
	add_child(_side)
	var task := UiTheme.label("COMET_TASK", UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.custom_minimum_size = Vector2(540, 0)
	_side.add_child(task)
	_status = UiTheme.label("", UiTheme.SIZE_BODY, "semibold", UiTheme.SCIENCE)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	_side.add_child(_status)
	var pause := BigButton.make("COMET_PAUSE", "pause", false, 540)
	pause.pressed.connect(func():
		_playing = not _playing
		pause.set_key("COMET_PLAY" if not _playing else "COMET_PAUSE"))
	_side.add_child(pause)
	var back := BigButton.make("COMET_BACK", "arrow_back", false, 540)
	back.pressed.connect(func(): closed.emit())
	_side.add_child(back)
	var credit := UiTheme.label("COMET_CREDIT", UiTheme.SIZE_SMALL - 6, "regular", UiTheme.TEXT_DIM)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.custom_minimum_size = Vector2(540, 0)
	_side.add_child(credit)
	Router.step("comet")
	_update_status()


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	if _t >= FRAME_SEC:
		_t = 0.0
		_frame = (_frame + 1) % _textures.size()
		_image.texture = _textures[_frame]
		_update_status()


func _update_status() -> void:
	if not _found:
		_status.text = tr("COMET_FRAME") % [_frame + 1, _textures.size()]


func _on_input(event: InputEvent) -> void:
	if _found:
		return
	if not (event is InputEventScreenTouch and event.pressed):
		return
	var img_pos: Vector2 = event.position / _scale
	var c: Array = _data.frames[_frame].comet
	# Accept the comet's spot in the frame on screen or, being kind, in any frame.
	var hit := false
	for f in _data.frames:
		if img_pos.distance_to(Vector2(f.comet[0], f.comet[1])) < TOL_PX:
			hit = true
	if hit:
		_success()
	else:
		_wrong += 1
		Audio.play("fail", "SFX", 0.5)
		_status.text = tr("COMET_WRONG") if _wrong < 3 else tr("COMET_HINT")
		_marks.queue_redraw()


func _success() -> void:
	_found = true
	_playing = true
	Audio.play("success")
	Confetti.burst(self)
	Router.step("comet_found")
	_status.text = tr("COMET_FOUND")
	_status.add_theme_color_override("font_color", UiTheme.SUCCESS)
	var info := UiTheme.label("COMET_INFO", UiTheme.SIZE_BODY - 6, "regular", UiTheme.TEXT)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(540, 0)
	_side.add_child(info)
	_side.move_child(info, 2)
	_marks.queue_redraw()


func _draw_marks() -> void:
	if _found:
		var pts := PackedVector2Array()
		for f in _data.frames:
			pts.append(Vector2(f.comet[0], f.comet[1]) * _scale)
		_marks.draw_polyline(pts, Color(UiTheme.ACCENT, 0.8), 3.0, true)
		for p in pts:
			_marks.draw_arc(p, 30.0, 0, TAU, 40, UiTheme.ACCENT_HI, 3.0, true)
	elif _wrong >= 3:
		# Hint: a generous circle around the comet's path.
		var a: Array = _data.frames[0].comet
		var b: Array = _data.frames[_data.frames.size() - 1].comet
		var mid := (Vector2(a[0], a[1]) + Vector2(b[0], b[1])) / 2.0 * _scale
		_marks.draw_arc(mid, Vector2(a[0], a[1]).distance_to(Vector2(b[0], b[1])) * _scale * 0.7, 0, TAU, 64,
			Color(UiTheme.ACCENT, 0.6), 4.0, true)
