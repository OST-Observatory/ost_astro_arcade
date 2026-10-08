## Constellation tracing: data (real stars to 6 mag, stick figures), the sky projection and
## the rules – which constellations a difficulty gets, how much help there is, edge checks,
## points and stars. Data: tools/constellations/build_constellations.py (d3-celestial).
class_name ConstellationLogic
extends RefCounted

const DATA := "res://assets/data/constellations/sky.json"
const ROUNDS := 3
## Faintest star shown (more faint stars = more distractors), how far the figure may sit off
## the middle of the view (fraction of its radius), ghost lines, and when member stars glow.
const RULES := {
	"explorer": {"mag": 5.0, "offset": 0.0, "ghost": true, "glow_after": 0.0, "mult": 1.0},
	"researcher": {"mag": 4.8, "offset": 0.15, "ghost": false, "glow_after": 12.0, "mult": 1.5},
	"pro": {"mag": 5.4, "offset": 0.3, "ghost": false, "glow_after": 25.0, "mult": 2.5},
}
const POINTS_PER_LINE := 40
const MIN_FIELD := 8.0
const WRONG_PENALTY := 30

var stars := {}            # hip -> [ra, dec, mag, bv]
var names := {}            # hip -> {"en", "de"}
var constellations: Array = []
var diff := "researcher"


func load_data() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for s in d.stars:
		stars[int(s[0])] = [float(s[1]), float(s[2]), float(s[3]), float(s[4])]
	for k in d.names:
		names[int(k)] = d.names[k]
	constellations = d.constellations


func rules() -> Dictionary:
	return RULES.get(diff, RULES.researcher)


## ROUNDS constellations of the difficulty's level (never the same twice).
func pick(rng: RandomNumberGenerator) -> Array:
	var pool := constellations.filter(func(c): return c.level == diff)
	var out := []
	while out.size() < ROUNDS and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


static func edge_key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


static func edge_set(c: Dictionary) -> Dictionary:
	var out := {}
	for e in c.edges:
		out[edge_key(int(e[0]), int(e[1]))] = true
	return out


static func members(c: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for e in c.edges:
		for h in e:
			if not out.has(int(h)):
				out.append(int(h))
	return out


## Gnomonic projection around (ra0, dec0): east to the left, north up (as seen looking south).
## Returns [x, y] in radians-on-the-tangent-plane, or null behind the tangent point.
static func project(ra: float, dec: float, ra0: float, dec0: float) -> Variant:
	var r := deg_to_rad(ra - ra0)
	var d := deg_to_rad(dec)
	var d0 := deg_to_rad(dec0)
	var cosc := sin(d0) * sin(d) + cos(d0) * cos(d) * cos(r)
	if cosc < 0.2:
		return null
	var x := cos(d) * sin(r) / cosc
	var y := (cos(d0) * sin(d) - sin(d0) * cos(d) * cos(r)) / cosc
	return Vector2(-x, -y)


## View for a constellation: tangent point (offset from the figure's centre for harder
## levels) and the pixel scale that fits the whole figure into the given size.
func view_for(c: Dictionary, area: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var ra0 := float(c.center[0])
	var dec0 := float(c.center[1])
	var off := float(rules().offset) * float(c.radius)
	if off > 0.0:
		var ang := rng.randf() * TAU
		dec0 = clampf(dec0 + off * sin(ang), -80.0, 85.0)
		ra0 += off * cos(ang) / maxf(cos(deg_to_rad(dec0)), 0.2)
	# Fit every member star, with a margin.
	var ext := Vector2.ZERO
	for h in members(c):
		var s: Array = stars[h]
		var p: Variant = project(s[0], s[1], ra0, dec0)
		if p != null:
			ext = ext.max((p as Vector2).abs())
	var scale := minf(area.x * 0.44 / maxf(ext.x, 0.01), area.y * 0.42 / maxf(ext.y, 0.01))
	# Small figures: keep at least MIN_FIELD degrees from the middle to the top edge, so the
	# sky around them does not look empty.
	scale = minf(scale, area.y * 0.5 / tan(deg_to_rad(MIN_FIELD)))
	return {"ra0": ra0, "dec0": dec0, "scale": scale}


## Star radius in pixels by magnitude.
static func star_radius(mag: float) -> float:
	return clampf(2.0 + (5.0 - mag) * 2.1, 1.4, 14.0)


## Colour from the B-V colour index (blue-white ... orange-red).
static func star_color(bv: float) -> Color:
	var t := clampf((bv + 0.2) / 1.9, 0.0, 1.0)
	var blue := Color(0.7, 0.8, 1.0)
	var white := Color(1.0, 0.98, 0.94)
	var red := Color(1.0, 0.68, 0.42)
	return blue.lerp(white, t / 0.35) if t < 0.35 else white.lerp(red, (t - 0.35) / 0.65)


## Points for one traced constellation.
func round_points(lines: int, wrong: int, seconds: float) -> int:
	var base := lines * POINTS_PER_LINE - wrong * WRONG_PENALTY + int(maxf(0.0, 240.0 - seconds * 3.0))
	return int(maxi(50, base) * float(rules().mult))


## Stars from the share of wrong connections and the time per line.
static func stars_for(total_lines: int, wrong: int, seconds: float) -> int:
	var err := float(wrong) / maxf(total_lines, 1)
	var pace := seconds / maxf(total_lines, 1)
	if err <= 0.15 and pace <= 6.0:
		return 3
	if err <= 0.5 and pace <= 12.0:
		return 2
	return 1
