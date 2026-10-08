## Hub overlay "Leaderboards": pick a game on the left, today's or all-time best on the right.
class_name LeaderboardOverlay
extends Control

var _game := ""
var _today := true
var _game_buttons := {}
var _toggle: Array[BigButton] = []
var _table_slot: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.ACCENT, 0.5), 3))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 30)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	head.add_child(UiTheme.icon("trophy", 84, UiTheme.ACCENT))
	var title := UiTheme.label("LB_TITLE", UiTheme.SIZE_H2 + 8, "serif")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := BigButton.make("CLOSE", "close", false, 300)
	close.pressed.connect(queue_free)
	head.add_child(close)
	v.add_child(head)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 40)
	v.add_child(body)
	var games := VBoxContainer.new()
	games.add_theme_constant_override("separation", 14)
	body.add_child(games)
	for g in GameRegistry.visible_games():
		if g.status != "ready" or GameRegistry.is_external(g):
			continue
		var b := BigButton.make(g.title, g.icon, false, 520)
		b.pressed.connect(_select.bind(g.id))
		games.add_child(b)
		_game_buttons[g.id] = b
		if _game == "":
			_game = g.id
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 22)
	body.add_child(right)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	for k in [["LB_TODAY", true], ["LB_ALL", false]]:
		var b := BigButton.make(k[0], "", false, 320)
		b.pressed.connect(func():
			_today = k[1]
			_refresh())
		row.add_child(b)
		_toggle.append(b)
	right.add_child(row)
	_table_slot = VBoxContainer.new()
	_table_slot.custom_minimum_size = Vector2(1040, 860)
	right.add_child(_table_slot)
	_refresh()


func _select(game_id: String) -> void:
	_game = game_id
	_refresh()


func _refresh() -> void:
	for id in _game_buttons:
		_mark(_game_buttons[id], id == _game)
	_mark(_toggle[0], _today)
	_mark(_toggle[1], not _today)
	for c in _table_slot.get_children():
		c.queue_free()
	_table_slot.add_child(LeaderboardTable.make(_game, _today, 10, "", 1040.0))


static func _mark(b: Button, on: bool) -> void:
	var box := UiTheme.box(Color(UiTheme.ACCENT, 0.2) if on else UiTheme.SURFACE, UiTheme.ACCENT if on else UiTheme.LINE, 3 if on else 2)
	for s in ["normal", "hover"]:
		b.add_theme_stylebox_override(s, box)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.75))
