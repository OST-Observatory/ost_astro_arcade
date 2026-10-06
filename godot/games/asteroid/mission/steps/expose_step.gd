## Step 3 – expose: choose the exposure time, then watch the three images build up.
## Short = fainter asteroid (harder, more points), long = deeper image (easier, fewer
## points because telescope time is precious). 0.75 mag = factor 2 in exposure time.
class_name ExposeStep
extends MissionStep

const CHOICES := [
	{"key": "EXPOSE_SHORT", "offset": 0.75, "mult": 1.2, "icon": "timer"},
	{"key": "EXPOSE_NORMAL", "offset": 0.0, "mult": 1.0, "icon": "brightness_3"},
	{"key": "EXPOSE_LONG", "offset": -0.75, "mult": 0.85, "icon": "visibility"},
]
const BUILD_SEC := 1.6

var _base_s := 60.0
var _row: HBoxContainer
var _previews: Array[TextureRect] = []
var _frames: CcdFrames


func _ready() -> void:
	super._ready()
	add_header("EXPOSE_TITLE", "EXPOSE_TASK")
	# Exposure that gives the stage's target brightness (see BlinkChallenge.depth_for).
	var r: Dictionary = BlinkChallenge.RULES[mission.difficulty]
	var depth := BlinkChallenge.depth_for(float(mission.scenario.data.v_best), r.mag)
	_base_s = clampf(60.0 * pow(10.0, -0.4 * depth), 5.0, 900.0)
	_row = HBoxContainer.new()
	_row.position = Vector2(180, 420)
	_row.add_theme_constant_override("separation", 48)
	add_child(_row)
	for c in CHOICES:
		_row.add_child(_choice_card(c))


func _choice_card(c: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(700, 560)
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := UiTheme.icon(c.icon, 110, UiTheme.ACCENT)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	var secs := _base_s * pow(10.0, -0.4 * float(c.offset))
	var t := plain_label(_format_time(secs), 84, "bold", UiTheme.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	for pair in [[c.key, UiTheme.SIZE_H2 - 8, "semibold", UiTheme.TEXT], [c.key + "_DESC", UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT_DIM]]:
		var l := UiTheme.label(pair[0], pair[1], pair[2], pair[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(620, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	b.pressed.connect(func(): _choose(c, secs))
	return b


static func _format_time(secs: float) -> String:
	return "%d s" % int(round(secs)) if secs < 120.0 else "%d min" % int(round(secs / 60.0))


func _choose(c: Dictionary, secs: float) -> void:
	Audio.play("tap")
	mission.exposure_offset = c.offset
	mission.exposure_mult = c.mult
	mission.exposure_s = secs
	mission.challenge = BlinkChallenge.create(mission.scenario, mission.difficulty, mission.rng,
		{"obs_index": mission.obs_index, "center": mission.pointing, "exposure_offset": c.offset})
	_row.queue_free()
	await _expose_animation()
	done()


func _expose_animation() -> void:
	_frames = CcdFrames.new()
	add_child(_frames)
	_frames.build(mission.challenge.stars_px, mission.challenge.frames)
	var h := HBoxContainer.new()
	h.position = Vector2(180, 420)
	h.add_theme_constant_override("separation", 40)
	add_child(h)
	var mins := mission.challenge.frame_minutes()
	for i in BlinkChallenge.FRAMES:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 14)
		var tr_rect := TextureRect.new()
		tr_rect.texture = _frames.textures[i]
		tr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_rect.custom_minimum_size = Vector2(720, 480)
		var m := ShaderMaterial.new()
		m.shader = preload("res://games/asteroid/ccd/ccd_display.gdshader")
		m.set_shader_parameter("frame", _frames.textures[i])
		m.set_shader_parameter("image_size", Vector2(AsteroidScenario.IMAGE_SIZE))
		m.set_shader_parameter("seed", float(i * 7 + 3))
		m.set_shader_parameter("bg", 0.003 * float(mission.sky.get("bg_factor", 1.0)))
		m.set_shader_parameter("signal_scale", 0.0)
		tr_rect.material = m
		v.add_child(tr_rect)
		var cap := plain_label(tr("EXPOSE_FRAME") % [i + 1, mins[i]], UiTheme.SIZE_BODY, "medium", UiTheme.TEXT_DIM)
		v.add_child(cap)
		h.add_child(v)
		_previews.append(tr_rect)
	for i in BlinkChallenge.FRAMES:
		Audio.play("whoosh", "SFX", 1.4)
		var tw := create_tween()
		tw.tween_method(func(x): (_previews[i].material as ShaderMaterial).set_shader_parameter("signal_scale", x), 0.0, 1.0, BUILD_SEC)
		await tw.finished
		Audio.play("tick")
	await get_tree().create_timer(0.6).timeout
