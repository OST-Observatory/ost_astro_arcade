## 3D solar system for the explorer and the missions: Sun, planets, moons, dwarf planets and
## comets (BodyCatalog) plus thousands of asteroids and Kuiper-belt objects (SmallBodies, on
## the GPU) at their true positions for any date, with orbits, an ecliptic grid and an orbit
## camera (one finger rotates, two fingers zoom, tap selects, double tap flies there).
## Scene unit = 1 AU. Floating origin: the focused body sits at the scene origin and the rest
## is placed relative to it, so close-ups stay precise with 32-bit floats. Every body is drawn
## at least MIN_PX pixels wide and becomes a true-size textured sphere when the camera comes close.
class_name SolarView
extends Node3D

signal body_tapped(id: String)        # "" = empty space
signal body_double_tapped(id: String)
signal arrived(id: String)            # a fly_to() has finished

const MIN_PX := 7.0
const FOV := 45.0
const DIST_MAX := 1500.0
const JD_MIN := 2396758.5             # 1850-01-01
const JD_MAX := 2506331.5             # 2150-01-01
const GRID_RINGS := [1.0, 5.0, 10.0, 30.0, 50.0, 100.0]
const PICK_PX := 60.0
const SMALL_PICK_PX := 26.0
const FLY_TIME := 1.8
const OVERVIEW_DIST := 18.0           # start view: the planets out to Jupiter and Saturn
const IDLE_SPIN_AFTER := 20.0
const LABEL_PX := 0.0005
const SATURN_RING_R := 140500.0 / 58232.0   # outer edge of the F ring in Saturn radii

var jd := 2461000.5
var rate := 0.0                       # days per second
var focus := "sun"
var selected := ""
var yaw := -1.2
var pitch := 0.5
var dist := 8.0                       # camera distance to the focus (AU)
var idle_spin := true
var show_minor := true                # dwarf planets, comets, small bodies (missions hide them)
var gestures := TouchGestures.new()
var small: SmallBodies
var overlay: Node3D                   # heliocentric scene axes (AU): mission lines and markers

var _bodies := {}                     # id -> {node, mesh, label, r, base, spin, tail}
var _orbits := {}                     # id -> [MeshInstance3D, alpha]
var _grid: Array = []                 # [MeshInstance3D, radius, Label3D]
var _grid_root: Node3D
var _helio_root: Node3D
var _cam: Camera3D
var _light: OmniLight3D
var _marker: Sprite3D
var _origin := Vector3.ZERO           # heliocentric ecliptic position at the scene origin
var _fly := {}
var _spin_vel := Vector2.ZERO
var _idle := 0.0
var _orbit_jd := -1e12
var _scene_pos := {}                  # id -> scene position this frame
var _labels: CanvasLayer


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://games/solar/scene/space_sky.gdshader")
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.1, 0.12)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_helio_root = Node3D.new()
	add_child(_helio_root)
	overlay = Node3D.new()
	_helio_root.add_child(overlay)
	_grid_root = Node3D.new()
	add_child(_grid_root)
	_light = OmniLight3D.new()
	_light.omni_range = 100000.0
	_light.omni_attenuation = 0.0
	_light.light_energy = 0.95
	_light.shadow_enabled = false
	add_child(_light)

	_labels = CanvasLayer.new()
	add_child(_labels)
	for id: String in BodyCatalog.ids():
		_make_body(id)
	_build_grid()
	small = SmallBodies.new()
	small.setup(int(Settings.quality_3d().get("small_bodies", 10000)))
	add_child(small)

	_marker = Sprite3D.new()
	_marker.texture = _ring_texture()
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.fixed_size = true
	_marker.no_depth_test = true
	_marker.pixel_size = 0.0009
	_marker.modulate = Color(UiTheme.ACCENT, 0.95)
	_marker.visible = false
	add_child(_marker)

	_cam = Camera3D.new()
	_cam.fov = FOV
	add_child(_cam)
	_cam.make_current()

	gestures.dragged.connect(_on_drag)
	gestures.pinched.connect(func(f: float, _c: Vector2): zoom_by(f, false))
	gestures.tapped.connect(func(p: Vector2): body_tapped.emit(pick(p)))
	gestures.double_tapped.connect(func(p: Vector2): body_double_tapped.emit(pick(p)))
	_update_scene()


# --- building ---------------------------------------------------------------------------------

func _make_body(id: String) -> void:
	var node := Node3D.new()
	add_child(node)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 64
	sm.rings = 32
	mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	var tex := BodyCatalog.texture_path(id)
	if tex != "":
		mat.albedo_texture = load(tex)
	else:
		mat.albedo_color = BodyCatalog.color(id)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	if id == "sun":
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(2.4, 2.1, 1.7)   # HDR: the Sun glows
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mesh)
	if id == "saturn":
		var ring := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * 2.0 * SATURN_RING_R
		ring.mesh = pm
		var rm := ShaderMaterial.new()
		rm.shader = preload("res://games/solar/scene/saturn_rings.gdshader")
		rm.set_shader_parameter("profile", load("res://assets/solar/saturn_rings.png"))
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(ring)
	# Names are 2D labels over the 3D picture (Label3D vanishes at close-up distances).
	var label := UiTheme.label(BodyCatalog.display_name(id) if id != "67p" else "67P", 27, "medium",
		BodyCatalog.color(id).lightened(0.3))
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.add_child(label)
	var tail: Node3D = null
	if BodyCatalog.kind(id) == "comet":
		tail = _make_tail()
		node.add_child(tail)
	_bodies[id] = {"node": node, "mesh": mesh, "label": label, "r": BodyCatalog.radius_au(id),
		"base": _body_basis(id), "spin": 0.0, "tail": tail}


## Mesh orientation: local Y = spin axis (texture poles), local X = node of the equator.
static func _body_basis(id: String) -> Basis:
	var b := Rotation.equator_basis(id)
	var x := Kepler.to_godot(b.x)
	var y := Kepler.to_godot(b.z)
	return Basis(x, y, x.cross(y))


func _make_tail() -> Node3D:
	var pivot := Node3D.new()
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.16
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	mi.position = Vector3(0, -0.5, 0)   # tip at the comet, local -Y away from the Sun
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	float k = pow(1.0 - UV.y, 1.6) * abs(dot(NORMAL, VIEW));
	ALBEDO = vec3(0.55, 0.75, 1.0) * k * 0.9;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	return pivot


func _build_orbits() -> void:
	_orbit_jd = jd
	for id: String in _orbits:
		(_orbits[id][0] as Node).queue_free()
	_orbits.clear()
	for id: String in BodyCatalog.ids():
		if id == "sun":
			continue
		var moon := BodyCatalog.kind(id) == "moon"
		var alpha: float = {"planet": 0.5, "moon": 0.35, "dwarf": 0.22, "comet": 0.16}.get(BodyCatalog.kind(id), 0.3)
		var pts := BodyCatalog.orbit_points(id, jd, 128 if moon else (1024 if BodyCatalog.kind(id) == "comet" else 512))
		var line := SpaceDraw.line(pts, Color(BodyCatalog.color(id), alpha), 1.0)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if moon:
			(_bodies[BodyCatalog.parent(id)].node as Node3D).add_child(line)
		else:
			_helio_root.add_child(line)
		_orbits[id] = [line, alpha]


func _build_grid() -> void:
	for r in GRID_RINGS:
		var pts := PackedVector3Array()
		for k in 257:
			var a := TAU * k / 256.0
			pts.append(Vector3(cos(a), sin(a), 0.0) * r)
		var line := SpaceDraw.line(pts, Color(UiTheme.SCIENCE, 0.2), 0.6)
		_grid_root.add_child(line)
		var l := SpaceDraw.label(tr("SOL_AU") % AstroFormat.num(r, 0), Kepler.to_godot(Vector3(r * 0.7071, -r * 0.7071, 0.0)),
			Color(UiTheme.SCIENCE, 0.7))
		l.pixel_size = LABEL_PX * 0.8
		_grid_root.add_child(l)
		_grid.append([line, r, l])


static func _ring_texture() -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.72, 0.8, 0.9, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	return tex


# --- camera and input ------------------------------------------------------------------------

## Feeds an input event; offset = position of the view on screen. True if it was used.
func handle_input(event: InputEvent, offset: Vector2) -> bool:
	if event is InputEventMouseButton and event.pressed and gestures.area.has_point(event.position - offset):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15, false)
			_idle = 0.0
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15, false)
			_idle = 0.0
			return true
	var ev := event.xformed_by(Transform2D(0.0, -offset))
	if gestures.handle(ev):
		_idle = 0.0
		return true
	return false


func _on_drag(d: Vector2) -> void:
	yaw -= d.x * 0.006
	pitch = clampf(pitch + d.y * 0.006, -1.5, 1.5)
	_spin_vel = Vector2(-d.x, d.y) * 0.006 * 30.0


## factor > 1 zooms in.
func zoom_by(factor: float, smooth := true) -> void:
	_idle = 0.0
	var target := clampf(dist / factor, min_dist(), DIST_MAX)
	if smooth:
		create_tween().tween_property(self, "dist", target, 0.35).set_trans(Tween.TRANS_SINE)
	else:
		dist = target


func min_dist() -> float:
	if focus.begins_with("sb:"):
		return 2e-5
	return maxf(BodyCatalog.radius_au(focus) * 1.8, 2e-6)


func view_top() -> void:
	_idle = 0.0
	create_tween().tween_property(self, "pitch", 1.45, 0.6).set_trans(Tween.TRANS_SINE)


func view_edge() -> void:
	_idle = 0.0
	create_tween().tween_property(self, "pitch", 0.03, 0.6).set_trans(Tween.TRANS_SINE)


## A good viewing distance for a body.
func nice_dist(id: String) -> float:
	if id == "sun":
		return OVERVIEW_DIST
	if id.begins_with("sb:"):
		return 0.5
	match BodyCatalog.kind(id):
		"comet":
			return 0.3
		"planet":
			return BodyCatalog.radius_au(id) * (16.0 if id == "saturn" else 7.0)
	return BodyCatalog.radius_au(id) * 7.0


## Flies the camera to a body (it becomes the focus); d < 0: nice_dist().
func fly_to(id: String, d := -1.0) -> void:
	_idle = 0.0
	_fly = {"from": _origin, "to": id, "t": 0.0, "d0": dist, "d1": d if d > 0.0 else nice_dist(id)}


func is_flying() -> bool:
	return not _fly.is_empty()


## Heliocentric position of a catalogue body or of a small body ("sb:<index>").
func helio_of(id: String) -> Vector3:
	if id.begins_with("sb:"):
		return SmallBodies.position_of(small.rows[int(id.substr(3))], jd)
	return BodyCatalog.helio(id, jd)


## Scene position of a heliocentric point (AU).
func to_scene(helio: Vector3) -> Vector3:
	return Kepler.to_godot(helio - _origin)


func camera() -> Camera3D:
	return _cam


## The body under a screen position (view coordinates): "" if none, "sb:<k>" for a small body.
func pick(pos: Vector2) -> String:
	var best := ""
	var best_d := PICK_PX
	for id: String in _bodies:
		var b: Dictionary = _bodies[id]
		if not (b.node as Node3D).visible:
			continue
		var sp: Vector3 = (b.node as Node3D).position
		if _cam.is_position_behind(sp):
			continue
		var d := _cam.unproject_position(sp).distance_to(pos)
		d = maxf(0.0, d - _radius_px(id, sp))
		if d < best_d:
			best_d = d
			best = id
	if best != "":
		return best
	var pts := small.positions(jd)
	best_d = SMALL_PICK_PX
	for k in pts.size():
		var sp := Kepler.to_godot(pts[k] - _origin)
		if _cam.is_position_behind(sp):
			continue
		var d := _cam.unproject_position(sp).distance_to(pos)
		if d < best_d:
			best_d = d
			best = "sb:%d" % k
	return best


func _px_per_au(d: float) -> float:
	return get_viewport().get_visible_rect().size.y / (2.0 * maxf(d, 1e-12) * tan(deg_to_rad(FOV * 0.5)))


func _radius_px(id: String, sp: Vector3) -> float:
	var d := _cam.position.distance_to(sp)
	return maxf(float(_bodies[id].r) * _px_per_au(d), MIN_PX * 0.5)


## Screen position (view coordinates) of a body, or Vector2(-1, -1) if behind the camera.
func screen_pos(id: String) -> Vector2:
	var sp := to_scene(helio_of(id))
	return Vector2(-1, -1) if _cam.is_position_behind(sp) else _cam.unproject_position(sp)


# --- per frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if rate != 0.0:
		jd = clampf(jd + rate * delta, JD_MIN, JD_MAX)
		if jd <= JD_MIN or jd >= JD_MAX:
			rate = 0.0
	if not _fly.is_empty():
		_fly.t = minf(float(_fly.t) + delta / FLY_TIME, 1.0)
		var s := smoothstep(0.0, 1.0, float(_fly.t))
		_origin = (_fly.from as Vector3).lerp(helio_of(_fly.to), s)
		dist = exp(lerpf(log(float(_fly.d0)), log(float(_fly.d1)), s))
		if _fly.t >= 1.0:
			focus = _fly.to
			_fly = {}
			arrived.emit(focus)
	else:
		_origin = helio_of(focus)
	if not gestures.active():
		yaw += _spin_vel.x * delta
		pitch = clampf(pitch + _spin_vel.y * delta, -1.5, 1.5)
		_spin_vel *= pow(0.03, delta)
	_idle += delta
	if idle_spin and _idle > IDLE_SPIN_AFTER:
		yaw += 0.04 * delta
	_update_scene()


func _update_scene() -> void:
	if absf(jd - _orbit_jd) > 3650.0:
		_build_orbits()
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	_cam.position = dir * dist
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	# Near and far grow with the zoom: with a far/near ratio much above 1e7 Godot's frustum
	# maths fails and close-up planets vanish. The camera never comes closer than 1.8 radii
	# (min_dist), so the surface is always beyond a tenth of the distance.
	_cam.near = maxf(dist * 0.1, 1e-9)
	_cam.far = clampf(dist * 4e4, 60.0, 20000.0)
	var sun_pos := Kepler.to_godot(-_origin)
	_helio_root.position = sun_pos
	_grid_root.position = sun_pos
	_light.position = sun_pos
	small.visible = show_minor
	small.update(jd, Kepler.to_godot(_origin), _px_per_au(dist), 1.0 - absf(sin(pitch)))
	var spin_now := absf(rate) <= 2.0

	_scene_pos.clear()
	var screen := {}
	for id: String in _bodies:
		var sp := Kepler.to_godot(BodyCatalog.helio(id, jd) - _origin)
		_scene_pos[id] = sp
		screen[id] = Vector2(-1e6, -1e6) if _cam.is_position_behind(sp) else _cam.unproject_position(sp)
	var radius_px := {}
	for id: String in _bodies:
		var b: Dictionary = _bodies[id]
		var p: Vector3 = _scene_pos[id]
		var node: Node3D = b.node
		node.position = p
		var ppa := _px_per_au(_cam.position.distance_to(p))
		var r := maxf(float(b.r), MIN_PX * 0.5 / ppa)
		radius_px[id] = r * ppa
		if spin_now:
			b.spin = deg_to_rad(Rotation.spin_angle(id, jd))
		(b.mesh as MeshInstance3D).basis = ((b.base as Basis) * Basis(Vector3.UP, float(b.spin))).scaled(Vector3.ONE * r)
		# Moons disappear into their planet, planets into the Sun, when they get too close on screen.
		var par := BodyCatalog.parent(id)
		var sep := INF
		if par != "":
			sep = (screen[id] as Vector2).distance_to(screen[par])
		node.visible = id == focus or id == selected or sep > (14.0 if BodyCatalog.kind(id) == "moon" else 5.0)
		if not show_minor and BodyCatalog.kind(id) in ["dwarf", "comet"]:
			node.visible = false
		if b.tail:
			_place_tail(b.tail, p, sun_pos, BodyCatalog.helio(id, jd).length())
	# Labels: focus and selection first, then in catalogue order (Sun, planets, moons, dwarf
	# planets, comets); a label that would overlap one already placed stays hidden.
	var placed: Array[Rect2] = []
	var order: Array = [focus, selected]
	order.append_array(BodyCatalog.ids())
	var done := {}
	for id: String in order:
		if not _bodies.has(id) or done.has(id):
			continue
		done[id] = true
		var label: Label = _bodies[id].label
		var vis := (_bodies[id].node as Node3D).visible and (screen[id] as Vector2).x > -1e5
		if vis:
			var w := label.size.x
			var rect := Rect2(screen[id] - Vector2(w / 2.0, 6.0 + label.size.y + float(radius_px[id])), label.size)
			rect.position.y = maxf(rect.position.y, 120.0)   # a big planet close up: name stays on screen
			label.position = rect.position
			for q in placed:
				if q.intersects(rect):
					vis = id == focus or id == selected
					break
			if vis:
				placed.append(rect)
		label.visible = vis
	# Orbits: heliocentric ones fade out in close-ups (a polyline cannot follow the planet that
	# closely), moon orbits show together with their moons.
	var fade := clampf((dist - 0.01) / 0.04, 0.0, 1.0)
	for id: String in _orbits:
		var line: MeshInstance3D = _orbits[id][0]
		var a: float = _orbits[id][1] * (1.8 if id == focus or id == selected else 1.0)
		if BodyCatalog.kind(id) == "moon" or not show_minor:
			line.visible = (_bodies[id].node as Node3D).visible
		else:
			a *= fade
			line.visible = a > 0.01
		(line.material_override as StandardMaterial3D).albedo_color.a = minf(a, 1.0)
	for g in _grid:
		var x: float = g[1] / dist
		var f := smoothstep(0.04, 0.2, x) * (1.0 - smoothstep(2.5, 6.0, x))
		(g[0] as MeshInstance3D).visible = f > 0.01
		((g[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.22 * f
		(g[2] as Label3D).visible = f > 0.5
	_marker.visible = false
	if selected != "":
		var sp := to_scene(helio_of(selected))
		var big := selected in _bodies and _radius_px(selected, sp) > 26.0
		_marker.visible = not big
		_marker.position = sp


func _place_tail(pivot: Node3D, p: Vector3, sun_pos: Vector3, r_sun: float) -> void:
	var length := 0.35 * clampf((3.0 - r_sun) / 2.0, 0.0, 1.0)
	pivot.visible = length > 0.003
	if not pivot.visible:
		return
	var y := (sun_pos - p).normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	pivot.basis = Basis(x * length, y * length, x.cross(y) * length)
