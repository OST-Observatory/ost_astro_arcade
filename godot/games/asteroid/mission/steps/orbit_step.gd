## Step 6 – the orbit (the "wow" moment): the inner solar system in 3D with the real orbit
## of the observed asteroid. A faint bundle of neighbouring orbits shows how well the
## orbit is determined: the more precise the measurement, the narrower the bundle.
## (Honest simplification: the game matches the measurements to the known JPL orbit.)
class_name OrbitStep
extends MissionStep

const VIEW := Rect2(150, 280, 1760, 1100)
const PLANETS := [["mercury", Color("a7a7a7"), 0.06], ["venus", Color("e8cfa0"), 0.09],
	["earth", Color("4dd0e1"), 0.09], ["mars", Color("e2725b"), 0.075], ["jupiter", Color("d8b48a"), 0.2]]
const BUNDLE := 18

var _jd := 0.0
var _el: Dictionary
var _cam: Camera3D
var _pivot: Node3D
var _asteroid: MeshInstance3D
var _t := 0.0
var _orbit_pts: PackedVector3Array


func _ready() -> void:
	super._ready()
	var sc := mission.scenario
	add_header("ORBIT_TITLE", "ORBIT_TASK")
	_el = sc.data.elements
	_jd = Kepler.jd_from_iso(sc.sample_at(mission.obs_index).t)
	_orbit_pts = Kepler.orbit_points(_el.a, _el.e, _el.incl, _el.Omega, _el.w, 360)
	_build_3d()
	_build_panel()


func _build_3d() -> void:
	var container := SubViewportContainer.new()
	container.position = VIEW.position
	container.size = VIEW.size
	container.stretch = true
	add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	container.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.012)
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var root := Node3D.new()
	vp.add_child(root)
	# The Sun.
	root.add_child(_sphere(Vector3.ZERO, 0.25, Color(1.0, 0.85, 0.5), 6.0))
	for p in PLANETS:
		var el := Kepler.planet_elements(p[0], _jd)
		root.add_child(_line(Kepler.orbit_points(el.a, el.e, el.i, el.node, el.w, 256), Color(p[1], 0.45), 1.2))
		var pos := Kepler.to_godot(Kepler.planet_position(p[0], _jd))
		root.add_child(_sphere(pos, p[2], p[1], 1.5))
		if p[0] != "mercury":  # too crowded next to Venus/Mars at this scale
			root.add_child(_label(tr("PLANET_" + p[0].to_upper()), pos + Vector3(0, p[2] + 0.15, 0), p[1]))
	# Uncertainty bundle: neighbouring orbits within the measurement error.
	var err := maxf(mission.measure_error_arcsec, 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for k in BUNDLE:
		var da := rng.randfn(0.0, 0.006 * err * _el.a)
		var de := rng.randfn(0.0, 0.004 * err)
		var dw := rng.randfn(0.0, 0.6 * err)
		var pts := Kepler.orbit_points(_el.a + da, clampf(_el.e + de, 0.0, 0.95), _el.incl, _el.Omega, _el.w + dw, 256)
		root.add_child(_line(pts, Color(1.0, 0.65, 0.25, 0.18), 1.0))
	root.add_child(_line(_orbit_pts, Color(1.0, 0.7, 0.28), 3.0))
	var apos := Kepler.to_godot(Kepler.asteroid_position(_el, _jd))
	_asteroid = _sphere(apos, 0.1, Color(1.0, 0.72, 0.3), 3.0)
	root.add_child(_asteroid)
	var name_label := _label(mission.scenario.display_name(), Vector3(0, 0.3, 0), UiTheme.ACCENT_HI)
	_asteroid.add_child(name_label)
	# Line of sight Earth -> asteroid on the observing night.
	var epos := Kepler.to_godot(Kepler.planet_position("earth", _jd))
	root.add_child(_line(_dashed(epos, apos), Color(0.6, 0.9, 1.0, 0.7), 1.0, true))

	_pivot = Node3D.new()
	root.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 40
	_cam.far = 200
	_pivot.add_child(_cam)
	_frame_camera(0.0)


func _frame_camera(tilt: float) -> void:
	var r := maxf(_el.a * (1.0 + _el.e), 1.7) * 2.6
	var elev := lerpf(PI / 2.0 - 0.05, 0.55, tilt)
	_cam.position = Vector3(0, sin(elev) * r, cos(elev) * r)
	_cam.look_at(Vector3.ZERO)


func _process(delta: float) -> void:
	_t += delta
	_frame_camera(clampf((_t - 1.0) / 4.0, 0.0, 1.0))
	_pivot.rotation.y = -0.05 * maxf(_t - 5.0, 0.0)
	# Let the asteroid fly along its orbit: one revolution in about 10 seconds.
	var days_per_s: float = Kepler.period_years(_el.a) * 365.25 / 10.0
	_asteroid.position = Kepler.to_godot(Kepler.asteroid_position(_el, _jd + _t * days_per_s))


func _sphere(pos: Vector3, radius: float, col: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = 2.0 * radius
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	mi.material_override = m
	mi.position = pos
	return mi


func _line(pts: PackedVector3Array, col: Color, energy: float, _dashed := false) -> MeshInstance3D:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var v := PackedVector3Array()
	for p in pts:
		v.append(p if _dashed else Kepler.to_godot(p))
	arr[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES if _dashed else Mesh.PRIMITIVE_LINE_STRIP, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.emission_enabled = true
	m.emission = Color(col, 1.0)
	m.emission_energy_multiplier = energy
	mi.material_override = m
	return mi


## Points for a dashed line in scene space (pairs for PRIMITIVE_LINES).
static func _dashed(a: Vector3, b: Vector3, n := 24) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in n:
		if k % 2 == 0:
			out.append(a.lerp(b, float(k) / n))
			out.append(a.lerp(b, float(k + 1) / n))
	return out


func _label(text: String, pos: Vector3, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font = UiTheme.font("medium")
	l.font_size = 36
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.pixel_size = 0.0011
	l.modulate = Color(col, 0.9)
	l.no_depth_test = true
	l.fixed_size = true
	return l


func _build_panel() -> void:
	var sc := mission.scenario
	var f: Dictionary = sc.data.facts
	var v := VBoxContainer.new()
	v.position = Vector2(1960, 300)
	v.custom_minimum_size = Vector2(540, 0)
	v.add_theme_constant_override("separation", 18)
	add_child(v)
	var title := plain_label(sc.display_name(), UiTheme.SIZE_H2, "serif_bold", UiTheme.ACCENT_HI)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(540, 0)
	v.add_child(title)
	var cls_key: String = MissionState.CLASS_KEYS.get(f.class_code, "")
	var lines: Array[String] = []
	if cls_key != "":
		lines.append(tr(cls_key))
	lines.append(tr("ORBIT_FACT_A") % AstroFormat.num(_el.a, 2))
	lines.append(tr("ORBIT_FACT_P") % AstroFormat.num(Kepler.period_years(_el.a), 1))
	lines.append(tr("ORBIT_FACT_E") % AstroFormat.num(_el.e, 2))
	var ee := Kepler.planet_elements("earth", _jd)
	var moid := Kepler.moid(_orbit_pts, Kepler.orbit_points(ee.a, ee.e, ee.i, ee.node, ee.w, 360))
	lines.append(tr("ORBIT_FACT_MOID") % AstroFormat.num(moid * Kepler.AU_KM / 1e6, 0 if moid > 0.07 else 1))
	if moid < 0.05:
		lines.append(tr("ORBIT_FACT_CLOSE"))
	lines.append(tr("ORBIT_FACT_ACCURACY") % AstroFormat.num(mission.measure_error_arcsec, 1))
	for line in lines:
		var l := plain_label("•  " + line, UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(540, 0)
		v.add_child(l)
	var go := BigButton.make("ORBIT_NEXT", "play_arrow", true, 540)
	go.pressed.connect(done)
	v.add_child(go)
