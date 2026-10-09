## Explore the solar system with five "find …" tasks: tap bodies to learn about them; the
## right one solves the task (faster = more points). After HINT_AFTER seconds a button flies
## there. When the round is over the visitor can keep exploring freely.
class_name ExploreMode
extends Control

signal menu_pressed

var view: SolarView
var diff := "researcher"
var panel := Rect2()
var view_rect := Rect2()
var rng := RandomNumberGenerator.new()
var _tasks: Array = []
var _index := 0
var _t := 0.0
var _hinted := false
var _total := 0
var _free := false
var _col: VBoxContainer
var _task_box: PanelContainer
var _task_head: Label
var _task_text: Label
var _task_time: Label
var _hint_btn: BigButton
var _feedback: Label
var _card: InfoCard
var _result: PanelContainer


static func make(v: SolarView, difficulty: String, panel_rect: Rect2, view_r: Rect2) -> ExploreMode:
	var m := ExploreMode.new()
	m.view = v
	m.diff = difficulty
	m.panel = panel_rect
	m.view_rect = view_r
	return m


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var today := floorf(MarsTransfer.jd_now() - 0.5) + 0.5
	view.jd = today
	view.rate = 1.0
	view.focus = "sun"
	view.selected = ""
	view.dist = 4.5
	view.pitch = 0.55
	view.small.highlight("")
	var bar := TimeBar.make(view, today)
	bar.position = Vector2(view_rect.position.x + 24, view_rect.end.y - 140)
	add_child(bar)

	_col = VBoxContainer.new()
	_col.position = panel.position
	_col.custom_minimum_size = Vector2(panel.size.x, 0)
	_col.add_theme_constant_override("separation", 18)
	add_child(_col)
	_task_box = PanelContainer.new()
	_task_box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.ACCENT, 0.55), 3, 22))
	_col.add_child(_task_box)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	_task_box.add_child(tv)
	var head_row := HBoxContainer.new()
	tv.add_child(head_row)
	_task_head = _plain(UiTheme.SIZE_SMALL, "semibold", UiTheme.ACCENT_HI)
	_task_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(_task_head)
	_task_time = _plain(UiTheme.SIZE_SMALL, "semibold", UiTheme.TEXT_DIM)
	head_row.add_child(_task_time)
	_task_text = _plain(UiTheme.SIZE_BODY, "medium", UiTheme.TEXT)
	_task_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_task_text.custom_minimum_size = Vector2(panel.size.x - 60, 0)
	tv.add_child(_task_text)
	_hint_btn = BigButton.make("SOL_HINT", "lightbulb", false, int(panel.size.x - 60))
	_hint_btn.pressed.connect(_hint)
	tv.add_child(_hint_btn)
	_feedback = _plain(UiTheme.SIZE_SMALL, "medium", UiTheme.TEXT)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size = Vector2(panel.size.x, 0)
	_col.add_child(_feedback)
	_card = InfoCard.make(panel.size.x)
	_card.fly_pressed.connect(func(id: String):
		view.fly_to(id)
		_card.show_body(id, view))
	_col.add_child(_card)
	var howto := UiTheme.label("SOL_HOWTO", UiTheme.SIZE_SMALL - 6, "regular", UiTheme.TEXT_DIM)
	howto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	howto.custom_minimum_size = Vector2(panel.size.x, 0)
	howto.position = Vector2(panel.position.x, panel.end.y - 80)
	add_child(howto)
	var menu := SolarMenuButton.make(panel)
	menu.pressed.connect(func(): menu_pressed.emit())
	add_child(menu)

	view.body_tapped.connect(_on_tap)
	view.body_double_tapped.connect(func(id: String):
		_on_tap(id)
		if id != "":
			view.fly_to(id))
	view.arrived.connect(func(_id: String): _card.show_body(_card.id, view))
	_start_round()


func _exit_tree() -> void:
	for sig in [view.body_tapped, view.body_double_tapped, view.arrived]:
		for c in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)


func _plain(font_size: int, kind: String, col: Color) -> Label:
	var l := UiTheme.label("", font_size, kind, col)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


func _start_round() -> void:
	_tasks = FindTasks.pick(diff, rng)
	_index = 0
	_total = 0
	_free = false
	_task_box.visible = true
	Router.step("find_1")
	_show_task()


func _show_task() -> void:
	_t = 0.0
	_hinted = false
	_hint_btn.visible = false
	var task: Dictionary = _tasks[_index]
	_task_head.text = tr("SOL_TASK_N") % [_index + 1, _tasks.size()]
	_task_text.text = tr("SOL_FIND_" + str(task.id).to_upper())
	view.small.highlight("")


func _process(delta: float) -> void:
	if _free or _tasks.is_empty():
		return
	_t += delta
	_task_time.text = "%d s" % int(_t)
	if _t >= FindTasks.HINT_AFTER and not _hint_btn.visible and not _hinted:
		_hint_btn.visible = true


func _hint() -> void:
	var task: Dictionary = _tasks[_index]
	_hinted = true
	_hint_btn.visible = false
	view.fly_to(str(task.fly))
	for a in task.accept:
		if str(a).begins_with("class:"):
			view.small.highlight(str(a).substr(6))
			break
	# Small bodies cannot be flown to as a group: a sentence says where to look.
	_feedback.text = tr("SOL_HINT_" + str(task.id).to_upper()) if task.id in ["trojan", "neo", "kuiper"] else ""
	_feedback.add_theme_color_override("font_color", UiTheme.SCIENCE)


func _on_tap(id: String) -> void:
	view.selected = id
	_card.show_body(id, view)
	if id == "" or _free or _tasks.is_empty():
		return
	var task: Dictionary = _tasks[_index]
	var cls := ""
	if id.begins_with("sb:"):
		cls = SmallBodies.class_of(view.small.rows[int(id.substr(3))])
	if FindTasks.accepts(task, id, cls):
		var p := FindTasks.points(_t, _hinted)
		_total += p
		Audio.play("success", "SFX", 0.7)
		_feedback.text = tr("SOL_FOUND") % p
		_feedback.add_theme_color_override("font_color", UiTheme.SUCCESS)
		_index += 1
		if _index >= _tasks.size():
			_round_done()
		else:
			Router.step("find_%d" % (_index + 1))
			_show_task()
	else:
		Audio.play("tick")
		_feedback.text = tr("SOL_NOT_IT")
		_feedback.add_theme_color_override("font_color", UiTheme.TEXT_DIM)


func _round_done() -> void:
	_free = true
	_task_box.visible = false
	_card.visible = false
	view.small.highlight("")
	Router.step("done")
	var st := FindTasks.stars(_total)
	var pts := FindTasks.score(_total, diff)
	var rank := Scores.submit("solar", Session.player_name, pts, st, {"mode": "explore"})
	Router.complete({"score": pts, "stars": st, "mode": "explore"})
	if st == 3:
		Confetti.burst(self)
	_result = PanelContainer.new()
	_result.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SUCCESS, 0.6), 3))
	_col.add_child(_result)
	_col.move_child(_result, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_result.add_child(v)
	v.add_child(UiTheme.label("SOL_FIND_DONE", UiTheme.SIZE_H2 - 6, "serif", UiTheme.SUCCESS))
	var star_row := HBoxContainer.new()
	for i in 3:
		star_row.add_child(UiTheme.icon("star" if i < st else "star_border", 76, UiTheme.ACCENT))
	v.add_child(star_row)
	var l := _plain(UiTheme.SIZE_SMALL, "semibold", UiTheme.ACCENT_HI)
	l.text = tr("AST_SCORE") % pts + "  ·  " + tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(panel.size.x - 60, 0)
	v.add_child(l)
	var keep := BigButton.make("SOL_KEEP_EXPLORING", "explore", false, int(panel.size.x - 60))
	keep.pressed.connect(func():
		_result.queue_free()
		_feedback.text = "")
	v.add_child(keep)
	v.add_child(ResultActions.make("SOL_AGAIN_FIND", "travel_explore", func():
		_result.queue_free()
		_feedback.text = ""
		_start_round(), panel.size.x - 60.0, true))
