## A touch-friendly value knob: title and current value on top, below a thick slider with
## big minus/plus buttons on both sides (easy for small fingers, precise for everyone).
class_name KnobSlider
extends VBoxContainer

signal changed(value: float)

var slider: HSlider
var formatter: Callable    # float -> String shown next to the title
var _value_label: Label
var _buttons: Array[Button] = []


static func make(title_key: String, min_v: float, max_v: float, step: float, value: float,
		fmt: Callable) -> KnobSlider:
	var k := KnobSlider.new()
	k.formatter = fmt
	k.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	var title := UiTheme.label(title_key, UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	k._value_label = UiTheme.label("", UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.SCIENCE)
	k._value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	top.add_child(k._value_label)
	k.add_child(top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	k.slider = HSlider.new()
	k.slider.min_value = min_v
	k.slider.max_value = max_v
	k.slider.step = step
	k.slider.value = value
	k.slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	k.slider.custom_minimum_size.y = 80
	k.slider.focus_mode = Control.FOCUS_NONE
	var track := UiTheme.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := UiTheme.box(Color(UiTheme.SCIENCE, 0.7), Color(0, 0, 0, 0), 0, 8)
	fill.content_margin_top = 8
	fill.content_margin_bottom = 8
	k.slider.add_theme_stylebox_override("slider", track)
	k.slider.add_theme_stylebox_override("grabber_area", fill)
	k.slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob_texture(64, UiTheme.TEXT)
	k.slider.add_theme_icon_override("grabber", knob)
	k.slider.add_theme_icon_override("grabber_highlight", _knob_texture(64, UiTheme.ACCENT_HI))
	k.slider.value_changed.connect(k._on_value)
	var minus := k._step_button("remove", -1)
	row.add_child(minus)
	row.add_child(k.slider)
	row.add_child(k._step_button("add", 1))
	k.add_child(row)
	k._refresh()
	return k


var value: float:
	get:
		return slider.value


func set_enabled(on: bool) -> void:
	slider.editable = on
	for b in _buttons:
		b.disabled = not on
	modulate.a = 1.0 if on else 0.55


func _step_button(icon_name: String, dir: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(UiTheme.TOUCH_MIN, UiTheme.TOUCH_MIN)
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var ic := UiTheme.icon(icon_name, 52, UiTheme.TEXT)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	b.pressed.connect(func():
		Audio.play("tick")
		slider.value += slider.step * dir)
	_buttons.append(b)
	return b


func _on_value(_v: float) -> void:
	_refresh()
	changed.emit(slider.value)


func _refresh() -> void:
	_value_label.text = formatter.call(slider.value) if formatter.is_valid() else str(slider.value)


static func _knob_texture(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d, 0.0, 1.0)
			var rim := clampf(d - (c - 5.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(col.lerp(Color(0.1, 0.1, 0.15), rim * 0.6), a))
	return ImageTexture.create_from_image(img)
