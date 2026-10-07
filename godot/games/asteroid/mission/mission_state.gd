## Everything one asteroid mission decides and scores, shared by all steps.
class_name MissionState
extends RefCounted

const STEPS := ["plan", "dome", "align", "expose", "blink", "measure", "orbit"]
const MAX_POINTS := {"plan": 300, "align": 300, "measure": 400}
## JPL SBDB orbit class -> explanation string.
const CLASS_KEYS := {
	"MBA": "AST_CLASS_MBA", "IMB": "AST_CLASS_MBA", "OMB": "AST_CLASS_MBA",
	"MCA": "AST_CLASS_MCA", "AMO": "AST_CLASS_NEO", "APO": "AST_CLASS_NEO",
	"ATE": "AST_CLASS_NEO", "IEO": "AST_CLASS_NEO", "TJN": "AST_CLASS_TJN",
}

var rng := RandomNumberGenerator.new()
var difficulty := "researcher"
var scenario: AsteroidScenario
var obs_index := 0.0                 # track index chosen in "plan the night"
var sky := {}                        # quality_at(obs_index)
var pointing := Vector2.ZERO         # telescope pointing (arcsec) from "align"
var exposure_offset := 0.0           # mag: +0.75 short, 0 normal, -0.75 long
var exposure_s := 60.0
var exposure_mult := 1.0
var challenge: BlinkChallenge
var blink := {}                      # result of the blink step
var measured: Array[Vector2] = []    # tapped asteroid positions (image px)
var measure_error_arcsec := 0.0
var points := {}                     # step -> points


func sample(i: float) -> Dictionary:
	return scenario.sample_at(i)


## Observing conditions at a track index: quality 0..1 for the score and the sky
## background factor for the CCD simulation (moonlight, airmass, twilight).
func quality_at(i: float) -> Dictionary:
	var s := sample(i)
	var alt: float = s.alt
	var ok: bool = s.sun_alt < -12.0 and alt > 25.0
	var airmass := 1.0 / maxf(sin(deg_to_rad(maxf(alt, 5.0))), 0.1)
	var moon_up := clampf(sin(deg_to_rad(float(s.moon_alt))), 0.0, 1.0)
	var moon_term: float = float(s.moon_illum) * moon_up * (1.0 - 0.6 * clampf(float(s.moon_sep) / 150.0, 0.0, 1.0))
	var q_alt := clampf((alt - 25.0) / 45.0, 0.0, 1.0)
	var q_moon := 1.0 - moon_term
	var q_dark := clampf((-float(s.sun_alt) - 12.0) / 6.0, 0.0, 1.0)
	var q := 0.5 * q_alt + 0.3 * q_moon + 0.2 * q_dark
	var bg := clampf((1.0 + 3.0 * moon_term) * (0.7 + 0.3 * airmass) * (1.0 + 2.0 * (1.0 - q_dark)), 1.0, 5.0)
	return {"ok": ok, "q": q, "q_alt": q_alt, "q_moon": q_moon, "q_dark": q_dark,
		"bg_factor": bg, "airmass": airmass, "moon_term": moon_term}


## Difficulty multiplier, applied to every step's points (pro missions score more).
func diff_mult() -> float:
	return float(BlinkChallenge.RULES[difficulty].mult)


func total_points() -> int:
	var t := 0
	for k in points:
		t += int(points[k])
	return t


## 1-3 stars for the whole mission.
func stars() -> int:
	var b: int = blink.get("stars", 1)
	var acc := measure_error_arcsec < 2.0
	if b == 3 and acc and float(points.get("plan", 0)) >= 200:
		return 3
	return 2 if b >= 2 else 1
