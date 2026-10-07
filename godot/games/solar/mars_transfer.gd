## Hohmann transfer from Earth to Mars, using the real planet positions (Kepler elements):
## the spacecraft leaves Earth's orbit, flies half an ellipse around the Sun and arrives on the
## opposite side at Mars' orbit. It only meets Mars if Mars is there at that moment – which
## happens about every 26 months (the launch windows).
## Honest simplification: both orbits are treated as lying in one plane (Mars is tilted by
## 1.85 deg), and the launch is exactly tangential.
class_name MarsTransfer
extends RefCounted

const AU_KM := 149597870.7
const DAYS_PER_YEAR := 365.25

var jd_launch := 0.0
var r1 := 1.0               # AU, Earth at launch
var r2 := 1.5               # AU, Mars' orbit at the arrival longitude
var lon1 := 0.0             # rad, heliocentric ecliptic longitude at launch
var a := 1.25               # AU, transfer ellipse
var e := 0.2
var days := 259.0           # flight time
var miss_deg := 0.0         # signed: + Mars is ahead of the spacecraft at arrival
var phase_deg := 0.0        # Mars ahead of Earth at launch


static func compute(jd: float) -> MarsTransfer:
	var t := MarsTransfer.new()
	t.jd_launch = jd
	var earth := Kepler.planet_position("earth", jd)
	t.r1 = Vector2(earth.x, earth.y).length()
	t.lon1 = atan2(earth.y, earth.x)
	var lon2 := t.lon1 + PI
	t.r2 = mars_radius_at(lon2, jd)
	t.a = (t.r1 + t.r2) / 2.0
	t.e = (t.r2 - t.r1) / (t.r2 + t.r1)
	t.days = 0.5 * pow(t.a, 1.5) * DAYS_PER_YEAR
	var mars_arr := Kepler.planet_position("mars", jd + t.days)
	t.miss_deg = rad_to_deg(wrapf(atan2(mars_arr.y, mars_arr.x) - lon2, -PI, PI))
	var mars_now := Kepler.planet_position("mars", jd)
	t.phase_deg = rad_to_deg(wrapf(atan2(mars_now.y, mars_now.x) - t.lon1, -PI, PI))
	return t


## Distance of Mars' orbit from the Sun (AU) in the direction of an ecliptic longitude.
static func mars_radius_at(lon: float, jd: float) -> float:
	var el := Kepler.planet_elements("mars", jd)
	var varpi := deg_to_rad(float(el.node) + float(el.w))
	return float(el.a) * (1.0 - el.e * el.e) / (1.0 + el.e * cos(lon - varpi))


## Phase angle (Mars ahead of Earth at launch) that a Hohmann transfer needs.
static func ideal_phase_deg() -> float:
	var a_t := (1.0 + 1.524) / 2.0
	var tof_years := 0.5 * pow(a_t, 1.5)
	return 180.0 - 360.0 * tof_years / 1.881


## Spacecraft position (heliocentric AU, ecliptic) after a fraction f of the flight.
func position_at(f: float) -> Vector3:
	var m := PI * clampf(f, 0.0, 1.0)
	var ea := Kepler.solve_eccentric_anomaly(m, e)
	var x := a * (cos(ea) - e)
	var y := a * sqrt(1.0 - e * e) * sin(ea)
	var c := cos(lon1)
	var s := sin(lon1)
	return Vector3(c * x - s * y, s * x + c * y, 0.0)


func arrival_point() -> Vector3:
	return position_at(1.0)


## How far Mars is from the arrival point (km, along its orbit).
func miss_km() -> float:
	return absf(deg_to_rad(miss_deg)) * r2 * AU_KM


## Best launch date (smallest miss) between jd_from and jd_to, searched in 1-day steps.
static func best_launch(jd_from: float, jd_to: float) -> float:
	var best := jd_from
	var best_miss := INF
	var jd := jd_from
	while jd <= jd_to:
		var m := absf(compute(jd).miss_deg)
		if m < best_miss:
			best_miss = m
			best = jd
		jd += 1.0
	return best


static func stars(miss_deg_abs: float, diff: String) -> int:
	var tight := 0.7 if diff == "pro" else 1.0
	if miss_deg_abs <= 1.0 * tight:
		return 3
	if miss_deg_abs <= 3.0 * tight:
		return 2
	return 1 if miss_deg_abs <= 8.0 else 0


static func score(miss_deg_abs: float, attempts: int, diff: String) -> int:
	var base := maxf(0.0, 1000.0 - miss_deg_abs * 90.0) + maxi(0, 3 - attempts) * 100
	var mult: float = {"explorer": 1.0, "researcher": 1.5, "pro": 2.5}.get(diff, 1.0)
	return int(base * mult)


static func jd_now() -> float:
	return Time.get_unix_time_from_system() / 86400.0 + 2440587.5


static func iso_from_jd(jd: float) -> String:
	return Time.get_datetime_string_from_unix_time(int((jd - 2440587.5) * 86400.0))


## Roughly how many days later (+) or earlier (-) the launch should be to hit Mars.
static func days_off(jd: float) -> float:
	var m0 := compute(jd).miss_deg
	var slope := compute(jd + 1.0).miss_deg - m0   # about -0.7 deg per day near a window
	if absf(slope) < 0.05:
		return 0.0
	return -m0 / slope


## First launch window after jd_from: the day of the first miss minimum below 2 degrees.
static func next_window(jd_from: float, jd_to: float) -> float:
	var jd := jd_from
	var prev := absf(compute(jd).miss_deg)
	while jd < jd_to:
		jd += 1.0
		var m := absf(compute(jd).miss_deg)
		if prev < 2.0 and m >= prev:
			return jd - 1.0
		prev = m
	return best_launch(jd_from, jd_to)
