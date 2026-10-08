## Astro quiz: 10 questions of rising difficulty, 20 s each, jokers (50:50, +15 s),
## streak bonus and an explanation after every answer, then a result screen.
extends Control

const ANSWER_SIZE := Vector2(1080, 168)
const LETTERS := ["A", "B", "C", "D"]

var skip_intro := false   # screenshots/tests
var rng_seed := 0
var logic := QuizLogic.new()
var _rng := RandomNumberGenerator.new()
var _seen: Array = []
var _layer: Control           # everything of the current question
var _buttons: Array[Button] = []
var _ring: RingProgress
var _time_label: Label
var _score_label: Label
var _dots: Array[Control] = []
var _joker_fifty: BigButton
var _joker_time: BigButton
var _time_left := 0.0
var _time_total := QuizLogic.TIME_PER_QUESTION
var _answering := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	add_child(Starfield.new())
	if not skip_intro:
		var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("quiz"))
		add_child(start)
		await start.start_pressed
		start.queue_free()
		if await _pick_mode() == "duel":
			var duel := QuizDuel.new()
			add_child(duel)
			return
	_new_round()


## Solo round or duel for two players at the same screen.
func _pick_mode() -> String:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 50)
	add_child(v)
	var t := UiTheme.label("QUIZ_MODE", UiTheme.SIZE_H2 + 10, "serif")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	v.add_child(row)
	var chosen := [""]
	for m in [["solo", "person", "QUIZ_MODE_SOLO", "QUIZ_MODE_SOLO_DESC"], ["duel", "groups", "QUIZ_MODE_DUEL", "QUIZ_MODE_DUEL_DESC"]]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(760, 520)
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 24)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var ic := UiTheme.icon(m[1], 180, UiTheme.ACCENT if m[0] == "solo" else UiTheme.SCIENCE)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ic)
		var name := UiTheme.label(m[2], UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(name)
		var desc := UiTheme.label(m[3], UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT_DIM)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(680, 0)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(desc)
		b.pressed.connect(func():
			Audio.play("tap")
			chosen[0] = m[0])
		row.add_child(b)
	while chosen[0] == "":
		await get_tree().process_frame
	v.queue_free()
	return chosen[0]


func _new_round() -> void:
	for c in get_children():
		if not (c is Starfield):
			c.queue_free()
	Session.ensure_name()
	logic.new_round(Session.difficulty_name(), _rng, _seen)
	for q in logic.round_questions:
		_seen.append(q.id)
	_build_top_bar()
	Router.step("round")
	_show_question()


func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(200, 46)
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)
	_dots.clear()
	for i in QuizLogic.ROUND:
		var d := Panel.new()
		d.custom_minimum_size = Vector2(44, 44)
		d.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE, UiTheme.LINE, 2, 22))
		bar.add_child(d)
		_dots.append(d)
	_score_label = UiTheme.label("", UiTheme.SIZE_H2, "bold", UiTheme.ACCENT_HI)
	_score_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_score_label.position = Vector2(1000, 34)
	add_child(_score_label)
	_joker_fifty = BigButton.make("QUIZ_JOKER_FIFTY", "", false, 220)
	_joker_fifty.position = Vector2(1720, 28)
	_joker_fifty.pressed.connect(_use_fifty)
	add_child(_joker_fifty)
	_joker_time = BigButton.make("QUIZ_JOKER_TIME", "timer", false, 260)
	_joker_time.position = Vector2(1980, 28)
	_joker_time.pressed.connect(_use_time)
	add_child(_joker_time)
	_update_top()


func _update_top() -> void:
	_score_label.text = tr("AST_SCORE") % logic.points + (("   " + tr("QUIZ_STREAK") % logic.streak) if logic.streak >= 2 else "")
	_joker_fifty.disabled = not logic.joker_fifty or not _answering
	_joker_time.disabled = not logic.joker_time or not _answering


func _set_dot(i: int, state: String) -> void:
	var col: Color = {"current": UiTheme.ACCENT, "right": UiTheme.SUCCESS, "wrong": UiTheme.DANGER}[state]
	_dots[i].add_theme_stylebox_override("panel", UiTheme.box(Color(col, 0.85), col, 2, 22))


# --- one question ---------------------------------------------------------------------

func _show_question() -> void:
	if _layer:
		_layer.queue_free()
	if logic.is_finished():
		_show_result()
		return
	var q := logic.current()
	var loc := I18n.locale
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	_set_dot(logic.index, "current")

	var text := _plain(QuizLogic.text(q, "text", loc), UiTheme.SIZE_H2 + 6, "serif")
	text.position = Vector2(200, 150)
	text.size = Vector2(2000, 220)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_layer.add_child(text)
	_ring = RingProgress.new()
	_ring.position = Vector2(2250, 160)
	_ring.size = Vector2(190, 190)
	_layer.add_child(_ring)
	_time_label = _plain("", 64, "bold", UiTheme.TEXT)
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ring.add_child(_time_label)

	var has_image: bool = q.has("image") and ResourceLoader.exists(q.image)
	if has_image:
		var img := TextureRect.new()
		img.texture = load(q.image)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.position = Vector2(200, 410)
		img.size = Vector2(1040, 740)
		_layer.add_child(img)
		var credit := _plain(str(q.get("credit", "")), 20, "regular", UiTheme.TEXT_DIM)
		credit.position = Vector2(200, 1148)
		credit.size = Vector2(1040, 60)
		credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_layer.add_child(credit)

	_buttons.clear()
	var answers: Array = QuizLogic.text(q, "answers", loc)
	for i in 4:
		var b := _answer_button(LETTERS[i], str(answers[i]))
		if has_image:
			b.position = Vector2(1320, 400 + i * (ANSWER_SIZE.y + 30))
		else:
			b.position = Vector2(170 + (i % 2) * (ANSWER_SIZE.x + 60), 520 + (i / 2) * (ANSWER_SIZE.y + 70))
		b.pressed.connect(_on_answer.bind(i))
		_layer.add_child(b)
		_buttons.append(b)

	_time_total = QuizLogic.TIME_PER_QUESTION
	_time_left = _time_total
	_answering = true
	_update_top()


func _answer_button(letter: String, answer: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = ANSWER_SIZE
	b.size = ANSWER_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 32
	h.offset_right = -24
	h.add_theme_constant_override("separation", 28)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var badge := _plain(letter, 44, "bold", UiTheme.ACCENT)
	badge.custom_minimum_size = Vector2(60, 0)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(badge)
	var l := _plain(answer, UiTheme.SIZE_BODY + 4, "medium", UiTheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if answer.length() > 70:
		l.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	h.add_child(l)
	return b


func _process(delta: float) -> void:
	if not _answering or not is_instance_valid(_ring):
		return
	_time_left -= delta
	_ring.value = clampf(_time_left / _time_total, 0.0, 1.0)
	_ring.color = UiTheme.DANGER if _time_left < 5.0 else UiTheme.ACCENT
	var s := ceili(maxf(_time_left, 0.0))
	if _time_label.text != str(s):
		_time_label.text = str(s)
		if s <= 5 and s > 0:
			Audio.play("tick")
	if _time_left <= 0.0:
		_on_answer(-1)


func _use_fifty() -> void:
	for i in logic.fifty_fifty(_rng):
		_buttons[i].disabled = true
		_buttons[i].modulate.a = 0.25
	_update_top()


func _use_time() -> void:
	logic.joker_time = false
	_time_left += QuizLogic.EXTRA_TIME
	_time_total += QuizLogic.EXTRA_TIME
	_update_top()


func _on_answer(choice: int) -> void:
	if not _answering:
		return
	_answering = false
	var q := logic.current()
	var right := int(q.correct)
	var pos := logic.index
	var earned := logic.answer(choice, _time_left)
	var ok := choice == right
	_set_dot(pos, "right" if ok else "wrong")
	Audio.play("success" if ok else "fail")
	for i in 4:
		var col := UiTheme.SUCCESS if i == right else (UiTheme.DANGER if i == choice else UiTheme.LINE)
		var bg := Color(col, 0.35) if (i == right or i == choice) else UiTheme.SURFACE
		for st in ["normal", "hover", "pressed", "disabled"]:
			_buttons[i].add_theme_stylebox_override(st, UiTheme.box(bg, col, 4 if i == right else 2))
		_buttons[i].disabled = true
	_update_top()
	_show_feedback(q, ok, choice == -1, earned)


func _show_feedback(q: Dictionary, ok: bool, timeout: bool, earned: int) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(170, 1205)
	panel.custom_minimum_size = Vector2(2220, 200)
	var col := UiTheme.SUCCESS if ok else UiTheme.DANGER
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, col, 3))
	_layer.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 32)
	panel.add_child(h)
	h.add_child(UiTheme.icon("check" if ok else "close", 96, col))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := tr("QUIZ_RIGHT") % earned if ok else (tr("QUIZ_TIMEOUT") if timeout else tr("QUIZ_WRONG"))
	v.add_child(_plain(head, UiTheme.SIZE_H2 - 8, "semibold", col))
	var ex := _plain(str(QuizLogic.text(q, "explain", I18n.locale)), UiTheme.SIZE_BODY, "regular", UiTheme.TEXT)
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ex.custom_minimum_size = Vector2(1500, 0)
	v.add_child(ex)
	h.add_child(v)
	var next := BigButton.make("QUIZ_NEXT" if not logic.is_finished() else "QUIZ_RESULT", "play_arrow", true, 380)
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(_show_question)
	h.add_child(next)


# --- result -----------------------------------------------------------------------------

func _show_result() -> void:
	_layer = null
	_answering = false
	_joker_fifty.visible = false
	_joker_time.visible = false
	_update_top()
	var stars := logic.stars()
	var rank := Scores.submit("quiz", Session.player_name, logic.points, stars, {"correct": logic.correct})
	Router.complete({"score": logic.points, "stars": stars, "correct": logic.correct, "best_streak": logic.best_streak})
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 50)
	add_child(v)
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 120)
	v.add_child(cols)
	var res := VBoxContainer.new()
	res.alignment = BoxContainer.ALIGNMENT_CENTER
	res.add_theme_constant_override("separation", 26)
	cols.add_child(res)
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		star_row.add_child(UiTheme.icon("star" if i < stars else "star_border", 150, UiTheme.ACCENT))
	res.add_child(star_row)
	for line in [[tr("QUIZ_CORRECT_OF") % [logic.correct, QuizLogic.ROUND], UiTheme.SIZE_TITLE - 16, "serif", UiTheme.TEXT],
			[tr("AST_SCORE") % logic.points, UiTheme.SIZE_H2 + 10, "bold", UiTheme.ACCENT_HI],
			[tr("QUIZ_BEST_STREAK") % logic.best_streak, UiTheme.SIZE_BODY + 4, "regular", UiTheme.TEXT_DIM],
			[tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))], UiTheme.SIZE_BODY + 4, "medium", UiTheme.TEXT_DIM]]:
		var l := _plain(line[0], line[1], line[2], line[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		res.add_child(l)
	# Today's leaderboard next to the result, the visitor's own entry highlighted.
	var lb := VBoxContainer.new()
	lb.add_theme_constant_override("separation", 16)
	lb.add_child(UiTheme.label("LB_TODAY_TITLE", UiTheme.SIZE_H2 - 6, "serif", UiTheme.ACCENT_HI))
	lb.add_child(LeaderboardTable.make("quiz", true, 8, str(rank.entry.id), 900.0))
	cols.add_child(lb)
	v.add_child(ResultActions.make("QUIZ_AGAIN", "refresh", _new_round, 1700.0, false))
	Audio.play("success")


func _plain(t: String, font_size: int, kind := "regular", color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(t, font_size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l
