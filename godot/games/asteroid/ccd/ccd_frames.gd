## Renders the noiseless signal of the blink frames on the GPU: real Gaia stars as
## Gaussian PSFs, the asteroid at its position in each frame, and the distractors
## (cosmic-ray hits, hot pixels, a variable star, a satellite trail).
## Each frame is an HDR SubViewport that renders once; ccd_display.gdshader adds noise.
class_name CcdFrames
extends Node

const FWHM_PX := 2.6        # ~3.6" seeing at 1.394"/px
const HALO_FWHM_PX := 8.0   # scattered light around bright stars
const HALO_FRACTION := 0.05
const SPIKE_MAG := 11.0     # stars brighter than this show diffraction spikes
const SPIKE_ANGLE := 0.42   # orientation of the CDK20 spider vanes (rad)
const ZERO_POINT_G := 12.0  # magnitude with peak signal 1.0

var textures: Array[Texture2D] = []
var _psf: Texture2D


## frames: Array of Dictionary {
##   "asteroid": Vector2 px, "asteroid_mag": float,
##   "cosmics": Array[[Vector2 px, float length, float angle]],
##   "hot": Array[Vector2 px], "variable": {"px": Vector2, "mag": float} or {},
##   "satellite": [Vector2 a, Vector2 b] or [] }
## stars_px: Array of [Vector2 px, float mag]
func build(stars_px: Array, frames: Array) -> void:
	_psf = _make_psf_texture()
	for c in get_children():
		c.queue_free()
	textures.clear()
	for f in frames:
		var vp := SubViewport.new()
		vp.size = AsteroidScenario.IMAGE_SIZE
		vp.use_hdr_2d = true
		vp.transparent_bg = false
		vp.disable_3d = true
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var painter := _Painter.new()
		painter.psf = _psf
		painter.stars = stars_px
		painter.frame = f
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		painter.material = mat
		vp.add_child(painter)
		add_child(vp)
		textures.append(vp.get_texture())


static func peak_for_mag(mag: float) -> float:
	return pow(10.0, -0.4 * (mag - ZERO_POINT_G))


static func _make_psf_texture() -> GradientTexture2D:
	# Radial Gaussian sampled out to 3 sigma (exp(-(3r)^2 / 2)).
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	var a := [1.0, 0.835, 0.487, 0.198, 0.056, 0.0]
	g.colors = PackedColorArray(a.map(func(x): return Color(1, 1, 1, x)))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


class _Painter:
	extends Node2D

	var psf: Texture2D
	var stars: Array
	var frame: Dictionary

	func _blob(p: Vector2, peak: float, fwhm: float) -> void:
		var r := 3.0 * fwhm / 2.355
		draw_texture_rect(psf, Rect2(p - Vector2(r, r), Vector2(2 * r, 2 * r)), false, Color(peak, peak, peak, 1.0))

	func _star(p: Vector2, mag: float) -> void:
		var peak := CcdFrames.peak_for_mag(mag)
		_blob(p, peak, FWHM_PX)
		if mag < 15.0:
			_blob(p, peak * HALO_FRACTION, HALO_FWHM_PX)
		if mag < SPIKE_MAG:
			# Four diffraction spikes, fading outwards, longer for brighter stars.
			var length := 18.0 * pow(10.0, 0.2 * (SPIKE_MAG - mag))
			for k in 4:
				var dir := Vector2.from_angle(SPIKE_ANGLE + k * PI / 2.0)
				for seg in 4:
					var a := p + dir * (length * seg / 4.0)
					var b := p + dir * (length * (seg + 1) / 4.0)
					var v := peak * 0.004 * pow(0.45, seg)
					draw_line(a, b, Color(v, v, v), 1.2, true)

	func _draw() -> void:
		for s in stars:
			_star(s[0], s[1])
		if not frame.get("variable", {}).is_empty():
			_star(frame.variable.px, frame.variable.mag)
		# Asteroids: plain seeing disc, no halo or spikes (faint, and never bright enough here).
		_blob(frame.asteroid, CcdFrames.peak_for_mag(frame.asteroid_mag), FWHM_PX)
		for h in frame.get("hot", []):
			draw_rect(Rect2(h, Vector2.ONE), Color(3, 3, 3))
		for c in frame.get("cosmics", []):
			var p: Vector2 = c[0]
			var d: Vector2 = Vector2.from_angle(c[2]) * c[1]
			draw_line(p, p + d, Color(4, 4, 4), 1.3)
		var sat: Array = frame.get("satellite", [])
		if sat.size() == 2:
			draw_line(sat[0], sat[1], Color(0.05, 0.05, 0.05), 1.8, true)
