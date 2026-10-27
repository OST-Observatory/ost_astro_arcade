## The OST observatory in 3D (model: blender/build_observatory.py) with sky, lights and
## animation helpers: time of day, dome azimuth, shutter, telescope axes, camera shots.
## With set_sky_time() the real sky of that moment (RealSky); with look_enabled the visitor
## looks around by dragging, zooms with two fingers and taps the sky (sky_tapped).
class_name ObservatoryScene
extends Node3D

signal sky_tapped(dir: Vector3)
signal view_changed(name: String)

const MODEL := "res://assets/models/observatory.glb"
## Camera shots: [position, look_at] in metres (scene space, y up).
const SHOTS := {
	"street": [Vector3(-45, -12.3, 55), Vector3(0, 2, 0)],
	"roof": [Vector3(-7.0, 1.7, -1.5), Vector3(0, 2.6, 0)],
	"dome_close": [Vector3(-3.2, 2.2, -5.2), Vector3(0, 3.2, 0)],
	"inside": [Vector3(0.6, 1.6, 1.9), Vector3(-1.0, 1.25, -1.2)],
	"sky": [Vector3(0, 1.8, -0.2), Vector3(0, 6, 4)],
}
## Flights that bow through a point (quadratic Bézier), e.g. up over the building edge.
const VIA := {"street>roof": Vector3(-22, 6, 20)}
## Places to look around from (switch_view): in the dome and on the roof terrace.
const VIEWS := ["inside", "roof"]
## Facade texture: one tile is 15 m wide and 14 m high, 64 px per metre.
const FACADE_TILE := Vector2(15.0, 14.0)
## Window bands: one tile is 10 m (eight windows of 1.25 m) by 1.5 m.
const WINDOW_TILE := Vector2(10.0, 1.5)

## Dome geometry (model): centre of the hemisphere, its radius, and a point on the tube's
## optical axis in the OTA node's frame.
const DOME_CENTER := Vector3(0, 2.3, 0)
const DOME_RADIUS := 2.55
const OTA_AXIS := Vector3(0.4, 0, 0)

## Render layers (bits) that sort out which light reaches what, without shadow maps:
## WORLD    lit by sun, moon, street and stair lights: everything outside, including the
##          outer side of the dome and its shutter, flap and door;
## DOME_LIT lit by the red lamps only: the inner side of dome and base, everything inside.
## (Dome shell and base are split into inner and outer side in the model for this.)
const LAYER_WORLD := 1
const LAYER_DOME_LIT := 2

const FOV := 55.0
const FOV_MIN := 18.0
const PITCH_MIN := -30.0
const PITCH_MAX := 86.0

var night := 0.0
var camera: Camera3D
var sky: RealSky
var look_enabled := false
var gestures := TouchGestures.new()
var view_name := ""
var _yaw := 0.0     # viewing azimuth (deg)
var _pitch := 0.0   # viewing altitude (deg)
var _pull := 1.0    # zooming out beyond the widest view, inside the dome
var _switching := false
var _fade: ColorRect
var _street_lights: Array[OmniLight3D] = []
var _moonlight: DirectionalLight3D
var _stair_light: OmniLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _red_lights: Array[OmniLight3D] = []
var _dome: Node3D
var _shutter: Node3D
var _flap: Node3D
var _door: Node3D
var _ra: Node3D
var _dec: Node3D
var _ra0: Basis
var _dec0: Basis
var _materials := {}
var _fps_time := 0.0
var _fps_frames := 0


func _ready() -> void:
	var model: Node3D = load(MODEL).instantiate()
	add_child(model)
	_apply_materials(model)
	_dome = model.find_child("DomeRotator", true, false)
	_shutter = model.find_child("Shutter", true, false)
	_flap = model.find_child("ShutterFlap", true, false)
	_door = model.find_child("DomeDoor", true, false)
	_ra = model.find_child("RA_Axis", true, false)
	_dec = model.find_child("Dec_Axis", true, false)
	# The model's polar axis points to its -Z; turn the mount to the real north.
	_ra.transform = Transform3D(Basis(Vector3.UP, RealSky.COMPASS_YAW), Vector3.ZERO) * _ra.transform
	_ra0 = _ra.transform.basis
	_dec0 = _dec.transform.basis

	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://shared/sky/night_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_hdr_threshold = 1.0
	_env.ssao_enabled = bool(Settings.quality_3d().ssao)
	_env.ssao_intensity = 1.5
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_env.ambient_light_color = Color(0.32, 0.38, 0.55)
	# City light near the horizon (Potsdam, Berlin): the campus stands out against it.
	_sky_mat.set_shader_parameter("night_horizon", Color(0.05, 0.055, 0.085))

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.light_cull_mask = LAYER_WORLD
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	# Faint bluish light from above at night, so the setting can be made out.
	_moonlight = DirectionalLight3D.new()
	_moonlight.light_color = Color(0.6, 0.7, 1.0)
	_moonlight.rotation_degrees = Vector3(-55.0, 130.0, 0.0)
	_moonlight.shadow_enabled = true
	_moonlight.directional_shadow_max_distance = 60.0
	_moonlight.light_cull_mask = LAYER_WORLD
	add_child(_moonlight)
	for n in model.find_children("StreetLight*", "Node3D", true, false):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.omni_range = 16.0
		l.omni_attenuation = 1.2
		l.light_cull_mask = LAYER_WORLD
		n.add_child(l)
		_street_lights.append(l)
	# The red lamps light only the inner side of the dome and what is in it, everything
	# else only the outside lights: nothing leaks either way and no shadow maps are needed.
	_split_layers(model)
	for lamp in ["RedLamp0", "RedLamp1", "RedLamp2", "RedLamp3"]:
		var n: Node3D = model.find_child(lamp, true, false)
		if n:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.12, 0.05)
			l.omni_range = 4.2
			l.light_cull_mask = LAYER_DOME_LIT
			n.add_child(l)
			_red_lights.append(l)
	_stair_light = OmniLight3D.new()
	_stair_light.light_color = Color(1.0, 0.85, 0.6)
	_stair_light.omni_range = 4.0
	_stair_light.light_cull_mask = LAYER_WORLD
	_stair_light.position = Vector3(3.8, 2.5, 2.4)
	add_child(_stair_light)

	camera = Camera3D.new()
	camera.fov = FOV
	camera.far = 2000
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	set_shot("roof")
	set_night(0.0)
	gestures.dragged.connect(_on_drag)
	gestures.pinched.connect(func(f: float, _c: Vector2): _zoom(1.0 / f))
	gestures.tapped.connect(func(pos: Vector2):
		if look_enabled:
			sky_tapped.emit(camera.project_ray_normal(pos)))


## Dynamic resolution: below 40 frames per second the 3D view renders smaller (FSR upscaling),
## with headroom it goes back up to the quality setting. Keeps weaker GPUs smooth.
func _process(delta: float) -> void:
	_fps_time += delta
	_fps_frames += 1
	if _fps_time < 1.0:
		return
	var fps := _fps_frames / _fps_time
	_fps_time = 0.0
	_fps_frames = 0
	var vp := get_viewport()
	if not vp is SubViewport:
		return
	var top: float = Settings.quality_3d().scale
	var s := vp.scaling_3d_scale
	if fps < 40.0:
		s = maxf(0.5, s - 0.1)
	elif fps > 57.0:
		s = minf(top, s + 0.05)
	if not is_equal_approx(s, vp.scaling_3d_scale):
		vp.scaling_3d_scale = s
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR


# --- public API -------------------------------------------------------------------------

## 0 = late afternoon, 0.5 = dusk, 1 = astronomical night.
func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	var elev := lerpf(14.0, -20.0, night)
	_sun.rotation_degrees = Vector3(-elev, 205.0, 0.0)
	_sun.light_energy = clampf(remap(elev, -4.0, 10.0, 0.0, 1.3), 0.0, 1.3)
	_sun.light_color = Color(1.0, 0.75, 0.55).lerp(Color(1, 0.95, 0.9), clampf(elev / 14.0, 0.0, 1.0))
	_sun.visible = _sun.light_energy > 0.001
	_sky_mat.set_shader_parameter("night", smoothstep(0.35, 0.95, night))
	if sky:
		sky.set_alpha(smoothstep(0.55, 0.95, night))
	# Little ambient light at night (it would reach into the dome and wash out the red
	# light); the setting outside is lit by the moonlight (with shadows, so not inside).
	_env.ambient_light_energy = lerpf(1.0, 0.16, night)
	_env.ambient_light_sky_contribution = lerpf(1.0, 0.4, smoothstep(0.3, 0.9, night))
	_env.tonemap_exposure = lerpf(1.0, 1.25, night)
	var dark := smoothstep(0.4, 0.8, night)
	_moonlight.light_energy = 0.45 * dark
	_moonlight.visible = dark > 0.0
	for l in _street_lights:
		l.light_energy = 1.6 * dark
		l.visible = dark > 0.0
	if _materials.has("window_band"):
		(_materials["window_band"] as BaseMaterial3D).emission_energy_multiplier = 0.35 * dark
	if _materials.has("lamp_head"):
		(_materials["lamp_head"] as BaseMaterial3D).emission_energy_multiplier = 0.2 + 5.0 * dark
	var lamps_on := smoothstep(0.4, 0.8, night)
	for l in _red_lights:
		l.light_energy = 1.2 * lamps_on
	_stair_light.light_energy = 1.2 * lamps_on


func set_dome_azimuth(deg: float) -> void:
	# The slit of the model faces its -Z; azimuth grows clockwise seen from above.
	_dome.rotation.y = deg_to_rad(RealSky.alt_az(Vector3(0, 0, -1)).y - deg)


## 0 = closed, 1 = open (the shutter slides back over the zenith).
func set_shutter(open: float) -> void:
	# The upper shutter slides over the top of the dome to its back, then the lower flap
	# swings out on its struts (Baader dome).
	var o := clampf(open, 0.0, 1.0)
	_shutter.rotation.x = deg_to_rad(66.0 * smoothstep(0.0, 0.7, o))
	_flap.rotation.x = deg_to_rad(-95.0 * smoothstep(0.35, 1.0, o))


## 0 = closed, 1 = open: the dome door swings outwards to the south (hinge at its south edge).
func set_door(open: float) -> void:
	_door.rotation.y = deg_to_rad(-100.0 * clampf(open, 0.0, 1.0))


## Hour angle (deg, + = west) and declination (deg) of the telescope.
func set_telescope(hour_angle_deg: float, dec_deg: float) -> void:
	_ra.transform.basis = _ra0 * Basis(Vector3(0, 1, 0), deg_to_rad(-hour_angle_deg))
	_dec.transform.basis = _dec0 * Basis(Vector3(1, 0, 0), deg_to_rad(90.0 - dec_deg))


## Direction the optical tube points to (scene space, unit vector).
func tube_direction() -> Vector3:
	var ota: Node3D = _dec.find_child("OTA", true, false)
	return ota.global_basis.y.normalized()


## Azimuth (deg, from north over east) of the tube; used to make the dome follow.
func tube_azimuth() -> float:
	return RealSky.alt_az(tube_direction()).y


## Points the telescope and turns the dome slit to it, like the real dome automation.
func point_to(hour_angle_deg: float, dec_deg: float) -> void:
	set_telescope(hour_angle_deg, dec_deg)
	set_dome_azimuth(slit_azimuth())


## Azimuth (deg) the slit must face for the telescope to look through it. The tube sits
## well off the dome centre on the German mount, so (like a real dome controller) this is
## where its optical axis meets the dome, not simply the direction it points to.
func slit_azimuth() -> float:
	var ota: Node3D = _dec.find_child("OTA", true, false)
	var p := ota.global_transform * OTA_AXIS - DOME_CENTER
	var d := tube_direction()
	# Ray p + s d against the dome sphere |x| = DOME_RADIUS (s > 0).
	var b := p.dot(d)
	var s := -b + sqrt(maxf(b * b - (p.length_squared() - DOME_RADIUS * DOME_RADIUS), 0.0))
	return RealSky.alt_az(p + d * s).y


## Local sidereal time (deg) at the OST for a Julian date.
static func lst_deg(jd: float, lon_deg := 12.9733) -> float:
	return fposmod(280.46061837 + 360.98564736629 * (jd - 2451545.0) + lon_deg, 360.0)


func set_shot(name: String) -> void:
	var s: Array = SHOTS[name]
	camera.position = s[0]
	camera.look_at(s[1])
	view_name = name
	if name == "inside":
		set_door(1.0)   # whoever is inside came through the door


## Smooth camera move between shots ("" as `from`: from wherever the camera is now).
func fly(from: String, to: String, seconds: float) -> void:
	var a: Array = SHOTS[from] if from != "" else [camera.position, camera.position - camera.global_basis.z * 8.0]
	var b: Array = SHOTS[to]
	var via: Vector3 = VIA.get(from + ">" + to, ((a[0] as Vector3) + b[0]) / 2.0)
	var fov0 := camera.fov
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(t: float):
		camera.position = (a[0] as Vector3).lerp(via, t).lerp(via.lerp(b[0], t), t)
		camera.fov = lerpf(fov0, FOV, t)
		camera.look_at((a[1] as Vector3).lerp(b[1], t)), 0.0, 1.0, seconds)
	await tw.finished
	view_name = to
	if to == "inside":
		set_door(1.0)


## Jumps (with a short fade) to another place to look around from, keeping the direction
## (or turning to the shot's own target with `to_shot`).
func switch_view(name: String, to_shot := false, at_dark := Callable()) -> void:
	if name == view_name:
		return
	var look: Variant = SHOTS[name][1] if to_shot else null
	await view_from(SHOTS[name][0], look, name, FOV, at_dark)


## Jumps (with a short fade) to any place to look around from; `look` is a point to turn
## to (null: keep the direction). `name` says inside ("inside") or outside ("roof"); a wider
## `fov` than usual narrows back to normal with the first zoom.
func view_from(pos: Vector3, look: Variant = null, name := "roof", fov := FOV, at_dark := Callable()) -> void:
	if _switching:
		return
	_switching = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	await tw.finished
	if at_dark.is_valid():
		at_dark.call()   # changes nobody should see happen
	camera.position = pos
	camera.fov = fov
	view_name = name
	if name == "inside":
		set_door(1.0)
	if look != null:
		camera.look_at(look)
		var was := look_enabled
		set_look(true)
		look_enabled = was
	else:
		_apply_look()
	view_changed.emit(name)
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.35)
	await tw.finished
	_switching = false


# --- real sky and looking around ----------------------------------------------------------

## Shows the real sky (stars, Moon, Milky Way band) at a Julian date (UT).
func set_sky_time(jd: float) -> void:
	if sky == null:
		sky = RealSky.new()
		sky.follow = camera
		add_child(sky)
		_sky_mat.set_shader_parameter("star_brightness", 0.3)   # only faint filler stars
	sky.set_time(jd)
	_sky_mat.set_shader_parameter("galactic_pole", sky.galactic_pole())
	sky.set_alpha(smoothstep(0.55, 0.95, night))


## Turns looking around on or off; starts from the current camera direction.
func set_look(on: bool) -> void:
	look_enabled = on
	if on:
		var aa := RealSky.alt_az(-camera.global_basis.z)
		_pitch = clampf(aa.x, PITCH_MIN, PITCH_MAX)
		_yaw = aa.y


## Viewing direction as Vector2(alt, az) in degrees.
func view_alt_az() -> Vector2:
	return Vector2(_pitch, _yaw)


## Screen position of a direction, or null when it is behind the camera.
func screen_pos(dir: Vector3) -> Variant:
	var p := camera.global_position + dir.normalized() * 100.0
	if camera.is_position_behind(p):
		return null
	return camera.unproject_position(p)


## Feed with the input events of the view; positions relative to the viewport.
func handle_input(event: InputEvent) -> bool:
	if not look_enabled:
		return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom(0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9)
			return true
	return gestures.handle(event)


## Turns the view smoothly to a direction (scene space), e.g. to show where things happen.
func turn_to(dir: Vector3, seconds := 1.5) -> void:
	var aa := RealSky.alt_az(dir)
	var y0 := _yaw
	var p0 := _pitch
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(t: float):
		_yaw = fposmod(rad_to_deg(lerp_angle(deg_to_rad(y0), deg_to_rad(aa.y), t)), 360.0)
		_pitch = lerpf(p0, clampf(aa.x, PITCH_MIN, PITCH_MAX), t)
		_apply_look(), 0.0, 1.0, seconds)
	await tw.finished


func _on_drag(d: Vector2) -> void:
	if not look_enabled:
		return
	# The sky follows the finger: degrees per pixel from the vertical field of view.
	var k := camera.fov / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	_yaw = fposmod(_yaw - d.x * k, 360.0)
	_pitch = clampf(_pitch + d.y * k, PITCH_MIN, PITCH_MAX)
	_apply_look()


func _zoom(f: float) -> void:
	if not look_enabled:
		return
	# Zooming out further than the widest view takes you out of the dome onto the roof.
	if f > 1.0 and camera.fov >= FOV - 0.01 and view_name == "inside":
		_pull *= f
		if _pull > 1.35:
			_pull = 1.0
			switch_view("roof")
		return
	_pull = 1.0
	camera.fov = clampf(camera.fov * f, FOV_MIN, maxf(FOV, camera.fov))   # a wider view zooms in smoothly


func _apply_look() -> void:
	camera.look_at(camera.global_position + RealSky.horizon_dir(_pitch, _yaw))


## Render layers per part of the model (see LAYER_*).
func _split_layers(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var outer := _under(m, ["Shutter", "ShutterFlap", "DomeDoor"]) \
			or m.name.begins_with("DomeShellOuter") or m.name.begins_with("SlitFrame")
		var inner := m.name == "DomeInterior" or m.name.begins_with("RedLamp") \
			or _under(m, ["DomeRotator", "RA_Axis"])
		m.layers = LAYER_DOME_LIT if inner and not outer else LAYER_WORLD


func _under(n: Node, names: Array) -> bool:
	var p := n.get_parent()
	while p:
		if p.name in names:
			return true
		p = p.get_parent()
	return false


# --- materials --------------------------------------------------------------------------

func _apply_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if src == null:
				continue
			var name := src.resource_name
			m.set_surface_override_material(s, _material_for(name, src))


func _noise_tex(freq: float, size := 512, stretch := Vector2.ONE) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 4
	t.noise = n
	t.width = size
	t.height = size
	t.seamless = true
	return t


## Texture of the institute's facade: golden perforated panels of 1.25 m x 0.7 m (the
## windows are geometry in front of it, see the model).
func _facade_texture() -> ImageTexture:
	const PX := 64
	var w := int(FACADE_TILE.x * PX)
	var h := int(FACADE_TILE.y * PX)
	var alb := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var gold := Color(0.66, 0.53, 0.32)
	var pw := w / 12
	var ph := h / 20
	for i in 12:
		for j in 20:
			alb.fill_rect(Rect2i(i * pw, j * ph, pw, ph), gold * rng.randf_range(0.9, 1.08))
	# Lamellas of the perforated metal, then the joints between panels.
	for y in range(0, h, 6):
		alb.fill_rect(Rect2i(0, y, w, 2), gold * 0.78)
	for i in 13:
		alb.fill_rect(Rect2i(i * pw - 2, 0, 4, h), gold * 0.5)
	for j in 21:
		alb.fill_rect(Rect2i(0, j * ph - 2, w, 4), gold * 0.55)
	alb.generate_mipmaps()
	return ImageTexture.create_from_image(alb)


## Window bands: dark glass with frames every 1.25 m; at night some windows are lit.
func _window_textures() -> Array:
	const PX := 64
	var w := int(WINDOW_TILE.x * PX)
	var h := int(WINDOW_TILE.y * PX)
	var alb := Image.create(w, h, false, Image.FORMAT_RGB8)
	var emi := Image.create(w, h, false, Image.FORMAT_RGB8)
	alb.fill(Color(0.06, 0.08, 0.11))
	emi.fill(Color(0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var pw := w / 8
	for i in 8:
		if rng.randf() < 0.4:
			emi.fill_rect(Rect2i(i * pw + 4, 0, pw - 8, h), Color(1.0, 0.68, 0.36) * rng.randf_range(0.5, 1.0))
	for i in 9:
		alb.fill_rect(Rect2i(i * pw - 3, 0, 6, h), Color(0.35, 0.35, 0.36))
	alb.generate_mipmaps()
	emi.generate_mipmaps()
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(emi)]


## Panels of the roof structures: 1.6 m x 0.9 m, one tile 3.2 m x 1.8 m, 128 px per metre.
func _panel_texture() -> ImageTexture:
	var img := Image.create(410, 230, false, Image.FORMAT_RGB8)
	var gold := Color(0.78, 0.66, 0.42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 2:
		for j in 2:
			img.fill_rect(Rect2i(i * 205, j * 115, 205, 115), gold * rng.randf_range(0.92, 1.06))
	for i in 3:
		img.fill_rect(Rect2i(i * 205 - 2, 0, 4, 230), gold * 0.35)
	for j in 3:
		img.fill_rect(Rect2i(0, j * 115 - 2, 410, 4), gold * 0.4)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _material_for(name: String, src: Material) -> Material:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	if src is BaseMaterial3D:
		m.albedo_color = (src as BaseMaterial3D).albedo_color
		m.roughness = (src as BaseMaterial3D).roughness
		m.metallic = (src as BaseMaterial3D).metallic
	match name:
		"concrete":
			m.albedo_texture = _noise_tex(0.08)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.6, 0.6, 0.6)
			m.albedo_color = Color(0.5, 0.5, 0.49)
		"wood_floor":
			m.albedo_texture = _noise_tex(0.02)
			m.albedo_color = Color(0.8, 0.55, 0.34)   # the noise darkens it by about half
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(4.0, 0.25, 4.0)
		"dome_white", "paint_white":
			m.clearcoat_enabled = true
			m.clearcoat = 0.3
			m.roughness = 0.35
		"lamp_red":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.04)
			m.emission_energy_multiplier = 4.0
		"facade_gold":
			# Perforated golden panels (see _facade_texture), also on the window shades.
			m.albedo_color = Color(1, 1, 1)
			m.albedo_texture = _facade_texture()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.0 / FACADE_TILE.x, 1.0 / FACADE_TILE.y, 1.0 / FACADE_TILE.x)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m.metallic = 0.45
		"window_band":
			var wt := _window_textures()
			m.albedo_color = Color(1, 1, 1)
			m.albedo_texture = wt[0]
			m.emission_enabled = true
			m.emission = Color(1, 1, 1)
			m.emission_texture = wt[1]
			m.emission_energy_multiplier = 0.0
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.0 / WINDOW_TILE.x, 1.0 / WINDOW_TILE.y, 1.0 / WINDOW_TILE.x)
			m.roughness = 0.1
			m.metallic = 0.4
		"stair_gold":
			# Large plain brass-coloured panels with dark joints (the roof structures).
			m.albedo_color = Color(1, 1, 1)
			m.albedo_texture = _panel_texture()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.0 / 3.2, 1.0 / 1.8, 1.0 / 3.2)
			m.metallic = 0.5
			m.roughness = 0.45
		"gravel", "coping", "ballast":
			m.albedo_texture = _noise_tex(0.9 if name != "coping" else 0.1, 256)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.3, 0.3, 0.3)
		"grass":
			m.albedo_texture = _noise_tex(0.05, 512)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.08, 0.08, 0.08)
		"pavement", "asphalt":
			m.albedo_texture = _noise_tex(0.3, 256)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.25, 0.25, 0.25)
		"water":
			m.metallic = 0.3
			m.roughness = 0.04
		"lamp_head":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.82, 0.55)
			m.emission_energy_multiplier = 0.2
		"glass_dark":
			m.metallic = 0.6
			m.roughness = 0.08
		"tree", "tree_light", "tree_dark", "tree_pine":
			# Leaves: fine mottling, a little sheen where the sun catches them.
			m.albedo_texture = _noise_tex(0.6, 256)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.7, 0.7, 0.7)
			m.roughness = 0.75
		"bark", "bark_pine":
			m.albedo_texture = _noise_tex(0.3, 128, Vector2(1.0, 6.0))
			m.uv1_triplanar = true
		"hill":
			m.albedo_texture = _noise_tex(0.15, 256)
			m.uv1_triplanar = true
	_materials[name] = m
	return m
