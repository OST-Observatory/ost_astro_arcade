## Leaderboard of one game as a table: rank, name, stars, points. The visitor's own entry
## (highlight_id) is marked; if it is not among the shown rows, it is appended below.
class_name LeaderboardTable
extends VBoxContainer

const MEDALS := [Color("ffcf86"), Color("d7dbe4"), Color("d9a06b")]


static func make(game_id: String, today_only: bool, rows := 10, highlight_id := "", width := 900.0) -> LeaderboardTable:
	var t := LeaderboardTable.new()
	t.custom_minimum_size = Vector2(width, 0)
	t.add_theme_constant_override("separation", 6)
	var all: Array = Scores.top(game_id, 500, today_only)
	if all.is_empty():
		var empty := UiTheme.label("LB_EMPTY", UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(width, 0)
		t.add_child(empty)
		return t
	var own := -1
	for i in all.size():
		if highlight_id != "" and str(all[i].get("id", "")) == highlight_id:
			own = i
	for i in mini(rows, all.size()):
		t.add_child(t._row(i + 1, all[i], i == own, width))
	if own >= rows:
		var dots := UiTheme.label("…", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT_DIM)
		dots.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		t.add_child(dots)
		t.add_child(t._row(own + 1, all[own], true, width))
	return t


func _row(rank: int, e: Dictionary, own: bool, width: float) -> Control:
	var p := PanelContainer.new()
	var bg := Color(UiTheme.ACCENT, 0.22) if own else (Color(1, 1, 1, 0.04) if rank % 2 == 1 else Color(0, 0, 0, 0))
	var box := UiTheme.box(bg, UiTheme.ACCENT if own else Color(0, 0, 0, 0), 2 if own else 0, 14)
	box.set_content_margin_all(10)
	box.content_margin_left = 20
	box.content_margin_right = 20
	p.add_theme_stylebox_override("panel", box)
	p.custom_minimum_size = Vector2(width, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var size := UiTheme.SIZE_BODY - 2
	if rank <= 3:
		var medal := UiTheme.icon("trophy", 40, MEDALS[rank - 1])
		medal.custom_minimum_size = Vector2(70, 0)
		h.add_child(medal)
	else:
		h.add_child(_cell(str(rank) + ".", size, "semibold", UiTheme.TEXT_DIM, 70))
	var name := _cell(str(e.get("name", "")), size, "semibold" if own else "medium", UiTheme.ACCENT_HI if own else UiTheme.TEXT, 0)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(name)
	var stars := HBoxContainer.new()
	for i in 3:
		stars.add_child(UiTheme.icon("star" if i < int(e.get("stars", 0)) else "star_border", 30, UiTheme.ACCENT))
	h.add_child(stars)
	var pts := _cell(str(int(e.get("score", 0))), size, "bold", UiTheme.TEXT, 140)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pts)
	return p


static func _cell(text: String, size: int, kind: String, color: Color, min_w: float) -> Label:
	var l := UiTheme.label(text, size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.custom_minimum_size = Vector2(min_w, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
