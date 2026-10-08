## Knowledge card that unlocks a building block: a question with three answers (shuffled),
## then right/wrong, the explanation and a button to go on. Emits `done(right)`.
class_name QuizCard
extends Control

signal done(right: bool)

var question_id := ""
var order: Array = [0, 1, 2]
var _buttons: Array[BigButton] = []
var _box: VBoxContainer
var _answered := false


static func make(qid: String, rng: RandomNumberGenerator) -> QuizCard:
	var c := QuizCard.new()
	c.question_id = qid
	c.order = BuildLogic.answer_order(rng)
	return c


func _key(part: String) -> String:
	return "GAL_Q_%s_%s" % [question_id.to_upper(), part]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SCIENCE, 0.6), 3))
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(1300, 0)
	_box.add_theme_constant_override("separation", 26)
	panel.add_child(_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	head.add_child(UiTheme.icon("lightbulb", 70, UiTheme.SCIENCE))
	head.add_child(UiTheme.label("GAL_QUIZ_HEAD", UiTheme.SIZE_BODY, "semibold", UiTheme.SCIENCE))
	_box.add_child(head)
	var q := UiTheme.label(_key("Q"), UiTheme.SIZE_H2 - 4, "serif", UiTheme.TEXT)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(1300, 0)
	_box.add_child(q)
	for i in order:
		var b := BigButton.make(_key("A%d" % i), "", false, 1300)
		b.pressed.connect(_answer.bind(i, b))
		_box.add_child(b)
		_buttons.append(b)


func _answer(i: int, b: BigButton) -> void:
	if _answered:
		return
	_answered = true
	var right := i == 0
	Audio.play("success" if right else "fail", "SFX", 0.6)
	for k in _buttons.size():
		var bk := _buttons[k]
		bk.disabled = true
		var ok: bool = order[k] == 0
		if ok or bk == b:
			var col := UiTheme.SUCCESS if ok else UiTheme.DANGER
			for s in ["normal", "disabled"]:
				bk.add_theme_stylebox_override(s, UiTheme.box(Color(col, 0.25), col, 3))
	var res := UiTheme.label("GAL_QUIZ_RIGHT" if right else "GAL_QUIZ_WRONG", UiTheme.SIZE_BODY + 2, "semibold",
		UiTheme.SUCCESS if right else UiTheme.ACCENT_HI)
	_box.add_child(res)
	var ex := UiTheme.label(_key("EXPL"), UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ex.custom_minimum_size = Vector2(1300, 0)
	_box.add_child(ex)
	var go := BigButton.make("GAL_QUIZ_GO", "arrow_forward", true, 420)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(func():
		done.emit(right)
		queue_free())
	_box.add_child(go)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
