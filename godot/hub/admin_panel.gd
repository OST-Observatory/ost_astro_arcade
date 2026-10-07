## Admin menu behind PIN: today's statistics, sound, games on/off, leaderboard
## moderation, FPS overlay, touch test, PIN change, restart/shutdown.
## Texts are German only on purpose (staff tool, not for visitors).
class_name AdminPanel
extends Control

var _pin := ""
var _pin_label: Label
var _content: VBoxContainer
var _msg: Label
var _new_pin_mode := false


const _QUALITY_NAMES := {"high": "hoch", "medium": "mittel", "low": "niedrig"}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_show_pin_pad()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03, 1.0))


func _clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	queue_redraw()


# --- PIN pad ------------------------------------------------------------------------

func _show_pin_pad(title := "Admin-PIN") -> void:
	_clear()
	_pin = ""
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	center.add_child(v)
	var t := UiTheme.label(title, UiTheme.SIZE_H2, "serif")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_pin_label = UiTheme.label("", 72, "bold", UiTheme.ACCENT)
	_pin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin_label.custom_minimum_size = Vector2(0, 100)
	v.add_child(_pin_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	v.add_child(grid)
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"]:
		var b := _plain_button(k, Vector2(180, 130))
		b.pressed.connect(_on_pin_key.bind(k))
		grid.add_child(b)
	var cancel := _plain_button("Abbrechen", Vector2(0, UiTheme.TOUCH_MIN))
	cancel.pressed.connect(queue_free)
	v.add_child(cancel)


func _on_pin_key(k: String) -> void:
	Audio.play("tap")
	match k:
		"C":
			_pin = ""
		"OK":
			if _new_pin_mode:
				if _pin.length() >= 4:
					Settings.set_pin(_pin)
					_new_pin_mode = false
					_show_main("PIN geändert.")
				return
			if Settings.check_pin(_pin):
				_show_main()
			else:
				Audio.play("fail")
				_pin = ""
		_:
			if _pin.length() < 8:
				_pin += k
	_pin_label.text = "•".repeat(_pin.length())


# --- main panel ----------------------------------------------------------------------

func _show_main(message := "") -> void:
	_clear()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 120
	scroll.offset_right = -120
	scroll.offset_top = 60
	scroll.offset_bottom = -60
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 22)
	scroll.add_child(_content)

	var head := HBoxContainer.new()
	head.add_child(UiTheme.label("Admin", UiTheme.SIZE_TITLE, "serif"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := _plain_button(Icons.get_char("close") + "  Schließen", Vector2(320, UiTheme.TOUCH_MIN))
	close.pressed.connect(queue_free)
	head.add_child(close)
	_content.add_child(head)

	_msg = UiTheme.label(message, UiTheme.SIZE_BODY, "medium", UiTheme.SUCCESS)
	_content.add_child(_msg)
	if Settings.uses_default_pin():
		_content.add_child(UiTheme.label("⚠ Standard-PIN aktiv – bitte unten ändern.", UiTheme.SIZE_BODY, "semibold", UiTheme.DANGER))

	_section("Heute (%s)" % ScoreStore.today())
	var stats := Telemetry.sessions.summary(ScoreStore.today())
	if stats.is_empty():
		_content.add_child(UiTheme.label("Noch keine Spielsitzungen heute.", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT_DIM))
	for gid in stats:
		var s: Dictionary = stats[gid]
		_content.add_child(UiTheme.label("%s:  %d Sitzungen, %d beendet, Median %.0f s, gesamt %.0f min" % [
			tr(GameRegistry.get_entry(gid).get("title", gid)), s.sessions, s.completed, s.median_s, s.total_s / 60.0]))

	_section("Ton")
	_row([
		_toggle("Stumm", Settings.get_value("audio/muted"), func(on): Settings.set_value("audio/muted", on)),
		_slider(-30.0, 0.0, Settings.get_value("audio/master_db"), func(v): Settings.set_value("audio/master_db", v)),
		_action("Testton", func(): Audio.play("success")),
	])

	_section("Spiele")
	var games_row := []
	for g in GameRegistry.GAMES:
		var gid: String = g.id
		games_row.append(_toggle(tr(g.title), Settings.is_game_enabled(gid), func(on): _set_game_enabled(gid, on)))
	_row(games_row)
	_row([_toggle("Geplante Spiele anzeigen", Settings.get_value("general/show_upcoming"),
		func(on): Settings.set_value("general/show_upcoming", on))])

	_section("Bestenlisten")
	for g in GameRegistry.GAMES:
		for e in Scores.top(g.id, 10, true):
			var gid: String = g.id
			var eid: String = e.id
			_row([UiTheme.label("%s – %s (%d)" % [tr(g.title), e.name, e.score]),
				_action(Icons.get_char("delete") + " Löschen", func():
					Scores.store.remove(gid, eid)
					_show_main("Eintrag gelöscht."))])
	_row([_action("Heutige Einträge löschen", func():
			Scores.store.clear_today()
			_show_main("Heutige Bestenlisten gelöscht."))])

	_section("Anzeige & Test")
	_row([
		_toggle("FPS anzeigen", Settings.get_value("display/show_fps"), func(on): Settings.set_value("display/show_fps", on)),
		_action("3D-Qualität: " + _QUALITY_NAMES[str(Settings.get_value("display/quality_3d"))], func():
			var order := ["high", "medium", "low"]
			var i := order.find(str(Settings.get_value("display/quality_3d")))
			Settings.set_value("display/quality_3d", order[(i + 1) % order.size()])
			_show_main("3D-Qualität geändert (gilt ab dem nächsten Spielstart).")),
		_action("Touch-Test", func(): get_tree().change_scene_to_file("res://spikes/touch_test.tscn")),
		_action("PIN ändern", func():
			_new_pin_mode = true
			_show_pin_pad("Neue PIN (mind. 4 Ziffern)")),
	])

	_section("System")
	_row([
		_action("App neu starten", func(): get_tree().quit(3)),
		_action(Icons.get_char("power") + "  Herunterfahren", _shutdown),
	])
	_content.add_child(UiTheme.label("Daten: " + ProjectSettings.globalize_path(Settings.data_dir),
		UiTheme.SIZE_SMALL, "regular", UiTheme.TEXT_DIM))


func _set_game_enabled(gid: String, on: bool) -> void:
	var disabled: Array = (Settings.get_value("games/disabled") as Array).duplicate()
	disabled.erase(gid)
	if not on:
		disabled.append(gid)
	Settings.set_value("games/disabled", disabled)


func _shutdown() -> void:
	# Allowed for the kiosk user via a polkit rule (kiosk/ setup).
	OS.execute("systemctl", ["poweroff"])


# --- small widget helpers -------------------------------------------------------------

func _section(title: String) -> void:
	var l := UiTheme.label(title, UiTheme.SIZE_H2, "serif", UiTheme.ACCENT)
	_content.add_child(l)


func _row(items: Array) -> void:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 20)
	h.add_theme_constant_override("v_separation", 20)
	for it in items:
		h.add_child(it)
	_content.add_child(h)


func _plain_button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return b


func _action(text: String, cb: Callable) -> Button:
	var b := _plain_button(text, Vector2(0, UiTheme.TOUCH_MIN))
	b.pressed.connect(func():
		Audio.play("tap")
		cb.call())
	return b


func _toggle(text: String, on: bool, cb: Callable) -> Button:
	var b := _plain_button(text, Vector2(0, UiTheme.TOUCH_MIN))
	b.toggle_mode = true
	b.button_pressed = on
	b.toggled.connect(func(v):
		Audio.play("tap")
		cb.call(v))
	return b


func _slider(lo: float, hi: float, value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1.0
	s.value = value
	s.custom_minimum_size = Vector2(520, UiTheme.TOUCH_MIN)
	s.value_changed.connect(cb)
	return s
