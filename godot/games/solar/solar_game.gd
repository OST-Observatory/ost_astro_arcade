## Solar system: "Off to Mars!" – pick the launch day on a timeline (from today on), watch
## the transfer orbit, launch and see whether the spacecraft meets Mars. Real planet
## positions (Kepler elements); the launch windows come out of the physics by themselves.
## Explorers see a ghost Mars where Mars will be on arrival; researchers get the phase angle
## and "launch N days later" feedback; pros only "too early / too late".
extends Control

const VIEW := Rect2(40, 170, 1640, 1230)
const PANEL_X := 1730.0
const PANEL_W := 790.0
const RANGE_DAYS := 800
const FLIGHT_SECONDS := 5.0
const ATTEMPTS := 3
const PLANETS := [["mercury", Color("a7a7a7"), 0.035], ["venus", Color("e8cfa0"), 0.055],
	["earth", Color("4dd0e1"), 0.06], ["mars", Color("e2725b"), 0.05]]

var skip_intro := false   # screenshots/tests
var diff := "researcher"
var _jd0 := 0.0             # today
var _jd := 0.0              # chosen launch day
var _transfer: MarsTransfer
var _attempts := 0
var _best_miss := INF
var _flying := false
var _f := 0.0
var _fast := 1.0            # tap during the flight to fast-forward
var _root: Node3D
var _cam: Camera3D
var _bodies := {}           # planet -> MeshInstance3D
var _ghost: MeshInstance3D
var _target: MeshInstance3D
var _rocket: MeshInstance3D
var _ellipse: MeshInstance3D
var _trail: MeshInstance3D
var _slider: KnobSlider
var _launch_btn: BigButton
var _info: Label
var _feedback: Label
var _status: Label
var _date_label: Label
var _col: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Starfield.new())
	if not skip_intro:
		var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("solar"))
		add_child(start)
		await start.start_pressed
		start.queue_free()
	diff = Session.difficulty_name()
	_jd0 = floorf(MarsTransfer.jd_now() - 0.5) + 0.5
	_jd = _jd0
	_build_3d()
	_build_panel()
	_set_launch(_jd0)
	Router.step("plan")


# --- 3D ----------------------------------------------------------------------------------

func _build_3d() -> void:
	var frame := Panel.new()
	frame.position = VIEW.position - Vector2(6, 6)
	frame.size = VIEW.size + Vector2(12, 12)
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.6), Color(UiTheme.SCIENCE, 0.45), 3, 10))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var container := SubViewportContainer.new()
	container.position = VIEW.position
	container.size = VIEW.size
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	Settings.apply_3d(vp)
	container.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.012)
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	_root = Node3D.new()
	vp.add_child(_root)
	_root.add_child(SpaceDraw.sphere(Vector3.ZERO, 0.08, Color(1.0, 0.85, 0.5), 6.0))
	for p in PLANETS:
		var el := Kepler.planet_elements(p[0], _jd0)
		_root.add_child(SpaceDraw.line(Kepler.orbit_points(el.a, el.e, el.i, el.node, el.w, 256), Color(p[1], 0.4), 1.2))
		var body := SpaceDraw.sphere(Vector3.ZERO, p[2], p[1], 1.6)
		_root.add_child(body)
		var lbl := SpaceDraw.label(tr("PLANET_" + str(p[0]).to_upper()), Vector3(0, p[2] + 0.06, -p[2] - 0.05), p[1])
		lbl.pixel_size *= 0.4
		body.add_child(lbl)
		_bodies[p[0]] = body
	_ghost = SpaceDraw.sphere(Vector3.ZERO, 0.05, Color(0.89, 0.45, 0.36, 0.35), 1.0)
	_ghost.visible = diff != "pro"   # pros see it from the second attempt on
	_root.add_child(_ghost)
	_target = SpaceDraw.sphere(Vector3.ZERO, 0.03, Color(1.0, 0.85, 0.4), 3.0)
	_root.add_child(_target)
	_rocket = SpaceDraw.sphere(Vector3.ZERO, 0.025, Color(1.0, 1.0, 1.0), 5.0)
	_rocket.visible = false
	_root.add_child(_rocket)

	_cam = Camera3D.new()
	_cam.fov = 38
	_cam.far = 100
	_root.add_child(_cam)
	_cam.position = Vector3(0, 4.3, 1.9)
	_cam.look_at(Vector3(0, 0, 0.12))


func _place_planets(jd: float) -> void:
	for p in PLANETS:
		(_bodies[p[0]] as Node3D).position = Kepler.to_godot(Kepler.planet_position(p[0], jd))


func _rebuild_ellipse() -> void:
	if _ellipse:
		_ellipse.queue_free()
	var pts := PackedVector3Array()
	for k in 129:
		pts.append(_transfer.position_at(k / 128.0))
	_ellipse = SpaceDraw.line(pts, Color(1.0, 0.85, 0.4, 0.75), 1.6)
	_root.add_child(_ellipse)
	_target.position = Kepler.to_godot(_transfer.arrival_point())
	_ghost.position = Kepler.to_godot(Kepler.planet_position("mars", _jd + _transfer.days))


# --- panel -------------------------------------------------------------------------------

func _build_panel() -> void:
	var title := UiTheme.label("SOL_TITLE", UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
	title.position = Vector2(200, 52)
	add_child(title)
	_status = _plain("", UiTheme.SIZE_BODY, "semibold", UiTheme.ACCENT_HI)
	_status.position = Vector2(1250, 66)
	add_child(_status)
	_date_label = _plain("", UiTheme.SIZE_BODY + 2, "semibold", UiTheme.TEXT)
	_date_label.position = VIEW.position + Vector2(28, 20)
	add_child(_date_label)

	_col = VBoxContainer.new()
	_col.position = Vector2(PANEL_X, 160)
	_col.custom_minimum_size = Vector2(PANEL_W, 0)
	_col.add_theme_constant_override("separation", 22)
	add_child(_col)
	var task := UiTheme.label("SOL_TASK", UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.custom_minimum_size = Vector2(PANEL_W, 0)
	_col.add_child(task)
	_slider = KnobSlider.make("SOL_LAUNCH", 0, RANGE_DAYS, 1, 0, func(v: float) -> String:
		return AstroFormat.date(MarsTransfer.iso_from_jd(_jd0 + v)))
	_slider.changed.connect(func(v: float): _set_launch(_jd0 + v))
	_col.add_child(_slider)
	_info = _plain("", UiTheme.SIZE_BODY - 4, "medium", UiTheme.SCIENCE)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(PANEL_W, 0)
	_col.add_child(_info)
	_launch_btn = BigButton.make("SOL_GO", "rocket_launch", true, PANEL_W)
	_launch_btn.pressed.connect(_launch)
	_col.add_child(_launch_btn)
	_feedback = _plain("", UiTheme.SIZE_BODY - 2, "medium", UiTheme.TEXT)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size = Vector2(PANEL_W, 0)
	_col.add_child(_feedback)
	_update_status()


func _update_status() -> void:
	_status.text = tr("SOL_ATTEMPT") % [mini(_attempts + 1, ATTEMPTS), ATTEMPTS]


func _set_launch(jd: float) -> void:
	if _flying:
		return
	_jd = jd
	_transfer = MarsTransfer.compute(jd)
	_place_planets(jd)
	_rebuild_ellipse()
	_date_label.text = tr("SOL_DATE") % AstroFormat.date(MarsTransfer.iso_from_jd(jd))
	var lines := [tr("SOL_FLIGHT") % int(round(_transfer.days))]
	if diff != "pro":
		lines.append(tr("SOL_PHASE") % int(round(_transfer.phase_deg)))
	_info.text = "\n".join(lines)


# --- flight ------------------------------------------------------------------------------

func _launch() -> void:
	if _flying:
		return
	_flying = true
	_attempts += 1
	_launch_btn.disabled = true
	_slider.set_enabled(false)
	_feedback.text = ""
	Router.step("launch_%d" % _attempts)
	Audio.play("whoosh", "SFX", 0.7)
	_rocket.visible = true
	_f = 0.0
	_fast = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if _flying and event is InputEventMouseButton and event.pressed:
		_fast = 4.0


func _process(delta: float) -> void:
	if not _flying:
		return
	_f = minf(_f + delta * _fast / FLIGHT_SECONDS, 1.0)
	var jd := _jd + _f * _transfer.days
	_place_planets(jd)
	_rocket.position = Kepler.to_godot(_transfer.position_at(_f))
	if _trail:
		_trail.queue_free()
	var pts := PackedVector3Array()
	var n := int(64 * _f) + 2
	for k in n:
		pts.append(_transfer.position_at(_f * k / (n - 1)))
	_trail = SpaceDraw.line(pts, Color(1, 1, 1, 0.9), 3.0)
	_root.add_child(_trail)
	if _f < 1.0:
		_date_label.text = tr("SOL_DAY") % [int(_f * _transfer.days), int(round(_transfer.days)), AstroFormat.date(MarsTransfer.iso_from_jd(jd))]
	else:
		_date_label.text = tr("SOL_ARRIVAL") % AstroFormat.date(MarsTransfer.iso_from_jd(jd))
	if _f >= 1.0:
		_arrived()


func _arrived() -> void:
	_flying = false
	var miss := absf(_transfer.miss_deg)
	_best_miss = minf(_best_miss, miss)
	var st := MarsTransfer.stars(miss, diff)
	var lines: Array[String] = []
	if st >= 3:
		lines.append(tr("SOL_HIT"))
		Audio.play("success")
		Confetti.burst(self)
	else:
		lines.append(tr("SOL_MISS") % AstroFormat.num(_transfer.miss_km() / 1e6, 1))
		Audio.play("success" if st >= 2 else "fail", "SFX", 0.6)
		var days := MarsTransfer.days_off(_jd)
		if diff == "pro":
			lines.append(tr("SOL_LATER") if days > 0 else tr("SOL_EARLIER"))
		elif absf(days) <= 60.0:
			lines.append(tr("SOL_DAYS_LATER" if days > 0 else "SOL_DAYS_EARLIER") % maxi(1, int(round(absf(days)))))
		else:
			lines.append(tr("SOL_FAR"))
	_feedback.text = "\n".join(lines)
	if st >= 2 or _attempts >= ATTEMPTS:
		await get_tree().create_timer(2.0).timeout
		_finish()
		return
	_update_status()
	_rocket.visible = false
	if _trail:
		_trail.queue_free()
		_trail = null
	_ghost.visible = true
	_slider.set_enabled(true)
	_launch_btn.disabled = false
	_set_launch(_jd)


func _finish() -> void:
	Router.step("done")
	var st := MarsTransfer.stars(_best_miss, diff)
	var pts := MarsTransfer.score(_best_miss, _attempts, diff)
	var rank := Scores.submit("solar", Session.player_name, pts, st, {"miss_deg": snappedf(_best_miss, 0.01)})
	Router.complete({"score": pts, "stars": st, "miss_deg": snappedf(_best_miss, 0.01), "attempts": _attempts})
	_col.visible = false
	_status.visible = false
	var panel := PanelContainer.new()
	panel.position = Vector2(PANEL_X - 20, 160)
	panel.custom_minimum_size = Vector2(PANEL_W + 30, 1240)
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SUCCESS, 0.6), 3))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)
	v.add_child(UiTheme.label("SOL_RESULT_TITLE" if st >= 2 else "SOL_RESULT_TITLE_MISS", UiTheme.SIZE_H2, "serif", UiTheme.SUCCESS))
	var star_row := HBoxContainer.new()
	for i in 3:
		star_row.add_child(UiTheme.icon("star" if i < st else "star_border", 90, UiTheme.ACCENT))
	v.add_child(star_row)
	v.add_child(_plain(tr("AST_SCORE") % pts + "  ·  " + tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))],
		UiTheme.SIZE_BODY - 2, "semibold", UiTheme.ACCENT_HI))
	var best := MarsTransfer.next_window(_jd0, _jd0 + RANGE_DAYS)
	var fact := _plain(tr("SOL_FACT") % AstroFormat.date(MarsTransfer.iso_from_jd(best)), UiTheme.SIZE_BODY - 4, "regular", UiTheme.TEXT)
	fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fact.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	v.add_child(fact)
	var note := UiTheme.label("SOL_NOTE", UiTheme.SIZE_SMALL - 4, "regular", UiTheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	v.add_child(note)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var on_again := func():
		panel.queue_free()
		_attempts = 0
		_best_miss = INF
		_rocket.visible = false
		if _trail:
			_trail.queue_free()
			_trail = null
		_col.visible = true
		_status.visible = true
		_slider.set_enabled(true)
		_launch_btn.disabled = false
		_feedback.text = ""
		_update_status()
		_set_launch(_jd)
	v.add_child(ResultActions.make("SOL_AGAIN", "rocket_launch", on_again, PANEL_W - 30.0, true))


func _plain(t: String, font_size: int, kind := "regular", color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(t, font_size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
