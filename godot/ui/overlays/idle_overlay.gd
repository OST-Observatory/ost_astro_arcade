## "Are you still there?" countdown shown before a game returns to the hub.
## Any touch hides it again (Kiosk.activity).
class_name IdleOverlay
extends Control

var _count: Label
var _ring: RingProgress


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 40)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var q := UiTheme.label("IDLE_QUESTION", UiTheme.SIZE_TITLE, "serif")
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)

	_ring = RingProgress.new()
	_ring.custom_minimum_size = Vector2(320, 320)
	_ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_ring)
	_count = UiTheme.label("10", 160, "bold", UiTheme.ACCENT)
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.add_child(_count)

	var hint := UiTheme.label("IDLE_HINT", UiTheme.SIZE_H2, "regular", UiTheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func show_countdown(seconds_left: float, total: float) -> void:
	if not visible:
		visible = true
	var s := ceili(seconds_left)
	if _count.text != str(s):
		_count.text = str(s)
		Audio.play("tick", "UI", 1.0 + 0.05 * (total - s))
	_ring.value = clampf(seconds_left / total, 0.0, 1.0)


func hide_countdown() -> void:
	visible = false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.02, 0.88))
