## Initial positions and velocities of the stars of a galaxy, bit-identical to start() in
## galaxy_stars.gdshader: the shader's integer hash is ported here (64-bit ints masked to
## 32 bits), so CPU star i is exactly GPU particle i. Stars are placed in the galaxy's own
## frame (disk in the xz plane) and move with the velocities of a lookup table (the measured
## rotation curve in act 1, the galaxy's own model curve in act 2).
class_name StarSampler
extends RefCounted

const MASK := 0xFFFFFFFF
const VTAB := 128
const BULGE := 0
const DISK := 1
const GAS := 2


## uint32 multiply without overflowing GDScript's signed 64-bit ints.
static func mul32(x: int, c: int) -> int:
	var lo := (x * (c & 0xFFFF)) & MASK
	var hi := ((x * (c >> 16)) & 0xFFFF) << 16
	return (lo + hi) & MASK


static func hash_u(x: int) -> int:
	x &= MASK
	x ^= x >> 16
	x = mul32(x, 2146121005)
	x ^= x >> 15
	x = mul32(x, 2221713035)
	x ^= x >> 16
	return x


static func seed_for(index: int) -> int:
	return (mul32(index & MASK, 747796405) + 2891336453) & MASK


## Galaxy description shared with the shader:
##   f_bulge, f_gas (fractions of the particles), r_max (outermost disk star), a_bulge,
##   r_disk, r_gas (exponential scale lengths), spin (+1/-1), vtab (VTAB circular speeds from
##   r = 0 to vtab_rmax).
static func sample(index: int, g: Dictionary) -> Array:
	var s := hash_u(seed_for(index))
	var u := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	for i in 5:
		u[i] = float(s) / 4294967295.0
		s = hash_u(s)
	var kind := DISK
	if u[0] < float(g.f_bulge):
		kind = BULGE
	elif u[0] < float(g.f_bulge) + float(g.f_gas):
		kind = GAS
	var pos: Vector3
	var vel: Vector3
	if kind == BULGE:
		var a := float(g.a_bulge)
		var rmax := 4.0 * a
		var umax := pow(rmax / (rmax + a), 2.0)
		var q := sqrt(u[1] * umax)
		var r := a * q / (1.0 - q)
		var ct := 2.0 * u[2] - 1.0
		var st := sqrt(maxf(0.0, 1.0 - ct * ct))
		var ph := TAU * u[3]
		var n := Vector3(st * cos(ph), ct, st * sin(ph))
		pos = n * r
		# Circular orbit in a random plane through the centre.
		var e1 := n.cross(Vector3.UP if absf(ct) < 0.9 else Vector3.RIGHT).normalized()
		var e2 := n.cross(e1)
		var psi := TAU * u[4]
		vel = (e1 * cos(psi) + e2 * sin(psi)) * vtab_at(g, r)
	else:
		var sc := float(g.r_disk) if kind == DISK else float(g.r_gas)
		var rmax := float(g.r_max)
		var rr := -sc * log(1.0 - u[1] * (1.0 - exp(-rmax / sc)))
		var th := TAU * u[2]
		var zh := sc * (0.06 if kind == DISK else 0.025)
		var h := (2.0 * u[3] - 1.0) * zh
		pos = Vector3(rr * cos(th), h, rr * sin(th))
		# A little random motion around the circular orbit (epicycle), each star at its own
		# phase of it: 5 % radial, 3.5 % along the orbit (ratio of a flat rotation curve).
		# All stars at the same phase would swing in step and draw rings that are not there.
		var ph := TAU * u[4]
		var vc := vtab_at(g, rr)
		vel = Vector3(-sin(th), 0.0, cos(th)) * (vc * (1.0 + 0.035 * cos(ph)) * float(g.spin)) \
			+ Vector3(cos(th), 0.0, sin(th)) * (vc * 0.05 * sin(ph))
	return [pos, vel, kind]


static func vtab_at(g: Dictionary, r: float) -> float:
	var tab: PackedFloat32Array = g.vtab
	var f := clampf(r / float(g.vtab_rmax) * (VTAB - 1), 0.0, VTAB - 1.001)
	var i := int(f)
	return lerpf(tab[i], tab[i + 1], f - i)
