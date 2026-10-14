## Act 2 rules: badges for the shapes found by the FeatureDetector, the photo for each shape,
## recipe hints, points and stars for the whole galaxy-builder round.
class_name CollideLogic
extends RefCounted

const MAX_COLLISIONS := 3
const BADGE_POINTS := 250
## Real galaxies that show each shape.
const PHOTOS := {
	"tails": "res://assets/galaxy/images/mice.jpg",
	"bridge": "res://assets/galaxy/images/whirlpool.jpg",
	"ring": "res://assets/galaxy/images/cartwheel.jpg",
	"merger": "res://assets/puzzle/images/NGC_4038_NGC_4039_HaRGB.jpg",
}
const APPROACHES := ["headon", "grazing", "wide"]


## New badges in `found` (feature -> time or -1) that are not in `have` yet.
static func new_badges(found: Dictionary, have: Array) -> Array[String]:
	var out: Array[String] = []
	for f in FeatureDetector.FEATURES:
		if float(found.get(f, -1.0)) >= 0.0 and not have.has(f):
			out.append(f)
	return out


## A recipe per target galaxy and shape: [partner, approach, spin (0: either)]. Taken from
## the recipe matrix of tools/galaxy_calibrate.gd – each one gives the shape with the 250
## stars of the game and with 500 (so it is not luck of the draw).
const RECIPES := {
	"milkyway": {"tails": ["twin", "grazing", 1], "merger": ["twin", "headon", 0],
		"ring": ["spiral", "headon", 0], "bridge": ["twin", "wide", 1]},
	"ngc3198": {"tails": ["twin", "grazing", 1], "merger": ["spiral", "headon", 0],
		"ring": ["spiral", "headon", 0], "bridge": ["spiral", "wide", 1]},
	"ddo154": {"tails": ["dwarf", "headon", 0], "merger": ["dwarf", "headon", 0],
		"ring": ["dwarf", "headon", 0], "bridge": ["dwarf", "wide", 1]},
}


## A hint towards a badge the player does not have yet, for the galaxy they built, as text
## ("" when all badges are there).
static func recipe_hint(have: Array, target_id: String) -> String:
	var recipes: Dictionary = RECIPES.get(target_id, RECIPES.milkyway)
	for f in ["tails", "merger", "ring", "bridge"]:
		if have.has(f):
			continue
		var r: Array = recipes[f]
		var parts := [TranslationServer.translate("GAL_PARTNER_" + str(r[0]).to_upper()),
			TranslationServer.translate("GAL_APPROACH_" + str(r[1]).to_upper())]
		if int(r[2]) != 0:
			parts.append(TranslationServer.translate("GAL_SPIN_WITH" if int(r[2]) > 0 else "GAL_SPIN_AGAINST"))
		return TranslationServer.translate("GAL_RECIPE") % [TranslationServer.translate("GAL_FEATURE_" + f.to_upper()),
			"  ·  ".join(parts)]
	return ""


static func total_points(build_points: int, badges: int, diff: String) -> int:
	return build_points + int(badges * BADGE_POINTS * float(BuildLogic.MULT.get(diff, 1.0)))


static func stars(stable: bool, badges: int) -> int:
	return clampi((1 if stable else 0) + (1 if badges >= 1 else 0) + (1 if badges >= 3 else 0), 1, 3)
