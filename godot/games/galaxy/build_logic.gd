## Act 1 rules: how well the player's mass model matches the measured rotation curve, when a
## galaxy counts as stable, the knowledge questions that unlock each building block, points.
class_name BuildLogic
extends RefCounted

const STABLE := {"explorer": 90.0, "researcher": 90.0, "pro": 95.0}
const QUIZ_RIGHT := 100
const QUIZ_WRONG := 40
## Knowledge questions per building block and level (0 explorer, 1 researcher, 2 pro; keys
## GAL_Q_<id>_Q/_A0/_A1/_A2/_EXPL, A0 is right; the answers are shuffled for display).
const QUESTIONS := {
	"bh": [["bh_center", "bh_light"], ["bh_mass", "bh_image"], ["bh_stars", "bh_size"]],
	"stars": [["stars_disk", "stars_sun"], ["stars_count", "stars_bulge"], ["stars_arms", "stars_age"]],
	"gas": [["gas_birth", "gas_hydrogen"], ["gas_vs_stars", "gas_21cm"], ["gas_hot", "gas_dust"]],
	"halo": [["halo_mass", "halo_see"], ["halo_rubin", "halo_without"], ["halo_lensing", "halo_shape"]],
}
const LEVEL := {"explorer": 0, "researcher": 1, "pro": 2}
const MULT := {"explorer": 1.0, "researcher": 1.5, "pro": 2.5}


## 100 % = the model lies within the error bars everywhere; each 1 % beyond them costs 2.5 %.
static func match_percent(t: Dictionary, pot: GalaxyPotential) -> float:
	var sum := 0.0
	for p in t.points:
		var v := pot.v_circ(float(p[0]))
		sum += maxf(absf(v - float(p[1])) - float(p[2]), 0.0) / float(p[1])
	return clampf(100.0 - 250.0 * sum / t.points.size(), 0.0, 100.0)


static func is_stable(match: float, diff: String) -> bool:
	return match >= float(STABLE.get(diff, 90.0))


## One question per building block, picked at random from the player's level and, for
## researchers and pros, the level below (more variety, still fitting).
static func pick_questions(rng: RandomNumberGenerator, diff := "researcher") -> Dictionary:
	var level: int = LEVEL.get(diff, 1)
	var out := {}
	for c in QUESTIONS:
		var pool: Array = []
		for l in range(maxi(0, level - 1), level + 1):
			pool.append_array(QUESTIONS[c][l])
		out[c] = pool[rng.randi_range(0, pool.size() - 1)]
	return out


## Answer order for display: the right answer (index 0) at a random position.
static func answer_order(rng: RandomNumberGenerator) -> Array:
	var order := [0, 1, 2]
	for i in range(2, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order


static func quiz_points(right: bool) -> int:
	return QUIZ_RIGHT if right else QUIZ_WRONG


static func build_points(quiz: int, match: float, diff: String) -> int:
	return int((quiz + int(match) * 5) * float(MULT.get(diff, 1.0)))


## "45 Mrd. Sonnenmassen" style text for a mass in model units.
static func mass_text(m_model: float) -> String:
	var msun := m_model * GalaxyPotential.MSUN
	if msun <= 0.0:
		return TranslationServer.translate("GAL_MASS_NONE")
	if msun >= 1e9:
		return TranslationServer.translate("GAL_MASS_BN") % AstroFormat.num(msun / 1e9, 1 if msun < 1e10 else 0)
	if msun >= 1e6:
		return TranslationServer.translate("GAL_MASS_MN") % AstroFormat.num(msun / 1e6, 1 if msun < 1e7 else 0)
	return TranslationServer.translate("GAL_MASS_TH") % AstroFormat.num(msun / 1e3, 0)
