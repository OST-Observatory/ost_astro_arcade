## Spike: multi-touch test pattern for the kiosk display.
## Shows every active touch point with its index, the current/maximum number of
## simultaneous touches and a grid with 96 px cells (minimum touch target size).
extends Control

const COLORS := [
	Color("ffb347"), Color("4dd0e1"), Color("ff6f91"), Color("9ccc65"), Color("b39ddb"),
	Color("ffd54f"), Color("4fc3f7"), Color("f48fb1"), Color("aed581"), Color("90a4ae"),
]

var _touches := {}  # index -> Vector2
var _max_simultaneous := 0
var _total_events := 0
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_total_events += 1
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
	else:
		return
	_max_simultaneous = maxi(_max_simultaneous, _touches.size())
	queue_redraw()


func _draw() -> void:
	var r := get_rect()
	draw_rect(r, Color(0.02, 0.02, 0.05))
	var grid_col := Color(1, 1, 1, 0.06)
	for x in range(0, int(r.size.x), 96):
		draw_line(Vector2(x, 0), Vector2(x, r.size.y), grid_col)
	for y in range(0, int(r.size.y), 96):
		draw_line(Vector2(0, y), Vector2(r.size.x, y), grid_col)

	var lines := [
		"Touch-Test  ·  Fenster %dx%d  ·  Bildschirm %s" % [r.size.x, r.size.y, str(DisplayServer.screen_get_size())],
		"Aktiv: %d   Maximum gleichzeitig: %d   Ereignisse: %d" % [_touches.size(), _max_simultaneous, _total_events],
		"%s  ·  %s" % [RenderingServer.get_video_adapter_name(), DisplayServer.get_name()],
	]
	for i in lines.size():
		draw_string(_font, Vector2(48, 80 + i * 56), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 40)

	for idx in _touches:
		var p: Vector2 = _touches[idx]
		var c: Color = COLORS[idx % COLORS.size()]
		draw_circle(p, 70, Color(c, 0.25))
		draw_arc(p, 70, 0, TAU, 64, c, 4, true)
		draw_line(Vector2(p.x, 0), Vector2(p.x, r.size.y), Color(c, 0.3))
		draw_line(Vector2(0, p.y), Vector2(r.size.x, p.y), Color(c, 0.3))
		draw_string(_font, p + Vector2(-12, -86), str(idx), HORIZONTAL_ALIGNMENT_LEFT, -1, 44, c)
