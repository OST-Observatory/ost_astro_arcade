## Hohmann transfer from Earth to any planet, from the real planet positions: the probe flies
## half an ellipse around the Sun and arrives on the opposite side at the target's orbit.
## It meets the target only if the target is there at that moment (launch windows).
## Simplification: orbits treated as coplanar, tangential departure. MarsTransfer is the
## original Mars-only version (kept for the explorer mission).
class_name HohmannTransfer
extends RefCounted

var target := "mars"
var jd_launch := 0.0
var r1 := 1.0               # AU, Earth at launch
var r2 := 1.5               # AU, target orbit at the arrival longitude
var lon1 := 0.0             # rad
var a := 1.25
var e := 0.2
var days := 259.0
var miss_deg := 0.0         # + target ahead of the probe at arrival
var outward := true


static func compute(target_planet: String, jd: float) -> HohmannTransfer:
	var t := HohmannTransfer.new()
	t.target = target_planet
	t.jd_launch = jd
	var earth := Kepler.planet_position("earth", jd)
	t.r1 = Vector2(earth.x, earth.y).length()
	t.lon1 = atan2(earth.y, earth.x)
	var lon2 := t.lon1 + PI
	t.r2 = radius_at(target_planet, lon2, jd)
	t.outward = t.r2 > t.r1
	t.a = (t.r1 + t.r2) / 2.0
	t.e = absf(t.r2 - t.r1) / (t.r2 + t.r1)
	t.days = 0.5 * pow(t.a, 1.5) * 365.25
	var p := Kepler.planet_position(target_planet, jd + t.days)
	t.miss_deg = rad_to_deg(wrapf(atan2(p.y, p.x) - lon2, -PI, PI))
	return t


## Distance of a planet's orbit from the Sun (AU) towards an ecliptic longitude.
static func radius_at(planet: String, lon: float, jd: float) -> float:
	var el := Kepler.planet_elements(planet, jd)
	var varpi := deg_to_rad(float(el.node) + float(el.w))
	return float(el.a) * (1.0 - el.e * el.e) / (1.0 + el.e * cos(lon - varpi))


## Probe position (AU, ecliptic) after a fraction f of the flight. Outward the probe leaves
## at perihelion, inward (Venus, Mercury) at aphelion.
func position_at(f: float) -> Vector3:
	var m := PI * clampf(f, 0.0, 1.0) + (0.0 if outward else PI)
	var ea := Kepler.solve_eccentric_anomaly(fposmod(m, TAU), e)
	var x := a * (cos(ea) - e)
	var y := a * sqrt(1.0 - e * e) * sin(ea)
	var peri := lon1 if outward else lon1 + PI
	return Vector3(cos(peri) * x - sin(peri) * y, sin(peri) * x + cos(peri) * y, 0.0)


func arrival_point() -> Vector3:
	return position_at(1.0)


## Probe velocity at arrival (AU/day): tangential, prograde.
func arrival_velocity() -> Vector3:
	var r := arrival_point()
	var speed := sqrt(Kepler.GM_SUN * (2.0 / r.length() - 1.0 / a))
	return Vector3(-r.y, r.x, 0.0).normalized() * speed


func miss_au() -> float:
	return absf(deg_to_rad(miss_deg)) * r2


## First launch window after jd_from (miss minimum below max_deg), or -1.
static func next_window(target_planet: String, jd_from: float, jd_to: float, max_deg := 2.0) -> float:
	var jd := jd_from
	var prev := absf(compute(target_planet, jd).miss_deg)
	while jd < jd_to:
		jd += 1.0
		var m := absf(compute(target_planet, jd).miss_deg)
		if prev < max_deg and m >= prev:
			return jd - 1.0
		prev = m
	return -1.0
