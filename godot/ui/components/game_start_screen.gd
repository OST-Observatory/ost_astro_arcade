## Common start screen for every game: title, difficulty (optional), player name and a
## big start button. Games add it as their first screen and wait for `start_pressed`.
##   var s := GameStartScreen.make(Router.current, true)
##   add_child(s); await s.start_pressed
class_name GameStartScreen
extends Control

signal start_pressed

const DIFFS := [
	["DIFF_EXPLORER", "DIFF_EXPLORER_DESC", "star_border"],
	["DIFF_RESEARCHER", "DIFF_RESEARCHER_DESC", "star"],
	["DIFF_PRO", "DIFF_PRO_DESC", "trophy"],
]

var entry: Dictionary
var with_difficulty := true
var _diff_buttons: Array[Button] = []
var _name: Label


static func make(game: Dictionary, difficulty := true) -> GameStartScreen:
	var s := GameStartScreen.new()
	s.entry = game
	s.with_difficulty = difficulty
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Session.ensure_name()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 36)
	add_child(v)

	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 40)
	head.add_child(UiTheme.icon(entry.get("icon", "star"), 150, entry.get("color", UiTheme.ACCENT)))
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(UiTheme.label(entry.get("title", ""), UiTheme.SIZE_TITLE, "serif"))
	tv.add_child(UiTheme.label(entry.get("desc", ""), UiTheme.SIZE_H2 - 10, "regular", UiTheme.TEXT_DIM))
	head.add_child(tv)
	v.add_child(head)

	if with_difficulty:
		var q := UiTheme.label("DIFF_TITLE", UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(q)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 40)
		for i in DIFFS.size():
			var b := _difficulty_card(i)
			row.add_child(b)
			_diff_buttons.append(b)
		v.add_child(row)
		_update_difficulty()

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 24)
	name_row.add_child(UiTheme.icon("person", 72, UiTheme.SCIENCE))
	_name = UiTheme.label("", UiTheme.SIZE_H2 + 4, "semibold", UiTheme.TEXT)
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name.custom_minimum_size = Vector2(700, 0)
	name_row.add_child(_name)
	var reroll := BigButton.make("NAME_REROLL", "casino")
	reroll.pressed.connect(Session.reroll_name)
	name_row.add_child(reroll)
	var own := BigButton.make("NAME_OWN", "keyboard")
	own.pressed.connect(_open_name_entry)
	name_row.add_child(own)
	v.add_child(name_row)

	var go := BigButton.make("NAME_OK", "play_arrow", true, 640)
	go.custom_minimum_size.y = 140
	go.add_theme_font_size_override("font_size", 56)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.sound = "success"
	go.pressed.connect(func(): start_pressed.emit())
	v.add_child(go)

	Session.changed.connect(_refresh)
	_refresh()


func _difficulty_card(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(520, 220)
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var stars := HBoxContainer.new()
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in i + 1:
		var st := UiTheme.icon("star", 56, UiTheme.ACCENT)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stars.add_child(st)
	col.add_child(stars)
	for pair in [[DIFFS[i][0], UiTheme.SIZE_H2 - 8, "semibold", UiTheme.TEXT], [DIFFS[i][1], UiTheme.SIZE_SMALL, "regular", UiTheme.TEXT_DIM]]:
		var l := UiTheme.label(pair[0], pair[1], pair[2], pair[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	b.pressed.connect(func():
		Audio.play("tap")
		Session.set_difficulty(i as Session.Difficulty))
	return b


func _update_difficulty() -> void:
	for i in _diff_buttons.size():
		var active := i == Session.difficulty
		var box := UiTheme.box(Color(UiTheme.ACCENT, 0.18) if active else UiTheme.SURFACE,
			UiTheme.ACCENT if active else UiTheme.LINE, 4 if active else 2)
		for s in ["normal", "hover", "pressed"]:
			_diff_buttons[i].add_theme_stylebox_override(s, box)


func _refresh() -> void:
	_name.text = Session.player_name
	if with_difficulty:
		_update_difficulty()


func _open_name_entry() -> void:
	var e := NameEntry.new()
	add_child(e)
	await e.done
	e.queue_free()
