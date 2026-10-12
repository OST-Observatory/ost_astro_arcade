## Beyond the planets, for the "journey outwards" of the solar-system explorer:
##   Oort cloud  – presumed shell of icy bodies, 2,000–100,000 AU (inner part flattened);
##                 drawn schematically, it has never been observed directly
##   nearby stars – real positions (J2000 RA/Dec) and distances of the nearest and of some
##                 famous bright stars
##   Milky Way    – schematic model: bar, four spiral arms (log spirals, pitch 12°) and the
##                 Orion spur with the Sun 8.2 kpc from the centre, tilted to the ecliptic as
##                 in the sky (galactic pole and centre from the IAU definition, J2000)
## Positions are heliocentric ecliptic AU like everything else; the nodes live under the
## view's heliocentric root (scene axes, see Kepler.to_godot).
class_name DeepSpace
extends Node3D

const LY := 63241.077          # AU per light-year
const KPC := 206264806.2       # AU per kiloparsec
const R0_KPC := 8.2            # Sun – galactic centre
const ARM_PITCH := 12.0        # deg
const ARMS := ["scutum", "outer", "perseus", "sagittarius"]   # k = 0..3, see arm_point()
## id, name (de, en, es), RA deg, Dec deg, light-years, class (M, K, G, F, A, giant), own text
const STARS := [
	["proxima", ["Proxima Centauri", "Proxima Centauri", "Próxima Centauri"], 217.4289, -62.6795, 4.25, "M", true],
	["alphacen", ["Alpha Centauri A und B", "Alpha Centauri A and B", "Alfa Centauri A y B"], 219.9021, -60.8340, 4.37, "G", true],
	["barnard", ["Barnards Pfeilstern", "Barnard's Star", "Estrella de Barnard"], 269.4521, 4.6934, 5.96, "M", true],
	["wolf359", ["Wolf 359", "Wolf 359", "Wolf 359"], 164.1203, 7.0147, 7.86, "M", false],
	["lalande", ["Lalande 21185", "Lalande 21185", "Lalande 21185"], 165.8342, 35.9699, 8.31, "M", false],
	["sirius", ["Sirius", "Sirius", "Sirio"], 101.2872, -16.7161, 8.60, "A", true],
	["epseri", ["Epsilon Eridani", "Epsilon Eridani", "Épsilon Eridani"], 53.2327, -9.4583, 10.47, "K", true],
	["ross128", ["Ross 128", "Ross 128", "Ross 128"], 176.9370, 0.8045, 11.0, "M", false],
	["61cyg", ["61 Cygni", "61 Cygni", "61 Cygni"], 316.7248, 38.7495, 11.40, "K", true],
	["procyon", ["Prokyon", "Procyon", "Proción"], 114.8255, 5.2250, 11.46, "F", true],
	["tauceti", ["Tau Ceti", "Tau Ceti", "Tau Ceti"], 26.0170, -15.9375, 11.91, "G", true],
	["altair", ["Altair", "Altair", "Altair"], 297.6958, 8.8683, 16.73, "A", true],
	["vega", ["Wega", "Vega", "Vega"], 279.2347, 38.7837, 25.04, "A", true],
	["fomalhaut", ["Fomalhaut", "Fomalhaut", "Fomalhaut"], 344.4127, -29.6222, 25.13, "A", true],
	["arcturus", ["Arktur", "Arcturus", "Arturo"], 213.9153, 19.1824, 36.7, "giant", true],
]
const STAR_COLORS := {"M": Color(1.0, 0.55, 0.4), "K": Color(1.0, 0.75, 0.5), "G": Color(1.0, 0.93, 0.78),
	"F": Color(1.0, 0.97, 0.92), "A": Color(0.8, 0.87, 1.0), "giant": Color(1.0, 0.7, 0.45)}
const GC_RA := 266.40500       # Sgr A*
const GC_DEC := -28.93617
const NGP_RA := 192.85948
const NGP_DEC := 27.12825

var oort_alpha := 0.0
var star_alpha := 0.0
var galaxy_alpha := 0.0
var _oort: MultiMeshInstance3D
var _stars: MultiMeshInstance3D
var _galaxy: MultiMeshInstance3D


# --- coordinates -------------------------------------------------------------------------------

static func _eq_unit(ra: float, dec: float) -> Vector3:
	var a := deg_to_rad(ra)
	var d := deg_to_rad(dec)
	return Rotation.eq_to_ecl(Vector3(cos(d) * cos(a), cos(d) * sin(a), sin(d)))


## Galactic frame in ecliptic axes: x towards the centre, y towards longitude 90°, z north pole.
static func galactic_basis() -> Basis:
	var z := _eq_unit(NGP_RA, NGP_DEC)
	var x := _eq_unit(GC_RA, GC_DEC)
	x = (x - z * x.dot(z)).normalized()
	return Basis(x, z.cross(x), z)


static func gc_helio() -> Vector3:
	return galactic_basis().x * (R0_KPC * KPC)


## A point given in galactocentric kpc (θ measured from x towards y; the Sun at θ = 180°).
static func galactic_point(r_kpc: float, theta: float, z_kpc := 0.0) -> Vector3:
	var b := galactic_basis()
	return gc_helio() + (b.x * cos(theta) * r_kpc + b.y * sin(theta) * r_kpc + b.z * z_kpc) * KPC


## Spiral arm k at radius r (kpc): trailing log spirals (the Galaxy turns clockwise seen from
## the north pole), the arms crossing the Sun's direction at 5.0 (Scutum-Centaurus),
## 7.0 (Sagittarius), 9.8 (Perseus) and 13.7 kpc (outer arm).
static func arm_theta(k: int, r_kpc: float) -> float:
	return PI + k * PI / 2.0 + log(r_kpc / 5.0) / tan(deg_to_rad(ARM_PITCH))


static func star_index(id: String) -> int:
	for i in STARS.size():
		if STARS[i][0] == id:
			return i
	return -1


static func star_helio(i: int) -> Vector3:
	var s: Array = STARS[i]
	return _eq_unit(float(s[2]), float(s[3])) * float(s[4]) * LY


static func star_name(i: int) -> String:
	var names: Array = STARS[i][1]
	return str(names[maxi(0, ["de", "en", "es"].find(TranslationServer.get_locale().substr(0, 2)))])


## Ids handled here: "deep:oort", "deep:gc" and "deep:<star>".
static func has(id: String) -> bool:
	if not id.begins_with("deep:"):
		return false
	var k := id.substr(5)
	return k in ["oort", "gc"] or star_index(k) >= 0


static func helio(id: String) -> Vector3:
	var k := id.substr(5)
	if k == "gc":
		return gc_helio()
	if k == "oort":
		return Vector3(0.6, 0.0, 0.8) * 60000.0   # a spot in the cloud for its name
	return star_helio(star_index(k))


static func display_name(id: String) -> String:
	var k := id.substr(5)
	if k == "gc" or k == "oort":
		return TranslationServer.translate("SOL_DEEP_" + k.to_upper())
	return star_name(star_index(k))


# --- building ----------------------------------------------------------------------------------

func setup(galaxy_points: int) -> void:
	_oort = _make_points(_oort_points(), 1.3)
	_stars = _make_points(_star_points(), 4.0)
	_galaxy = _make_points(_galaxy_points(galaxy_points), 1.4)


func _make_points(pts: Array, px: float) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = pts.size()
	for k in pts.size():
		mm.set_instance_transform(k, Transform3D(Basis(), Kepler.to_godot(pts[k][0])))
		mm.set_instance_color(k, pts[k][1])
		mm.set_instance_custom_data(k, Color(float(pts[k][2]), 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://games/solar/scene/points.gdshader")
	mat.set_shader_parameter("px", px)
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3.ONE * -1e11, Vector3.ONE * 2e11)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## [position AU, colour, size]
static func _oort_points() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1950   # Oort's paper
	var out := []
	for i in 5000:
		var inner := i < 1500
		var r := (2000.0 * pow(10.0, rng.randf())) if inner else (20000.0 * pow(5.0, rng.randf()))
		var lon := rng.randf() * TAU
		# The inner (Hills) cloud is flattened towards the ecliptic, the outer cloud is round.
		var s := (rng.randf() * 2.0 - 1.0) * (0.55 if inner else 1.0)
		var c := sqrt(1.0 - s * s)
		out.append([Vector3(c * cos(lon), c * sin(lon), s) * r, Color(0.6, 0.75, 1.0, 0.45), 1.0])
	return out


static func _star_points() -> Array:
	var out := []
	for i in STARS.size():
		out.append([star_helio(i), Color(STAR_COLORS[STARS[i][5]], 1.0), 1.0])
	return out


static func _galaxy_points(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 26700
	var out := []
	var bar := deg_to_rad(153.0)   # near end of the bar at positive longitude, 27° from the Sun–centre line
	var arm_weights := [0.32, 0.18, 0.32, 0.18]   # Scutum-Centaurus and Perseus are the major arms
	for i in n:
		var u := rng.randf()
		var r: float
		var theta: float
		var z: float
		var col: Color
		var size := 1.0
		if u < 0.16:
			var along := rng.randfn(0.0, 1.7)
			var across := rng.randfn(0.0, 0.6)
			r = sqrt(along * along + across * across)
			theta = bar + atan2(across, along)
			z = rng.randfn(0.0, 0.35 * exp(-r / 3.0) + 0.1)
			col = Color(1.0, 0.82, 0.55, 0.35)
		elif u < 0.83:
			var pick := rng.randf()
			var k := 0
			var acc := 0.0
			for j in 4:
				acc += float(arm_weights[j])
				if pick <= acc:
					k = j
					break
			r = 3.5 - 3.2 * log(1.0 - rng.randf() * (1.0 - exp(-12.5 / 3.2)))
			theta = arm_theta(k, r) + rng.randfn(0.0, 0.025)
			r += rng.randfn(0.0, 0.18 + 0.015 * r)
			z = rng.randfn(0.0, 0.1)
			var hii := rng.randf() < 0.12
			col = Color(1.0, 0.45, 0.6, 0.55) if hii else Color(0.72, 0.82, 1.0, 0.3)
			size = 1.5 if hii else 1.0
		elif u < 0.845:
			# Orion spur: a short, faint arm piece through the Sun.
			theta = PI + rng.randf_range(-0.35, 0.3)
			r = R0_KPC * exp((theta - PI) * tan(deg_to_rad(12.0))) + rng.randfn(0.0, 0.25)
			z = rng.randfn(0.0, 0.08)
			col = Color(0.72, 0.82, 1.0, 0.3)
		else:
			r = -3.5 * log(1.0 - rng.randf() * (1.0 - exp(-16.0 / 3.5)))
			theta = rng.randf() * TAU
			z = rng.randfn(0.0, 0.2)
			col = Color(0.95, 0.88, 0.78, 0.18)
		out.append([galactic_point(r, theta, z), col, size])
	return out


# --- per frame ---------------------------------------------------------------------------------

## sun_d: camera distance from the Sun (AU). Each part shows on its own scale.
func update(sun_d: float, on: bool) -> void:
	oort_alpha = smoothstep(1500.0, 8000.0, sun_d) * (1.0 - smoothstep(1e6, 3e6, sun_d)) if on else 0.0
	star_alpha = smoothstep(3e4, 1.2e5, sun_d) * (1.0 - smoothstep(1e8, 4e8, sun_d)) if on else 0.0
	galaxy_alpha = smoothstep(1.5e8, 6e8, sun_d) if on else 0.0
	for p in [[_oort, oort_alpha], [_stars, star_alpha], [_galaxy, galaxy_alpha]]:
		var mi: MultiMeshInstance3D = p[0]
		mi.visible = float(p[1]) > 0.01
		(mi.material_override as ShaderMaterial).set_shader_parameter("alpha", p[1])


## Labels to show: [id or "", text, heliocentric position, colour, pickable].
func label_items() -> Array:
	var out := []
	if oort_alpha > 0.4:
		out.append(["deep:oort", display_name("deep:oort"), helio("deep:oort"), Color(0.7, 0.82, 1.0), true])
	if star_alpha > 0.4:
		for i in STARS.size():
			out.append(["deep:" + str(STARS[i][0]), star_name(i), star_helio(i), Color(STAR_COLORS[STARS[i][5]]).lightened(0.2), true])
	if galaxy_alpha > 0.4:
		out.append(["deep:gc", display_name("deep:gc"), gc_helio(), Color(1.0, 0.85, 0.6), true])
		var at := {"scutum": 7.5, "outer": 15.0, "perseus": 12.0, "sagittarius": 9.0}
		for k in ARMS.size():
			var r: float = at[ARMS[k]]
			out.append(["", TranslationServer.translate("SOL_ARM_" + str(ARMS[k]).to_upper()),
				galactic_point(r, arm_theta(k, r)), Color(0.75, 0.85, 1.0, 0.8), false])
		out.append(["", TranslationServer.translate("SOL_ARM_ORION"), galactic_point(R0_KPC * 1.06, PI + 0.3),
			Color(0.75, 0.85, 1.0, 0.8), false])
	return out
