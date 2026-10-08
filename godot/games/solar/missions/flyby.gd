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


## Closest approach to a planet within `years` after the swing-by: [distance AU, jd].
func closest_to(target_planet: String, years := 20.0) -> Array:
	var best := INF
	var best_jd := jd_flyby
	var jd := jd_flyby
	var end := jd_flyby + years * 365.25
	while jd < end:
		var d := position(jd).distance_to(Kepler.planet_position(target_planet, jd))
		if d < best:
			best = d
			best_jd = jd
		jd += 5.0
	# Refine around the best coarse sample.
	jd = best_jd - 5.0
	while jd < best_jd + 5.0:
		var d := position(jd).distance_to(Kepler.planet_position(target_planet, jd))
		if d < best:
			best = d
			best_jd = jd
		jd += 0.25
	return [best, best_jd]
