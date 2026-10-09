## Attract-mode slide "Explorers' gallery": the asteroids that visitors have found with the
## asteroid hunt, all circling the Sun together in time-lapse, the newest ones labelled with
## the name of their discoverer.
class_name GallerySlide
extends Control

const SHOWN := 40          # newest orbits drawn
const LABELLED := 5
const DAYS_PER_SECOND := 60.0

var entries: Array = []
var _jd0 := 0.0
var _t := 0.0
var _view: SolarView
var _rocks: Array = []       # [Node3D, elements]


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
	Settings.apply_3d(vp)
	container.add_child(vp)
	# The same solar system as in the game (textures, orbits, names), in time-lapse.
	_view = SolarView.new()
	vp.add_child(_view)
	_view.show_minor = false
	_view.idle_spin = false
	_view.jd = _jd0
	_view.rate = DAYS_PER_SECOND
	_view.dist = 10.2
	_view.pitch = 0.58
	visibility_changed.connect(func():
		_view.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED)
	var newest := entries.slice(maxi(0, entries.size() - SHOWN))
	for i in newest.size():
		var e: Dictionary = newest[i]
		var el: Dictionary = e.elements
		var fresh := i >= newest.size() - LABELLED
		var col := UiTheme.ACCENT if fresh else Color(1.0, 0.75, 0.4, 0.5)
		_view.overlay.add_child(SpaceDraw.line(Kepler.orbit_points(el.a, el.e, el.incl, el.Omega, el.w, 180), Color(col, 0.5 if fresh else 0.18), 1.4))
		var rock := Sprite3D.new()
		rock.texture = _dot_texture()
		rock.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		rock.fixed_size = true
		rock.no_depth_test = true
		rock.pixel_size = 0.00026 if fresh else 0.00016
		rock.modulate = col
		_view.overlay.add_child(rock)
		if fresh:
			var lbl := SpaceDraw.label("%s · %s" % [e.name, e.player], Vector3.ZERO, UiTheme.ACCENT_HI)
			lbl.pixel_size = 0.0005
			lbl.offset = Vector2(0, 30)
			rock.add_child(lbl)
		_rocks.append([rock, el])

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
	var jd := _view.jd
	for r in _rocks:
		(r[0] as Node3D).position = Kepler.to_godot(Kepler.asteroid_position(r[1], jd))
	_view.yaw = 0.04 * t


static func _dot_texture() -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	return tex
