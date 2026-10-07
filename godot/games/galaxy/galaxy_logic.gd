## Galaxy builder rules: the targets (real interacting galaxies and the encounter that
## reproduces them in GalaxyModel), which knobs each difficulty unlocks, how the density-map
## correlation becomes a similarity in percent, points, stars and "warmer/colder" hints.
class_name GalaxyLogic
extends RefCounted

const ATTEMPTS := 5
## Model time unit in million years (1e11 solar masses, 3 kpc length unit).
const MYR_PER_UNIT := 7.7

## Knobs the player can turn: [min, max, step, start value].
const CONTROLS := {
	"t_after": [10.0, 80.0, 5.0, 25.0],
	"m2": [0.2, 1.0, 0.1, 0.5],
	"q": [2.0, 12.0, 1.0, 8.0],
	"incl2": [-90.0, 90.0, 15.0, 0.0],
	"spin1": [-1.0, 1.0, 2.0, -1.0],   # a switch: against / along the orbit
}

## base/ceil: mean correlation of random knob settings and of the target with itself
## (another star sample); measured with tools/galaxy_calibrate.gd.
const TARGETS := [
	{"id": "antennae", "image": "res://assets/puzzle/images/NGC_4038_NGC_4039_HaRGB.jpg",
		"credit": "OST-Sternwarte, Universität Potsdam",
		"params": {"m2": 1.0, "q": 5.0, "e": 0.9, "incl1": 60.0, "incl2": -60.0, "t_after": 45.0,
			"view": Vector3(0, 90, -30)},
		"extent": 32.0, "pro": "incl2", "base": 0.551, "ceil": 0.981},
	{"id": "mice", "image": "res://assets/galaxy/images/mice.jpg",
		"credit": "NASA, H. Ford (JHU), G. Illingworth (UCSC/LO), M. Clampin (STScI), G. Hartig (STScI), ACS Science Team, ESA (CC BY 4.0)",
		"params": {"m2": 1.0, "q": 6.0, "e": 1.0, "friction": 0.0, "incl1": 40.0, "incl2": 20.0,
			"node2": 60.0, "t_after": 30.0, "view": Vector3(10, 8, 30)},
		"extent": 28.0, "pro": "incl2", "base": 0.716, "ceil": 0.990},
	{"id": "whirlpool", "image": "res://assets/galaxy/images/whirlpool.jpg",
		"credit": "NASA, ESA, S. Beckwith (STScI), Hubble Heritage Team (STScI/AURA) (CC BY 4.0)",
		"params": {"m2": 0.3, "q": 10.0, "e": 1.0, "incl1": 0.0, "incl2": 70.0, "spin1": 1.0,
			"t_after": 15.0, "view": Vector3(0, 90, 0)},
		"extent": 20.0, "pro": "spin1", "base": 0.567, "ceil": 0.995},
]

const DIFF_MULT := {"explorer": 1.0, "researcher": 1.5, "pro": 2.5}


static func target(id: String) -> Dictionary:
	for t in TARGETS:
		if t.id == id:
			return t
	return TARGETS[0]


## Knobs unlocked at a difficulty; the others stay at the target's true values.
static func controls_for(t: Dictionary, diff: String) -> Array[String]:
	var out: Array[String] = ["t_after", "m2"]
	if diff != "explorer":
		out.append("q")
	if diff == "pro":
		out.append(t.pro)
	return out


## Start values of the unlocked knobs, nudged away from the answer so no knob starts right.
static func start_values(t: Dictionary, controls: Array[String]) -> Dictionary:
	var out := {}
	for c in controls:
		var spec: Array = CONTROLS[c]
		if c.begins_with("spin"):
			out[c] = -float(t.params[c])   # switches start on the wrong side
			continue
		var v := float(spec[3])
		if absf(v - float(t.params[c])) < float(spec[2]) * 1.5:
			v = clampf(v + float(spec[2]) * 3.0 * (1.0 if v < float(spec[1]) - float(spec[2]) * 3.0 else -1.0),
				float(spec[0]), float(spec[1]))
		out[c] = v
	return out


## Full model parameters: the target's encounter with the player's knob values.
static func params_for(t: Dictionary, knobs: Dictionary) -> Dictionary:
	var p: Dictionary = (t.params as Dictionary).duplicate()
	p.merge(knobs, true)
	return p


static func density(t: Dictionary, p: Dictionary, n := 3000, seed := 7) -> PackedFloat32Array:
	return GalaxyModel.density_map(p, GalaxyModel.simulate(p, n, seed), GalaxyModel.MAP_SIZE, t.extent)


## Correlation -> similarity 0..100: an average random guess gets 30 %, a perfect match 100 %
## (scaled between "base" and "ceil", so every target is equally hard).
static func similarity(t: Dictionary, corr: float) -> int:
	var x := (corr - float(t.base)) / maxf(float(t.ceil) - float(t.base), 0.01)
	return int(round(100.0 * clampf(0.3 + 0.7 * x, 0.0, 1.0)))


static func stars(best: int) -> int:
	if best >= 90:
		return 3
	if best >= 75:
		return 2
	return 1 if best >= 50 else 0


## Points: best similarity, a bonus for every attempt left over (weighted by the similarity,
## so giving up early does not pay), times the difficulty factor.
static func score(best: int, attempts_used: int, diff: String) -> int:
	var base := best * 10 + int(maxi(0, ATTEMPTS - attempts_used) * 80 * pow(best / 100.0, 2.0))
	return int(base * float(DIFF_MULT.get(diff, 1.0)))


static func myr(t_units: float) -> int:
	return int(round(t_units * MYR_PER_UNIT / 10.0)) * 10


## Hint for the knob that is furthest off (relative to its range): [knob, +1 or -1], or [] if
## everything is within one step.
static func hint(t: Dictionary, knobs: Dictionary) -> Array:
	var worst := ""
	var worst_d := 0.0
	for c in knobs:
		var spec: Array = CONTROLS[c]
		var d := (float(t.params[c]) - float(knobs[c])) / (float(spec[1]) - float(spec[0]))
		if absf(d) > absf(worst_d) and absf(float(t.params[c]) - float(knobs[c])) > float(spec[2]) * 1.01:
			worst = c
			worst_d = d
	if worst == "":
		return []
	return [worst, 1 if worst_d > 0.0 else -1]
