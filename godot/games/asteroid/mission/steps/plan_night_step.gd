## Step 1 – plan the night: drag the time cursor across the night. The chart shows the
## asteroid's altitude, the Moon and twilight; a good choice (high, dark, little
## moonlight) gives points AND a darker, less noisy sky in the images later.
class_name PlanNightStep
extends MissionStep

const CHART := Rect2(180, 370, 1700, 820)

var _first := 0                      # first/last track index shown (sun below -6 deg)
var _last := 0
var _cursor := 0.0
var _info: Label
var _quality: RingProgress
var _quality_label: Label
var _hint: Label
var _ok_btn: BigButton
var _dragging := false


func _ready() -> void:
	super._ready()
	add_header("PLAN_TITLE", "PLAN_TASK")
	var track := mission.scenario.track
	_first = track.size()
	for i in track.size():
		if float(track[i].sun_alt) < -6.0:
			_first = mini(_first, i)
			_last = i
	# Start in early evening twilight so the player has to look for a better time.
	_cursor = float(_first + 2)
	_build_side_panel()
	_update()


func _build_side_panel() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(1950, 330)
	v.custom_minimum_size = Vector2(540, 0)
	v.add_theme_constant_override("separation", 22)
	add_child(v)
	_quality = RingProgress.new()
	_quality.custom_minimum_size = Vector2(260, 260)
	_quality.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_quality)
	_quality_label = plain_label("", 76, "bold", UiTheme.ACCENT)
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quality_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quality_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quality.add_child(_quality_label)
	var cap := UiTheme.label("PLAN_QUALITY", UiTheme.SIZE_SMALL, "medium", UiTheme.TEXT_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	_info = plain_label("", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(540, 250)
	v.add_child(_info)
	_hint = plain_label("", UiTheme.SIZE_BODY, "medium", UiTheme.ACCENT_HI)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(540, 120)
	v.add_child(_hint)
	_ok_btn = BigButton.make("PLAN_OK", "check", true, 540)
	_ok_btn.pressed.connect(_confirm)
	v.add_child(_ok_btn)


# --- chart ---------------------------------------------------------------------------

func _x_for(i: float) -> float:
	return CHART.position.x + (i - _first) / maxf(1.0, float(_last - _first)) * CHART.size.x


func _y_for(alt: float) -> float:
	return CHART.end.y - clampf(alt, 0.0, 90.0) / 90.0 * CHART.size.y


func _draw() -> void:
	var track := mission.scenario.track
	# Twilight background: blue in twilight, black when astronomically dark.
	for i in range(_first, _last):
		var sun: float = track[i].sun_alt
		var dark := clampf((-sun - 6.0) / 12.0, 0.0, 1.0)
		var col := Color(0.05, 0.12, 0.28).lerp(Color(0.01, 0.01, 0.03), dark)
		draw_rect(Rect2(_x_for(i), CHART.position.y, _x_for(i + 1) - _x_for(i) + 1, CHART.size.y), col)
	draw_rect(CHART, UiTheme.LINE, false, 2.0)
	# Altitude grid every 30 degrees.
	var font := UiTheme.font("regular")
	for alt in [30, 60]:
		var y := _y_for(alt)
		draw_line(Vector2(CHART.position.x, y), Vector2(CHART.end.x, y), Color(1, 1, 1, 0.08), 1.0)
		draw_string(font, Vector2(CHART.position.x + 10, y - 8), "%d°" % alt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.TEXT_DIM)
	# Time labels every hour.
	for i in range(_first, _last + 1):
		var t: String = track[i].t
		if t.substr(14, 2) == "00":
			var x := _x_for(i)
			draw_line(Vector2(x, CHART.end.y), Vector2(x, CHART.end.y + 12), UiTheme.TEXT_DIM, 2.0)
			draw_string(font, Vector2(x - 34, CHART.end.y + 48), Kepler.local_time_hhmm(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.TEXT_DIM)
	# Moon (dashed, brightness = illumination) and target altitude curves.
	var moon_col := Color(0.85, 0.85, 0.75, 0.35 + 0.5 * float(track[_first].moon_illum))
	for i in range(_first, _last):
		if i % 2 == 0 and float(track[i].moon_alt) > 0.0:
			draw_line(Vector2(_x_for(i), _y_for(track[i].moon_alt)), Vector2(_x_for(i + 1), _y_for(track[i + 1].moon_alt)), moon_col, 3.0, true)
	var pts := PackedVector2Array()
	for i in range(_first, _last + 1):
		pts.append(Vector2(_x_for(i), _y_for(track[i].alt)))
	draw_polyline(pts, UiTheme.SCIENCE, 5.0, true)
	# Usable window shading (sun < -12, altitude > 25).
	for i in range(_first, _last):
		if not mission.quality_at(i).ok:
			draw_rect(Rect2(_x_for(i), CHART.position.y, _x_for(i + 1) - _x_for(i) + 1, CHART.size.y), Color(0, 0, 0, 0.35))
	# Legend.
	draw_string(font, Vector2(CHART.position.x + 16, CHART.position.y + 44), tr("PLAN_LEGEND_TARGET"), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UiTheme.SCIENCE)
	draw_string(font, Vector2(CHART.position.x + 16, CHART.position.y + 88), tr("PLAN_LEGEND_MOON") % int(round(float(track[_first].moon_illum) * 100)), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, moon_col)
	# Cursor.
	var cx := _x_for(_cursor)
	var s := mission.sample(_cursor)
	draw_line(Vector2(cx, CHART.position.y), Vector2(cx, CHART.end.y), UiTheme.ACCENT, 4.0)
	draw_circle(Vector2(cx, _y_for(s.alt)), 16.0, UiTheme.ACCENT)
	draw_circle(Vector2(cx, CHART.end.y + 90), 34.0, UiTheme.ACCENT)
	draw_string(UiTheme.font("icons"), Vector2(cx - 22, CHART.end.y + 112), Icons.get_char("timer"), HORIZONTAL_ALIGNMENT_LEFT, -1, 44, UiTheme.BG)


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		_dragging = event.pressed and Rect2(CHART.position, CHART.size + Vector2(0, 160)).has_point(event.position)
		pos = event.position
	elif event is InputEventScreenDrag and _dragging:
		pos = event.position
	else:
		return
	if _dragging:
		var f := clampf((pos.x - CHART.position.x) / CHART.size.x, 0.0, 1.0)
		var new_cursor := lerpf(_first, _last, f)
		if int(round(new_cursor)) != int(round(_cursor)):
			Audio.play("tick", "UI", 0.8 + 0.4 * f, -10.0)
		_cursor = new_cursor
		_update()


func _update() -> void:
	var i := roundf(_cursor)
	var s := mission.sample(i)
	var q := mission.quality_at(i)
	_quality.value = q.q
	_quality.color = UiTheme.SUCCESS if q.q > 0.7 else (UiTheme.ACCENT if q.q > 0.4 else UiTheme.DANGER)
	_quality_label.text = "%d" % int(round(q.q * 100))
	_info.text = tr("PLAN_INFO") % [Kepler.local_time_hhmm(s.t), int(round(float(s.alt))),
		int(round(float(s.sun_alt))), tr("PLAN_MOON_UP") if float(s.moon_alt) > 0 else tr("PLAN_MOON_DOWN")]
	if not q.ok:
		_hint.text = tr("PLAN_HINT_TWILIGHT") if float(s.sun_alt) >= -12.0 else tr("PLAN_HINT_LOW")
	elif q.q_alt < 0.5:
		_hint.text = tr("PLAN_HINT_HIGHER")
	elif q.q_moon < 0.6:
		_hint.text = tr("PLAN_HINT_MOON")
	else:
		_hint.text = tr("PLAN_HINT_GOOD")
	_ok_btn.disabled = not q.ok
	queue_redraw()


func _confirm() -> void:
	var i := roundf(_cursor)
	mission.obs_index = i
	mission.sky = mission.quality_at(i)
	mission.points["plan"] = int(round(MissionState.MAX_POINTS.plan * mission.sky.q * mission.diff_mult()))
	done()
