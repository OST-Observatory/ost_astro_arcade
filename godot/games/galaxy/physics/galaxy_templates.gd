## The galaxies to rebuild, with their measured rotation curves (data pipeline:
## tools/galaxy/build_rotation_curves.py), the reference mass model, the look of the star
## populations and the knob steps per difficulty. Also the partner galaxies for collisions.
class_name GalaxyTemplates
extends RefCounted

const DATA := "res://assets/data/galaxy/rotation_curves.json"
const COMPONENTS := ["bh", "stars", "gas", "halo"]

## Knob values per difficulty, as factors: bh on the galaxy's typical black hole (BH_TYPICAL),
## stars and gas on the reference mass, halo on the halo mass (v_halo^2). Pros get sliders
## (PRO_RANGE), plus the halo core radius.
const STEPS := {
	"explorer": {"bh": [0.0, 1.0, 100.0], "stars": [0.0, 0.5, 1.0, 2.0], "gas": [0.0, 0.5, 1.0, 2.0],
		"halo": [0.0, 0.5, 1.0, 1.5]},
	"researcher": {"bh": [0.0, 0.1, 1.0, 10.0, 100.0], "stars": [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0],
		"gas": [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0], "halo": [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5]},
}
const PRO_RANGE := {"bh": [0.0, 100.0], "stars": [0.0, 2.5], "gas": [0.0, 2.5], "halo": [0.0, 2.0], "core": [0.25, 4.0]}
## Typical central black hole (Msun): Sgr A* for the Milky Way; small late-type spirals and
## dwarfs host much lighter ones (if any).
const BH_TYPICAL := {"milkyway": 4.3e6, "ngc3198": 1e6, "ddo154": 1e4}

## Look of each target: particle fractions (bulge, gas), colours, display size.
const LOOK := {
	"milkyway": {"f_bulge": 0.16, "f_gas": 0.12, "core": Color(1.0, 0.84, 0.6), "edge": Color(0.55, 0.7, 1.0)},
	"ngc3198": {"f_bulge": 0.0, "f_gas": 0.3, "core": Color(1.0, 0.86, 0.66), "edge": Color(0.5, 0.72, 1.0)},
	"ddo154": {"f_bulge": 0.0, "f_gas": 0.55, "core": Color(0.85, 0.85, 1.0), "edge": Color(0.45, 0.62, 1.0)},
}

static var _cache := {}


static func targets() -> Array:
	if _cache.is_empty():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		for t in d.targets:
			_cache[t.id] = _prepare(t)
	return _cache.values()


static func get_target(id: String) -> Dictionary:
	targets()
	return _cache.get(id, _cache.values()[0])


static func _prepare(t: Dictionary) -> Dictionary:
	var out := t.duplicate(true)
	out.reference = GalaxyPotential.from_physical(t.model)
	# Data points in model units: [R, v, err].
	var pts := []
	for p in t.data:
		pts.append([float(p[0]) / GalaxyPotential.KPC, float(p[1]) / GalaxyPotential.KMS,
			float(p[2]) / GalaxyPotential.KMS])
	out.points = pts
	out.r_last = float(pts[pts.size() - 1][0])
	out.look = LOOK.get(t.id, LOOK.milkyway)
	return out


## Builds the player's galaxy from knob values (see STEPS); shapes stay those of the target.
static func build(t: Dictionary, knobs: Dictionary) -> GalaxyPotential:
	var ref: GalaxyPotential = t.reference
	var p := ref.copy()
	p.m_bh = float(knobs.get("bh", 0.0)) * float(BH_TYPICAL.get(t.id, 1e6)) / GalaxyPotential.MSUN
	var fs := float(knobs.get("stars", 0.0))
	p.m_bulge = ref.m_bulge * fs
	p.m_disk = ref.m_disk * fs
	p.m_gas = ref.m_gas * float(knobs.get("gas", 0.0))
	p.v_halo = ref.v_halo * sqrt(maxf(float(knobs.get("halo", 0.0)), 0.0))
	p.r_core = ref.r_core * float(knobs.get("core", 1.0))
	return p


## The knobs that reproduce the reference model.
static func reference_knobs(t: Dictionary) -> Dictionary:
	return {"bh": 1.0, "stars": 1.0, "gas": 1.0, "halo": 1.0, "core": 1.0}


## Galaxy description for StarSampler / the shader. `vtab` holds circular speeds from r = 0 to
## vtab_rmax: the measured curve where there is data (act 1) or the model curve (act 2).
## blend (act 1 only): 0 = the measured speeds, 1 = the speeds of the player's own model. The
## better the model fits, the closer the stars start to its speeds, otherwise the few per cent
## left between model and data make all stars at one radius swing in step (rings that would
## not be there in a galaxy in balance).
static func star_setup(t: Dictionary, pot: GalaxyPotential, measured: bool, spin := 1.0, blend := 0.0) -> Dictionary:
	var ref: GalaxyPotential = t.reference
	var rmax := float(t.r_last)
	var vtab_rmax := rmax * 1.25
	var tab := PackedFloat32Array()
	tab.resize(StarSampler.VTAB)
	for i in StarSampler.VTAB:
		var r := vtab_rmax * i / float(StarSampler.VTAB - 1)
		tab[i] = lerpf(measured_v(t, r), pot.v_circ(r), blend) if measured else pot.v_circ(r)
	return {"f_bulge": t.look.f_bulge, "f_gas": t.look.f_gas, "r_max": rmax, "a_bulge": maxf(ref.a_bulge, 0.05),
		"r_disk": maxf(ref.a_disk * 0.9, 0.1), "r_gas": maxf(ref.a_gas * 0.6, 0.15), "spin": spin,
		"vtab": tab, "vtab_rmax": vtab_rmax}


## Measured circular speed at radius r (model units): the data where available, the reference
## model inside the first and beyond the last data point.
static func measured_v(t: Dictionary, r: float) -> float:
	var pts: Array = t.points
	if r <= float(pts[0][0]) or r >= float(pts[pts.size() - 1][0]):
		var ref: GalaxyPotential = t.reference
		return ref.v_circ(maxf(r, 1e-4))
	for i in range(1, pts.size()):
		if r <= float(pts[i][0]):
			var f := (r - float(pts[i - 1][0])) / (float(pts[i][0]) - float(pts[i - 1][0]))
			return lerpf(float(pts[i - 1][1]), float(pts[i][1]), f)
	return float(pts[pts.size() - 1][1])


## Partner galaxies for collisions (besides galaxies saved by visitors): [id, target].
const PARTNERS := [["dwarf", "ddo154"], ["spiral", "ngc3198"], ["twin", "milkyway"]]


static var _thumbs := {}


## A small picture of a galaxy (seen at an angle), drawn from the same star distribution as
## the simulation; cached per target.
static func thumbnail(t: Dictionary, size := 220) -> ImageTexture:
	var key := "%s_%d" % [t.id, size]
	if _thumbs.has(key):
		return _thumbs[key]
	var setup := star_setup(t, t.reference, false)
	var acc := PackedFloat32Array()
	acc.resize(size * size * 3)
	# Same scale for all galaxies, so a dwarf looks small next to the Milky Way.
	var biggest := 0.0
	for other in targets():
		biggest = maxf(biggest, float(other.r_last))
	var scale := size * 0.46 / biggest
	var core: Color = t.look.core
	var edge: Color = t.look.edge
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(55.0))
	for i in 12000:
		var s := StarSampler.sample(i, setup)
		var p: Vector3 = tilt * (s[0] as Vector3)
		var px := int(size * 0.5 + p.x * scale)
		var py := int(size * 0.5 + p.y * scale)
		if px < 0 or py < 0 or px >= size or py >= size:
			continue
		var f := clampf(Vector2(s[0].x, s[0].z).length() / float(t.r_last), 0.0, 1.0)
		var c := core.lerp(edge, sqrt(f))
		var o := (py * size + px) * 3
		acc[o] += c.r
		acc[o + 1] += c.g
		acc[o + 2] += c.b
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var o := (y * size + x) * 3
			# Soft tone curve: faint outskirts stay visible, the centre does not burn out.
			img.set_pixel(x, y, Color(1.0 - exp(-acc[o] * 0.6), 1.0 - exp(-acc[o + 1] * 0.6), 1.0 - exp(-acc[o + 2] * 0.6)))
	var tex := ImageTexture.create_from_image(img)
	_thumbs[key] = tex
	return tex
