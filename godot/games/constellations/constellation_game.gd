## Constellations: the stick figure is shown on the left; find the pattern in the real sky
## (Hipparcos stars) on the right and connect its stars with a finger – drag from star to
## star or tap one star after the other. Three constellations per game; explorers see faint
## guide lines, higher levels show more (fainter) stars and place the figure off-centre.
extends Control

const SKY := Rect2(560, 150, 1960, 1250)
const PICK_TAP := 64.0      # px: touching a star
const PICK_PASS := 36.0     # px: dragging through a star
const HINT_PENALTY := 60

var skip_intro := false   # screenshots/tests
var rng_seed := 0
var logic := ConstellationLogic.new()
var _rng := RandomNumberGenerator.new()
var _queue: Array = []
var _round := 0
var _con: Dictionary
var _edges := {}            # edge key -> true (the figure)
var _done := {}             # edge key -> true (traced)
var _members: Array[int] = []
var _pos := {}              # hip -> screen position (visible stars)
var _active := -1           # star the next line starts from
var _finger := Vector2.ZERO
var _dragging := false
var _wrong_flash := []      # [from, to, time left]
var _glow := 0.0            # member highlight strength
var _hint_until := 0.0
var _elapsed := 0.0
var _wrong := 0
var _hints := 0
var _total_points := 0
var _total_lines := 0
var _total_wrong := 0
var _total_time := 0.0
var _playing := false
var _sky: _SkyLayer
var _lines: _LineLayer
var _figure: _FigureThumb
var _panel: VBoxContainer
var _name_label: Label
var _progress: Label
var _status: Label
var _hint_btn: BigButton
var _overlay: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	logic.load_data()
	var bg := ColorRect.new()
	bg.color = Color("03040a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if not skip_intro:
		var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("constellations"))
		add_child(start)
		await start.start_pressed
		start.queue_free()
	logic.diff = Session.difficulty_name()
	_queue = logic.pick(_rng)
	_build_ui()
	_next_round()


func _build_ui() -> void:
	var frame := Panel.new()
	frame.position = SKY.position - Vector2(4, 4)
	frame.size = SKY.size + Vector2(8, 8)
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0.01, 0.015, 0.04, 1), Color(UiTheme.SCIENCE, 0.35), 2, 10))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_sky = _SkyLayer.new()
	_sky.position = SKY.position
	_sky.size = SKY.size
	_sky.clip_contents = true
	add_child(_sky)
	_lines = _LineLayer.new()
	_lines.game = self
	_lines.position = SKY.position
	_lines.size = SKY.size
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)

	var title := UiTheme.label("GAME_CONSTELLATIONS", UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
	title.position = Vector2(200, 52)
	add_child(title)
	_status = _plain("", UiTheme.SIZE_BODY, "semibold", UiTheme.ACCENT_HI)
	_status.position = Vector2(1500, 66)
	add_child(_status)

	_panel = VBoxContainer.new()
	_panel.position = Vector2(50, 170)
	_panel.custom_minimum_size = Vector2(470, 0)
	_panel.add_theme_constant_override("separation", 18)
	add_child(_panel)
	var find := UiTheme.label("CON_FIND", UiTheme.SIZE_SMALL, "semibold", UiTheme.SCIENCE)
	find.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	find.custom_minimum_size = Vector2(470, 0)
	_panel.add_child(find)
	_name_label = _plain("", UiTheme.SIZE_H2 - 6, "serif", UiTheme.ACCENT_HI)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.custom_minimum_size = Vector2(470, 0)
	_panel.add_child(_name_label)
	_figure = _FigureThumb.new()
	_figure.custom_minimum_size = Vector2(470, 470)
	_panel.add_child(_figure)
	_progress = _plain("", UiTheme.SIZE_BODY, "medium", UiTheme.TEXT)
	_panel.add_child(_progress)
	var how := UiTheme.label("CON_HOW", UiTheme.SIZE_SMALL - 2, "regular", UiTheme.TEXT_DIM)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(470, 0)
	_panel.add_child(how)
	_hint_btn = BigButton.make("CON_HINT", "lightbulb", false, 470)
	_hint_btn.pressed.connect(_use_hint)
	_panel.add_child(_hint_btn)


func _next_round() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	if _round >= _queue.size():
		_finish()
		return
	_con = _queue[_round]
	_round += 1
	_edges = ConstellationLogic.edge_set(_con)
	_done = {}
	_members = ConstellationLogic.members(_con)
	_active = -1
	_dragging = false
	_wrong_flash = []
	_glow = 0.0
	_hint_until = 0.0
	_elapsed = 0.0
	_wrong = 0
	_hints = 0
	var view := logic.view_for(_con, SKY.size, _rng)
	_pos.clear()
	var mag_limit := float(logic.rules().mag)
	var center := SKY.size / 2.0
	var draw := []
	for hip in logic.stars:
		var s: Array = logic.stars[hip]
		var is_member := _members.has(hip)
		if s[2] > mag_limit and not is_member:
			continue
		var p: Variant = ConstellationLogic.project(s[0], s[1], view.ra0, view.dec0)
		if p == null:
			continue
		var xy: Vector2 = center + (p as Vector2) * float(view.scale)
		if xy.x < -20 or xy.y < -20 or xy.x > SKY.size.x + 20 or xy.y > SKY.size.y + 20:
			continue
		_pos[hip] = xy
		draw.append([xy, s[2], s[3]])
	_sky.stars = draw
	_sky.queue_redraw()
	_name_label.text = _tr_dict(_con.name)
	_figure.set_figure(_con, logic)
	_hint_btn.disabled = false
	_update_labels()
	_playing = true
	Router.step("con_%d" % _round)


func _tr_dict(d: Dictionary) -> String:
	return str(d.get(I18n.locale, d.get("en", "")))


func _update_labels() -> void:
	_progress.text = tr("CON_LINES") % [_done.size(), _edges.size()]
	_status.text = tr("CON_ROUND") % [_round, _queue.size()] + "   ·   " + tr("CON_WRONG") % _wrong


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var rules := logic.rules()
	var want := 0.0
	if float(rules.glow_after) > 0.0 and _elapsed > float(rules.glow_after):
		want = 0.6
	if _elapsed < _hint_until:
		want = 1.0
	if bool(rules.ghost):
		want = maxf(want, 0.35)
	_glow = move_toward(_glow, want, delta * 2.0)
	for f in _wrong_flash:
		f[2] -= delta
	_wrong_flash = _wrong_flash.filter(func(f): return f[2] > 0.0)
	_lines.queue_redraw()


# --- input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventScreenTouch and event.index == 0:
		var local: Vector2 = event.position - SKY.position
		if event.pressed:
			if not Rect2(Vector2.ZERO, SKY.size).has_point(local):
				return
			var s := _star_at(local, PICK_TAP)
			if s < 0:
				return
			if _active >= 0 and s != _active:
				_connect(_active, s)   # tap-tap mode
			else:
				_active = s
				Audio.play("tick")
			_dragging = true
			_finger = local
		else:
			if _dragging and _active >= 0:
				var s := _star_at(local, PICK_TAP * 0.7)
				if s >= 0 and s != _active:
					_connect(_active, s)
			_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == 0 and _dragging:
		var local: Vector2 = event.position - SKY.position
		_finger = local
		if _active >= 0:
			var s := _star_at(local, PICK_PASS)
			# Passing a star only counts if it belongs to the figure; random stars along the
			# way are ignored (releasing on one still counts as a try).
			if s >= 0 and s != _active and _members.has(s):
				_connect(_active, s)
		get_viewport().set_input_as_handled()


func _star_at(local: Vector2, max_px: float) -> int:
	var best := -1
	var best_d := max_px
	for hip in _pos:
		var d: float = (_pos[hip] as Vector2).distance_to(local)
		# Bright stars are easier to hit.
		d -= ConstellationLogic.star_radius(logic.stars[hip][2]) * 0.5
		if d < best_d:
			best_d = d
			best = hip
	return best


func _connect(a: int, b: int) -> void:
	var key := ConstellationLogic.edge_key(a, b)
	if _edges.has(key):
		if not _done.has(key):
			_done[key] = true
			Audio.play("tap")
		_active = b
		_update_labels()
		if _done.size() == _edges.size():
			_complete()
	else:
		_wrong += 1
		_wrong_flash.append([_pos[a], _pos[b], 0.6])
		Audio.play("fail", "SFX", 0.5)
		_update_labels()
		# The line starts again from the star it came from.


func _use_hint() -> void:
	_hints += 1
	_hint_until = _elapsed + 4.0
	Audio.play("whoosh", "SFX", 0.4)


func _complete() -> void:
	_playing = false
	_dragging = false
	_active = -1
	_hint_btn.disabled = true
	Audio.play("success")
	var pts := logic.round_points(_edges.size(), _wrong + _hints * HINT_PENALTY / ConstellationLogic.WRONG_PENALTY, _elapsed)
	_total_points += pts
	_total_lines += _edges.size()
	_total_wrong += _wrong + _hints * 2
	_total_time += _elapsed
	_lines.celebrate = 0.0
	create_tween().tween_property(_lines, "celebrate", 1.0, 0.8)
	_show_fact(pts)


func _show_fact(pts: int) -> void:
	_overlay = PanelContainer.new()
	_overlay.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SUCCESS, 0.6), 3))
	_overlay.position = Vector2(SKY.position.x + 160, SKY.end.y - 330)
	_overlay.custom_minimum_size = Vector2(SKY.size.x - 320, 300)
	add_child(_overlay)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	_overlay.add_child(row)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	row.add_child(v)
	var head := _plain(_tr_dict(_con.name) + "  ·  " + tr("CON_POINTS") % pts, UiTheme.SIZE_BODY + 4, "semibold", UiTheme.SUCCESS)
	v.add_child(head)
	var fact := _plain(_tr_dict(_con.fact), UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
	fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fact.custom_minimum_size = Vector2(SKY.size.x - 900, 0)
	v.add_child(fact)
	var next := BigButton.make("CON_NEXT" if _round < _queue.size() else "CON_FINISH", "arrow_forward", true, 380)
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(_next_round)
	row.add_child(next)


func _finish() -> void:
	_playing = false
	Router.step("done")
	var stars := ConstellationLogic.stars_for(_total_lines, _total_wrong, _total_time)
	var rank := Scores.submit("constellations", Session.player_name, _total_points, stars,
		{"constellations": _queue.map(func(c): return c.id)})
	Router.complete({"score": _total_points, "stars": stars, "wrong": _total_wrong,
		"seconds": snappedf(_total_time, 0.1)})
	Audio.play("success")
	if stars == 3:
		Confetti.burst(self)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SUCCESS, 0.6), 3))
	panel.position = Vector2(SKY.position.x + 460, 330)
	panel.custom_minimum_size = Vector2(1040, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	panel.add_child(v)
	v.add_child(UiTheme.label("CON_RESULT_TITLE", UiTheme.SIZE_H2 + 8, "serif", UiTheme.SUCCESS))
	var star_row := HBoxContainer.new()
	for i in 3:
		star_row.add_child(UiTheme.icon("star" if i < stars else "star_border", 100, UiTheme.ACCENT))
	v.add_child(star_row)
	var names := ", ".join(_queue.map(func(c): return _tr_dict(c.name)))
	var done := _plain(tr("CON_RESULT") % [names, _total_wrong], UiTheme.SIZE_BODY, "medium", UiTheme.TEXT)
	done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	done.custom_minimum_size = Vector2(980, 0)
	v.add_child(done)
	v.add_child(_plain(tr("AST_SCORE") % _total_points + "  ·  " + tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))],
		UiTheme.SIZE_BODY, "semibold", UiTheme.ACCENT_HI))
	var on_again := func():
		panel.queue_free()
		_round = 0
		_total_points = 0
		_total_lines = 0
		_total_wrong = 0
		_total_time = 0.0
		_queue = logic.pick(_rng)
		_next_round()
	v.add_child(ResultActions.make("CON_AGAIN", "stars", on_again, 980.0, true))


func _plain(t: String, font_size: int, kind := "regular", color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(t, font_size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The real sky: every visible star with size by brightness and colour by B-V index.
class _SkyLayer:
	extends Control
	var stars := []    # [pos, mag, bv]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for s in stars:
			var r := ConstellationLogic.star_radius(s[1])
			var c := ConstellationLogic.star_color(s[2])
			if r > 4.0:
				draw_circle(s[0], r * 2.6, Color(c, 0.07))
				draw_circle(s[0], r * 1.6, Color(c, 0.16))
			draw_circle(s[0], r, c)


## Lines: guide lines, traced lines, the line under the finger, wrong tries, member glow.
class _LineLayer:
	extends Control
	var game: Node
	var celebrate := 0.0:
		set(v):
			celebrate = v
			queue_redraw()

	func _draw() -> void:
		var g = game
		if g._con.is_empty():
			return
		var ghost := bool(g.logic.rules().ghost)
		for e in g._con.edges:
			var a: int = int(e[0])
			var b: int = int(e[1])
			if not (g._pos.has(a) and g._pos.has(b)):
				continue
			var key := ConstellationLogic.edge_key(a, b)
			if g._done.has(key):
				var col := UiTheme.SCIENCE.lerp(UiTheme.ACCENT_HI, celebrate) if not g._playing else UiTheme.SCIENCE
				draw_line(g._pos[a], g._pos[b], Color(col, 0.35), 14.0, true)
				draw_line(g._pos[a], g._pos[b], col, 4.0, true)
			elif ghost:
				_dashed(g._pos[a], g._pos[b], Color(1, 1, 1, 0.22))
		if g._glow > 0.01:
			for h in g._members:
				if g._pos.has(h):
					draw_arc(g._pos[h], 26.0, 0, TAU, 40, Color(UiTheme.ACCENT, 0.7 * g._glow), 3.0, true)
		for f in g._wrong_flash:
			draw_line(f[0], f[1], Color(UiTheme.DANGER, clampf(f[2] / 0.6, 0.0, 1.0)), 5.0, true)
		if g._active >= 0 and g._pos.has(g._active):
			draw_arc(g._pos[g._active], 30.0, 0, TAU, 40, UiTheme.ACCENT_HI, 4.0, true)
			if g._dragging:
				draw_line(g._pos[g._active], g._finger, Color(UiTheme.ACCENT_HI, 0.8), 4.0, true)

	func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
		var n := int(a.distance_to(b) / 18.0)
		for i in range(0, n, 2):
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 3.0, true)


## The stick figure as a small template (no background stars).
class _FigureThumb:
	extends Control
	var _pts := {}
	var _edges := []

	func set_figure(c: Dictionary, logic: ConstellationLogic) -> void:
		_pts.clear()
		_edges = c.edges
		var raw := {}
		var lo := Vector2(INF, INF)
		var hi := -lo
		for h in ConstellationLogic.members(c):
			var s: Array = logic.stars[h]
			var p: Variant = ConstellationLogic.project(s[0], s[1], c.center[0], c.center[1])
			raw[h] = [p, s[2]]
			lo = lo.min(p)
			hi = hi.max(p)
		var span := (hi - lo)
		var pad := 40.0
		var area := custom_minimum_size   # fixed size; layout may not have run yet
		var sc := minf((area.x - 2 * pad) / maxf(span.x, 1e-4), (area.y - 2 * pad) / maxf(span.y, 1e-4))
		var off := (area - span * sc) / 2.0
		for h in raw:
			_pts[h] = [off + ((raw[h][0] as Vector2) - lo) * sc, raw[h][1]]
		queue_redraw()

	func _draw() -> void:
		draw_style_box(UiTheme.box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.12), 2, 16), Rect2(Vector2.ZERO, size))
		for e in _edges:
			draw_line(_pts[int(e[0])][0], _pts[int(e[1])][0], Color(UiTheme.SCIENCE, 0.8), 3.0, true)
		for h in _pts:
			draw_circle(_pts[h][0], ConstellationLogic.star_radius(_pts[h][1]) * 0.8 + 2.0, Color(1, 1, 1))
