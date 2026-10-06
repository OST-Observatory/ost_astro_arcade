## Step 5 – measure the positions: each exposure is shown strongly magnified around the
## asteroid. Tap its centre as precisely as possible. Astrometry like this is what turns
## a discovery into an orbit; the accuracy decides how sharp the orbit in step 6 is.
class_name MeasureStep
extends MissionStep

const VIEW := Rect2(500, 330, 900, 900)
const SPAN_PX := 90.0                 # image pixels shown across the view (x10 zoom)
const ASSIST_PX := {"explorer": 2.0, "researcher": 1.0, "pro": 0.0}

var _frames: CcdFrames
var _view: TextureRect
var _index := 0
var _centers: Array[Vector2] = []     # view centre per frame (image px), not centred on target
var _taps: Array[Vector2] = []
var _errors: Array[float] = []
var _msg: Label
var _counter: Label
var _cross := Vector2(-1, -1)
var _locked := false


func _ready() -> void:
	super._ready()
	add_header("MEASURE_TITLE", "MEASURE_TASK")
	var ch := mission.challenge
	_frames = CcdFrames.new()
	add_child(_frames)
	_frames.build(ch.stars_px, ch.frames)
	for a in ch.asteroid_px:
		_centers.append(a + Vector2(mission.rng.randf_range(-18, 18), mission.rng.randf_range(-18, 18)))

	var bg := Panel.new()
	bg.position = VIEW.position - Vector2(6, 6)
	bg.size = VIEW.size + Vector2(12, 12)
	bg.add_theme_stylebox_override("panel", UiTheme.box(Color.BLACK, Color(UiTheme.SCIENCE, 0.5), 3, 10))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_view = TextureRect.new()
	_view.position = VIEW.position
	_view.size = VIEW.size
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var m := ShaderMaterial.new()
	m.shader = preload("res://games/asteroid/ccd/ccd_display.gdshader")
	m.set_shader_parameter("image_size", Vector2(AsteroidScenario.IMAGE_SIZE))
	m.set_shader_parameter("bg", 0.003 * float(mission.sky.get("bg_factor", 1.0)))
	m.set_shader_parameter("view_span", Vector2.ONE * SPAN_PX / Vector2(AsteroidScenario.IMAGE_SIZE))
	_view.material = m
	_view.gui_input.connect(_on_input)
	add_child(_view)

	var v := VBoxContainer.new()
	v.position = Vector2(1520, 330)
	v.custom_minimum_size = Vector2(900, 0)
	v.add_theme_constant_override("separation", 28)
	add_child(v)
	_counter = plain_label("", UiTheme.SIZE_H2, "semibold", UiTheme.ACCENT)
	v.add_child(_counter)
	var why := UiTheme.label("MEASURE_WHY", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT_DIM)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.custom_minimum_size = Vector2(900, 0)
	v.add_child(why)
	_msg = plain_label("", UiTheme.SIZE_BODY + 2, "medium", UiTheme.ACCENT_HI)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(900, 160)
	v.add_child(_msg)
	_show(0)


func _show(i: int) -> void:
	_index = i
	_cross = Vector2(-1, -1)
	_locked = false
	var m := _view.material as ShaderMaterial
	_view.texture = _frames.textures[i]
	m.set_shader_parameter("frame", _frames.textures[i])
	m.set_shader_parameter("seed", float(i * 7 + 3))
	m.set_shader_parameter("view_center", _centers[i] / Vector2(AsteroidScenario.IMAGE_SIZE))
	_counter.text = tr("MEASURE_COUNTER") % [i + 1, BlinkChallenge.FRAMES]
	queue_redraw()


func _view_to_image(p: Vector2) -> Vector2:
	return _centers[_index] + (p / VIEW.size - Vector2(0.5, 0.5)) * SPAN_PX


func _image_to_view(px: Vector2) -> Vector2:
	return VIEW.position + ((px - _centers[_index]) / SPAN_PX + Vector2(0.5, 0.5)) * VIEW.size


func _on_input(event: InputEvent) -> void:
	if _locked or not (event is InputEventScreenTouch) or event.pressed:
		return
	var p := _view_to_image(event.position)
	var truth: Vector2 = mission.challenge.asteroid_px[_index]
	var err := p.distance_to(truth)
	if err > 12.0:
		Audio.play("fail", "UI", 1.0, -6.0)
		_msg.text = tr("MEASURE_MISS")
		return
	# Small snap-in help for younger players (explorer/researcher).
	var assist: float = ASSIST_PX.get(mission.difficulty, 0.0)
	if err <= assist:
		p = truth
		err = 0.0
	_locked = true
	_cross = p
	_taps.append(p)
	_errors.append(err)
	Audio.play("tap")
	var arcsec := err * AsteroidScenario.ARCSEC_PER_PX
	_msg.text = tr("MEASURE_RESULT") % AstroFormat.num(arcsec, 1)
	queue_redraw()
	await get_tree().create_timer(1.1).timeout
	if _index + 1 < BlinkChallenge.FRAMES:
		_show(_index + 1)
	else:
		_finish()


func _draw() -> void:
	if _cross.x < 0:
		return
	var c := _image_to_view(_cross)
	var t := _image_to_view(mission.challenge.asteroid_px[_index])
	draw_arc(t, 22.0, 0, TAU, 48, Color(UiTheme.SUCCESS, 0.9), 3.0, true)
	draw_line(c + Vector2(-34, 0), c + Vector2(34, 0), UiTheme.ACCENT, 3.0)
	draw_line(c + Vector2(0, -34), c + Vector2(0, 34), UiTheme.ACCENT, 3.0)


func _finish() -> void:
	var mean_px := 0.0
	for e in _errors:
		mean_px += e
	mean_px /= _errors.size()
	mission.measured = _taps
	mission.measure_error_arcsec = mean_px * AsteroidScenario.ARCSEC_PER_PX
	mission.points["measure"] = int(clampf(MissionState.MAX_POINTS.measure * (1.0 - mean_px / 6.0), 40.0, MissionState.MAX_POINTS.measure) * mission.diff_mult())
	Audio.play("success")
	done()
