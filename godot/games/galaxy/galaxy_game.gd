## Galaxy builder: pick a real pair of colliding galaxies, then turn the knobs (time since
## the encounter, mass, distance, tilt) until the simulated collision looks like the photo.
## Every run is scored by comparing star-density maps of the player's encounter with the
## encounter that reproduces the photo (GalaxyModel on the CPU, in a background thread).
## Five attempts; hints say which knob is furthest off (not for pros).
extends Control

const VIEW := Rect2(40, 170, 1540, 1230)
const PANEL_X := 1625.0
const PANEL_W := 890.0

var skip_intro := false   # screenshots/tests
var target_id := ""       # preset target (skips the picker)
var logic_diff := ""
var _target: Dictionary
var _knobs := {}
var _controls: Array[String] = []
var _sliders := {}
var _switch_buttons: Array[Button] = []
var _view: GalaxyView
var _ref_map := PackedFloat32Array()
var _thread: Thread
var _attempts := 0
var _best := 0
var _running := false
var _phase := "build"      # build -> run -> build ... -> result
var _ui: Control
var _col: VBoxContainer
var _run_btn: BigButton
var _done_btn: BigButton
var _ring: RingProgress
var _sim_label: Label
var _attempt_label: Label
var _hint_label: Label
var _time_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	logic_diff = Session.difficulty_name()
	add_child(Starfield.new())
	if not skip_intro:
		var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("galaxy"))
		add_child(start)
		await start.start_pressed
		start.queue_free()
		logic_diff = Session.difficulty_name()
	if target_id == "":
		await _pick_target()
	else:
		_target = GalaxyLogic.target(target_id)
	_start()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func _clear() -> void:
	for c in get_children():
		if not (c is Starfield):
			c.queue_free()
	_sliders.clear()
	_switch_buttons.clear()


# --- target picker -----------------------------------------------------------------------

func _pick_target() -> void:
	_clear()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 40)
	add_child(v)
	var t := UiTheme.label("GAL_PICK", UiTheme.SIZE_H2 + 10, "serif")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UiTheme.label("GAL_PICK_SUB", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	v.add_child(row)
	var chosen := [null]
	for e in GalaxyLogic.TARGETS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(700, 640)
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 18
		col.offset_right = -18
		col.offset_top = 18
		col.add_theme_constant_override("separation", 14)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var img := TextureRect.new()
		img.texture = load(e.image)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.custom_minimum_size = Vector2(664, 470)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(img)
		var name := UiTheme.label("GAL_T_" + str(e.id).to_upper(), UiTheme.SIZE_BODY + 4, "semibold", UiTheme.ACCENT_HI)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(name)
		b.pressed.connect(func():
			Audio.play("tap")
			chosen[0] = e)
		row.add_child(b)
	while chosen[0] == null:
		await get_tree().process_frame
	_target = chosen[0]
	v.queue_free()


# --- building ------------------------------------------------------------------------------

func _start() -> void:
	_clear()
	_attempts = 0
	_best = 0
	_phase = "build"
	_running = false
	_ref_map = PackedFloat32Array()
	_controls = GalaxyLogic.controls_for(_target, logic_diff)
	_knobs = GalaxyLogic.start_values(_target, _controls)

	var frame := Panel.new()
	frame.position = VIEW.position - Vector2(6, 6)
	frame.size = VIEW.size + Vector2(12, 12)
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.6), Color(UiTheme.SCIENCE, 0.45), 3, 10))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var vp := SubViewportContainer.new()
	vp.stretch = true
	vp.position = VIEW.position
	vp.size = VIEW.size
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	vp.add_child(sv)
	_view = GalaxyView.new()
	sv.add_child(_view)
	_view.finished.connect(_on_run_finished)

	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var title := UiTheme.label("GAL_T_" + str(_target.id).to_upper(), UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
	title.position = Vector2(200, 52)
	_ui.add_child(title)
	_attempt_label = _plain("", UiTheme.SIZE_BODY + 2, "semibold", UiTheme.ACCENT_HI)
	_attempt_label.position = Vector2(1240, 66)
	_ui.add_child(_attempt_label)
	_sim_label = UiTheme.label("GAL_SIM", UiTheme.SIZE_SMALL, "semibold", UiTheme.SCIENCE)
	_sim_label.position = VIEW.position + Vector2(28, 20)
	_ui.add_child(_sim_label)
	_time_label = _plain("", UiTheme.SIZE_BODY, "medium", UiTheme.TEXT)
	_time_label.position = VIEW.position + Vector2(28, VIEW.size.y - 70)
	_ui.add_child(_time_label)

	# Right column: the real photo, the knobs, the run button and the score ring.
	var col := VBoxContainer.new()
	_col = col
	col.position = Vector2(PANEL_X, 150)
	col.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_theme_constant_override("separation", 16)
	_ui.add_child(col)
	var photo_title := UiTheme.label("GAL_REAL", UiTheme.SIZE_SMALL, "semibold", UiTheme.ACCENT)
	col.add_child(photo_title)
	var photo := TextureRect.new()
	photo.texture = load(_target.image)
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.custom_minimum_size = Vector2(PANEL_W, 400)
	col.add_child(photo)
	var credit := _plain(_credit(), UiTheme.SIZE_SMALL - 8, "regular", UiTheme.TEXT_DIM)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_child(credit)
	for c in _controls:
		col.add_child(_make_control(c))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 18)
	_run_btn = BigButton.make("GAL_RUN", "play_arrow", true, 500)
	_run_btn.pressed.connect(_run)
	buttons.add_child(_run_btn)
	_done_btn = BigButton.make("GAL_DONE", "check", false, 280)
	_done_btn.pressed.connect(_finish)
	_done_btn.visible = false
	buttons.add_child(_done_btn)
	col.add_child(buttons)

	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 22)
	_ring = RingProgress.new()
	_ring.custom_minimum_size = Vector2(150, 150)
	_ring.value = 0.0
	_ring.color = UiTheme.SUCCESS
	score_row.add_child(_ring)
	_hint_label = _plain("", UiTheme.SIZE_BODY - 2, "medium", UiTheme.TEXT)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(PANEL_W - 180, 0)
	_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_row.add_child(_hint_label)
	col.add_child(score_row)
	_hint_label.text = tr("GAL_TASK")

	_update_attempts()
	_preview()
	Router.step("build")
	# The reference map is needed only after the first run; start it right away.
	_compute_async({})


func _make_control(c: String) -> Control:
	var spec: Array = GalaxyLogic.CONTROLS[c]
	if c.begins_with("spin"):
		var box := VBoxContainer.new()
		box.add_child(UiTheme.label("GAL_K_" + c.to_upper(), UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		for v in [1.0, -1.0]:
			var b := BigButton.make("GAL_SPIN_WITH" if v > 0 else "GAL_SPIN_AGAINST", "rotate_right" if v > 0 else "rotate_left", false, 400)
			b.toggle_mode = true
			b.button_pressed = is_equal_approx(float(_knobs[c]), v)
			b.pressed.connect(func():
				_knobs[c] = v
				for o in _switch_buttons:
					o.button_pressed = o == b
				_preview())
			_switch_buttons.append(b)
			row.add_child(b)
		box.add_child(row)
		return box
	var k := KnobSlider.make("GAL_K_" + c.to_upper(), spec[0], spec[1], spec[2], _knobs[c], _formatter(c))
	k.changed.connect(func(v: float):
		_knobs[c] = v
		_preview())
	_sliders[c] = k
	return k


func _formatter(c: String) -> Callable:
	match c:
		"t_after":
			return func(v: float) -> String: return tr("GAL_V_MYR") % GalaxyLogic.myr(v)
		"m2":
			return func(v: float) -> String: return tr("GAL_V_MASS") % int(round(v * 100.0))
		"q":
			return func(v: float) -> String: return tr("GAL_V_LY") % int(round(v * 10.0))
		_:
			return func(v: float) -> String: return "%d°" % int(v)


func _credit() -> String:
	return tr("GAL_CREDIT") % _target.credit


## Shows the two galaxies before the collision with the current knob values.
func _preview() -> void:
	if _running:
		return
	_view.setup(GalaxyLogic.params_for(_target, _knobs), _target.extent)
	_time_label.text = tr("GAL_BEFORE")


func _update_attempts() -> void:
	_attempt_label.text = tr("GAL_ATTEMPT") % [mini(_attempts + 1, GalaxyLogic.ATTEMPTS), GalaxyLogic.ATTEMPTS]
	if _best > 0:
		_attempt_label.text += "   ·   " + tr("GAL_BEST") % _best


func _set_inputs(on: bool) -> void:
	_run_btn.disabled = not on
	_done_btn.disabled = not on
	for k in _sliders.values():
		(k as KnobSlider).set_enabled(on)
	for b in _switch_buttons:
		b.disabled = not on


func _run() -> void:
	if _running:
		return
	_running = true
	_phase = "run"
	_attempts += 1
	_set_inputs(false)
	Router.step("run_%d" % _attempts)
	Audio.play("whoosh", "SFX", 0.6)
	var p := GalaxyLogic.params_for(_target, _knobs)
	_view.setup(p, _target.extent)
	_view.play()
	_compute_async(_knobs.duplicate())
	_hint_label.text = tr("GAL_RUNNING")


func _process(_delta: float) -> void:
	if _running and _view:
		var left := GalaxyModel.t_end(_view.params) - _view.t
		var after := _view.t - GalaxyModel.T_PERI
		if after < 0.0:
			_time_label.text = tr("GAL_T_TO_ENCOUNTER") % GalaxyLogic.myr(-after)
		else:
			_time_label.text = tr("GAL_T_SINCE") % GalaxyLogic.myr(after)
		if left <= 0.0:
			_time_label.text = tr("GAL_T_NOW")


# --- scoring in a background thread ------------------------------------------------------

var _result_corr := -2.0


## Computes the reference map (once) and, if knobs are given, the player's map + correlation.
func _compute_async(knobs: Dictionary) -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_result_corr = -2.0
	_thread = Thread.new()
	var t := _target
	var ref := _ref_map
	_thread.start(func() -> Array:
		var r := ref if not ref.is_empty() else GalaxyLogic.density(t, t.params)
		var corr := -2.0
		if not knobs.is_empty():
			corr = GalaxyModel.correlation(r, GalaxyLogic.density(t, GalaxyLogic.params_for(t, knobs)))
		return [r, corr])


func _collect() -> float:
	var res: Array = _thread.wait_to_finish()
	_ref_map = res[0]
	return float(res[1])


func _on_run_finished() -> void:
	if _phase != "run":
		return
	_phase = "build"
	var corr := _collect()
	var sim := GalaxyLogic.similarity(_target, corr)
	_running = false
	var improved := sim > _best
	_best = maxi(_best, sim)
	_time_label.text = tr("GAL_T_NOW")
	var tw := create_tween()
	tw.tween_property(_ring, "value", sim / 100.0, 0.8).set_trans(Tween.TRANS_CUBIC)
	_ring.color = UiTheme.SUCCESS if sim >= 90 else (UiTheme.ACCENT if sim >= 50 else UiTheme.DANGER)
	Audio.play("success" if improved else "tick")
	var lines := [tr("GAL_SIMILARITY") % sim]
	var h := GalaxyLogic.hint(_target, _knobs)
	if sim >= 97 or _attempts >= GalaxyLogic.ATTEMPTS:
		_hint_label.text = "\n".join(lines)
		_update_attempts()
		await get_tree().create_timer(1.6).timeout
		_finish()
		return
	if h.is_empty() or sim >= 90:
		lines.append(tr("GAL_HINT_CLOSE"))
	elif logic_diff != "pro":
		var knob: String = h[0]
		if knob.begins_with("spin"):
			lines.append(tr("GAL_HINT_SPIN"))
		else:
			lines.append(tr("GAL_HINT_%s_%s" % [knob.to_upper(), "UP" if int(h[1]) > 0 else "DOWN"]))
	else:
		lines.append(tr("GAL_TRY_AGAIN"))
	_hint_label.text = "\n".join(lines)
	_update_attempts()
	_done_btn.visible = true
	_set_inputs(true)


# --- result ------------------------------------------------------------------------------

func _finish() -> void:
	if _running:
		return
	_running = true
	_phase = "result"
	_set_inputs(false)
	Router.step("done")
	var stars := GalaxyLogic.stars(_best)
	var pts := GalaxyLogic.score(_best, _attempts, logic_diff)
	var rank := Scores.submit("galaxy", Session.player_name, pts, stars, {"target": _target.id})
	Router.complete({"score": pts, "stars": stars, "similarity": _best, "attempts": _attempts,
		"target": _target.id})
	Audio.play("success")
	_show_result(pts, stars, rank)


func _show_result(pts: int, stars: int, rank: Dictionary) -> void:
	_col.visible = false
	_attempt_label.visible = false
	var panel := PanelContainer.new()
	panel.position = Vector2(PANEL_X - 20, 150)
	panel.custom_minimum_size = Vector2(PANEL_W + 30, 1230)
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SUCCESS, 0.6), 3))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)
	v.add_child(UiTheme.label("GAL_RESULT_TITLE", UiTheme.SIZE_H2, "serif", UiTheme.SUCCESS))
	var star_row := HBoxContainer.new()
	for i in 3:
		star_row.add_child(UiTheme.icon("star" if i < stars else "star_border", 90, UiTheme.ACCENT))
	v.add_child(star_row)
	v.add_child(_plain(tr("GAL_RESULT") % [_best, _attempts], UiTheme.SIZE_BODY, "medium", UiTheme.TEXT))
	v.add_child(_plain(tr("AST_SCORE") % pts + "  ·  " + tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))],
		UiTheme.SIZE_BODY - 2, "semibold", UiTheme.ACCENT_HI))
	var name := UiTheme.label("GAL_T_" + str(_target.id).to_upper(), UiTheme.SIZE_BODY + 2, "semibold", UiTheme.ACCENT_HI)
	v.add_child(name)
	var desc := UiTheme.label("GAL_D_" + str(_target.id).to_upper(), UiTheme.SIZE_BODY - 4, "regular", UiTheme.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	v.add_child(desc)
	var answer := _plain(_answer_text(), UiTheme.SIZE_SMALL - 2, "regular", UiTheme.SCIENCE)
	answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answer.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	v.add_child(answer)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var home := BigButton.make("BACK_TO_HUB", "home", false, 360)
	home.pressed.connect(func(): Router.go_home("home"))
	row.add_child(home)
	var again := BigButton.make("GAL_AGAIN", "blur_on", true, 440)
	again.pressed.connect(func():
		_running = false
		await _pick_target()
		_start())
	row.add_child(again)
	v.add_child(row)
	# Show the "true" encounter that reproduces the photo behind the result.
	_running = false
	_view.setup(_target.params, _target.extent)
	_view.play()
	_running = true
	_sim_label.text = tr("GAL_TRUE_SIM")


## The knob values that reproduce the photo.
func _answer_text() -> String:
	var parts: Array[String] = []
	for c in _controls:
		var v := float(_target.params[c])
		if c.begins_with("spin"):
			parts.append(tr("GAL_K_" + c.to_upper()) + ": " + tr("GAL_SPIN_WITH" if v > 0 else "GAL_SPIN_AGAINST"))
		else:
			parts.append(tr("GAL_K_" + c.to_upper()) + ": " + _formatter(c).call(v))
	return tr("GAL_ANSWER") + "\n" + "\n".join(parts)


func _plain(t: String, font_size: int, kind := "regular", color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(t, font_size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
