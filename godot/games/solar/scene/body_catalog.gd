## The named bodies of the solar-system explorer (assets/data/solar/bodies.json): names and
## texts per language, physical data and heliocentric positions at any date – planets from
## Kepler.PLANETS, moons from Moons, dwarf planets and comets from their SBDB elements.
## Positions: heliocentric ecliptic J2000 in AU (Kepler.to_godot() for scene axes).
class_name BodyCatalog
extends RefCounted

const PATH := "res://assets/data/solar/bodies.json"
const TEXTURES := "res://assets/solar/textures/textures.json"
const AU_KM := 149597870.7
const EARTH_MASS := 5.972e24
## Colour of the dot, label and orbit; also the sphere colour where there is no texture.
const COLORS := {
	"sun": Color("ffd27a"), "mercury": Color("b5aca4"), "venus": Color("e8cfa0"), "earth": Color("6fb7ff"),
	"mars": Color("e2725b"), "jupiter": Color("d8b48a"), "saturn": Color("e6cf98"), "uranus": Color("9fdde4"),
	"neptune": Color("5b7fe0"), "moon": Color("c9c9c9"), "io": Color("e8d36a"), "europa": Color("d9c7a8"),
	"ganymede": Color("a39a8c"), "callisto": Color("7d7368"), "titan": Color("e0a050"),
	"ceres": Color("9e9890"), "pluto": Color("d8c3a5"), "haumea": Color("e8e8ee"), "makemake": Color("c98e6a"),
	"eris": Color("eeeeee"), "sedna": Color("b4553f"), "halley": Color("bfe3ff"), "67p": Color("bfe3ff"),
	"halebopp": Color("bfe3ff"), "encke": Color("bfe3ff"),
}
## Period (days) used to draw the orbit of the Moon (Meeus' orbit is not a closed ellipse).
const MOON_MONTH := 27.321661

static var _bodies := {}
static var _order: Array = []
static var _textures := {}


static func _load() -> void:
	if not _bodies.is_empty():
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for b in data.bodies:
		_bodies[b.id] = b
		_order.append(b.id)
	if FileAccess.file_exists(TEXTURES):
		_textures = JSON.parse_string(FileAccess.get_file_as_string(TEXTURES))


static func ids() -> Array:
	_load()
	return _order


static func has(id: String) -> bool:
	_load()
	return _bodies.has(id)


static func entry(id: String) -> Dictionary:
	_load()
	return _bodies.get(id, {})


static func kind(id: String) -> String:
	return str(entry(id).get("kind", ""))


static func parent(id: String) -> String:
	return str(entry(id).get("parent", ""))


static func _lang() -> String:
	return TranslationServer.get_locale().substr(0, 2)


static func _text(id: String, field: String) -> String:
	var d: Dictionary = entry(id).get(field, {})
	return str(d.get(_lang(), d.get("en", "")))


static func display_name(id: String) -> String:
	return _text(id, "name")


static func type_text(id: String) -> String:
	return _text(id, "type")


static func description(id: String) -> String:
	return _text(id, "text")


static func radius_km(id: String) -> float:
	return float(entry(id).get("radius_km", 1.0))


static func radius_au(id: String) -> float:
	return radius_km(id) / AU_KM


static func mass_kg(id: String) -> float:
	var m: Variant = entry(id).get("mass_kg")
	return float(m) if m != null else 0.0


static func color(id: String) -> Color:
	return COLORS.get(id, Color(0.8, 0.8, 0.8))


static func texture_path(id: String) -> String:
	_load()
	return str(_textures[id].file) if _textures.has(id) else ""


## Orbital elements (deg, AU) of a body that circles the Sun, at a date.
static func elements(id: String, jd: float) -> Dictionary:
	if Kepler.PLANETS.has(id):
		return Kepler.planet_elements(id, jd)
	var el: Dictionary = entry(id).get("elements", {})
	if el.is_empty():
		return {}
	return {"a": float(el.a), "e": float(el.e), "i": float(el.i), "node": float(el.node), "w": float(el.w),
		"M": float(el.M) + float(el.n) * (jd - float(el.epoch))}


## Heliocentric ecliptic position (AU).
static func helio(id: String, jd: float) -> Vector3:
	if id == "sun" or id == "":
		return Vector3.ZERO
	if Kepler.PLANETS.has(id):
		return Kepler.planet_position(id, jd)
	if kind(id) == "moon":
		return helio(parent(id), jd) + Moons.offset(id, jd)
	var el := elements(id, jd)
	return Kepler.position(el.a, el.e, el.i, el.node, el.w, el.M)


## Orbit as a polyline: heliocentric for bodies around the Sun, relative to the planet for moons.
static func orbit_points(id: String, jd: float, n := 512) -> PackedVector3Array:
	if kind(id) == "moon":
		var period := MOON_MONTH if id == "moon" else float(Moons.CIRCULAR[id][2])
		var pts := PackedVector3Array()
		for k in n + 1:
			pts.append(Moons.offset(id, jd + period * k / n))
		return pts
	var el := elements(id, jd)
	return Kepler.orbit_points(el.a, el.e, el.i, el.node, el.w, n)


## Orbital period in days (around the Sun, or around the planet for moons).
static func period_days(id: String, jd: float) -> float:
	if kind(id) == "moon":
		return MOON_MONTH if id == "moon" else float(Moons.CIRCULAR[id][2])
	var el := elements(id, jd)
	return Kepler.period_years(float(el.a)) * 365.25 if not el.is_empty() else 0.0
