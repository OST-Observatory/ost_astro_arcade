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


## A hint towards a badge the player does not have yet (key GAL_RECIPE_<FEATURE>), or "".
static func recipe_hint(have: Array) -> String:
	for f in ["tails", "merger", "ring", "bridge"]:
		if not have.has(f):
			return "GAL_RECIPE_" + f.to_upper()
	return ""


static func total_points(build_points: int, badges: int, diff: String) -> int:
	return build_points + int(badges * BADGE_POINTS * float(BuildLogic.MULT.get(diff, 1.0)))


static func stars(stable: bool, badges: int) -> int:
	return clampi((1 if stable else 0) + (1 if badges >= 1 else 0) + (1 if badges >= 3 else 0), 1, 3)
