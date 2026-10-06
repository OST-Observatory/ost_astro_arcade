## One observing scenario (built by tools/asteroid/build_scenarios.py): a real asteroid,
## its ephemeris for one night from Golm, and the real Gaia star field around it.
## Sky coordinates are tangent-plane offsets (xi east, eta north) in arcsec from the
## field centre; image coordinates follow the usual astronomical display: north up, east left.
class_name AsteroidScenario
extends RefCounted

const DATA_DIR := "res://assets/data/asteroid/"

# Camera: QHY600 on the CDK20, shown 6x binned -> 1596 x 1064 px.
# The game uses a 1536 x 1024 crop (35.7' x 23.8' at 1.394"/px).
const IMAGE_SIZE := Vector2i(1536, 1024)
const ARCSEC_PER_PX := 1.394

var data: Dictionary
var stars: Array  # [[xi, eta, G, bp_rp, variable], ...]
var track: Array


static func load_index() -> Array:
	var txt := FileAccess.get_file_as_string(DATA_DIR + "index.json")
	var parsed: Variant = JSON.parse_string(txt)
	return parsed.scenarios if parsed is Dictionary else []


static func load_by_id(id: String) -> AsteroidScenario:
	var txt := FileAccess.get_file_as_string(DATA_DIR + "scenarios/%s.json" % id)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_error("AsteroidScenario: cannot load %s" % id)
		return null
	var s := AsteroidScenario.new()
	s.data = parsed
	s.stars = parsed.field.stars
	s.track = parsed.track
	return s


## Picks a random scenario playable at the difficulty (see BlinkChallenge.is_eligible).
## Scenarios needing less exposure correction are more likely. Avoids `exclude` ids.
static func pick(difficulty: String, rng: RandomNumberGenerator, exclude: Array = []) -> AsteroidScenario:
	var pool := BlinkChallenge.eligible(load_index(), difficulty)
	var fresh := pool.filter(func(e): return not exclude.has(e.id))
	if not fresh.is_empty():
		pool = fresh
	if pool.is_empty():
		pool = load_index()
	if pool.is_empty():
		return null
	var target: float = BlinkChallenge.RULES[difficulty].mag
	var weights := pool.map(func(e): return 1.0 / (1.0 + absf(target - e.v)))
	var r: float = rng.randf() * weights.reduce(func(a, b): return a + b, 0.0)
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return load_by_id(pool[i].id)
	return load_by_id(pool[-1].id)


## "(3) Juno" – the usual way to write a numbered minor planet.
func display_name() -> String:
	var n: String = data.facts.get("name", "")
	if n == "" or n.is_valid_int():
		# Unnamed: SBDB gives "48438 (1989 WJ2)" -> use the provisional designation.
		var full := str(data.facts.get("fullname", ""))
		n = full.get_slice("(", 1).trim_suffix(")") if full.contains("(") else ""
	return "(%d) %s" % [data.number, n] if n != "" else "(%d)" % data.number


## "Harding, K." -> "K. Harding"; several discoverers are kept as they are.
func discoverer() -> String:
	var who := str(data.facts.discovery.get("who", ""))
	var parts := who.split(", ")
	return "%s %s" % [parts[1], parts[0]] if parts.size() == 2 and not who.contains(" and ") else who


## Asteroid offset (xi, eta in arcsec) at a fractional track index (10-minute steps).
func position_at(index_f: float) -> Vector2:
	var i := clampi(int(floor(index_f)), 0, track.size() - 2)
	var f := clampf(index_f - i, 0.0, 1.0)
	var a: Dictionary = track[i]
	var b: Dictionary = track[i + 1]
	return Vector2(lerpf(a.xi, b.xi, f), lerpf(a.eta, b.eta, f))


func sample_at(index_f: float) -> Dictionary:
	return track[clampi(int(round(index_f)), 0, track.size() - 1)]


## Sky offset (arcsec) -> image pixel for a pointing centre given in arcsec.
static func sky_to_px(sky: Vector2, center: Vector2) -> Vector2:
	var d := (sky - center) / ARCSEC_PER_PX
	return Vector2(IMAGE_SIZE) / 2.0 + Vector2(-d.x, -d.y)


static func px_to_sky(px: Vector2, center: Vector2) -> Vector2:
	var d := px - Vector2(IMAGE_SIZE) / 2.0
	return center + Vector2(-d.x, -d.y) * ARCSEC_PER_PX
