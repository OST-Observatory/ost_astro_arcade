## The real night sky above the OST at a given time: the 5000 stars to 6 mag of the
## constellation game, optional stick figures with names, and the Moon with its phase.
## Lives at a large radius around the camera (follows it), so the dome and the trees hide it.
## Scene axes: north = -Z, east = +X, up = +Y; azimuth from north over east.
class_name RealSky
extends Node3D

const SKY := "res://assets/data/constellations/sky.json"
const LAT := 52.4092
const RADIUS := 900.0
const OBLIQUITY := 23.4393
## North galactic pole (J2000), for the Milky Way band of the sky shader.
const GAL_POLE := Vector2(192.85948, 27.12825)

var follow: Camera3D
var _stars: MultiMeshInstance3D
var _star_mat: ShaderMaterial
var _lines: MeshInstance3D
var _line_mat: StandardMaterial3D
var _names: Array[Label3D] = []
var _moon: MeshInstance3D
var _moon_mat: ShaderMaterial
var _lst := 0.0
var _alpha := 1.0
var _figures := false


## Unit vector to altitude/azimuth (deg).
static func horizon_dir(alt: float, az: float) -> Vector3:
	var a := deg_to_rad(alt)
	var z := deg_to_rad(az)
	return Vector3(sin(z) * cos(a), sin(a), -cos(z) * cos(a))


## Altitude/azimuth (deg) of a unit vector, as Vector2(alt, az).
static func alt_az(d: Vector3) -> Vector2:
	var v := d.normalized()
	return Vector2(rad_to_deg(asin(clampf(v.y, -1.0, 1.0))), fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0))


## Direction of right ascension/declination (deg) at a local sidereal time (deg).
static func equatorial_dir(ra: float, dec: float, lst: float) -> Vector3:
	var h := deg_to_rad(lst - ra)
	var d := deg_to_rad(dec)
	var p := deg_to_rad(LAT)
	var east := Vector3(1, 0, 0)
	var north := Vector3(0, 0, -1)
	var up := Vector3(0, 1, 0)
	var meridian := -north * sin(p) + up * cos(p)   # hour angle 0 on the equator
	var pole := north * cos(p) + up * sin(p)
	return meridian * cos(d) * cos(h) - east * cos(d) * sin(h) + pole * sin(d)


## Right ascension/declination (deg) of the Sun, low precision (0.01 deg).
static func sun_radec(jd: float) -> Vector2:
	var n := jd - 2451545.0
	var l := deg_to_rad(280.460 + 0.9856474 * n)
	var g := deg_to_rad(357.528 + 0.9856003 * n)
	var lam := l + deg_to_rad(1.915 * sin(g) + 0.020 * sin(2.0 * g))
	return _ecl_to_eq(lam, 0.0)


static func _ecl_to_eq(lam: float, beta: float) -> Vector2:
	var e := deg_to_rad(OBLIQUITY)
	var ra := atan2(sin(lam) * cos(e) - tan(beta) * sin(e), cos(lam))
	var dec := asin(sin(beta) * cos(e) + cos(beta) * sin(e) * sin(lam))
	return Vector2(fposmod(rad_to_deg(ra), 360.0), rad_to_deg(dec))


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SKY))
	_star_mat = ShaderMaterial.new()
	_star_mat.shader = preload("res://games/solar/scene/points.gdshader")
	_star_mat.set_shader_parameter("px", 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	_stars = MultiMeshInstance3D.new()
	_stars.multimesh = mm
	_stars.material_override = _star_mat
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.extra_cull_margin = 16384.0
	add_child(_stars)
	_stars.set_meta("stars", data.stars)

	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.albedo_color = Color(0.55, 0.7, 1.0, 0.45)
	_lines = MeshInstance3D.new()
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.extra_cull_margin = 16384.0
	_lines.visible = false
	add_child(_lines)
	var by_id := {}
	for s in data.stars:
		by_id[int(s[0])] = s
	_lines.set_meta("by_id", by_id)
	_lines.set_meta("constellations", data.constellations)

	_moon_mat = ShaderMaterial.new()
	_moon_mat.shader = preload("res://games/asteroid/observatory/moon.gdshader")
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS * 0.97 * tan(deg_to_rad(0.26))
	sphere.height = sphere.radius * 2.0
	_moon = MeshInstance3D.new()
	_moon.mesh = sphere
	_moon.material_override = _moon_mat
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_moon)


func _process(_delta: float) -> void:
	if follow:
		global_position = follow.global_position


## Places everything for a Julian date (UT).
func set_time(jd: float) -> void:
	_lst = ObservatoryScene.lst_deg(jd)
	var stars: Array = _stars.get_meta("stars")
	var mm := _stars.multimesh
	mm.instance_count = 0
	var up := stars.filter(func(s): return equatorial_dir(s[1], s[2], _lst).y > -0.02)
	mm.instance_count = up.size()
	for i in up.size():
		var s: Array = up[i]
		var d := equatorial_dir(s[1], s[2], _lst)
		var mag: float = s[3]
		var c := ConstellationLogic.star_color(float(s[4]) if s.size() > 4 else 0.6)
		var bright := 1.0 + 1.5 * clampf((1.5 - mag) / 3.0, 0.0, 1.0)
		var a := clampf(0.3 + 0.7 * (6.0 - mag) / 5.0, 0.3, 1.0) * smoothstep(-1.0, 8.0, rad_to_deg(asin(d.y)))
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, d * RADIUS))
		mm.set_instance_color(i, Color(c.r * bright, c.g * bright, c.b * bright, a))
		mm.set_instance_custom_data(i, Color(1.6 + 6.0 * pow(10.0, -0.2 * (mag + 1.0)), 0, 0, 0))
	_build_figures()
	# The Moon (geocentric, good to about 1 degree) lit from the Sun's direction.
	var lbr := Moons.moon_lbr(jd)
	var m := _ecl_to_eq(deg_to_rad(lbr.x), deg_to_rad(lbr.y))
	var md := equatorial_dir(m.x, m.y, _lst)
	_moon.position = md * RADIUS * 0.97
	_moon.visible = md.y > -0.01
	var sun := sun_radec(jd)
	_moon_mat.set_shader_parameter("sun_dir", equatorial_dir(sun.x, sun.y, _lst))


func _build_figures() -> void:
	for n in _names:
		n.queue_free()
	_names.clear()
	var by_id: Dictionary = _lines.get_meta("by_id")
	var verts := PackedVector3Array()
	var lang := TranslationServer.get_locale().substr(0, 2)
	for c in _lines.get_meta("constellations"):
		for e in c.edges:
			if not (by_id.has(int(e[0])) and by_id.has(int(e[1]))):
				continue
			var a: Array = by_id[int(e[0])]
			var b: Array = by_id[int(e[1])]
			var da := equatorial_dir(a[1], a[2], _lst)
			var db := equatorial_dir(b[1], b[2], _lst)
			if da.y < 0.0 and db.y < 0.0:
				continue
			verts.append(da * RADIUS * 0.99)
			verts.append(db * RADIUS * 0.99)
		var cd := equatorial_dir(c.center[0], c.center[1], _lst)
		if cd.y > 0.03:
			var l := Label3D.new()
			l.text = str(c.name.get(lang, c.name.en))
			l.font = UiTheme.font("medium")
			l.font_size = 30
			l.outline_size = 0
			l.fixed_size = true
			l.pixel_size = 0.0011
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.modulate = Color(0.65, 0.78, 1.0, 0.8)
			l.position = cd * RADIUS * 0.98
			l.visible = _figures
			add_child(l)
			_names.append(l)
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
		mesh.surface_set_material(0, _line_mat)
	_lines.mesh = mesh


## 0 = invisible (day) ... 1 = full night.
func set_alpha(a: float) -> void:
	_alpha = a
	_star_mat.set_shader_parameter("alpha", a)
	_line_mat.albedo_color.a = 0.45 * a
	for n in _names:
		n.modulate.a = 0.8 * a


func show_figures(on: bool) -> void:
	_figures = on
	_lines.visible = on
	for n in _names:
		n.visible = on


func figures_shown() -> bool:
	return _figures


## Direction of a sky position (deg) at the time last set.
func dir_of(ra: float, dec: float) -> Vector3:
	return equatorial_dir(ra, dec, _lst)


func galactic_pole() -> Vector3:
	return equatorial_dir(GAL_POLE.x, GAL_POLE.y, _lst)
