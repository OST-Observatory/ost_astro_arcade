## Asteroid hunt, core step: the blink comparator.
## Three exposures of the same sky field, 20 minutes apart, are shown in turn. Stars
## stay put, the asteroid jumps. Tap it! Holding a finger shows a loupe; wrong taps
## get an explanation (cosmic ray, hot pixel, variable star, satellite, star).
extends Control

const IMAGE_RECT := Rect2(168, 150, 1680, 1120)
const PANEL_X := 1904
const PANEL_W := 600.0
const BLINK_SEC := 0.6
const HOLD_SEC := 0.25
const LOUPE_SIZE := 420.0
const LOUPE_ZOOM := 3.5

var challenge: BlinkChallenge
var _rng := RandomNumberGenerator.new()
var _frames: CcdFrames
var _view: TextureRect
var _loupe: TextureRect
var _marks: _Marks
var _dots: Array[Label] = []
var _msg: Label
var _timer_label: Label
var _frame := 0
var _blink_t := 0.0
var _paused := false
var _elapsed := 0.0
var _running := false
var _wrong := 0
var _hints := 0
var _press_t := -1.0
var _press_pos := Vector2.ZERO
var _loupe_on := false
var skip_intro := false  # screenshots/tests: go straight to the blink view
var rng_seed := 0        # 0 = random


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	add_child(Starfield.new())
	if skip_intro:
		_new_round()
		return
	var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("asteroid"))
	add_child(start)
	await start.start_pressed
	start.queue_free()
	Router.step("start")
	await _intro()
	_new_round()


func _intro() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 34)
	add_child(v)
	for item in [["AST_INTRO_TITLE", UiTheme.SIZE_TITLE, "serif", UiTheme.TEXT],
			["AST_INTRO_TEXT", UiTheme.SIZE_H2 - 6, "regular", UiTheme.TEXT],
			["AST_INTRO_HOLD", UiTheme.SIZE_BODY + 4, "regular", UiTheme.SCIENCE]]:
		var l := UiTheme.label(item[0], item[1], item[2], item[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1700, 0)
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(l)
	var go := BigButton.make("AST_GO", "play_arrow", true, 520)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(go)
	await go.pressed
	v.queue_free()


# --- round setup -----------------------------------------------------------------------

func _new_round() -> void:
	for c in get_children():
		if not (c is Starfield):
			c.queue_free()
	Session.ensure_name()
	var diff := Session.difficulty_name()
	var sc := AsteroidScenario.pick(diff, _rng)
	if sc == null:
		push_error("No asteroid scenarios found – run tools/asteroid/build_scenarios.py")
		return
	challenge = BlinkChallenge.create(sc, diff, _rng)
	_frames = CcdFrames.new()
	add_child(_frames)
	_frames.build(challenge.stars_px, challenge.frames)
	_build_ui()
	_frame = 0
	_blink_t = 0.0
	_elapsed = 0.0
	_wrong = 0
	_hints = 0
	_paused = false
	_running = true
	_show_frame(0)
	Router.step("blink")


func _build_ui() -> void:
	var frame_bg := Panel.new()
	frame_bg.position = IMAGE_RECT.position - Vector2(6, 6)
	frame_bg.size = IMAGE_RECT.size + Vector2(12, 12)
	frame_bg.add_theme_stylebox_override("panel", UiTheme.box(Color.BLACK, Color(UiTheme.SCIENCE, 0.5), 3, 10))
	frame_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame_bg)

	_view = _ccd_rect(false)
	_view.position = IMAGE_RECT.position
	_view.size = IMAGE_RECT.size
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	add_child(_view)

	_marks = _Marks.new()
	_marks.game = self
	_marks.position = IMAGE_RECT.position
	_marks.size = IMAGE_RECT.size
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marks)

	_loupe = _ccd_rect(true)
	_loupe.size = Vector2(LOUPE_SIZE, LOUPE_SIZE)
	_loupe.visible = false
	_loupe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_loupe)

	# Right panel: task, frame indicator, timer, feedback.
	var panel := VBoxContainer.new()
	panel.position = Vector2(PANEL_X, IMAGE_RECT.position.y)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_theme_constant_override("separation", 30)
	add_child(panel)
	var title := UiTheme.label("AST_INTRO_TITLE", UiTheme.SIZE_H2, "serif")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(title)
	var task := UiTheme.label("AST_TASK", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_child(task)

	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 18)
	_dots.clear()
	for i in BlinkChallenge.FRAMES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 130)
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.flat = true
		b.pressed.connect(_on_dot.bind(i))
		var l := UiTheme.label(str(i + 1), 60, "bold", UiTheme.TEXT_DIM)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SURFACE, UiTheme.LINE, 3, 65))
		b.add_child(l)
		dots.add_child(b)
		_dots.append(l)
	panel.add_child(dots)
	var minutes := UiTheme.label("AST_FRAME_TIMES", UiTheme.SIZE_SMALL, "regular", UiTheme.TEXT_DIM)
	minutes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	minutes.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_child(minutes)

	_timer_label = UiTheme.label("", UiTheme.SIZE_H2, "medium", UiTheme.SCIENCE)
	_timer_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	panel.add_child(_timer_label)

	_msg = UiTheme.label("", UiTheme.SIZE_BODY, "medium", UiTheme.ACCENT_HI)
	_msg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(PANEL_W, 340)
	panel.add_child(_msg)

	var date_info := UiTheme.label("", UiTheme.SIZE_SMALL, "regular", UiTheme.TEXT_DIM)
	date_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	date_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	date_info.custom_minimum_size = Vector2(PANEL_W, 0)
	date_info.text = tr("AST_FIELD_INFO") % [BlinkResult._date(challenge.scenario.data.night), "CDK20 · QHY600", "35′ × 24′"]
	panel.add_child(date_info)


func _ccd_rect(is_loupe: bool) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _frames.textures[0]
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	var m := ShaderMaterial.new()
	m.shader = preload("res://games/asteroid/ccd/ccd_display.gdshader")
	m.set_shader_parameter("image_size", Vector2(AsteroidScenario.IMAGE_SIZE))
	m.set_shader_parameter("circle", is_loupe)
	r.material = m
	return r


# --- per frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_timer_label.text = "%d:%02d" % [int(_elapsed) / 60, int(_elapsed) % 60]
	if not _paused:
		_blink_t += delta
		if _blink_t >= BLINK_SEC:
			_blink_t = 0.0
			_show_frame((_frame + 1) % BlinkChallenge.FRAMES)
	var hint_times: Array = challenge.rules.hints
	if _hints < hint_times.size() and _elapsed >= hint_times[_hints]:
		_hints += 1
		_msg.text = tr("AST_HINT_%d" % _hints)
		Audio.play("tick")
		_marks.queue_redraw()
	if _press_t >= 0.0:
		_press_t += delta
		if _press_t >= HOLD_SEC and not _loupe_on:
			_loupe_on = true
			_update_loupe(_press_pos)


func _show_frame(i: int) -> void:
	_frame = i
	for v in [_view, _loupe]:
		v.texture = _frames.textures[i]
		(v.material as ShaderMaterial).set_shader_parameter("frame", _frames.textures[i])
		(v.material as ShaderMaterial).set_shader_parameter("seed", float(i * 7 + 3))
	for d in _dots.size():
		var active := d == i
		_dots[d].add_theme_color_override("font_color", UiTheme.BG if active else UiTheme.TEXT_DIM)
		_dots[d].add_theme_stylebox_override("normal",
			UiTheme.box(UiTheme.ACCENT if active else UiTheme.SURFACE, UiTheme.ACCENT_HI if active else UiTheme.LINE, 3, 65))


func _on_dot(i: int) -> void:
	Audio.play("tap")
	if _paused and _frame == i:
		_paused = false
		return
	_paused = true
	_show_frame(i)


# --- input -------------------------------------------------------------------------------

func _on_view_input(event: InputEvent) -> void:
	if not _running:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press_t = 0.0
			_press_pos = event.position
		else:
			var was_hold := _loupe_on
			_press_t = -1.0
			_loupe_on = false
			_loupe.visible = false
			if not was_hold:
				_on_tap(event.position)
	elif event is InputEventScreenDrag:
		_press_pos = event.position
		if _loupe_on:
			_update_loupe(event.position)
		elif event.relative.length() > 12.0:
			_press_t = 0.0  # moving finger: treat as a hold in progress, not a tap


func _view_to_image(p: Vector2) -> Vector2:
	return p / IMAGE_RECT.size * Vector2(AsteroidScenario.IMAGE_SIZE)


func _update_loupe(p: Vector2) -> void:
	_loupe.visible = true
	var uv := p / IMAGE_RECT.size
	var m := _loupe.material as ShaderMaterial
	m.set_shader_parameter("view_center", uv)
	var span := Vector2.ONE * (LOUPE_SIZE / LOUPE_ZOOM) / IMAGE_RECT.size
	m.set_shader_parameter("view_span", span)
	# Show the loupe above the finger so it is not covered.
	_loupe.position = IMAGE_RECT.position + p - Vector2(LOUPE_SIZE / 2.0, LOUPE_SIZE + 60.0)
	_loupe.position.y = maxf(_loupe.position.y, 8.0)


func _on_tap(view_pos: Vector2) -> void:
	var p := _view_to_image(view_pos)
	var kind := challenge.classify(p, _frame)
	_marks.add_tap(view_pos, kind == "asteroid")
	if kind == "asteroid":
		_found()
		return
	_wrong += 1
	Audio.play("fail", "UI", 1.0, -6.0)
	_msg.text = tr("AST_WRONG_" + kind.to_upper())


func _found() -> void:
	_running = false
	_paused = true
	Audio.play("success")
	Router.step("found")
	var secs := _elapsed
	var pts := challenge.score(secs, _wrong, _hints)
	var stars := BlinkChallenge.stars_for(_wrong, _hints)
	var rank := Scores.submit("asteroid", Session.player_name, pts, stars,
		{"object": challenge.scenario.display_name()})
	Router.complete({"score": pts, "stars": stars, "wrong": _wrong, "hints": _hints,
		"seconds": snappedf(secs, 0.1), "object": challenge.scenario.data.number})
	_marks.show_solution = true
	_marks.queue_redraw()
	await get_tree().create_timer(1.6).timeout
	var result := BlinkResult.new()
	result.setup(challenge, pts, stars, rank, secs)
	result.again.connect(_new_round)
	add_child(result)


## Markers drawn over the image: tap feedback, hint circles, the solution.
class _Marks:
	extends Control

	var game: Node
	var show_solution := false
	var _taps: Array = []  # [pos, ok, age]
	var _hint_center := Vector2.ZERO

	func add_tap(p: Vector2, ok: bool) -> void:
		_taps.append([p, ok, 0.0])
		queue_redraw()

	func _process(delta: float) -> void:
		for t in _taps:
			t[2] += delta
		_taps = _taps.filter(func(t): return t[2] < 1.2)
		if not _taps.is_empty() or game._hints > 0:
			queue_redraw()

	func _to_view(px: Vector2) -> Vector2:
		return px / Vector2(AsteroidScenario.IMAGE_SIZE) * size

	func _draw() -> void:
		var ch: BlinkChallenge = game.challenge
		for t in _taps:
			var a: float = 1.0 - t[2] / 1.2
			var col := UiTheme.SUCCESS if t[1] else UiTheme.DANGER
			draw_arc(t[0], 30.0 + 40.0 * t[2], 0, TAU, 48, Color(col, a), 4.0, true)
		if game._hints > 0 and not show_solution:
			if _hint_center == Vector2.ZERO:
				# Hint circle around the asteroid, but not centred on it.
				var off := Vector2.from_angle(randf() * TAU) * 120.0
				_hint_center = ch.asteroid_px[1] + off
			var r := 330.0 if game._hints == 1 else 150.0
			var c := _to_view(_hint_center if game._hints == 1 else ch.asteroid_px[1] + (_hint_center - ch.asteroid_px[1]) * 0.3)
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
			draw_arc(c, r * size.x / AsteroidScenario.IMAGE_SIZE.x, 0, TAU, 96, Color(UiTheme.SCIENCE, 0.4 + 0.4 * pulse), 4.0, true)
		if show_solution:
			var pts := ch.asteroid_px.map(func(p): return _to_view(p))
			for i in pts.size():
				draw_arc(pts[i], 26.0, 0, TAU, 40, UiTheme.SUCCESS, 4.0, true)
				if i > 0:
					draw_line(pts[i - 1], pts[i], Color(UiTheme.SUCCESS, 0.8), 3.0, true)
