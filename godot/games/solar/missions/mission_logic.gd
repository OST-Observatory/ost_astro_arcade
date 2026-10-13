## Rules of the solar-system missions (no UI):
##   explorer   – Mars, Hohmann transfer, launch day on a slider (ghost Mars shown)
##   researcher – Jupiter directly, launch day over about three years (ghost Jupiter shown)
##   pro        – Saturn via a Jupiter swing-by: launch window, side and distance of the pass;
##                the resulting path and the closest approach to Saturn are always shown.
class_name MissionLogic
extends RefCounted

const TARGET := {"explorer": "mars", "researcher": "jupiter", "pro": "saturn"}
const RANGE_DAYS := {"explorer": 800, "researcher": 1100}
const ATTEMPTS := 3
const WINDOW_YEARS := 20.0
const RP_MIN := 1.1          # closest approach to Jupiter in Jupiter radii
const RP_MAX := 30.0
const SATURN_YEARS := 20.0   # how long after the swing-by Saturn is looked for
const HILL_SATURN := 0.43    # AU


static func target(diff: String) -> String:
	return TARGET.get(diff, "mars")


## Phase angle (deg) the target must be ahead of Earth at launch for a Hohmann transfer:
## the probe covers 180 deg while the target moves on during the flight (its real motion
## on its elliptic orbit, so the number fits the launch date).
static func ideal_phase(planet: String, jd: float) -> float:
	var t := HohmannTransfer.compute(planet, jd)
	var a := Kepler.planet_position(planet, jd)
	var b := Kepler.planet_position(planet, jd + t.days)
	return 180.0 - rad_to_deg(wrapf(atan2(b.y, b.x) - atan2(a.y, a.x), 0.0, TAU))


## Current phase angle (deg): how far the target is ahead of Earth.
static func phase(planet: String, jd: float) -> float:
	var e := Kepler.planet_position("earth", jd)
	var p := Kepler.planet_position(planet, jd)
	return rad_to_deg(wrapf(atan2(p.y, p.x) - atan2(e.y, e.x), 0.0, TAU))


static func direct_stars(miss_deg_abs: float) -> int:
	return MarsTransfer.stars(miss_deg_abs, "explorer")


static func direct_score(miss_deg_abs: float, attempts: int, diff: String) -> int:
	return MarsTransfer.score(miss_deg_abs, attempts, diff)


## Stars for the swing-by mission from the closest approach to Saturn (AU).
static func flyby_stars(d_au: float) -> int:
	if d_au < HILL_SATURN + 0.02:
		return 3
	if d_au < 1.0:
		return 2
	return 1 if d_au < 2.0 else 0


static func flyby_score(d_au: float, attempts: int) -> int:
	var base := maxf(0.0, 1000.0 - d_au * 350.0) + maxi(0, ATTEMPTS - attempts) * 100
	return int(base * 2.5)


## Jupiter launch windows from jd_from on, for `years` years.
static func jupiter_windows(jd_from: float, years := WINDOW_YEARS) -> Array:
	var out := []
	var jd := jd_from
	var end := jd_from + years * 365.25
	while jd < end:
		var w := HohmannTransfer.next_window("jupiter", jd, minf(jd + 450.0, end))
		if w < 0.0:
			break
		out.append(w)
		jd = w + 200.0
	return out


## The whole swing-by mission for a window, pass distance and side:
## {transfer, flyby, closest: AU, jd_closest, escapes}.
static func plan_flyby(jd_launch: float, rp_radii: float, side: float) -> Dictionary:
	var t := HohmannTransfer.compute("jupiter", jd_launch)
	var f := Flyby.compute(t, rp_radii, side)
	var c := f.closest_to("saturn", SATURN_YEARS)
	return {"transfer": t, "flyby": f, "closest": float(c[0]), "jd_closest": float(c[1]), "approach": c[2],
		"escapes": f.escapes()}


## Best result a window allows (over both sides and the whole pass-distance range).
static func best_for_window(jd_launch: float) -> Dictionary:
	var best := {"closest": INF}
	for side in [1.0, -1.0]:
		var rp := RP_MIN
		while rp <= RP_MAX:
			var p := plan_flyby(jd_launch, rp, side)
			if float(p.closest) < float(best.closest):
				best = p
				best["rp"] = rp
				best["side"] = side
			rp *= 1.25
	return best


## Roughly how many days later (+) or earlier (-) the launch should be to meet the planet.
static func days_off(planet: String, jd: float) -> float:
	var m0 := HohmannTransfer.compute(planet, jd).miss_deg
	var slope := HohmannTransfer.compute(planet, jd + 1.0).miss_deg - m0
	if absf(slope) < 0.01:
		return 0.0
	return -m0 / slope
