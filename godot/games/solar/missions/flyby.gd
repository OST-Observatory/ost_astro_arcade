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
## approach?]. Only real approaches count – moments when the distance stops shrinking and
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


## Planet positions on the coarse time grid after the swing-by – the same for every pass
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
