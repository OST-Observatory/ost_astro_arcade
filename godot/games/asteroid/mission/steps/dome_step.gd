## Step 2, open the dome: the observatory in 3D under the real sky of the chosen night.
## The visitor looks around (drag, pinch), opens the shutter and, inside the dome, taps the
## direction where the orbit prediction puts the asteroid. The dome turns there and the
## telescope slews to the predicted position (hour angle/declination at the chosen time).
## Then there is time to look around before the fine alignment.
class_name DomeStep
extends MissionStep

## Pointing tolerance (deg) per difficulty; after a few misses the marker helps everyone.
const TOLERANCE := {"explorer": 30.0, "researcher": 22.0, "pro": 15.0}
const MISSES_FOR_MARKER := 2
## Dome parked with the slit towards the roof view, so the visitor sees it open; once the
## visitor is inside it stands at home, slit to the north where the parked telescope points,
## so that turning to the target is clearly seen.
const PARK_AZ := 200.0
const HOME_AZ := 0.0
var _obs: ObservatoryScene
var _btn: BigButton
var _next: BigButton
var _figures: BigButton
var _go_out: BigButton
var _go_in: BigButton
var _title: Label
var _task: Label
var _header: VBoxContainer
var _where_box: PanelContainer
var _where_label: Label
var _tip: Label
var _taps := []             # [direction, hit, time] of the taps on the sky
var _status: Label
var _overlay: Control
var _shade: ColorRect
var _phase := "outside"     # outside, opening, point, slewing, ready
var _sample := {}
var _target := Vector3.UP   # predicted asteroid direction
var _misses := 0
var _marker := false
var _t := 0.0


func _ready() -> void:
	super._ready()
	_sample = mission.sample(mission.obs_index)
	var vp := SubViewportContainer.new()
	vp.stretch = true
	vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	Settings.apply_3d(sv)
	vp.add_child(sv)
	_obs = ObservatoryScene.new()
	sv.add_child(_obs)
	_obs.set_night(0.95)
	_obs.set_sky_time(Kepler.jd_from_iso(_sample.t))
	_obs.set_shutter(0.0)
	_obs.point_to(0.0, 90.0)   # parked at the pole
	_obs.set_dome_azimuth(PARK_AZ)
	_obs.set_shot("roof")
	_obs.set_look(true)
	_obs.sky_tapped.connect(_on_sky_tap)
	_target = _obs.sky.dir_of(float(_sample.ra), float(_sample.dec))
	_marker = mission.difficulty == "explorer"

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.35)
	_shade.position = Vector2(0, 0)
	_shade.size = Vector2(2560, 300)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	var header := add_header("DOME_TITLE", "DOME_TASK")
	_header = header
	_title = header.get_child(0) as Label
	_task = header.get_child(1) as Label
	# Where to point, set apart: framed, in the accent colour, with a compass.
	_where_box = PanelContainer.new()
	var sb := UiTheme.box(Color(0.06, 0.04, 0.02, 0.75), UiTheme.ACCENT, 3)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_where_box.add_theme_stylebox_override("panel", sb)
	_where_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_where_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	hb.add_child(UiTheme.icon("explore", 60, UiTheme.ACCENT))
	_where_label = plain_label("", UiTheme.SIZE_H2 - 2, "semibold", UiTheme.ACCENT_HI)
	_where_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_where_label)
	_where_box.add_child(hb)
	_where_box.visible = false
	header.add_child(_where_box)
	_tip = UiTheme.label("DOME_TIP", UiTheme.SIZE_SMALL + 2, "regular", UiTheme.TEXT_DIM)
	_tip.visible = false
	header.add_child(_tip)
	_task.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_task.text = tr("DOME_TASK")
	_status = plain_label("", UiTheme.SIZE_H2 - 6, "semibold", UiTheme.ACCENT_HI)
	_status.position = Vector2(180, 1130)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1500, 0)
	add_child(_status)
	_figures = BigButton.make("DOME_FIGURES", "auto_awesome", false, 360)
	_figures.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL + 4)
	_figures.position = Vector2(2140, 330)
	_figures.pressed.connect(func():
		_obs.sky.show_figures(not _obs.sky.figures_shown())
		Audio.play("tap"))
	add_child(_figures)
	_go_out = BigButton.make("DOME_GO_OUT", "zoom_out", false, 360)
	_go_in = BigButton.make("DOME_GO_IN", "zoom_in", false, 360)
	for b in [_go_out, _go_in]:
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL + 4)
		b.position = Vector2(2140, 450)
		b.visible = false
		add_child(b)
	_go_out.pressed.connect(func(): _obs.switch_view("roof"))
	_go_in.pressed.connect(func(): _obs.switch_view("inside"))
	_obs.view_changed.connect(func(_n: String):
		_update_view_buttons())
	_btn = BigButton.make("DOME_OPEN", "power", true, 620)
	_btn.custom_minimum_size.y = 150
	_btn.add_theme_font_size_override("font_size", 54)
	_btn.position = Vector2(1760, 1150)
	_btn.pressed.connect(_open)
	add_child(_btn)
	_next = BigButton.make("DOME_NEXT", "arrow_forward", true, 620)
	_next.custom_minimum_size.y = 150
	_next.add_theme_font_size_override("font_size", 48)
	_next.position = Vector2(1760, 1150)
	_next.visible = false
	_next.pressed.connect(done)
	add_child(_next)
	# Fade in from black: hides the first frames while the 3D view starts up.
	var fade := ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.45)
	tw.tween_callback(fade.queue_free)


func _process(delta: float) -> void:
	_t += delta
	_overlay.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _obs.handle_input(event):
		accept_event()


func _open() -> void:
	_btn.disabled = true
	_btn.visible = false
	_phase = "opening"
	_obs.set_look(false)
	Router.step("dome_open")
	_status.text = tr("DOME_OPENING")
	await _obs.fly("", "roof", 1.2)
	Audio.play("whoosh", "SFX", 0.6)
	var tw := create_tween()
	tw.tween_method(_obs.set_shutter, 0.0, 1.0, 3.0).set_trans(Tween.TRANS_SINE)
	await tw.finished
	_status.text = ""
	await _obs.switch_view("inside", true, func(): _obs.set_dome_azimuth(HOME_AZ))
	_obs.set_look(true)
	_phase = "point"
	_title.text = "DOME_TITLE_POINT"   # the observatory is open now: next comes the pointing
	_where_label.text = _where()
	_where_box.visible = true
	_tip.visible = true
	_set_task(tr("DOME_POINT"))
	_update_view_buttons()


## Inside the dome "go outside", on the roof "into the dome" (after opening).
func _update_view_buttons() -> void:
	var open := _phase in ["point", "slewing", "ready"]
	_go_out.visible = open and _obs.view_name == "inside"
	_go_in.visible = open and _obs.view_name == "roof"


## New task text; the dark band behind the header grows with it.
func _set_task(text: String) -> void:
	_task.text = text
	await get_tree().process_frame
	_shade.size.y = maxf(300.0, _header.get_global_rect().end.y + 30.0)


## Where the asteroid stands, in words (explorer, observer) or as azimuth (expert).
func _where() -> String:
	var alt := int(round(float(_sample.alt)))
	var az := float(_sample.az)
	var t: String
	if mission.difficulty == "pro":
		t = tr("DOME_WHERE_PRO") % [int(round(az)), alt]
	else:
		t = tr("DOME_WHERE") % [tr("DIR8_%d" % (int(round(az / 45.0)) % 8)), alt]
	return t.left(1).to_upper() + t.substr(1)


func _on_sky_tap(dir: Vector3) -> void:
	if _phase != "point":
		return
	var tol: float = TOLERANCE.get(mission.difficulty, 22.0)
	var hit := rad_to_deg(dir.angle_to(_target)) <= tol
	_taps.append([dir, hit, _t])
	if hit:
		_slew()
		return
	_misses += 1
	Audio.play("fail", "SFX", 0.5)
	_status.text = tr("DOME_MISS") % _hint(dir, tol)
	if _misses >= MISSES_FOR_MARKER and not _marker:
		_marker = true
		_status.text += "\n" + tr("DOME_MARK_HELP")


## "further right and higher": seen from the tapped direction, as the visitor faces it.
func _hint(dir: Vector3, tol: float) -> String:
	var a := RealSky.alt_az(dir)
	var t := RealSky.alt_az(_target)
	var daz := wrapf(t.y - a.y, -180.0, 180.0) * cos(deg_to_rad(clampf(a.x, 0.0, 80.0)))
	var dalt := t.x - a.x
	var parts: Array[String] = []
	if absf(daz) > tol * 0.5 or absf(daz) >= absf(dalt):
		parts.append(tr("DOME_HINT_RIGHT") if daz > 0.0 else tr("DOME_HINT_LEFT"))
	if absf(dalt) > tol * 0.5 or parts.is_empty():
		parts.append(tr("DOME_HINT_UP") if dalt > 0.0 else tr("DOME_HINT_DOWN"))
	return (" " + tr("DOME_AND") + " ").join(PackedStringArray(parts))


func _slew() -> void:
	_phase = "slewing"
	Audio.play("success")
	_status.text = tr("DOME_SLEWING")
	_where_box.visible = false
	_tip.visible = false
	# From the target's side, a little raised: the slit swings round from the north into
	# view and the telescope turns out of it, towards the visitor (and the target behind).
	var aa := RealSky.alt_az(_target)
	await _obs.view_from(Vector3(0, 3.2, 0) + RealSky.horizon_dir(aa.x * 0.45, aa.y) * 11.0, Vector3(0, 2.9, 0), "roof")
	# Real pointing for the chosen time: hour angle = local sidereal time - right ascension.
	var jd := Kepler.jd_from_iso(_sample.t)
	var ha := wrapf(ObservatoryScene.lst_deg(jd) - float(_sample.ra), -180.0, 180.0)
	var dec := float(_sample.dec)
	_obs.set_telescope(ha, dec)
	var az_end := _obs.tube_azimuth()
	_obs.set_telescope(0.0, 90.0)   # back to park until the slew starts (no one-frame jump)
	var slew := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	slew.tween_method(func(t: float):
		_obs.set_telescope(ha * t, lerpf(90.0, dec, t))
		_obs.set_dome_azimuth(rad_to_deg(lerp_angle(deg_to_rad(HOME_AZ), deg_to_rad(az_end), t))), 0.0, 1.0, 6.0)
	Audio.play("whoosh", "SFX", 0.45)
	await slew.finished
	_phase = "ready"
	_status.text = tr("DOME_READY") % [int(round(float(_sample.alt))), int(round(_obs.tube_azimuth()))]
	_set_task(tr("DOME_LOOK"))
	_next.visible = true
	Audio.play("tick")


# --- overlay: compass on the horizon, predicted position -----------------------------------

func _draw_overlay() -> void:
	var font := UiTheme.font("semibold")
	var pro := mission.difficulty == "pro"
	for k in 8:
		var p: Variant = _obs.screen_pos(RealSky.horizon_dir(0.0, k * 45.0))
		if p == null:
			continue
		var txt := tr("DIR8S_%d" % k) + (" %d°" % (k * 45) if pro else "")
		var size := 44 if k % 2 == 0 else 34
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var col := UiTheme.ACCENT_HI if k == 0 else Color(0.85, 0.9, 1.0, 0.85)
		_overlay.draw_line(p - Vector2(0, 14), p + Vector2(0, 14), col, 3.0)
		_overlay.draw_string_outline(font, p + Vector2(-w / 2.0, -26), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(0, 0, 0, 0.6))
		_overlay.draw_string(font, p + Vector2(-w / 2.0, -26), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	if _marker and _phase in ["outside", "point", "slewing"]:
		_draw_marker(font)
	_draw_taps()


## Where the visitor tapped: a fading red ring with a cross for a miss, a green ring that
## stays for the hit (also seen from outside while the dome turns there).
func _draw_taps() -> void:
	for tap in _taps:
		var p: Variant = _obs.screen_pos(tap[0])
		if p == null:
			continue
		var age: float = _t - float(tap[2])
		if tap[1]:
			var r := 50.0 + 6.0 * sin(_t * 4.0)
			_overlay.draw_arc(p, r, 0.0, TAU, 64, UiTheme.SUCCESS, 6.0, true)
			_overlay.draw_arc(p, 8.0, 0.0, TAU, 24, UiTheme.SUCCESS, 4.0, true)
		elif age < 2.0:
			var c := Color(UiTheme.DANGER, 1.0 - age / 2.0)
			_overlay.draw_arc(p, 40.0, 0.0, TAU, 48, c, 5.0, true)
			_overlay.draw_line(p - Vector2(16, 16), p + Vector2(16, 16), c, 5.0, true)
			_overlay.draw_line(p - Vector2(16, -16), p + Vector2(16, -16), c, 5.0, true)


func _draw_marker(font: Font) -> void:
	# Keep clear of the header (top) and the buttons (bottom).
	var top := _shade.size.y + 80.0
	var rect := Rect2(Vector2(120, top), _overlay.size - Vector2(240, top + 330))
	var p: Variant = _obs.screen_pos(_target)
	var col := UiTheme.ACCENT
	if p != null and rect.has_point(p):
		var r := 62.0 + 8.0 * sin(_t * 4.0)
		_overlay.draw_arc(p, r, 0.0, TAU, 64, col, 5.0, true)
		var txt := tr("DOME_MARK")
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_overlay.draw_string_outline(font, p + Vector2(-w / 2.0, r + 44), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, Color(0, 0, 0, 0.6))
		_overlay.draw_string(font, p + Vector2(-w / 2.0, r + 44), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, col)
		return
	# Off screen: an arrow at the edge pointing the way to turn.
	var local := _obs.camera.global_basis.inverse() * _target
	var v := Vector2(local.x, -local.y)
	if v.length() < 1e-4:
		v = Vector2(1, 0)
	v = v.normalized()
	var c := rect.get_center()
	var s := minf(rect.size.x / 2.0 / maxf(absf(v.x), 1e-4), rect.size.y / 2.0 / maxf(absf(v.y), 1e-4))
	var tip := c + v * s
	var side := v.orthogonal() * 34.0
	var pulse := 1.0 + 0.12 * sin(_t * 5.0)
	_overlay.draw_colored_polygon(PackedVector2Array([tip, tip - v * 70.0 * pulse + side, tip - v * 70.0 * pulse - side]), col)
