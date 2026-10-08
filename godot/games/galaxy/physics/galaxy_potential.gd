## Mass model of one galaxy, built from the pieces the player adds: a supermassive black hole,
## a stellar bulge (Hernquist), a stellar disk and a gas disk (Miyamoto–Nagai) and a dark
## matter halo (cored logarithmic, cut off at r_trunc). Formulas match
## tools/galaxy/build_rotation_curves.py and the GPU shader (galaxy_potential.gdshaderinc).
## Model units: G = 1, mass 1e11 Msun, length 3 kpc, velocity 378.6 km/s, time 7.75 Myr.
## The disk lies in the local xz plane (local y = disk axis); `basis` turns it into the world.
class_name GalaxyPotential
extends RefCounted

const KPC := 3.0           # kpc per length unit
const MSUN := 1e11         # solar masses per mass unit
const KMS := 378.64        # km/s per velocity unit (sqrt(G M / L))
const MYR := 7.75          # million years per time unit
const BH_SOFT := 0.01      # softening of the black hole (30 pc)
const UNIFORMS := 16       # floats per galaxy in to_uniforms()

var m_bh := 0.0
var m_bulge := 0.0
var a_bulge := 0.2
var m_disk := 0.0
var a_disk := 1.0
var b_disk := 0.1
var m_gas := 0.0
var a_gas := 2.0
var b_gas := 0.2
var v_halo := 0.0
var r_core := 1.0
var r_trunc := 30.0
var basis := Basis.IDENTITY


## From a model in physical units (kpc, km/s, Msun) as written by the data pipeline.
static func from_physical(m: Dictionary) -> GalaxyPotential:
	var p := GalaxyPotential.new()
	p.m_bh = float(m.get("bh", 0.0)) / MSUN
	p.m_bulge = float(m.bulge.m) / MSUN
	p.a_bulge = float(m.bulge.a) / KPC
	p.m_disk = float(m.disk.m) / MSUN
	p.a_disk = float(m.disk.a) / KPC
	p.b_disk = float(m.disk.b) / KPC
	p.m_gas = float(m.gas.m) / MSUN
	p.a_gas = float(m.gas.a) / KPC
	p.b_gas = float(m.gas.b) / KPC
	p.v_halo = float(m.halo.vh) / KMS
	p.r_core = float(m.halo.rc) / KPC
	p.r_trunc = float(m.halo.rt) / KPC
	return p


func copy() -> GalaxyPotential:
	var p := GalaxyPotential.new()
	for k in ["m_bh", "m_bulge", "a_bulge", "m_disk", "a_disk", "b_disk", "m_gas", "a_gas", "b_gas",
			"v_halo", "r_core", "r_trunc"]:
		p.set(k, get(k))
	p.basis = basis
	return p


func to_dict() -> Dictionary:
	return {"m_bh": m_bh, "m_bulge": m_bulge, "a_bulge": a_bulge, "m_disk": m_disk, "a_disk": a_disk,
		"b_disk": b_disk, "m_gas": m_gas, "a_gas": a_gas, "b_gas": b_gas, "v_halo": v_halo,
		"r_core": r_core, "r_trunc": r_trunc}


static func from_dict(d: Dictionary) -> GalaxyPotential:
	var p := GalaxyPotential.new()
	for k in d:
		p.set(k, float(d[k]))
	return p


# --- forces --------------------------------------------------------------------------------

## Acceleration at a position given in the galaxy's own frame (disk in the xz plane).
func accel_local(p: Vector3) -> Vector3:
	var a := Vector3.ZERO
	var r2 := p.length_squared()
	var r := sqrt(r2)
	if m_bh > 0.0:
		var s2 := r2 + BH_SOFT * BH_SOFT
		a -= p * (m_bh / (s2 * sqrt(s2)))
	if m_bulge > 0.0 and r > 1e-9:
		a -= p * (m_bulge / (r * (r + a_bulge) * (r + a_bulge)))
	a += _mn_accel(p, m_disk, a_disk, b_disk)
	a += _mn_accel(p, m_gas, a_gas, b_gas)
	if v_halo > 0.0:
		if r < r_trunc:
			a -= p * (v_halo * v_halo / (r2 + r_core * r_core))
		else:
			a -= p * (_halo_mass_trunc() / (r2 * r))
	return a


## Acceleration at a position relative to the galaxy centre, in world orientation.
func accel(rel: Vector3) -> Vector3:
	return basis * accel_local(basis.transposed() * rel)


static func _mn_accel(p: Vector3, m: float, a: float, b: float) -> Vector3:
	if m <= 0.0:
		return Vector3.ZERO
	var s := sqrt(p.y * p.y + b * b)
	var d2 := p.x * p.x + p.z * p.z + (a + s) * (a + s)
	var d3 := d2 * sqrt(d2)
	return Vector3(-m * p.x / d3, -m * p.y * (a + s) / (s * d3), -m * p.z / d3)


func _halo_mass_trunc() -> float:
	return v_halo * v_halo * r_trunc * r_trunc * r_trunc / (r_trunc * r_trunc + r_core * r_core)


# --- rotation curve --------------------------------------------------------------------------

## Squared circular velocity of each component at radius R in the disk plane.
func v2_parts(rr: float) -> Dictionary:
	var r2 := rr * rr
	var out := {}
	out.bh = m_bh * r2 / pow(r2 + BH_SOFT * BH_SOFT, 1.5)
	out.bulge = m_bulge * rr / ((rr + a_bulge) * (rr + a_bulge))
	out.disk = m_disk * r2 / pow(r2 + (a_disk + b_disk) * (a_disk + b_disk), 1.5)
	out.gas = m_gas * r2 / pow(r2 + (a_gas + b_gas) * (a_gas + b_gas), 1.5)
	if rr < r_trunc:
		out.halo = v_halo * v_halo * r2 / (r2 + r_core * r_core)
	else:
		out.halo = _halo_mass_trunc() / rr
	return out


func v_circ(rr: float) -> float:
	var s := 0.0
	for v in v2_parts(rr).values():
		s += v
	return sqrt(maxf(s, 0.0))


## Mass inside radius r, treating every component as round (good enough between galaxies).
func mass_within(r: float) -> float:
	var s := 0.0
	for v in v2_parts(maxf(r, 1e-6)).values():
		s += v
	return s * r


func total_mass() -> float:
	return m_bh + m_bulge + m_disk + m_gas + _halo_mass_trunc()


func halo_density(r: float) -> float:
	if r >= r_trunc or v_halo <= 0.0:
		return 0.0
	var c2 := r_core * r_core
	return v_halo * v_halo * (3.0 * c2 + r * r) / (4.0 * PI * (c2 + r * r) * (c2 + r * r))


## Packed parameters for the GPU shader (UNIFORMS floats).
func to_uniforms() -> PackedFloat32Array:
	return PackedFloat32Array([m_bh, m_bulge, a_bulge, m_disk, a_disk, b_disk, m_gas, a_gas, b_gas,
		v_halo, r_core, r_trunc, _halo_mass_trunc(), 0.0, 0.0, 0.0])
