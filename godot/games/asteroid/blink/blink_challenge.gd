## Pure game logic of the blink comparison (no nodes): builds the three frames for a
## scenario and difficulty, and classifies a tap. Kept separate so it can be unit tested.
class_name BlinkChallenge
extends RefCounted

const FRAME_STEP_MIN := 20.0   # minutes between exposures
const FRAMES := 3

## depth: magnitude offset from the exposure time (negative = longer, brighter image).
## dither: pointing offset between exposures in px (hot pixels then appear to jump).
const RULES := {
	"explorer": {"cosmics": 1, "hot": 0, "variable": false, "satellite": false, "tol": 34.0,
		"hints": [15.0, 30.0], "mult": 1.0, "depth": -0.5, "dither": 0.0},
	"researcher": {"cosmics": 3, "hot": 3, "variable": true, "satellite": false, "tol": 22.0,
		"hints": [25.0, 50.0], "mult": 1.5, "depth": 0.0, "dither": 0.0},
	"pro": {"cosmics": 6, "hot": 6, "variable": true, "satellite": true, "tol": 13.0,
		"hints": [60.0, 100.0], "mult": 2.5, "depth": 1.0, "dither": 14.0},
}

var scenario: AsteroidScenario
var difficulty: String
var rules: Dictionary
var center := Vector2.ZERO          # pointing centre (arcsec)
var start_index := 0.0              # track index (10-min steps) of frame 1
var asteroid_px: Array[Vector2] = []
var frames: Array = []              # specs for CcdFrames.build
var stars_px: Array = []
var variable := {}                  # {"px", "base_mag"} if used
var hot_px: Array[Vector2] = []
var cosmic_px: Array = []           # per frame: Array[Vector2]
var satellite := []                 # [a, b] in frame 2 or []
var dither: Array[Vector2] = []     # per-frame offset of the detector relative to the sky


static func create(sc: AsteroidScenario, diff: String, rng: RandomNumberGenerator) -> BlinkChallenge:
	var c := BlinkChallenge.new()
	c.scenario = sc
	c.difficulty = diff
	c.rules = RULES.get(diff, RULES.researcher)
	c._setup(rng)
	return c


func _setup(rng: RandomNumberGenerator) -> void:
	start_index = float(scenario.data.best_index) - FRAME_STEP_MIN / 10.0
	var mid := scenario.position_at(start_index + FRAME_STEP_MIN / 10.0)
	# Point so the asteroid is NOT in the middle: anywhere in the inner 70 % of the field.
	var half := Vector2(AsteroidScenario.IMAGE_SIZE) * AsteroidScenario.ARCSEC_PER_PX / 2.0
	center = mid + Vector2(rng.randf_range(-0.7, 0.7) * half.x, rng.randf_range(-0.7, 0.7) * half.y)

	var size := Vector2(AsteroidScenario.IMAGE_SIZE)
	for s in scenario.stars:
		var p := AsteroidScenario.sky_to_px(Vector2(s[0], s[1]), center)
		if p.x < -5 or p.y < -5 or p.x > size.x + 5 or p.y > size.y + 5:
			continue
		if s[4] == 1 and variable.is_empty() and rules.variable and _inside(p, 80.0):
			variable = {"px": p, "base_mag": float(s[2])}
			continue
		stars_px.append([p, float(s[2])])
	if rules.variable and variable.is_empty():
		# No Gaia variable in view: promote a mid-bright star (game simplification).
		for i in stars_px.size():
			if stars_px[i][1] > 13.5 and stars_px[i][1] < 15.5 and _inside(stars_px[i][0], 120.0):
				variable = {"px": stars_px[i][0], "base_mag": stars_px[i][1]}
				stars_px.remove_at(i)
				break

	for i in rules.hot:
		hot_px.append(_random_px(rng, 40.0))
	for f in FRAMES:
		var d := Vector2.ZERO
		if rules.dither > 0.0 and f > 0:
			d = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.6, 1.0) * rules.dither
		dither.append(d)
	var v_mag: float = scenario.data.v_best
	for f in FRAMES:
		var t := start_index + f * FRAME_STEP_MIN / 10.0
		var a := AsteroidScenario.sky_to_px(scenario.position_at(t), center)
		asteroid_px.append(a)
		var frame_cos: Array[Vector2] = []
		var cos_specs := []
		for k in rules.cosmics:
			var p := _random_px(rng, 30.0)
			frame_cos.append(p)
			cos_specs.append([p, rng.randf_range(0.5, 4.0), rng.randf_range(0.0, TAU)])
		cosmic_px.append(frame_cos)
		var spec := {
			"asteroid": a, "asteroid_mag": v_mag,
			"cosmics": cos_specs, "hot": hot_in_frame(f),
			"variable": {} if variable.is_empty() else {"px": variable.px, "mag": variable.base_mag + [0.0, -0.9, 0.5][f]},
			"satellite": [],
		}
		if rules.satellite and f == 1:
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


## Hot pixels sit on the detector; frames are aligned on the stars, so with dithering
## they appear shifted by the pointing offset of that exposure.
func hot_in_frame(f: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for h in hot_px:
		out.append(h + dither[f])
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
	for f in FRAMES:
		for h in hot_in_frame(f):
			if p.distance_to(h) <= 12.0:
				return "hot_jump" if rules.dither > 0.0 else "hot"
	if not variable.is_empty() and p.distance_to(variable.px) <= 16.0:
		return "variable"
	if satellite.size() == 2 and frame_idx == 1:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, satellite[0], satellite[1])) <= 12.0:
			return "satellite"
	for s in stars_px:
		if s[1] < 17.5 and p.distance_to(s[0]) <= 10.0:
			return "star"
	return "nothing"


## Score for a solved round (>= 0): speed, accuracy and hints, scaled by difficulty.
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
