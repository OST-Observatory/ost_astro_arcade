## Attract-mode slide "Explorers' gallery": the asteroids that visitors have found with the
## asteroid hunt, all circling the Sun together in time-lapse, the newest ones labelled with
## the name of their discoverer.
class_name GallerySlide
extends Control

const SHOWN := 40          # newest orbits drawn
const LABELLED := 5
const DAYS_PER_SECOND := 60.0
const PLANETS := [["mercury", Color("a7a7a7"), 0.035], ["venus", Color("e8cfa0"), 0.05],
	["earth", Color("4dd0e1"), 0.055], ["mars", Color("e2725b"), 0.045], ["jupiter", Color("d8b48a"), 0.11]]

var entries: Array = []
var _jd0 := 0.0
var _t := 0.0
var _root: Node3D
var _cam: Camera3D
var _planets := {}
var _rocks: Array = []       # [MeshInstance3D, elements]


static func has_entries() -> bool:
	return not load_entries().is_empty()


static func load_entries() -> Array:
	return GalleryStore.new(Settings.data_path("gallery.json")).entries


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	entries = load_entries()
	_jd0 = Time.get_unix_time_from_system() / 86400.0 + 2440587.5
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	container.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	_root = Node3D.new()
	vp.add_child(_root)
	_root.add_child(SpaceDraw.sphere(Vector3.ZERO, 0.12, Color(1.0, 0.85, 0.5), 6.0))
	for p in PLANETS:
		var el := Kepler.planet_elements(p[0], _jd0)
		_root.add_child(SpaceDraw.line(Kepler.orbit_points(el.a, el.e, el.i, el.node, el.w, 256), Color(p[1], 0.35), 1.0))
		var body := SpaceDraw.sphere(Vector3.ZERO, p[2], p[1], 1.6)
		_root.add_child(body)
		_planets[p[0]] = body
	var newest := entries.slice(maxi(0, entries.size() - SHOWN))
	for i in newest.size():
		var e: Dictionary = newest[i]
		var el: Dictionary = e.elements
		var fresh := i >= newest.size() - LABELLED
		var col := UiTheme.ACCENT if fresh else Color(1.0, 0.75, 0.4, 0.5)
		_root.add_child(SpaceDraw.line(Kepler.orbit_points(el.a, el.e, el.incl, el.Omega, el.w, 180), Color(col, 0.5 if fresh else 0.18), 1.4))
		var rock := SpaceDraw.sphere(Vector3.ZERO, 0.03 if fresh else 0.02, col, 3.0)
		_root.add_child(rock)
		if fresh:
			var lbl := SpaceDraw.label("%s · %s" % [e.name, e.player], Vector3(0, 0.12, 0), UiTheme.ACCENT_HI)
			lbl.pixel_size *= 0.5
			rock.add_child(lbl)
		_rocks.append([rock, el])
	_cam = Camera3D.new()
	_cam.fov = 40
	_cam.far = 200
	_root.add_child(_cam)

	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 70
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var title := UiTheme.label("ATTRACT_GALLERY", UiTheme.SIZE_TITLE - 20, "serif", UiTheme.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var sub := UiTheme.label("", UiTheme.SIZE_H2 - 8, "regular", UiTheme.ACCENT_HI)
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sub.text = tr("ATTRACT_GALLERY_SUB") % entries.size()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(sub)
	_update(0.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_update(_t)


func _update(t: float) -> void:
	var jd := _jd0 + t * DAYS_PER_SECOND
	for p in PLANETS:
		(_planets[p[0]] as Node3D).position = Kepler.to_godot(Kepler.planet_position(p[0], jd))
	for r in _rocks:
		(r[0] as Node3D).position = Kepler.to_godot(Kepler.asteroid_position(r[1], jd))
	var ang := 0.04 * t
	_cam.position = Vector3(sin(ang) * 8.5, 5.6, cos(ang) * 8.5)
	_cam.look_at(Vector3.ZERO)
