## Circular progress ring (0..1), e.g. around a countdown number or a timer.
class_name RingProgress
extends Control

@export var value := 1.0:
	set(v):
		value = v
		queue_redraw()
@export var color := UiTheme.ACCENT
@export var width := 12.0


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - width
	draw_arc(c, r, 0, TAU, 128, Color(1, 1, 1, 0.1), width, true)
	if value > 0.0:
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * value, 128, color, width, true)
