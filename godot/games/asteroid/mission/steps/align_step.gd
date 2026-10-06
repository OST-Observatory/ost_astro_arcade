## Step 2 – align the telescope: a finder chart of real bright stars around the target.
## Drag the sky until the predicted asteroid position sits inside the camera field
## (rectangle). The ring shows "warmer/colder". Where you aim is where the images are taken.
class_name AlignStep
extends MissionStep

const VIEW := Rect2(180, 380, 1720, 1000)
const ARCSEC_PER_PX := 6.0          # finder chart scale (about 2.9 x 1.8 degrees visible)
const START_OFFSET_DEG := Vector2(0.55, 1.0)  # min/max initial mispointing

var _pointing := Vector2.ZERO       # arcsec, sky offset at the chart centre
var _target := Vector2.ZERO
var _stars: Array = []              # [xi, eta, mag]
var _drag := false
var _elapsed := 0.0
var _done := false
var _ring: RingProgress
var _status: Label
var _last_band := -1


func _ready() -> void:
	super._ready()
	add_header("ALIGN_TITLE", "ALIGN_TASK")
	var sc := mission.scenario
	_target = sc.position_at(mission.obs_index)
	if sc.data.has("finder"):
		_stars = sc.data.finder.stars
	else:
		_stars = sc.stars.filter(func(s): return s[2] < 14.0).map(func(s): return [s[0], s[1], s[2]])
	var ang := mission.rng.randf() * TAU
	var dist := mission.rng.randf_range(START_OFFSET_DEG.x, START_OFFSET_DEG.y) * 3600.0
	_pointing = _target + Vector2.from_angle(ang) * dist

	var v := VBoxContainer.new()
	v.position = Vector2(1960, 330)
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 26)
	add_child(v)
	_ring = RingProgress.new()
	_ring.custom_minimum_size = Vector2(260, 260)
	_ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_ring)
	_status = plain_label("", UiTheme.SIZE_BODY + 2, "medium", UiTheme.ACCENT_HI)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 200)
	v.add_child(_status)
	var legend := UiTheme.label("ALIGN_LEGEND", UiTheme.SIZE_SMALL, "regular", UiTheme.TEXT_DIM)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size = Vector2(520, 0)
	v.add_child(legend)
	_update_status()


func _process(delta: float) -> void:
	if not _done:
		_elapsed += delta
		queue_redraw()


func _sky_to_view(sky: Vector2) -> Vector2:
	var d := (sky - _pointing) / ARCSEC_PER_PX
	return VIEW.get_center() + Vector2(-d.x, -d.y)  # north up, east left


func _fov_rect() -> Rect2:
	var s := Vector2(AsteroidScenario.IMAGE_SIZE) * AsteroidScenario.ARCSEC_PER_PX / ARCSEC_PER_PX
	return Rect2(VIEW.get_center() - s / 2.0, s)


func _draw() -> void:
	draw_rect(VIEW, Color(0.01, 0.015, 0.04))
	var font := UiTheme.font("regular")
	for s in _stars:
		var p := _sky_to_view(Vector2(s[0], s[1]))
		if not VIEW.grow(-4).has_point(p):
			continue
		var r := clampf(9.0 - 0.6 * float(s[2]), 2.0, 8.0)
		draw_circle(p, r, Color(1, 1, 1, clampf(1.4 - 0.06 * float(s[2]), 0.6, 1.0)))
	# Predicted asteroid position (from the orbit).
	var t := _sky_to_view(_target)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0)
	if VIEW.has_point(t):
		draw_arc(t, 26.0 + 6.0 * pulse, 0, TAU, 48, UiTheme.ACCENT, 4.0, true)
		draw_line(t + Vector2(-40, 0), t + Vector2(-18, 0), UiTheme.ACCENT, 3.0)
		draw_line(t + Vector2(18, 0), t + Vector2(40, 0), UiTheme.ACCENT, 3.0)
		draw_line(t + Vector2(0, -40), t + Vector2(0, -18), UiTheme.ACCENT, 3.0)
		draw_line(t + Vector2(0, 18), t + Vector2(0, 40), UiTheme.ACCENT, 3.0)
	elif mission.difficulty != "pro":
		# Arrow at the edge pointing to the target (not in pro mode).
		var c := VIEW.get_center()
		var dir := (t - c).normalized()
		var edge := c + dir * (minf(VIEW.size.x, VIEW.size.y) / 2.0 - 70.0)
		draw_line(edge - dir * 60.0, edge, UiTheme.ACCENT, 8.0, true)
		draw_colored_polygon(PackedVector2Array([edge + dir * 30.0, edge + dir.orthogonal() * 22.0, edge - dir.orthogonal() * 22.0]), UiTheme.ACCENT)
	# Camera field of view.
	var fov := _fov_rect()
	var inside := _target_inside()
	draw_rect(fov, UiTheme.SUCCESS if inside else UiTheme.SCIENCE, false, 4.0)
	draw_string(font, fov.position + Vector2(8, -12), "CDK20 · QHY600  35′ × 24′", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiTheme.SCIENCE)
	draw_rect(VIEW, UiTheme.LINE, false, 2.0)
	# Compass.
	var cpos := VIEW.position + Vector2(70, VIEW.size.y - 70)
	draw_string(font, cpos + Vector2(-8, -36), tr("ALIGN_NORTH"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiTheme.TEXT_DIM)
	draw_line(cpos, cpos + Vector2(0, -28), UiTheme.TEXT_DIM, 2.0)
	draw_string(font, cpos + Vector2(-60, 8), tr("ALIGN_EAST"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiTheme.TEXT_DIM)
	draw_line(cpos, cpos + Vector2(-28, 0), UiTheme.TEXT_DIM, 2.0)


func _target_inside() -> bool:
	return _fov_rect().grow(-60.0).has_point(_sky_to_view(_target))


func _gui_input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventScreenTouch:
		_drag = event.pressed and VIEW.has_point(event.position)
		if not event.pressed and _target_inside():
			_finish()
	elif event is InputEventScreenDrag and _drag:
		# Dragging the sky: moving the finger right moves the view west (pointing east).
		_pointing += Vector2(event.relative.x, event.relative.y) * ARCSEC_PER_PX
		_update_status()


func _update_status() -> void:
	var dist_deg := _pointing.distance_to(_target) / 3600.0
	_ring.value = clampf(1.0 - dist_deg / START_OFFSET_DEG.y, 0.0, 1.0)
	var band := 0 if dist_deg > 0.7 else (1 if dist_deg > 0.35 else (2 if dist_deg > 0.12 else 3))
	_ring.color = [UiTheme.DANGER, UiTheme.ACCENT, UiTheme.ACCENT_HI, UiTheme.SUCCESS][band]
	_status.text = tr(["ALIGN_COLD", "ALIGN_WARM", "ALIGN_HOT", "ALIGN_INSIDE"][band]) if not _target_inside() else tr("ALIGN_RELEASE")
	if band != _last_band:
		Audio.play("tick", "UI", 0.8 + 0.25 * band)
		_last_band = band


func _finish() -> void:
	_done = true
	Audio.play("success")
	mission.pointing = _pointing
	mission.points["align"] = int(clampf(MissionState.MAX_POINTS.align - _elapsed * 4.0, 60.0, MissionState.MAX_POINTS.align) * mission.diff_mult())
	_status.text = tr("ALIGN_DONE")
	await get_tree().create_timer(1.2).timeout
	done()
