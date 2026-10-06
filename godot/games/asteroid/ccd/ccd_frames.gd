## Renders the noiseless signal of the blink frames on the GPU: real Gaia stars as
## Gaussian PSFs, the asteroid at its position in each frame, and the distractors
## (cosmic-ray hits, hot pixels, a variable star, a satellite trail).
## Each frame is an HDR SubViewport that renders once; ccd_display.gdshader adds noise.
class_name CcdFrames
extends Node

const FWHM_PX := 2.6        # ~3.6" seeing at 1.394"/px
const HALO_FWHM_PX := 8.0   # scattered light around bright stars
const HALO_FRACTION := 0.02
const WIDE_HALO_FWHM_PX := 22.0  # extra glow that makes very bright stars look bigger
const WIDE_HALO_FRACTION := 0.0012
const HALO_PEAK_CAP := 100.0  # halos stop growing above ~7 mag (no giant saturated discs)
const SPIKE_MAG := 10.5     # stars brighter than this show diffraction spikes
const SPIKE_ANGLE := 0.42   # orientation of the CDK20 spider vanes (rad)
# Spike brightness I(r) = peak * SPIKE_K * (SPIKE_R0 / (SPIKE_R0 + r))^2: it fades like 1/r^2
# and ends where it drops below SPIKE_FLOOR (about half the sky noise), at most SPIKE_MAX_PX.
const SPIKE_K := 0.02
const SPIKE_R0 := 3.0
const SPIKE_FLOOR := 0.0004
const SPIKE_MAX_PX := 160.0
const SPIKE_SEGMENTS := 18
const ZERO_POINT_G := 12.0  # magnitude with peak signal 1.0

var textures: Array[Texture2D] = []
var _psf: Texture2D
var _halo: Texture2D


## frames: Array of Dictionary {
##   "asteroid": Vector2 px, "asteroid_mag": float,
##   "cosmics": Array[[Vector2 px, float length, float angle]],
##   "hot": Array[Vector2 px], "variable": {"px": Vector2, "mag": float} or {},
##   "satellite": [Vector2 a, Vector2 b] or [] }
## stars_px: Array of [Vector2 px, float mag]
func build(stars_px: Array, frames: Array) -> void:
	_psf = _make_psf_texture()
	_halo = _make_halo_texture()
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
		painter.halo = _halo
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


## Scattered-light profile: soft core with a long, smoothly vanishing tail, so even
## saturated halos have no visible edge.
static func _make_halo_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.08, 0.18, 0.3, 0.45, 0.6, 0.75, 0.88, 1.0])
	var a := [1.0, 0.7, 0.38, 0.17, 0.07, 0.028, 0.01, 0.003, 0.0]
	g.colors = PackedColorArray(a.map(func(x): return Color(1, 1, 1, x)))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


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
	var halo: Texture2D
	var stars: Array
	var frame: Dictionary

	func _blob(p: Vector2, peak: float, fwhm: float) -> void:
		var r := 3.0 * fwhm / 2.355
		draw_texture_rect(psf, Rect2(p - Vector2(r, r), Vector2(2 * r, 2 * r)), false, Color(peak, peak, peak, 1.0))

	func _halo_blob(p: Vector2, peak: float, fwhm: float) -> void:
		var r := 2.5 * fwhm
		draw_texture_rect(halo, Rect2(p - Vector2(r, r), Vector2(2 * r, 2 * r)), false, Color(peak, peak, peak, 1.0))

	func _star(p: Vector2, mag: float) -> void:
		var peak := CcdFrames.peak_for_mag(mag)
		_blob(p, peak, FWHM_PX)
		if mag < 12.0:
			_halo_blob(p, minf(peak, HALO_PEAK_CAP) * HALO_FRACTION, HALO_FWHM_PX)
		if mag < 9.0:
			_halo_blob(p, minf(peak, HALO_PEAK_CAP) * WIDE_HALO_FRACTION, WIDE_HALO_FWHM_PX)
		if mag < SPIKE_MAG:
			_spikes(p, peak)

	## Four diffraction spikes from the secondary-mirror spider. Segment lengths grow
	## geometrically (fine near the star, coarse far out) and fade smoothly to the sky.
	func _spikes(p: Vector2, peak: float) -> void:
		var length := minf(SPIKE_R0 * (sqrt(peak * SPIKE_K / SPIKE_FLOOR) - 1.0), SPIKE_MAX_PX)
		if length < 4.0:
			return
		var r0 := 1.5
		var ratio := pow(length / r0, 1.0 / SPIKE_SEGMENTS)
		for k in 4:
			var dir := Vector2.from_angle(SPIKE_ANGLE + k * PI / 2.0)
			var r := r0
			for seg in SPIKE_SEGMENTS:
				var r_next := r * ratio
				var mid := 0.5 * (r + r_next)
				var taper := 1.0 - pow(mid / length, 2.0)
				var v := peak * SPIKE_K * pow(SPIKE_R0 / (SPIKE_R0 + mid), 2.0) * taper
				var w := lerpf(1.3, 0.8, mid / length)
				draw_line(p + dir * r, p + dir * r_next, Color(v, v, v), w, true)
				r = r_next

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
