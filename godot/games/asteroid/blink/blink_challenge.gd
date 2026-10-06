## Pure game logic of the blink comparison (no nodes): builds the three frames for a
## scenario and difficulty, and classifies a tap. Kept separate so it can be unit tested.
##
## Difficulty is normalised, not left to the catalogue: like a real observer, the game
## picks the EXPOSURE TIME so the asteroid reaches a target brightness in the image, and
## the TIME BETWEEN EXPOSURES so it moves a target distance. Both are honest observer
## choices; the star field follows the same exposure.
class_name BlinkChallenge
extends RefCounted

const FRAMES := 3
const MAX_DEPTH := 3.0                # longer exposure: up to 3 mag deeper (x16 in time)
const MAX_SHORTEN := 1.0              # shorter exposure: at most 1 mag, so the star field stays rich
const INTERVAL_MIN := 12.0            # minutes between exposures, allowed range
const INTERVAL_MAX := 90.0

## mag: asteroid brightness in the image (it may be up to `brighter` mag brighter if the
## object is bright and the exposure cannot be shortened further); motion_px: path from
## frame 1 to frame 3.
## Tuned after playtests (2026-10): explorer clearly visible, pro only slightly harder
## than researcher.
const RULES := {
	"explorer": {"mag": 12.3, "jitter": 0.3, "brighter": 3.0, "motion_px": 32.0, "cosmics": 1, "hot": 0,
		"variable": false, "satellite": 0.0, "tol": 40.0, "hints": [12.0, 25.0, 40.0], "mult": 1.0},
	"researcher": {"mag": 13.7, "jitter": 0.2, "brighter": 1.0, "motion_px": 26.0, "cosmics": 1, "hot": 2,
		"variable": true, "satellite": 0.0, "tol": 32.0, "hints": [15.0, 30.0, 50.0], "mult": 1.5},
	"pro": {"mag": 14.2, "jitter": 0.2, "brighter": 0.4, "motion_px": 18.0, "cosmics": 3, "hot": 4,
		"variable": true, "satellite": 0.5, "tol": 22.0, "hints": [30.0, 55.0, 85.0], "mult": 2.5},
}

var scenario: AsteroidScenario
var difficulty: String
var rules: Dictionary
var depth := 0.0                    # mag offset applied to everything (exposure time)
var interval_min := 20.0            # minutes between exposures
var center := Vector2.ZERO          # pointing centre (arcsec)
var start_index := 0.0              # track index (10-min steps) of frame 1
var asteroid_px: Array[Vector2] = []
var asteroid_mag := 0.0             # brightness in the image (after exposure)
var frames: Array = []              # specs for CcdFrames.build
var stars_px: Array = []
var variable := {}                  # {"px", "base_mag"} if used
var hot_px: Array[Vector2] = []
var cosmic_px: Array = []           # per frame: Array[Vector2]
var satellite := []                 # [a, b] in frame 2 or []


static func create(sc: AsteroidScenario, diff: String, rng: RandomNumberGenerator) -> BlinkChallenge:
	var c := BlinkChallenge.new()
	c.scenario = sc
	c.difficulty = diff
	c.rules = RULES.get(diff, RULES.researcher)
	c._setup(rng)
	return c


## Motion of a scenario at its best time in image px per minute.
static func px_per_min(entry: Dictionary) -> float:
	return float(entry.rate_arcsec_h) / 60.0 / AsteroidScenario.ARCSEC_PER_PX


## Ideal exposure interval for the difficulty (may lie outside the allowed range).
static func ideal_interval(entry: Dictionary, diff: String) -> float:
	return RULES[diff].motion_px / 2.0 / maxf(px_per_min(entry), 1e-6)


## Exposure shift (mag) that brings an object of brightness v closest to `target`.
static func depth_for(v: float, target: float) -> float:
	# Positive = fainter (shorter exposure), negative = brighter (longer exposure).
	return clampf(target - v, -MAX_DEPTH, MAX_SHORTEN)


## Can this scenario be played at this difficulty without bending physics too far?
static func is_eligible(entry: Dictionary, diff: String) -> bool:
	var r: Dictionary = RULES[diff]
	var iv := ideal_interval(entry, diff)
	var m := float(entry.v) + depth_for(float(entry.v), r.mag)
	return m >= r.mag - r.brighter - 0.01 and m <= r.mag + 0.01 and iv >= INTERVAL_MIN and iv <= INTERVAL_MAX


## Index entries playable at this difficulty, closest exposures first.
static func eligible(index: Array, diff: String) -> Array:
	var out := index.filter(func(e): return is_eligible(e, diff))
	out.sort_custom(func(a, b): return absf(RULES[diff].mag - a.v) < absf(RULES[diff].mag - b.v))
	return out


func _setup(rng: RandomNumberGenerator) -> void:
	var entry := {"v": scenario.data.v_best, "rate_arcsec_h": scenario.data.rate_arcsec_h}
	interval_min = clampf(ideal_interval(entry, difficulty), INTERVAL_MIN, INTERVAL_MAX)
	var target: float = rules.mag + rng.randf_range(-rules.jitter, rules.jitter)
	depth = depth_for(float(scenario.data.v_best), target)
	asteroid_mag = float(scenario.data.v_best) + depth

	var step := interval_min / 10.0  # track samples are 10 minutes apart
	start_index = float(scenario.data.best_index) - step
	var mid := scenario.position_at(start_index + step)
	# Point so the asteroid is NOT in the middle: anywhere in the inner 70 % of the field.
	var half := Vector2(AsteroidScenario.IMAGE_SIZE) * AsteroidScenario.ARCSEC_PER_PX / 2.0
	center = mid + Vector2(rng.randf_range(-0.7, 0.7) * half.x, rng.randf_range(-0.7, 0.7) * half.y)

	var size := Vector2(AsteroidScenario.IMAGE_SIZE)
	for s in scenario.stars:
		var p := AsteroidScenario.sky_to_px(Vector2(s[0], s[1]), center)
		if p.x < -5 or p.y < -5 or p.x > size.x + 5 or p.y > size.y + 5:
			continue
		var m: float = s[2] + depth
		if s[4] == 1 and variable.is_empty() and rules.variable and _inside(p, 80.0) and m < 15.5:
			variable = {"px": p, "base_mag": m}
			continue
		stars_px.append([p, m])
	if rules.variable and variable.is_empty():
		# No suitable Gaia variable in view: promote a moderately bright star (simplification).
		for i in stars_px.size():
			if stars_px[i][1] > 13.0 and stars_px[i][1] < 15.0 and _inside(stars_px[i][0], 120.0):
				variable = {"px": stars_px[i][0], "base_mag": stars_px[i][1]}
				stars_px.remove_at(i)
				break

	for i in rules.hot:
		hot_px.append(_random_px(rng, 40.0))
	var with_satellite: bool = rng.randf() < rules.satellite
	for f in FRAMES:
		var a := AsteroidScenario.sky_to_px(scenario.position_at(start_index + f * step), center)
		asteroid_px.append(a)
		var frame_cos: Array[Vector2] = []
		var cos_specs := []
		for k in rules.cosmics:
			var p := _random_px(rng, 30.0)
			frame_cos.append(p)
			cos_specs.append([p, rng.randf_range(0.5, 4.0), rng.randf_range(0.0, TAU)])
		cosmic_px.append(frame_cos)
		var spec := {
			"asteroid": a, "asteroid_mag": asteroid_mag,
			"cosmics": cos_specs, "hot": hot_px,
			"variable": {} if variable.is_empty() else {"px": variable.px, "mag": variable.base_mag + [0.0, -0.9, 0.5][f]},
			"satellite": [],
		}
		if with_satellite and f == 1:
			var y0 := rng.randf_range(100, size.y - 100)
			satellite = [Vector2(-10, y0), Vector2(size.x + 10, y0 + rng.randf_range(-400, 400))]
			spec.satellite = satellite
		frames.append(spec)


func _inside(p: Vector2, margin: float) -> bool:
	var s := Vector2(AsteroidScenario.IMAGE_SIZE)
	return p.x > margin and p.y > margin and p.x < s.x - margin and p.y < s.y - margin


func _random_px(rng: RandomNumberGenerator, margin: float) -> Vector2:
	var s := Vector2(AsteroidScenario.IMAGE_SIZE)
	return Vector2(rng.randf_range(margin, s.x - margin), rng.randf_range(margin, s.y - margin))


## Minutes after frame 1 at which each frame was taken.
func frame_minutes() -> Array[int]:
	var out: Array[int] = []
	for f in FRAMES:
		out.append(int(round(f * interval_min)))
	return out


## Motion of the asteroid between first and last frame, in arcsec.
func motion_arcsec() -> float:
	return asteroid_px[0].distance_to(asteroid_px[FRAMES - 1]) * AsteroidScenario.ARCSEC_PER_PX


## Classifies a tap at image pixel `p` while frame `frame_idx` is shown.
## Returns "asteroid", "cosmic", "hot", "variable", "satellite", "star" or "nothing".
func classify(p: Vector2, frame_idx: int) -> String:
	var tol: float = rules.tol
	for a in asteroid_px:
		if p.distance_to(a) <= tol:
			return "asteroid"
	for f in cosmic_px.size():
		for c in cosmic_px[f]:
			if p.distance_to(c) <= 14.0:
				return "cosmic"
	for h in hot_px:
		if p.distance_to(h) <= 12.0:
			return "hot"
	if not variable.is_empty() and p.distance_to(variable.px) <= 16.0:
		return "variable"
	if satellite.size() == 2 and frame_idx == 1:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, satellite[0], satellite[1])) <= 12.0:
			return "satellite"
	for s in stars_px:
		if s[1] < 17.5 and p.distance_to(s[0]) <= 10.0:
			return "star"
	return "nothing"


## Score for a solved round (>= 100 x multiplier): speed, accuracy and hints.
func score(seconds: float, wrong_taps: int, hints_used: int) -> int:
	var base := 1000.0 + maxf(0.0, 600.0 - seconds * 6.0)
	base -= wrong_taps * 80.0 + hints_used * 200.0
	return int(maxf(100.0, base) * rules.mult)


static func stars_for(wrong_taps: int, hints_used: int) -> int:
	if hints_used == 0 and wrong_taps <= 1:
		return 3
	if hints_used <= 1 and wrong_taps <= 4:
		return 2
	return 1
