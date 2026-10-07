## The OST observatory in 3D (model: blender/build_observatory.py) with sky, lights and
## animation helpers: time of day, dome azimuth, shutter, telescope axes, camera shots.
class_name ObservatoryScene
extends Node3D

const MODEL := "res://assets/models/observatory.glb"
## Camera shots: [position, look_at] in metres (scene space, y up).
const SHOTS := {
	"street": [Vector3(-2, -12.5, -48), Vector3(0, 0, 0)],
	"roof": [Vector3(-7.0, 1.7, -6.5), Vector3(0, 2.6, 0)],
	"dome_close": [Vector3(-3.2, 2.2, -5.2), Vector3(0, 3.2, 0)],
	"inside": [Vector3(-1.6, 1.55, -1.8), Vector3(0.3, 2.3, 0.6)],
	"sky": [Vector3(0, 1.8, -0.2), Vector3(0, 6, 4)],
}

var night := 0.0
var camera: Camera3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _red_lights: Array[OmniLight3D] = []
var _dome: Node3D
var _shutter: Node3D
var _ra: Node3D
var _dec: Node3D
var _ra0: Basis
var _dec0: Basis
var _materials := {}


func _ready() -> void:
	var model: Node3D = load(MODEL).instantiate()
	add_child(model)
	_apply_materials(model)
	_dome = model.find_child("DomeRotator", true, false)
	_shutter = model.find_child("Shutter", true, false)
	_ra = model.find_child("RA_Axis", true, false)
	_dec = model.find_child("Dec_Axis", true, false)
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
	_env.ssao_enabled = bool(Settings.quality_3d()[3])
	_env.ssao_intensity = 1.5
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	for lamp in ["RedLamp0", "RedLamp1", "RedLamp2", "RedLamp3"]:
		var n: Node3D = model.find_child(lamp, true, false)
		if n:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.12, 0.05)
			l.omni_range = 3.2
			l.shadow_enabled = true  # keeps the red light inside the dome
			n.add_child(l)
			_red_lights.append(l)
	var stair := OmniLight3D.new()
	stair.light_color = Color(1.0, 0.85, 0.6)
	stair.omni_range = 4.0
	stair.shadow_enabled = true
	stair.position = Vector3(5.0, 2.3, -2.3)
	add_child(stair)
	_red_lights.append(stair)

	camera = Camera3D.new()
	camera.fov = 55
	camera.far = 2000
	add_child(camera)
	set_shot("roof")
	set_night(0.0)


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
	_env.ambient_light_energy = lerpf(1.0, 0.08, night)
	_env.tonemap_exposure = lerpf(1.0, 1.25, night)
	for l in _red_lights:
		l.light_energy = lerpf(0.0, 0.45, smoothstep(0.4, 0.8, night))


func set_dome_azimuth(deg: float) -> void:
	_dome.rotation.y = deg_to_rad(-deg)


## 0 = closed, 1 = open (the shutter slides back over the zenith).
func set_shutter(open: float) -> void:
	_shutter.rotation.x = deg_to_rad(-100.0 * clampf(open, 0.0, 1.0))


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
	var d := tube_direction()
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)


## Points the telescope and turns the dome slit to it, like the real dome automation.
func point_to(hour_angle_deg: float, dec_deg: float) -> void:
	set_telescope(hour_angle_deg, dec_deg)
	set_dome_azimuth(tube_azimuth())


## Local sidereal time (deg) at the OST for a Julian date.
static func lst_deg(jd: float, lon_deg := 12.9733) -> float:
	return fposmod(280.46061837 + 360.98564736629 * (jd - 2451545.0) + lon_deg, 360.0)


func set_shot(name: String) -> void:
	var s: Array = SHOTS[name]
	camera.position = s[0]
	camera.look_at(s[1])


## Smooth camera move between shots (or explicit [pos, target] pairs).
func fly(from: String, to: String, seconds: float) -> void:
	var a: Array = SHOTS[from]
	var b: Array = SHOTS[to]
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(t: float):
		camera.position = (a[0] as Vector3).lerp(b[0], t)
		camera.look_at((a[1] as Vector3).lerp(b[1], t)), 0.0, 1.0, seconds)
	await tw.finished


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
			m.albedo_texture = _noise_tex(0.4, 256)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
		"glass_dark":
			m.metallic = 0.6
			m.roughness = 0.08
		"tree", "hill":
			m.albedo_texture = _noise_tex(0.15, 256)
			m.uv1_triplanar = true
	_materials[name] = m
	return m
