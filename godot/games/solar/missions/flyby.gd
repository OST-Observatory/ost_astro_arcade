## Gravity assist (swing-by) at a planet, patched conics in the ecliptic plane: the probe
## arrives on a Hohmann transfer, its velocity relative to the planet (v_inf) keeps its size
## but turns by delta = 2 asin(1 / (1 + r_p v_inf^2 / mu)); passing on one side or the other
## turns it one way or the other. The new heliocentric orbit is then followed to the next
## target. Units: AU, days.
class_name Flyby
extends RefCounted

const KM_PER_AU := 149597870.7
const SEC_PER_DAY := 86400.0
## Gravitational parameter (km^3/s^2) and radius (km) of the swing-by planets.
const PLANETS := {"jupiter": [1.26686534e8, 71492.0], "venus": [3.24859e5, 6051.8], "earth": [3.986004e5, 6371.0]}

var transfer: HohmannTransfer
var planet := "jupiter"
var jd_flyby := 0.0
var r_p_radii := 5.0       # closest approach in planet radii
var side := 1.0            # +1: turn counter-clockwise (seen from ecliptic north), -1: clockwise
var v_inf_in := Vector3.ZERO
var v_inf_out := Vector3.ZERO
var delta_deg := 0.0
var elements := {}          # heliocentric orbit after the swing-by
var reached_planet := true


static func mu_au(p: String) -> float:
	return float(PLANETS[p][0]) / pow(KM_PER_AU, 3.0) * SEC_PER_DAY * SEC_PER_DAY


static func compute(t: HohmannTransfer, rp_radii: float, turn_side: float) -> Flyby:
	var f := Flyby.new()
	f.transfer = t
	f.planet = t.target
	f.r_p_radii = rp_radii
	f.side = turn_side
	f.jd_flyby = t.jd_launch + t.days
	f.reached_planet = absf(t.miss_deg) < 3.0
	var v_probe := t.arrival_velocity()
	var vp := Kepler.planet_velocity(f.planet, f.jd_flyby)
	vp.z = 0.0
	f.v_inf_in = v_probe - vp
	var vinf := f.v_inf_in.length()
	var rp := rp_radii * float(PLANETS[f.planet][1]) / KM_PER_AU
	var delta := 2.0 * asin(1.0 / (1.0 + rp * vinf * vinf / mu_au(f.planet)))
	f.delta_deg = rad_to_deg(delta)
	var ang := delta * turn_side
	f.v_inf_out = Vector3(f.v_inf_in.x * cos(ang) - f.v_inf_in.y * sin(ang), f.v_inf_in.x * sin(ang) + f.v_inf_in.y * cos(ang), 0.0)
	var pos := Kepler.planet_position(f.planet, f.jd_flyby)
	pos.z = 0.0
	f.elements = Kepler.elements_from_state(pos, vp + f.v_inf_out, f.jd_flyby)
	return f


func position(jd: float) -> Vector3:
	return Kepler.state_position(elements, jd)


func escapes() -> bool:
	return float(elements.e) >= 1.0


## Closest approach to a planet within `years` after the swing-by: [distance AU, jd, true
## approach?]. Only real approaches count, moments when the distance stops shrinking and
## grows again; the smallest of them wins. Without any (the probe only moves away, or is
## still coming closer at the end) the closest edge of the time span is returned.
func closest_to(target_planet: String, years := 20.0) -> Array:
	var step := 10.0
	var n := int(years * 365.25 / step)
	var planet_pos := _planet_grid(target_planet, step, n)
	var best := INF
	var best_jd := jd_flyby
	var edge := INF
	var edge_jd := jd_flyby
	var prev2 := INF
	var prev := INF
	for k in n + 1:
		var jd := jd_flyby + k * step
		var d := position(jd).distance_to(planet_pos[k])
		if (k == 0 or k == n) and d < edge:
			edge = d
			edge_jd = jd
		if prev2 < INF and prev < prev2 and prev <= d:   # the moment of the swing-by itself is no approach
			var r := _refine(target_planet, jd - 2.0 * step, jd)
			if float(r[0]) < best:
				best = r[0]
				best_jd = r[1]
		prev2 = prev
		prev = d
	if best < INF:
		return [best, best_jd, true]
	return [edge, edge_jd, false]


## The probe's chance to meet a planet farther out, as a mission is planned: on the probe's
## first way out after the swing-by, the moment it reaches the planet's distance from the
## Sun, or, if it falls short, the moment it comes closest to that distance, and the
## closest approach within ±ENCOUNTER_DAYS of it. Only the first way out counts, and the two
## reference moments merge exactly when the orbit just touches the planet's distance, so
## the result changes smoothly with the pass distance (searching later orbits or a fixed
## time span jumps between candidates years apart). For wide misses see the end of encounter().
## [distance AU, jd, planet's distance reached?, reference jd]
const ENCOUNTER_DAYS := 730.0


func encounter(target_planet: String, years := 20.0) -> Array:
	var step := 10.0
	var n := int(years * 365.25 / step)
	var planet_pos := _planet_grid(target_planet, step, n)
	var t_cross := -1.0
	var t_peak := -1.0
	var g_peak := INF
	var g_prev2 := INF
	var g_prev := INF
	for k in n + 1:
		var jd := jd_flyby + k * step
		var g := position(jd).length() - planet_pos[k].length()   # < 0: still inside the planet's distance
		if g >= 0.0 and t_cross < 0.0:
			# Crossing, interpolated linearly between the two samples.
			t_cross = jd - step * g / (g - g_prev) if k > 0 else jd
		if g_prev2 < INF and g_prev > g_prev2 and g_prev >= g:
			# End of the first way out: the vertex of the parabola through the last three samples.
			var den := g_prev2 - 2.0 * g_prev + g
			var off := clampf(0.5 * (g_prev2 - g) / den, -1.0, 1.0) if absf(den) > 1e-12 else 0.0
			t_peak = jd - step + off * step
			g_peak = g_prev - 0.25 * (g_prev2 - g) * off
			break
		g_prev2 = g_prev
		g_prev = g
	var reached := t_cross >= 0.0
	var t_ref := jd_flyby + years * 365.25
	if t_peak < 0.0:
		t_ref = t_cross if reached else t_ref   # still on the way out (or leaving for good)
	elif not reached:
		t_ref = t_peak
	else:
		# Just reaching the planet's distance, the crossing moves very fast with the pass
		# distance (it splits from the turning point like a square root); near that edge the
		# turning point counts instead, blended smoothly.
		t_ref = lerpf(t_cross, t_peak, 1.0 - smoothstep(0.0, 0.8, g_peak))
	# A wide miss has no meaningful closest approach: with the planet far away the distance
	# hardly changes or even has a hump around the reference moment, and "nearest" flips
	# between before and after. So the search reach shrinks with the miss: full ±2 years
	# below 1.5 AU (where stars are won), none above 3 AU (the reference moment itself),
	# smoothly in between, the result never jumps.
	var d_ref := _dist(target_planet, t_ref)
	var w := 1.0 - smoothstep(1.5, 3.0, d_ref)
	var reach := ENCOUNTER_DAYS * w
	var lo := maxf(jd_flyby, t_ref - reach)
	var hi := minf(jd_flyby + years * 365.25, t_ref + reach)
	t_ref = clampf(t_ref, lo, hi)
	var best_jd := t_ref
	var best := d_ref
	if reach > 0.0:
		# From the reference moment downhill to the nearest approach (not across a hump).
		var h := minf(2.0, reach)
		best = _dist(target_planet, t_ref)
		var dir := -1.0 if _dist(target_planet, maxf(lo, t_ref - h)) < _dist(target_planet, minf(hi, t_ref + h)) else 1.0
		while true:
			var nxt := best_jd + dir * h
			if nxt < lo or nxt > hi:
				break
			var d := _dist(target_planet, nxt)
			if d >= best:
				break
			best = d
			best_jd = nxt
		var r := _refine(target_planet, maxf(lo, best_jd - h), minf(hi, best_jd + h))
		if float(r[0]) < best:
			best = r[0]
			best_jd = r[1]
		best_jd = lerpf(t_ref, best_jd, w)
		best = _dist(target_planet, best_jd)
	return [best, best_jd, reached, t_ref]


## Planet positions on the coarse time grid after the swing-by, the same for every pass
## distance and side of one launch window, so they are kept (moving a slider stays smooth).
static var _grids := {}


func _planet_grid(target_planet: String, step: float, n: int) -> PackedVector3Array:
	var key := "%s %.3f %.1f %d" % [target_planet, jd_flyby, step, n]
	if not _grids.has(key):
		if _grids.size() > 64:
			_grids.clear()
		var pts := PackedVector3Array()
		pts.resize(n + 1)
		for k in n + 1:
			pts[k] = Kepler.planet_position(target_planet, jd_flyby + k * step)
		_grids[key] = pts
	return _grids[key]


func _dist(target_planet: String, jd: float) -> float:
	return position(jd).distance_to(Kepler.planet_position(target_planet, jd))


## Smallest distance in [lo, hi] (fixed bounds), quarter-day steps.
func _refine(target_planet: String, lo: float, hi: float) -> Array:
	var best := INF
	var best_jd := lo
	var jd := lo
	while jd <= hi:
		var d := _dist(target_planet, jd)
		if d < best:
			best = d
			best_jd = jd
		jd += 0.25
	return [best, best_jd]
