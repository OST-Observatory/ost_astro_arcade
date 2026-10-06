## Modal dialog with a dimmed background: message plus up to three big buttons.
## Usage: var choice: String = await Dialog.ask(parent, "KEY", [["YES_KEY", "check", true, "yes"], ...])
class_name Dialog
extends Control

signal chosen(id: String)


static func ask(parent: Node, message_key: String, buttons: Array, icon := "") -> String:
	var d := Dialog.new()
	parent.add_child(d)
	d._build(message_key, buttons, icon)
	var id: String = await d.chosen
	d.queue_free()
	return id


func _build(message_key: String, buttons: Array, icon: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.ACCENT, 0.5), 3))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 40)
	v.custom_minimum_size = Vector2(900, 0)
	panel.add_child(v)
	if icon != "":
		v.add_child(UiTheme.icon(icon, 110, UiTheme.ACCENT))
	var msg := UiTheme.label(message_key, UiTheme.SIZE_H2, "serif")
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	v.add_child(row)
	for b in buttons:  # [text_key, icon, accent, id]
		var btn := BigButton.make(b[0], b[1], b[2], 360)
		btn.pressed.connect(func(): chosen.emit(b[3]))
		row.add_child(btn)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
