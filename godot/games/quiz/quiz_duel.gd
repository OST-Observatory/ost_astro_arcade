## Quiz duel: two players side by side, each with their own answer boxes; the question in
## the middle. Answers are read from raw touch events, so both can tap at the same moment
## (Godot buttons only follow the first finger). The solution appears once both have
## answered or the time is up.
class_name QuizDuel
extends Control

const PANEL_W := 680.0
const BOX_H := 190.0
const LETTERS := ["A", "B", "C", "D"]
const COLORS := [Color("4dd0e1"), Color("ffb347")]

var rng_seed := 0
var logic := DuelLogic.new()
var _rng := RandomNumberGenerator.new()
var _layer: Control
var _boxes := [[], []]        # per player: 4 Panels
var _score_labels: Array[Label] = []
var _state_labels: Array[Label] = []
var _ring: RingProgress
var _time_label: Label
var _time_left := 0.0
var _open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	logic.new_round(_rng)
	Router.step("duel")
	_show_question()


func _panel_x(p: int) -> float:
	return 40.0 if p == 0 else 2560.0 - 40.0 - PANEL_W


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
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_boxes = [[], []]
	_score_labels.clear()
	_state_labels.clear()

	var count := _plain(tr("DUEL_QUESTION") % [logic.index + 1, DuelLogic.ROUND], UiTheme.SIZE_BODY, "semibold", UiTheme.TEXT_DIM)
	count.position = Vector2(760, 40)
	count.size = Vector2(1040, 50)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(count)
	var text := _plain(QuizLogic.text(q, "text", loc), UiTheme.SIZE_H2 - 4, "serif")
	text.position = Vector2(780, 110)
	text.size = Vector2(1000, 330)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_layer.add_child(text)
	if q.has("image") and ResourceLoader.exists(q.image):
		var img := TextureRect.new()
		img.texture = load(q.image)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.position = Vector2(800, 470)
		img.size = Vector2(960, 560)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(img)
	_ring = RingProgress.new()
	_ring.position = Vector2(1180, 1080)
	_ring.size = Vector2(200, 200)
	_layer.add_child(_ring)
	_time_label = _plain("", 64, "bold", UiTheme.TEXT)
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ring.add_child(_time_label)

	var answers: Array = QuizLogic.text(q, "answers", loc)
	for p in 2:
		var x := _panel_x(p)
		var head_x := x + (170.0 if p == 0 else 0.0)   # keep clear of the home button
		var name := _plain(tr("DUEL_PLAYER") % (p + 1), UiTheme.SIZE_H2 - 6, "serif", COLORS[p])
		name.position = Vector2(head_x, 60)
		_layer.add_child(name)
		var score := _plain(tr("AST_SCORE") % logic.scores[p], UiTheme.SIZE_BODY + 4, "bold", UiTheme.TEXT)
		score.position = Vector2(head_x, 150)
		_layer.add_child(score)
		_score_labels.append(score)
		var state := _plain("", UiTheme.SIZE_BODY, "semibold", COLORS[p])
		state.position = Vector2(x, 1290)
		state.size = Vector2(PANEL_W, 80)
		_layer.add_child(state)
		_state_labels.append(state)
		for i in 4:
			var box := _answer_box(LETTERS[i], str(answers[i]), COLORS[p])
			box.position = Vector2(x, 260 + i * (BOX_H + 22))
			_layer.add_child(box)
			_boxes[p].append(box)
	_time_left = QuizLogic.TIME_PER_QUESTION
	_open = true


func _answer_box(letter: String, answer: String, col: Color) -> Panel:
	var box := Panel.new()
	box.size = Vector2(PANEL_W, BOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE, Color(col, 0.35), 2, 22))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 26
	h.offset_right = -20
	h.add_theme_constant_override("separation", 22)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(h)
	var badge := _plain(letter, 44, "bold", col)
	badge.custom_minimum_size = Vector2(50, 0)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(badge)
	var l := _plain(answer, UiTheme.SIZE_BODY if answer.length() < 60 else UiTheme.SIZE_SMALL, "medium", UiTheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return box


func _input(event: InputEvent) -> void:
	if not _open or not (event is InputEventScreenTouch and event.pressed):
		return
	for p in 2:
		if logic.has_answered(p):
			continue
		for i in 4:
			var box: Panel = _boxes[p][i]
			if Rect2(box.position, box.size).has_point(event.position):
				_answer(p, i)
				get_viewport().set_input_as_handled()
				return


func _answer(p: int, i: int) -> void:
	logic.answer(p, i, _time_left)
	Audio.play("tap")
	var box: Panel = _boxes[p][i]
	box.add_theme_stylebox_override("panel", UiTheme.box(Color(COLORS[p], 0.35), COLORS[p], 4, 22))
	_state_labels[p].text = tr("DUEL_LOCKED")
	if logic.both_answered():
		_reveal()


func _process(delta: float) -> void:
	if not _open:
		return
	_time_left -= delta
	_ring.value = clampf(_time_left / QuizLogic.TIME_PER_QUESTION, 0.0, 1.0)
	_time_label.text = str(maxi(0, int(ceil(_time_left))))
	if _time_left <= 0.0:
		_reveal()


func _reveal() -> void:
	_open = false
	var q := logic.current()
	var right := int(q.correct)
	for p in 2:
		for i in 4:
			var box: Panel = _boxes[p][i]
			if i == right:
				box.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.SUCCESS, 0.3), UiTheme.SUCCESS, 4, 22))
			elif i == logic.choices[p]:
				box.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.DANGER, 0.25), UiTheme.DANGER, 4, 22))
		var pts: int = logic.earned[p]
		_state_labels[p].text = ("+%d" % pts) if pts > 0 else (tr("DUEL_NO_ANSWER") if logic.choices[p] < 0 else tr("DUEL_WRONG"))
		_state_labels[p].add_theme_color_override("font_color", UiTheme.SUCCESS if pts > 0 else UiTheme.DANGER)
		_score_labels[p].text = tr("AST_SCORE") % logic.scores[p]
	Audio.play("success" if logic.earned[0] > 0 or logic.earned[1] > 0 else "fail", "SFX", 0.6)
	_ring.visible = false
	var ex := _plain(str(QuizLogic.text(q, "explain", I18n.locale)), UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ex.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ex.position = Vector2(800, 1040)
	ex.size = Vector2(960, 150)
	_layer.add_child(ex)
	var next := BigButton.make("QUIZ_NEXT" if logic.index + 1 < DuelLogic.ROUND else "QUIZ_RESULT", "play_arrow", true, 420)
	next.position = Vector2(1070, 1240)
	next.pressed.connect(func():
		logic.next()
		_show_question())
	_layer.add_child(next)


func _show_result() -> void:
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	Router.step("duel_done")
	Router.complete({"mode": "duel", "scores": logic.scores, "winner": logic.winner()})
	Audio.play("success")
	Confetti.burst(self)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 34)
	_layer.add_child(v)
	var w := logic.winner()
	var trophy := UiTheme.icon("trophy", 200, UiTheme.ACCENT if w < 0 else COLORS[w])
	trophy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(trophy)
	var head := _plain(tr("DUEL_DRAW") if w < 0 else tr("DUEL_WINS") % (w + 1), UiTheme.SIZE_TITLE - 10, "serif",
		UiTheme.TEXT if w < 0 else COLORS[w])
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var scores := _plain(tr("DUEL_SCORES") % [logic.scores[0], logic.scores[1]], UiTheme.SIZE_H2, "medium", UiTheme.TEXT)
	scores.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(scores)
	var on_again := func():
		_layer.queue_free()
		_layer = null
		logic.new_round(_rng)
		_show_question()
	v.add_child(ResultActions.make("DUEL_AGAIN", "refresh", on_again, 1700.0, false))


func _plain(t: String, font_size: int, kind := "regular", color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(t, font_size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
