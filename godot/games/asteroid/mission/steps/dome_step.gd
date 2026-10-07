## Step 2 – open the dome: the observatory in 3D at the chosen night. One big button opens
## the shutter; the camera moves inside and the telescope slews to the asteroid's real
## position (hour angle/declination at the chosen time), the dome turning along with it.
class_name DomeStep
extends MissionStep

var _obs: ObservatoryScene
var _btn: BigButton
var _status: Label


func _ready() -> void:
	super._ready()
	var vp := SubViewportContainer.new()
	vp.stretch = true
	vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	vp.add_child(sv)
	_obs = ObservatoryScene.new()
	sv.add_child(_obs)
	_obs.set_night(0.95)
	_obs.set_shutter(0.0)
	_obs.point_to(0.0, 90.0)   # parked at the pole
	_obs.set_shot("roof")

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.position = Vector2(0, 0)
	shade.size = Vector2(2560, 300)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	add_header("DOME_TITLE", "DOME_TASK")
	_status = plain_label("", UiTheme.SIZE_H2 - 6, "semibold", UiTheme.ACCENT_HI)
	_status.position = Vector2(180, 1160)
	add_child(_status)
	_btn = BigButton.make("DOME_OPEN", "power", true, 620)
	_btn.custom_minimum_size.y = 150
	_btn.add_theme_font_size_override("font_size", 54)
	_btn.position = Vector2(1760, 1150)
	_btn.pressed.connect(_open)
	add_child(_btn)


func _open() -> void:
	_btn.disabled = true
	_btn.visible = false
	Router.step("dome_open")
	Audio.play("whoosh", "SFX", 0.6)
	_status.text = tr("DOME_OPENING")
	var tw := create_tween()
	tw.tween_method(_obs.set_shutter, 0.0, 1.0, 3.0).set_trans(Tween.TRANS_SINE)
	await tw.finished
	_status.text = tr("DOME_SLEWING")
	# Real pointing for the chosen time: hour angle = local sidereal time - right ascension.
	var s := mission.sample(mission.obs_index)
	var jd := Kepler.jd_from_iso(s.t)
	var ha := wrapf(ObservatoryScene.lst_deg(jd) - float(s.ra), -180.0, 180.0)
	_obs.fly("roof", "inside", 3.0)  # runs in parallel; the 4-s slew below outlasts it
	var slew := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	slew.tween_method(func(t: float): _obs.point_to(ha * t, lerpf(90.0, float(s.dec), t)), 0.0, 1.0, 4.0)
	Audio.play("whoosh", "SFX", 0.45)
	await slew.finished
	_status.text = tr("DOME_READY") % [int(round(float(s.alt))), int(round(_obs.tube_azimuth()))]
	Audio.play("success")
	await get_tree().create_timer(2.0).timeout
	done()
