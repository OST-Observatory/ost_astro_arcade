## Two-body orbits for the game: Kepler's equation, heliocentric positions from orbital
## elements, the major planets from JPL's approximate elements (Standish, valid
## 1800-2050), orbit polylines and the minimum distance between two orbits (MOID).
## Coordinates: heliocentric ecliptic J2000 in AU (x to the vernal equinox, z to the
## ecliptic north pole). Use to_godot() for scene space (y up).
class_name Kepler
extends RefCounted

const J2000 := 2451545.0
const AU_KM := 149597870.7

## a [AU], e, I [deg], L [deg], long. perihelion [deg], long. ascending node [deg],
## each followed by its rate per Julian century.
const PLANETS := {
	"mercury": [0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593,
		0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081],
	"venus": [0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255,
		0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418],
	"earth": [1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0,
		0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0],
	"mars": [1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891,
		0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343],
	"jupiter": [5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909,
		-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106],
	"saturn": [9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448,
		-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794],
}


static func solve_eccentric_anomaly(m_rad: float, e: float) -> float:
	var ea := m_rad if e < 0.8 else PI
	for i in 30:
		var d := (ea - e * sin(ea) - m_rad) / (1.0 - e * cos(ea))
		ea -= d
		if absf(d) < 1e-12:
			break
	return ea


## Heliocentric position for elements in degrees.
static func position(a: float, e: float, inc: float, node: float, arg_peri: float, mean_anom: float) -> Vector3:
	var ea := solve_eccentric_anomaly(deg_to_rad(fposmod(mean_anom, 360.0)), e)
	var xp := a * (cos(ea) - e)
	var yp := a * sqrt(1.0 - e * e) * sin(ea)
	return _rotate(xp, yp, deg_to_rad(inc), deg_to_rad(node), deg_to_rad(arg_peri))


static func _rotate(xp: float, yp: float, i: float, o: float, w: float) -> Vector3:
	var cw := cos(w)
	var sw := sin(w)
	var co := cos(o)
	var so := sin(o)
	var ci := cos(i)
	var si := sin(i)
	return Vector3(
		(cw * co - sw * so * ci) * xp + (-sw * co - cw * so * ci) * yp,
		(cw * so + sw * co * ci) * xp + (-sw * so + cw * co * ci) * yp,
		(sw * si) * xp + (cw * si) * yp)


## Planet elements at a Julian date: {a, e, i, node, w, M} (degrees).
static func planet_elements(planet: String, jd: float) -> Dictionary:
	var p: Array = PLANETS[planet]
	var t := (jd - J2000) / 36525.0
	var a: float = p[0] + p[6] * t
	var e: float = p[1] + p[7] * t
	var i: float = p[2] + p[8] * t
	var l: float = p[3] + p[9] * t
	var varpi: float = p[4] + p[10] * t
	var node: float = p[5] + p[11] * t
	return {"a": a, "e": e, "i": i, "node": node, "w": varpi - node, "M": l - varpi}


static func planet_position(planet: String, jd: float) -> Vector3:
	var el := planet_elements(planet, jd)
	return position(el.a, el.e, el.i, el.node, el.w, el.M)


## Asteroid elements as stored by the pipeline (JPL Horizons, ecliptic J2000):
## {a, e, incl, Omega, w, M, n (deg/day), datetime_jd}.
static func asteroid_position(el: Dictionary, jd: float) -> Vector3:
	var m: float = el.M + el.n * (jd - el.datetime_jd)
	return position(el.a, el.e, el.incl, el.Omega, el.w, m)


## Closed orbit as a polyline (heliocentric AU), sampled evenly in eccentric anomaly.
static func orbit_points(a: float, e: float, inc: float, node: float, arg_peri: float, n := 256) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var i := deg_to_rad(inc)
	var o := deg_to_rad(node)
	var w := deg_to_rad(arg_peri)
	for k in n + 1:
		var ea := TAU * k / n
		pts.append(_rotate(a * (cos(ea) - e), a * sqrt(1.0 - e * e) * sin(ea), i, o, w))
	return pts


## Minimum orbit intersection distance (AU) by sampling both orbits (good to ~0.005 AU).
static func moid(orbit_a: PackedVector3Array, orbit_b: PackedVector3Array) -> float:
	var best := INF
	for p in orbit_a:
		for q in orbit_b:
			best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


static func period_years(a: float) -> float:
	return pow(a, 1.5)


## Ecliptic (x, y, z) -> Godot scene (x, y up, z): ecliptic north becomes +y.
static func to_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## "2027-11-10T21:30:00Z" -> Julian date.
static func jd_from_iso(iso: String) -> float:
	return Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z")) / 86400.0 + 2440587.5


## Local civil time in Germany (CET/CEST with EU daylight-saving rules) as "HH:MM".
static func local_time_hhmm(iso: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z"))
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var dst_start := _last_sunday_unix(d.year, 3)
	var dst_end := _last_sunday_unix(d.year, 10)
	var offset := 7200 if unix >= dst_start and unix < dst_end else 3600
	var l := Time.get_datetime_dict_from_unix_time(unix + offset)
	return "%02d:%02d" % [l.hour, l.minute]


## 01:00 UTC on the last Sunday of the month (EU switch time).
static func _last_sunday_unix(year: int, month: int) -> int:
	var last_day := 31
	var t := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": last_day, "hour": 1, "minute": 0, "second": 0})
	var wd: int = Time.get_datetime_dict_from_unix_time(t).weekday  # 0 = Sunday
	return t - wd * 86400
