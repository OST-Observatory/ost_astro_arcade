## Missions in the 3D solar system (see MissionLogic): explorer → Mars, researcher → Jupiter,
## pro → Saturn with a Jupiter swing-by. Planning happens at the launch date with the
## transfer orbit, the target where it will be on arrival (ghost) and – for the swing-by –
## the path after Jupiter and the closest approach to Saturn always on screen. Then the
## flight runs in time-lapse (tap = faster).
class_name MissionMode
extends Control

signal menu_pressed

const FLIGHT_SECONDS := 5.0
const VIEW_DIST := {"mars": 4.6, "jupiter": 16.0, "saturn": 31.0}
const GHOST := Color(1.0, 1.0, 1.0, 0.45)

var view: SolarView
var diff := "researcher"
var panel := Rect2()
var view_rect := Rect2()
var planet := "mars"
var _jd0 := 0.0
var _jd := 0.0
var _transfer: HohmannTransfer
var _plan := {}
var _windows: Array = []
var _window := 0
var _rp := 5.0
var _side := -1.0
var _attempts := 0
var _best := INF
var _flying := false
var _phase := 0
var _f := 0.0
var _fast := 1.0
var _done := false
# 3D overlay (heliocentric scene axes)
var _ov: Node3D
var _preview: Node3D
var _ghost: Sprite3D
var _ghost2: Sprite3D
var _probe: Sprite3D
var _trail: MeshInstance3D
var _dist_label: Label3D
# panel
var _col: VBoxContainer
var _slider: KnobSlider
var _rp_slider: KnobSlider
var _win_buttons: Array[Button] = []
var _side_buttons := {}
var _info: Label
var _launch_btn: BigButton
var _feedback: Label
var _status: Label
var _date: Label


static func make(v: SolarView, difficulty: String, panel_rect: Rect2, view_r: Rect2) -> MissionMode:
	var m := MissionMode.new()
	m.view = v
	m.diff = difficulty
	m.panel = panel_rect
	m.view_rect = view_r
	return m


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet = MissionLogic.target(diff)
	_jd0 = floorf(MarsTransfer.jd_now() - 0.5) + 0.5
	_jd = _jd0
	view.rate = 0.0
	view.focus = "sun"
	view.selected = ""
	view.dist = VIEW_DIST[planet]
	view.pitch = 1.3
	view.show_minor = false
	view.small.highlight("")
	view.body_tapped.connect(_on_tap)

	_ov = Node3D.new()
	view.overlay.add_child(_ov)
	_preview = Node3D.new()
	_ov.add_child(_preview)
	_ghost = _marker(Color(BodyCatalog.color("jupiter" if planet == "saturn" else planet), 0.6), 0.0005)
	_ghost2 = _marker(Color(BodyCatalog.color("saturn"), 0.6), 0.0005)
	_ghost2.visible = planet == "saturn"
	_probe = _marker(Color(1, 1, 1, 1), 0.0003)
	_probe.visible = false
	_dist_label = SpaceDraw.label("", Vector3.ZERO, UiTheme.ACCENT_HI)
	_dist_label.pixel_size = SolarView.LABEL_PX
	_dist_label.font_size = 40
	_dist_label.visible = false
	_ov.add_child(_dist_label)

	_date = _plain(UiTheme.SIZE_BODY + 2, "semibold", UiTheme.TEXT)
	_date.position = Vector2(view_rect.position.x + 28, view_rect.end.y - 70)
	add_child(_date)
	_build_panel()
	if planet == "saturn":
		_windows = MissionLogic.jupiter_windows(_jd0)
		_select_window(0)
	else:
		_set_launch(_jd0)
	Router.step("plan")


func _exit_tree() -> void:
	if is_instance_valid(_ov):
		_ov.queue_free()
	view.show_minor = true
	if view.body_tapped.is_connected(_on_tap):
		view.body_tapped.disconnect(_on_tap)


func _marker(col: Color, px: float) -> Sprite3D:
	var s := Sprite3D.new()
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.fixed_size = true
	s.no_depth_test = true
	s.pixel_size = px
	s.modulate = col
	_ov.add_child(s)
	return s


func _plain(font_size: int, kind := "regular", col := UiTheme.TEXT) -> Label:
	var l := UiTheme.label("", font_size, kind, col)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	return l


# --- panel -------------------------------------------------------------------------------

func _build_panel() -> void:
	var w := panel.size.x
	_col = VBoxContainer.new()
	_col.position = panel.position
	_col.custom_minimum_size = Vector2(w, 0)
	_col.add_theme_constant_override("separation", 14)
	add_child(_col)
	var key := planet.to_upper()
	_col.add_child(UiTheme.label("SOL_M_TITLE_" + key, UiTheme.SIZE_H2 - 8, "serif", UiTheme.ACCENT_HI))
	_col.add_child(_wrap(UiTheme.label("SOL_M_TASK_" + key, UiTheme.SIZE_SMALL - 2, "regular", UiTheme.TEXT), w))
	if planet == "saturn":
		_col.add_child(UiTheme.label("SOL_WINDOWS", UiTheme.SIZE_SMALL, "semibold", UiTheme.TEXT))
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		_col.add_child(grid)
		for k in MissionLogic.jupiter_windows(_jd0).size():
			var b := Button.new()
			b.custom_minimum_size = Vector2((w - 48) / 5.0, 56)
			b.focus_mode = Control.FOCUS_NONE
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 4)
			var i := k
			b.pressed.connect(func():
				Audio.play("tap")
				_select_window(i))
			grid.add_child(b)
			_win_buttons.append(b)
		_col.add_child(UiTheme.label("SOL_SIDE", UiTheme.SIZE_SMALL, "semibold", UiTheme.TEXT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_col.add_child(row)
		for s in [["SOL_SIDE_OUT", -1.0], ["SOL_SIDE_IN", 1.0]]:
			var b := BigButton.make(s[0], "", false, int((w - 14) / 2.0))
			b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
			var side: float = s[1]
			b.pressed.connect(func():
				_side = side
				_update_preview())
			row.add_child(b)
			_side_buttons[side] = b
		_rp_slider = KnobSlider.make("SOL_RP", MissionLogic.RP_MIN, MissionLogic.RP_MAX, 0.1, _rp, func(v: float) -> String:
			return tr("SOL_RP_VALUE") % AstroFormat.num(v, 1))
		_rp_slider.changed.connect(func(v: float):
			_rp = v
			_update_preview())
		_col.add_child(_rp_slider)
	else:
		_slider = KnobSlider.make("SOL_LAUNCH", 0, MissionLogic.RANGE_DAYS[diff], 1, 0, func(v: float) -> String:
			return AstroFormat.date(MarsTransfer.iso_from_jd(_jd0 + v)))
		_slider.changed.connect(func(v: float): _set_launch(_jd0 + v))
		_col.add_child(_slider)
	_info = _wrap(_plain(UiTheme.SIZE_SMALL, "medium", UiTheme.SCIENCE), w)
	_col.add_child(_info)
	_launch_btn = BigButton.make("SOL_GO", "rocket_launch", true, int(w))
	_launch_btn.pressed.connect(_launch)
	_col.add_child(_launch_btn)
	_feedback = _wrap(_plain(UiTheme.SIZE_SMALL, "medium", UiTheme.TEXT), w)
	_col.add_child(_feedback)
	_status = _plain(UiTheme.SIZE_SMALL - 2, "semibold", UiTheme.TEXT_DIM)
	_status.position = Vector2(view_rect.end.x - 300, view_rect.end.y - 64)
	add_child(_status)
	var menu := SolarMenuButton.make(panel)
	menu.pressed.connect(func(): menu_pressed.emit())
	add_child(menu)
	_update_status()


func _update_status() -> void:
	_status.text = tr("SOL_ATTEMPT") % [mini(_attempts + 1, MissionLogic.ATTEMPTS), MissionLogic.ATTEMPTS]


func _set_controls(on: bool) -> void:
	_launch_btn.disabled = not on
	if _slider:
		_slider.set_enabled(on)
	if _rp_slider:
		_rp_slider.set_enabled(on)
	for b in _win_buttons:
		b.disabled = not on
	for s in _side_buttons:
		(_side_buttons[s] as BigButton).disabled = not on


func _select_window(i: int) -> void:
	if _flying:
		return
	_window = i
	for k in _win_buttons.size():
		var b := _win_buttons[k]
		b.text = AstroFormat.month(MarsTransfer.iso_from_jd(_windows[k]))
		var on := k == i
		var box := UiTheme.box(Color(UiTheme.ACCENT, 0.25) if on else UiTheme.SURFACE, UiTheme.ACCENT if on else UiTheme.LINE,
			3 if on else 2, 16)
		box.set_content_margin_all(6)
		# Buttons size themselves by their largest state style: all states get the small margin.
		for state in ["normal", "hover", "pressed", "disabled"]:
			var st := box.duplicate() as StyleBoxFlat
			if state == "hover":
				st.bg_color = st.bg_color.lightened(0.08)
			elif state == "disabled":
				st.bg_color.a *= 0.5
			b.add_theme_stylebox_override(state, st)
	_update_preview()


func _set_launch(jd: float) -> void:
	if _flying:
		return
	_jd = jd
	_update_preview()


# --- preview -------------------------------------------------------------------------------

func _clear_preview() -> void:
	for c in _preview.get_children():
		c.queue_free()


func _update_preview() -> void:
	_clear_preview()
	_dist_label.visible = false
	if planet == "saturn":
		_jd = _windows[_window]
		_plan = MissionLogic.plan_flyby(_jd, _rp, _side)
		_transfer = _plan.transfer
		for s in _side_buttons:
			var on: bool = s == _side
			(_side_buttons[s] as BigButton).add_theme_stylebox_override("normal",
				UiTheme.box(Color(UiTheme.ACCENT, 0.25) if on else UiTheme.SURFACE, UiTheme.ACCENT if on else UiTheme.LINE, 3 if on else 2))
	else:
		_transfer = HohmannTransfer.compute(planet, _jd)
	view.jd = _jd
	var pts := PackedVector3Array()
	for k in 129:
		pts.append(_transfer.position_at(k / 128.0))
	_preview.add_child(SpaceDraw.line(pts, Color(1.0, 0.85, 0.4, 0.8), 1.6))
	var arrive_jd := _jd + _transfer.days
	var lines: Array[String] = [tr("SOL_DATE") % AstroFormat.date(MarsTransfer.iso_from_jd(_jd))]
	if planet == "saturn":
		_ghost.position = Kepler.to_godot(Kepler.planet_position("jupiter", arrive_jd))
		var f: Flyby = _plan.flyby
		var end_jd := minf(float(_plan.jd_closest) + 400.0, f.jd_flyby + MissionLogic.SATURN_YEARS * 365.25)
		var out := PackedVector3Array()
		for k in 241:
			var p := f.position(lerpf(f.jd_flyby, end_jd, k / 240.0))
			out.append(p)
			if p.length() > 45.0:
				break
		_preview.add_child(SpaceDraw.line(out, Color(0.5, 0.95, 1.0, 0.85), 1.6))
		var sat := Kepler.planet_position("saturn", float(_plan.jd_closest))
		var probe := f.position(float(_plan.jd_closest))
		_ghost2.position = Kepler.to_godot(sat)
		_preview.add_child(SpaceDraw.line(SpaceDraw.dashed(Kepler.to_godot(probe), Kepler.to_godot(sat), 16),
			Color(UiTheme.ACCENT_HI, 0.9), 1.4, true))
		_dist_label.text = AstroFormat.num(float(_plan.closest), 2) + " " + tr("SOL_AU_UNIT")
		_dist_label.position = Kepler.to_godot((probe + sat) / 2.0)
		_dist_label.visible = true
		lines.append(tr("SOL_FLYBY_AT") % AstroFormat.date(MarsTransfer.iso_from_jd(arrive_jd)))
		if _plan.escapes:
			lines.append(tr("SOL_ESCAPES"))
		lines.append(tr("SOL_SATURN_DIST") % AstroFormat.num(float(_plan.closest), 2)
			+ ("  ✓" if float(_plan.closest) < MissionLogic.HILL_SATURN + 0.02 else ""))
	else:
		_ghost.position = Kepler.to_godot(Kepler.planet_position(planet, arrive_jd))
		lines.append(tr("SOL_FLIGHT") % int(round(_transfer.days)))
		lines.append(tr("SOL_PHASE_NOW") % [BodyCatalog.display_name(planet), int(round(MissionLogic.phase(planet, _jd))),
			int(round(MissionLogic.ideal_phase(planet, _jd)))])
	_info.text = "\n".join(lines)
	_date.text = tr("SOL_DATE") % AstroFormat.date(MarsTransfer.iso_from_jd(_jd))


# --- flight ------------------------------------------------------------------------------

func _launch() -> void:
	if _flying or _done:
		return
	_flying = true
	_attempts += 1
	_set_controls(false)
	_feedback.text = ""
	Router.step("launch_%d" % _attempts)
	Audio.play("whoosh", "SFX", 0.7)
	_probe.visible = true
	_phase = 0
	_f = 0.0
	_fast = 1.0


func _on_tap(_id: String) -> void:
	if _flying:
		_fast = 4.0


func _process(delta: float) -> void:
	if not _flying:
		return
	_f = minf(_f + delta * _fast / FLIGHT_SECONDS, 1.0)
	var jd: float
	var pts := PackedVector3Array()
	if _phase == 0:
		jd = _jd + _f * _transfer.days
		_probe.position = Kepler.to_godot(_transfer.position_at(_f))
		var n := int(64 * _f) + 2
		for k in n:
			pts.append(_transfer.position_at(_f * k / (n - 1)))
	else:
		var f: Flyby = _plan.flyby
		var end_jd := float(_plan.jd_closest)
		jd = lerpf(f.jd_flyby, end_jd, _f)
		_probe.position = Kepler.to_godot(f.position(jd))
		for k in 65:
			pts.append(_transfer.position_at(k / 64.0))
		var n := int(96 * _f) + 2
		for k in n:
			pts.append(f.position(lerpf(f.jd_flyby, jd, float(k) / (n - 1))))
	view.jd = jd
	if _trail:
		_trail.queue_free()
	_trail = SpaceDraw.line(pts, Color(1, 1, 1, 0.9), 3.0)
	_ov.add_child(_trail)
	_date.text = tr("SOL_FLIGHT_DATE") % AstroFormat.date(MarsTransfer.iso_from_jd(jd))
	if _f < 1.0:
		return
	if planet == "saturn" and _phase == 0:
		_phase = 1
		_f = 0.0
		Audio.play("whoosh", "SFX", 0.5)
		return
	_arrived()


func _arrived() -> void:
	_flying = false
	var lines: Array[String] = []
	var st: int
	var name := BodyCatalog.display_name(planet)
	if planet == "saturn":
		var d := float(_plan.closest)
		_best = minf(_best, d)
		st = MissionLogic.flyby_stars(d)
		lines.append(tr("SOL_M_SATURN_HIT" if st >= 3 else "SOL_M_SATURN_MISS") % AstroFormat.num(d, 2))
		if st < 3:
			lines.append(tr("SOL_M_SATURN_TIP"))
	else:
		var miss := absf(_transfer.miss_deg)
		_best = minf(_best, miss)
		st = MissionLogic.direct_stars(miss)
		if st >= 3:
			lines.append(tr("SOL_M_HIT") % name)
		else:
			lines.append(tr("SOL_M_MISS") % [name, AstroFormat.grouped(_transfer.miss_au() * Kepler.AU_KM / 1e6)])
			var days := MissionLogic.days_off(planet, _jd)
			if absf(days) <= 60.0:
				lines.append(tr("SOL_DAYS_LATER" if days > 0 else "SOL_DAYS_EARLIER") % maxi(1, int(round(absf(days)))))
			else:
				lines.append(tr("SOL_M_FAR") % name)
	if st >= 3:
		Audio.play("success")
		Confetti.burst(self)
	else:
		Audio.play("success" if st >= 2 else "fail", "SFX", 0.6)
	_feedback.text = "\n".join(lines)
	if st >= 2 or _attempts >= MissionLogic.ATTEMPTS:
		_done = true
		await get_tree().create_timer(2.5).timeout
		if is_inside_tree():
			_finish()
		return
	_update_status()
	_reset_flight()
	_set_controls(true)


func _reset_flight() -> void:
	_probe.visible = false
	if _trail:
		_trail.queue_free()
		_trail = null
	view.jd = _jd


func _finish() -> void:
	Router.step("done")
	var st: int
	var pts: int
	if planet == "saturn":
		st = MissionLogic.flyby_stars(_best)
		pts = MissionLogic.flyby_score(_best, _attempts)
	else:
		st = MissionLogic.direct_stars(_best)
		pts = MissionLogic.direct_score(_best, _attempts, diff)
	var rank := Scores.submit("solar", Session.player_name, pts, st, {"mode": "mission", "target": planet, "best": snappedf(_best, 0.01)})
	Router.complete({"score": pts, "stars": st, "mode": "mission", "target": planet, "attempts": _attempts})
	_col.visible = false
	var w := panel.size.x
	var box := PanelContainer.new()
	box.position = panel.position - Vector2(20, 0)
	box.custom_minimum_size = Vector2(w + 30, panel.size.y - 140)
	box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SUCCESS, 0.6), 3))
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	box.add_child(v)
	v.add_child(UiTheme.label("SOL_RESULT_TITLE" if st >= 2 else "SOL_RESULT_TITLE_MISS", UiTheme.SIZE_H2, "serif", UiTheme.SUCCESS))
	var star_row := HBoxContainer.new()
	for i in 3:
		star_row.add_child(UiTheme.icon("star" if i < st else "star_border", 84, UiTheme.ACCENT))
	v.add_child(star_row)
	v.add_child(_wrap(_plain(UiTheme.SIZE_SMALL, "semibold", UiTheme.ACCENT_HI), w - 30))
	(v.get_child(v.get_child_count() - 1) as Label).text = tr("AST_SCORE") % pts + "  ·  " \
		+ tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))]
	var fact := _wrap(_plain(UiTheme.SIZE_SMALL - 2), w - 30)
	if planet == "saturn":
		fact.text = tr("SOL_M_FACT_SATURN")
	else:
		var nxt := HohmannTransfer.next_window(planet, _jd0, _jd0 + MissionLogic.RANGE_DAYS[diff])
		fact.text = tr("SOL_M_FACT_" + planet.to_upper()) % AstroFormat.date(MarsTransfer.iso_from_jd(nxt if nxt > 0.0 else _jd0))
	v.add_child(fact)
	v.add_child(_wrap(UiTheme.label("SOL_NOTE", UiTheme.SIZE_SMALL - 6, "regular", UiTheme.TEXT_DIM), w - 30))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(ResultActions.make("SOL_AGAIN", "rocket_launch", func():
		box.queue_free()
		_attempts = 0
		_best = INF
		_done = false
		_reset_flight()
		_col.visible = true
		_feedback.text = ""
		_set_controls(true)
		_update_status()
		_update_preview(), w - 30.0, true))
