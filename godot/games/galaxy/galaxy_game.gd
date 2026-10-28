## Galaxy builder.
##   Act 1, build: pick a real galaxy with a measured rotation curve. Its stars move as fast as
##   measured; the player adds black hole, stars, gas and dark matter (each unlocked by a short
##   knowledge question) until the model curve matches the data and the galaxy holds together.
##   Act 2, collide: up to three collisions with a partner (or a visitor's galaxy); the shapes
##   that form (tails, bridge, ring, merger) earn badges next to real photos.
extends Control

## The visitor picked a target galaxy or "quick" (awaited instead of polling).
signal _target_chosen(id: String)

const VIEW := Rect2(40, 170, 1500, 1230)
const PANEL_X := 1580.0
const PANEL_W := 940.0
const BLOCK_W := 460.0
const GPU_STARS := 50000         # test stars per galaxy for the analysis on the graphics card
const BLOCK_ICONS := {"bh": "blur_on", "stars": "stars", "gas": "cloud", "halo": "visibility_off"}

var skip_intro := false   # screenshots/tests
var rng_seed := 0
var diff := "researcher"
var _rng := RandomNumberGenerator.new()
var _target: Dictionary
var _knobs := {"bh": 0.0, "stars": 0.0, "gas": 0.0, "halo": 0.0, "core": 1.0}
var _unlocked: Array = []
var _questions := {}
var _quiz_points := 0
var _match := 0.0
var _view: GalaxyView
var _chart: RotationCurveChart
var _match_label: Label
var _hint_label: Label
var _blocks_box: GridContainer
var _continue_btn: BigButton
var _time_label: Label
# act 2
var _badges: Array = []
var _collisions := 0
var _model: EncounterModel
var _thread: Thread
var _partner := "spiral"
var _gallery: Array = []
var _partner_thumb: TextureRect
var _partner_label: Label
var _approach := "grazing"
var _spin := 1.0
var _choice_buttons := {}
var _badge_icons := {}
var _info: Label
var _tip: PanelContainer
var _tip_label: Label
var _start_btn: BigButton
var _left_label: Label
var _running := false
var _finished := false
var _analysis: EncounterModel
var _progress: ProgressBar
var _progress_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	add_child(Starfield.new())
	if not skip_intro:
		var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("galaxy"))
		add_child(start)
		await start.start_pressed
		start.queue_free()
	diff = Session.difficulty_name()
	if not skip_intro:
		await _pick_target()


## One finger turns the 3D view, two fingers (or the wheel) zoom.
func _unhandled_input(event: InputEvent) -> void:
	if _view and is_instance_valid(_view) and _view.handle_input(event, VIEW.position):
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _analysis:
		_analysis.cancelled = true   # leaving: don't wait for the whole analysis
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func _clear() -> void:
	for c in get_children():
		if not (c is Starfield):
			c.queue_free()
	_choice_buttons.clear()
	_badge_icons.clear()


# --- target picker -------------------------------------------------------------------------

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
	for tg in GalaxyTemplates.targets():
		var b := Button.new()
		b.custom_minimum_size = Vector2(680, 420)
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 16)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		for line in [["GAL_T_" + str(tg.id).to_upper(), UiTheme.SIZE_H2 - 6, "serif", UiTheme.ACCENT_HI],
				["GAL_TD_" + str(tg.id).to_upper(), UiTheme.SIZE_BODY - 4, "regular", UiTheme.TEXT]]:
			var l := UiTheme.label(line[0], line[1], line[2], line[3])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(600, 0)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(l)
		var id: String = tg.id
		b.pressed.connect(func():
			Audio.play("tap")
			_target_chosen.emit(id))
		row.add_child(b)
	var quick := BigButton.make("GAL_QUICK", "bolt", false, 700)
	quick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quick.pressed.connect(func(): _target_chosen.emit("quick"))
	v.add_child(quick)
	var picked: String = await _target_chosen
	if picked == "quick":
		_target = GalaxyTemplates.get_target("milkyway")
		_knobs = GalaxyTemplates.reference_knobs(_target)
		_unlocked = GalaxyTemplates.COMPONENTS.duplicate()
		_match = BuildLogic.match_percent(_target, GalaxyTemplates.build(_target, _knobs))
		_quiz_points = 0
		_badges = []
		_collisions = 0
		start_collide()
	else:
		start_build(picked)


# --- act 1: build ------------------------------------------------------------------------------

func start_build(target_id: String) -> void:
	_clear()
	_target = GalaxyTemplates.get_target(target_id)
	_knobs = {"bh": 0.0, "stars": 0.0, "gas": 0.0, "halo": 0.0, "core": 1.0}
	_unlocked = []
	_quiz_points = 0
	_badges = []
	_collisions = 0
	_questions = BuildLogic.pick_questions(_rng, diff)
	_make_view()
	var title := _plain(tr("GAL_BUILD_TITLE") % tr("GAL_T_" + str(_target.id).to_upper()), UiTheme.SIZE_H2 - 4, "serif", UiTheme.TEXT)
	title.position = Vector2(200, 52)
	add_child(title)
	_time_label = _plain("", UiTheme.SIZE_BODY - 2, "medium", UiTheme.TEXT)
	_time_label.position = VIEW.position + Vector2(28, VIEW.size.y - 64)
	add_child(_time_label)
	var task := _plain(tr("GAL_BUILD_TASK"), UiTheme.SIZE_BODY - 4, "regular", UiTheme.TEXT)
	task.position = VIEW.position + Vector2(28, 20)
	task.custom_minimum_size = Vector2(VIEW.size.x - 56, 0)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(task)

	var col := VBoxContainer.new()
	col.position = Vector2(PANEL_X, 150)
	col.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.label("GAL_MATCH_HEAD", UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT_DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_match_label = _plain("", UiTheme.SIZE_H2 - 8, "bold", UiTheme.ACCENT_HI)
	head.add_child(_match_label)
	col.add_child(head)
	_chart = RotationCurveChart.new()
	_chart.custom_minimum_size = Vector2(PANEL_W, 400)
	col.add_child(_chart)
	var src := _plain(tr("GAL_DATA_SOURCE") % str(_target.source), UiTheme.SIZE_SMALL - 8, "regular", UiTheme.TEXT_DIM)
	src.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	src.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_child(src)
	_blocks_box = GridContainer.new()
	_blocks_box.columns = 2
	_blocks_box.add_theme_constant_override("h_separation", 20)
	_blocks_box.add_theme_constant_override("v_separation", 14)
	col.add_child(_blocks_box)
	_hint_label = _plain("", UiTheme.SIZE_SMALL, "medium", UiTheme.SCIENCE)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_child(_hint_label)
	_continue_btn = BigButton.make("GAL_TO_COLLIDE", "arrow_forward", true, PANEL_W)
	_continue_btn.pressed.connect(_finish_build)
	col.add_child(_continue_btn)

	var restart := BigButton.make("GAL_RESTART_SIM", "refresh", false, 0)
	restart.position = VIEW.end - Vector2(620, 130)
	restart.pressed.connect(func():
		_view.set_potential(_current_pot(), _match)
		_view.play())
	add_child(restart)

	_rebuild_blocks()
	_view.show_build(_target, _current_pot(), _match)
	_refresh()
	_show_intro()
	Router.step("build")


## Short explanation first; the stars start moving when the visitor is ready.
func _show_intro() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SCIENCE, 0.6), 3))
	card.position = VIEW.position + Vector2(160, 260)
	card.custom_minimum_size = Vector2(VIEW.size.x - 320, 0)
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	card.add_child(v)
	v.add_child(UiTheme.label("GAL_INTRO_TITLE", UiTheme.SIZE_H2 - 4, "serif", UiTheme.ACCENT_HI))
	for key in ["GAL_INTRO_1", "GAL_INTRO_2", "GAL_INTRO_3"]:
		var l := UiTheme.label(key, UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(VIEW.size.x - 400, 0)
		v.add_child(l)
	var go := BigButton.make("GAL_INTRO_GO", "play_arrow", true, 420)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(func():
		card.queue_free()
		_view.play())
	v.add_child(go)


func _make_view() -> void:
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
	Settings.apply_3d(sv)
	vp.add_child(sv)
	_view = GalaxyView.new()
	sv.add_child(_view)
	_view.gestures.area = Rect2(Vector2.ZERO, VIEW.size)
	_view.finished.connect(_on_collision_finished)


func _current_pot() -> GalaxyPotential:
	var k := {}
	for c in GalaxyTemplates.COMPONENTS:
		k[c] = _knobs[c] if _unlocked.has(c) else 0.0
	k.core = _knobs.core
	return GalaxyTemplates.build(_target, k)


## One row per building block: unlocked → its knob, next in line → "unlock" button, later → locked.
func _rebuild_blocks() -> void:
	for c in _blocks_box.get_children():
		c.queue_free()
	var next_found := false
	for comp in GalaxyTemplates.COMPONENTS:
		var row := VBoxContainer.new()
		row.custom_minimum_size = Vector2(BLOCK_W, 0)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 14)
		var col: Color = RotationCurveChart.COLORS[comp]
		head.add_child(UiTheme.icon(BLOCK_ICONS[comp], 44, col))
		head.add_child(UiTheme.label("GAL_BLOCK_" + comp.to_upper(), UiTheme.SIZE_BODY - 2, "semibold", col))
		row.add_child(head)
		if _unlocked.has(comp):
			row.add_child(_knob_for(comp))
			if comp == "halo" and diff == "pro":
				row.add_child(_knob_for("core"))
		elif not next_found:
			next_found = true
			var b := BigButton.make("GAL_UNLOCK", "lock_open", false, int(BLOCK_W))
			b.pressed.connect(_unlock.bind(comp))
			row.add_child(b)
		else:
			head.modulate.a = 0.4
		_blocks_box.add_child(row)


func _knob_for(comp: String) -> KnobSlider:
	var title := "GAL_KNOB_CORE" if comp == "core" else ""
	var k: KnobSlider
	if diff == "pro":
		var r: Array = GalaxyTemplates.PRO_RANGE[comp]
		var step := 1.0 if comp == "bh" else 0.05
		k = KnobSlider.make(title, r[0], r[1], step, float(_knobs[comp]), _formatter(comp, -1))
		k.changed.connect(func(v: float):
			_knobs[comp] = v
			_on_knob())
	else:
		var steps: Array = GalaxyTemplates.STEPS[diff][comp]
		var idx := steps.find(float(_knobs[comp]))
		k = KnobSlider.make(title, 0, steps.size() - 1, 1, maxi(idx, 0), _formatter(comp, 1))
		k.changed.connect(func(v: float):
			_knobs[comp] = float(steps[int(v)])
			_on_knob())
	return k


## Knob value text: the mass inside the measured region (or the core radius).
func _formatter(comp: String, stepped: int) -> Callable:
	return func(v: float) -> String:
		var val := v
		if stepped > 0:
			val = float(GalaxyTemplates.STEPS[diff][comp][int(v)])
		if comp == "core":
			return tr("GAL_V_KPC") % AstroFormat.num((_target.reference as GalaxyPotential).r_core * val * GalaxyPotential.KPC, 1)
		var k: Dictionary = _knobs.duplicate()
		k[comp] = val
		var p := GalaxyTemplates.build(_target, k)
		var r := float(_target.r_last)
		var v2 := p.v2_parts(r)
		var m := 0.0
		match comp:
			"bh": m = p.m_bh
			"stars": m = (float(v2.bulge) + float(v2.disk)) * r
			"gas": m = float(v2.gas) * r
			"halo": m = float(v2.halo) * r
		return BuildLogic.mass_text(m)


func _on_knob() -> void:
	_refresh()
	_view.set_potential(_current_pot(), _match)


func _refresh() -> void:
	var p := _current_pot()
	_match = BuildLogic.match_percent(_target, p)
	_chart.set_model(_target, p, _unlocked)
	var stable := BuildLogic.is_stable(_match, diff)
	_match_label.text = "%d %%" % int(_match)
	_match_label.add_theme_color_override("font_color", UiTheme.SUCCESS if stable else UiTheme.ACCENT_HI)
	_continue_btn.disabled = not (stable and _unlocked.has("halo"))
	_hint_label.text = _hint(stable)


func _hint(stable: bool) -> String:
	if stable and _unlocked.has("halo"):
		return tr("GAL_HINT_STABLE")
	if _unlocked.is_empty():
		return tr("GAL_HINT_EMPTY")
	if not _unlocked.has("halo"):
		return tr("GAL_HINT_NEED_MORE")
	return tr("GAL_HINT_TUNE")


func _unlock(comp: String) -> void:
	var card := QuizCard.make(_questions[comp], _rng)
	add_child(card)
	var right: bool = await card.done
	_quiz_points += BuildLogic.quiz_points(right)
	_unlocked.append(comp)
	Router.step("unlock_" + comp)
	_rebuild_blocks()
	_refresh()


func _finish_build() -> void:
	Router.step("stable")
	GalaxyGalleryStore.new(Settings.data_path("galaxy_gallery.json")).add(Session.player_name, _target.id,
		_knobs.duplicate(), _match, diff)
	start_collide()


# --- act 2: collide ----------------------------------------------------------------------------

func start_collide() -> void:
	_clear()
	_running = false
	_finished = false
	_make_view()
	var title := UiTheme.label("GAL_COLLIDE_TITLE", UiTheme.SIZE_H2 - 4, "serif", UiTheme.TEXT)
	title.position = Vector2(200, 52)
	add_child(title)
	_time_label = _plain("", UiTheme.SIZE_BODY - 2, "medium", UiTheme.TEXT)
	_time_label.position = VIEW.position + Vector2(28, VIEW.size.y - 64)
	add_child(_time_label)

	var col := VBoxContainer.new()
	col.position = Vector2(PANEL_X, 150)
	col.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var mine := _plain(tr("GAL_YOUR_GALAXY") % [tr("GAL_T_" + str(_target.id).to_upper()), Session.ensure_name()],
		UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.ACCENT_HI)
	mine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mine.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_child(mine)
	col.add_child(UiTheme.label("GAL_PARTNER", UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT_DIM))
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 20)
	_partner_thumb = TextureRect.new()
	_partner_thumb.custom_minimum_size = Vector2(120, 120)
	_partner_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prow.add_child(_partner_thumb)
	var pcol := VBoxContainer.new()
	pcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_partner_label = _plain("", UiTheme.SIZE_BODY, "semibold", UiTheme.TEXT)
	pcol.add_child(_partner_label)
	var choose := BigButton.make("GAL_PARTNER_CHOOSE", "grid_view", false, 520)
	choose.pressed.connect(_open_partner_picker)
	pcol.add_child(choose)
	prow.add_child(pcol)
	col.add_child(prow)
	_gallery = GalaxyGalleryStore.new(Settings.data_path("galaxy_gallery.json")).latest(12)
	_gallery.reverse()   # newest first
	_show_partner()
	col.add_child(UiTheme.label("GAL_APPROACH", UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT_DIM))
	var ap := HBoxContainer.new()
	ap.add_theme_constant_override("separation", 12)
	for a in CollideLogic.APPROACHES:
		ap.add_child(_choice("approach", a, "GAL_APPROACH_" + a.to_upper(), 300))
	col.add_child(ap)
	col.add_child(UiTheme.label("GAL_SPIN", UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT_DIM))
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 12)
	sp.add_child(_choice("spin", "with", "GAL_SPIN_WITH", 460))
	sp.add_child(_choice("spin", "against", "GAL_SPIN_AGAINST", 460))
	col.add_child(sp)
	_start_btn = BigButton.make("GAL_RUN", "play_arrow", true, int(PANEL_W))
	_start_btn.pressed.connect(_run_collision)
	col.add_child(_start_btn)
	_left_label = _plain("", UiTheme.SIZE_SMALL, "medium", UiTheme.TEXT_DIM)
	col.add_child(_left_label)
	col.add_child(UiTheme.label("GAL_BADGES", UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT_DIM))
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	for f in FeatureDetector.FEATURES:
		var b := VBoxContainer.new()
		b.custom_minimum_size = Vector2(225, 0)
		var ic := UiTheme.icon("workspace_premium", 64, UiTheme.TEXT_DIM)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(ic)
		var l := UiTheme.label("GAL_FEATURE_" + f.to_upper(), UiTheme.SIZE_SMALL - 2, "medium", UiTheme.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(l)
		strip.add_child(b)
		_badge_icons[f] = [ic, l]
	col.add_child(strip)
	var bar_row := VBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 6)
	_progress_label = _plain("", UiTheme.SIZE_SMALL, "medium", UiTheme.SCIENCE)
	_progress_label.custom_minimum_size = Vector2(PANEL_W, 0)
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar_row.add_child(_progress_label)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(PANEL_W, 22)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.add_theme_stylebox_override("background", UiTheme.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 13))
	_progress.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.SCIENCE, Color(0, 0, 0, 0), 0, 13))
	_progress.max_value = 1.0
	bar_row.add_child(_progress)
	bar_row.modulate.a = 0.0
	col.add_child(bar_row)
	_info = _plain(tr("GAL_COLLIDE_TASK"), UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_child(_info)
	# Tip after a collision without a new badge: stands out in its own coloured box.
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.SCIENCE, 0.14), Color(UiTheme.SCIENCE, 0.7), 2, 18))
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", 14)
	_tip.add_child(tip_row)
	tip_row.add_child(UiTheme.icon("lightbulb", 44, UiTheme.SCIENCE))
	_tip_label = _plain("", UiTheme.SIZE_SMALL, "semibold", UiTheme.SCIENCE)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(PANEL_W - 110, 0)
	tip_row.add_child(_tip_label)
	_tip.visible = false
	col.add_child(_tip)
	var done := BigButton.make("GAL_DONE", "check", false, int(PANEL_W))
	done.pressed.connect(_finish)
	col.add_child(done)
	_mark_choices()
	_update_badges()
	_preview_encounter()
	Router.step("collide")


func _choice(group: String, id: String, key: String, width: int) -> BigButton:
	var b := BigButton.make(key, "", false, width)
	b.pressed.connect(func():
		if _running:
			return
		match group:
			"partner": _partner = id
			"approach": _approach = id
			"spin": _spin = 1.0 if id == "with" else -1.0
		_mark_choices()
		_preview_encounter())
	_choice_buttons[group + ":" + id] = b
	return b


func _mark_choices() -> void:
	for key in _choice_buttons:
		var parts: PackedStringArray = str(key).split(":")
		var on := false
		match parts[0]:
			"partner": on = parts[1] == _partner
			"approach": on = parts[1] == _approach
			"spin": on = (parts[1] == "with") == (_spin > 0.0)
		LeaderboardOverlay._mark(_choice_buttons[key], on)
	_left_label.text = tr("GAL_LEFT") % (CollideLogic.MAX_COLLISIONS - _collisions)


## All partner options: [id, target id, label].
func _partner_text() -> String:
	for o in _partner_options():
		if o[0] == _partner:
			return str(o[2])
	return ""


func _partner_options() -> Array:
	var out := []
	for p in GalaxyTemplates.PARTNERS:
		out.append([p[0], p[1], tr("GAL_PARTNER_" + str(p[0]).to_upper())])
	for i in _gallery.size():
		out.append(["gallery_%d" % i, str(_gallery[i].target), tr("GAL_PARTNER_GALLERY") % str(_gallery[i].player)])
	return out


func _show_partner() -> void:
	for o in _partner_options():
		if o[0] == _partner:
			_partner_label.text = o[2]
			_partner_thumb.texture = GalaxyTemplates.thumbnail(GalaxyTemplates.get_target(o[1]))


## Partner choice as picture cards: the three galaxy types and the newest visitor galaxies.
func _open_partner_picker() -> void:
	if _running:
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.02, 0.94)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 30)
	overlay.add_child(v)
	var t := UiTheme.label("GAL_PARTNER_PICK", UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	var center := CenterContainer.new()
	center.add_child(grid)
	v.add_child(center)
	for o in _partner_options():
		var b := Button.new()
		b.custom_minimum_size = Vector2(400, 330)
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var img := TextureRect.new()
		img.texture = GalaxyTemplates.thumbnail(GalaxyTemplates.get_target(o[1]))
		img.custom_minimum_size = Vector2(220, 220)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(img)
		var l := _plain(o[2], UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.ACCENT_HI if o[0] == _partner else UiTheme.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(380, 0)
		col.add_child(l)
		var id: String = o[0]
		b.pressed.connect(func():
			Audio.play("tap")
			_partner = id
			_show_partner()
			_preview_encounter()
			overlay.queue_free())
		grid.add_child(b)
	var close := BigButton.make("CLOSE", "close", false, 360)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(overlay.queue_free)
	v.add_child(close)


func _partner_galaxy() -> Dictionary:
	if _partner.begins_with("gallery_"):
		var e: Dictionary = _gallery[int(_partner.trim_prefix("gallery_"))]
		var t := GalaxyTemplates.get_target(str(e.target))
		return {"pot": GalaxyTemplates.build(t, e.knobs), "target": t, "spin": 1.0}
	for p in GalaxyTemplates.PARTNERS:
		if p[0] == _partner:
			var t := GalaxyTemplates.get_target(p[1])
			return {"pot": t.reference, "target": t, "spin": 1.0}
	return {}


func _new_model() -> EncounterModel:
	var m := EncounterModel.new()
	m.setup({"pot": GalaxyTemplates.build(_target, _knobs), "target": _target, "spin": _spin}, _partner_galaxy(), _approach)
	return m


## Shows both galaxies at the start (not moving) for the current choices.
func _preview_encounter() -> void:
	_model = _new_model()
	_view.show_encounter(_model)
	_view.set_names([tr("GAL_YOURS"), _partner_text()])
	_view.stop()
	_time_label.text = tr("GAL_BEFORE")


func _run_collision() -> void:
	if _running or _collisions >= CollideLogic.MAX_COLLISIONS:
		return
	_running = true
	_collisions += 1
	_start_btn.disabled = true
	_mark_choices()
	Router.step("collision_%d" % _collisions)
	Audio.play("whoosh", "SFX", 0.6)
	_model = _new_model()
	_view.show_encounter(_model)
	_view.set_names([tr("GAL_YOURS"), _partner_text()])
	_view.play()
	_info.text = tr("GAL_RUNNING")
	_info.add_theme_color_override("font_color", UiTheme.TEXT)
	_tip.visible = false
	# The analysis runs on the CPU while the GPU shows the collision: the whole collision is
	# computed once more in the background with test stars; the result is shown at the end.
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = Thread.new()
	var m := _model
	_analysis = m
	_thread.start(func() -> Dictionary:
		# On the graphics card with many stars (faint rings stand out); without one, a few
		# hundred stars on the CPU.
		if m.run_stars_gpu(GPU_STARS):
			m.baseline(GPU_STARS)
		else:
			m.run_stars(250)
		return FeatureDetector.detect(m))


func _process(_delta: float) -> void:
	if _progress and is_instance_valid(_progress):
		var busy := _thread != null and _thread.is_alive() and _analysis != null
		(_progress.get_parent() as Control).modulate.a = 1.0 if busy else 0.0
		if busy:
			_progress.value = _analysis.progress()
			_progress_label.text = tr("GAL_PROGRESS") % int(_analysis.progress() * 100.0)
	if _view and _time_label and (_running or _view.mode == "build"):
		_time_label.text = tr("GAL_TIME") % int(round(_view.t * GalaxyPotential.MYR / 10.0) * 10)


func _on_collision_finished() -> void:
	if not _running:
		return
	if _thread.is_alive():
		_info.text = tr("GAL_ANALYSING")
		while _thread.is_alive():
			await get_tree().process_frame
			if not is_inside_tree():
				return   # left the game meanwhile; _exit_tree() takes care of the thread
	var found: Dictionary = _thread.wait_to_finish()
	_running = false
	var fresh := CollideLogic.new_badges(found, _badges)
	_badges.append_array(fresh)
	_update_badges()
	var seen := []
	for f in FeatureDetector.FEATURES:
		if float(found[f]) >= 0.0:
			seen.append(tr("GAL_FEATURE_" + f.to_upper()))
	_info.text = (tr("GAL_SEEN") % ", ".join(seen)) if not seen.is_empty() else tr("GAL_SEEN_NONE")
	_info.add_theme_color_override("font_color", UiTheme.SUCCESS if not seen.is_empty() else UiTheme.ACCENT_HI)
	if fresh.is_empty():
		var hint := CollideLogic.recipe_hint(_badges, str(_target.id))
		if hint != "":
			_tip_label.text = hint
			_tip.visible = true
		Audio.play("tick")
	else:
		Audio.play("success")
		for f in fresh:
			await _show_badge(f)
	_start_btn.disabled = _collisions >= CollideLogic.MAX_COLLISIONS
	_mark_choices()
	if _collisions >= CollideLogic.MAX_COLLISIONS:
		_finish()


func _update_badges() -> void:
	for f in _badge_icons:
		var on := _badges.has(f)
		(_badge_icons[f][0] as Label).add_theme_color_override("font_color", UiTheme.ACCENT if on else UiTheme.TEXT_DIM)
		(_badge_icons[f][1] as Label).add_theme_color_override("font_color", UiTheme.TEXT if on else UiTheme.TEXT_DIM)


## New badge: the shape next to a real galaxy that shows it.
func _show_badge(f: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.ACCENT, 0.7), 3))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	v.custom_minimum_size = Vector2(1200, 0)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.add_child(UiTheme.icon("workspace_premium", 80, UiTheme.ACCENT))
	head.add_child(_plain(tr("GAL_NEW_BADGE") % tr("GAL_FEATURE_" + f.to_upper()), UiTheme.SIZE_H2 - 4, "serif", UiTheme.ACCENT_HI))
	v.add_child(head)
	var path: String = CollideLogic.PHOTOS[f]
	if ResourceLoader.exists(path):
		var img := TextureRect.new()
		img.texture = load(path)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(1200, 560)
		v.add_child(img)
	var text := UiTheme.label("GAL_FEATURE_" + f.to_upper() + "_TEXT", UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(1200, 0)
	v.add_child(text)
	var go := BigButton.make("GAL_QUIZ_GO", "arrow_forward", true, 400)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(go)
	await go.pressed
	overlay.queue_free()


# --- result -------------------------------------------------------------------------------------

func _finish() -> void:
	if _finished:
		return
	if _running:
		# "Done" during a collision: stop it and its analysis; the thread is joined later.
		_view.stop()
		if _analysis:
			_analysis.cancelled = true
		_running = false
	_finished = true
	_running = true
	Router.step("done")
	var stable := BuildLogic.is_stable(_match, diff)
	var pts := CollideLogic.total_points(BuildLogic.build_points(_quiz_points, _match, diff), _badges.size(), diff)
	var stars := CollideLogic.stars(stable, _badges.size())
	var rank := Scores.submit("galaxy", Session.player_name, pts, stars, {"target": _target.id, "badges": _badges})
	Router.complete({"score": pts, "stars": stars, "match": snappedf(_match, 0.1), "badges": _badges, "target": _target.id})
	Audio.play("success")
	if stars == 3:
		Confetti.burst(self)
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
	var lines := [tr("GAL_RESULT_MATCH") % int(_match), tr("GAL_RESULT_BADGES") % [_badges.size(), FeatureDetector.FEATURES.size()],
		tr("AST_SCORE") % pts + "  ·  " + tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))]]
	for l in lines:
		v.add_child(_plain(l, UiTheme.SIZE_BODY, "medium", UiTheme.TEXT))
	var note := UiTheme.label("GAL_MODEL_NOTE", UiTheme.SIZE_SMALL - 4, "regular", UiTheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	v.add_child(note)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var on_again := func():
		_running = false
		await _pick_target()
	v.add_child(ResultActions.make("GAL_AGAIN", "blur_on", on_again, PANEL_W - 30.0, true))


func _plain(t: String, font_size: int, kind := "regular", color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(t, font_size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
