## Restricted three-body model of a galaxy encounter (after Toomre & Toomre 1972): two
## point-mass cores, each surrounded by a disk of massless test stars. The cores move on a
## bound orbit and slowly spiral together through dynamical friction (that is how real pairs
## like the Antennae merge). Their track is computed once on the CPU; the GPU shader and the
## CPU stars here both follow that same track. The CPU version (a few thousand stars) is used
## for scoring: it projects the stars onto the sky and compares smoothed density maps.
class_name GalaxyModel
extends RefCounted

const G := 1.0
const SOFTENING := 0.5
const CORE_SOFTENING := 1.0
## The cores first come closest at about this time; every run starts at t = 0.
const T_PERI := 50.0
const DISK_RMIN := 1.0
const DISK_RMAX := 7.0
const DISK_SCALE := 2.2
const DT := 0.1
const TRACK_DT := 0.05
## Dynamical friction: drag on the relative motion while the galaxies overlap.
const FRICTION := 0.025
const FRICTION_RADIUS := 7.0
const MAP_SIZE := 32
const MAP_EXTENT := 32.0
## Stars per map cell (for 3000 stars) at which a cell counts as about 63 % lit.
const SATURATION := 4.0

## Default parameters; targets and the player override a subset.
## m2: mass of galaxy 2 (galaxy 1 has mass 1); q: closest approach; e: orbit eccentricity
## (1 = parabola, < 1 bound); incl/node: disk tilt against the orbit plane and its turn about
## the orbit normal (deg); spin: +1 rotates with the orbit, -1 against it; t_after: time
## after closest approach at which the picture is taken; view: yaw/pitch/roll (deg).
const DEFAULTS := {
	"m2": 1.0, "q": 5.0, "e": 0.9,
	"incl1": 0.0, "node1": 0.0, "spin1": 1.0,
	"incl2": 0.0, "node2": 0.0, "spin2": 1.0,
	"t_after": 60.0, "view": Vector3(0.0, 90.0, 0.0),
}


static func with_defaults(p: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	out.merge(p, true)
	return out


static func total_mass(p: Dictionary) -> float:
	return 1.0 + float(p.m2)


static func t_end(p: Dictionary) -> float:
	return T_PERI + float(p.t_after)


## Fraction of the stars that belong to galaxy 2 (brightness roughly follows mass).
static func fraction2(p: Dictionary) -> float:
	var m2 := float(p.m2)
	return m2 / (1.0 + m2)


## Disk size scales with sqrt(mass) (constant surface density).
static func disk_scale(p: Dictionary, g: int) -> float:
	return 1.0 if g == 0 else sqrt(float(p.m2))


static func _rel_accel(gm: float, r: Vector3, v: Vector3, friction: float) -> Vector3:
	var r2 := r.length_squared() + CORE_SOFTENING * CORE_SOFTENING
	var a := -r * (gm / (r2 * sqrt(r2)))
	if friction > 0.0:
		a -= v * (friction * exp(-r.length_squared() / (FRICTION_RADIUS * FRICTION_RADIUS)))
	return a


## Relative position of core 2 (as seen from core 1) every TRACK_DT from t = 0 to t_end.
## The orbit lies in the xz plane: placed at pericentre at T_PERI, integrated backwards
## (without friction) to the start, then forwards with friction.
static func orbit_track(p: Dictionary) -> PackedVector3Array:
	var gm := G * total_mass(p)
	var q := float(p.q)
	var x := Vector3(q, 0.0, 0.0)
	var v := Vector3(0.0, 0.0, sqrt(gm * (1.0 + float(p.e)) / q))
	var back := int(round(T_PERI / TRACK_DT))
	for i in back:  # leapfrog runs backwards with a negative step
		v += _rel_accel(gm, x, v, 0.0) * (-0.5 * TRACK_DT)
		x += v * -TRACK_DT
		v += _rel_accel(gm, x, v, 0.0) * (-0.5 * TRACK_DT)
	var fr := float(p.get("friction", FRICTION))
	var n := int(ceil(t_end(p) / TRACK_DT)) + 2
	var track := PackedVector3Array()
	track.resize(n)
	for i in n:
		track[i] = x
		v += _rel_accel(gm, x, v, fr) * (0.5 * TRACK_DT)
		x += v * TRACK_DT
		v += _rel_accel(gm, x, v, fr) * (0.5 * TRACK_DT)
	return track


static func rel_at(track: PackedVector3Array, t: float) -> Vector3:
	var f := clampf(t / TRACK_DT, 0.0, track.size() - 1.001)
	var i := int(f)
	return track[i].lerp(track[i + 1], f - i)


static func core_positions(p: Dictionary, track: PackedVector3Array, t: float) -> Array[Vector3]:
	var rel := rel_at(track, t)
	var frac := float(p.m2) / total_mass(p)
	return [-rel * frac, rel * (1.0 - frac)]


static func core_velocities(p: Dictionary, track: PackedVector3Array, t: float) -> Array[Vector3]:
	var h := TRACK_DT
	var a := core_positions(p, track, maxf(t - h, 0.0))
	var b := core_positions(p, track, t + h)
	var span := (t + h) - maxf(t - h, 0.0)
	return [(b[0] - a[0]) / span, (b[1] - a[1]) / span]


## Local disk plane (xz) -> world, from the disk's tilt and node angle.
static func disk_basis(p: Dictionary, g: int) -> Basis:
	var incl := deg_to_rad(float(p["incl%d" % (g + 1)]))
	var node := deg_to_rad(float(p["node%d" % (g + 1)]))
	return Basis(Vector3.UP, node) * Basis(Vector3.RIGHT, incl)


## Observer basis: columns are screen right, screen up and the direction to the viewer.
static func view_basis(p: Dictionary) -> Basis:
	var v: Vector3 = p.view
	return Basis.from_euler(Vector3(deg_to_rad(-v.y), deg_to_rad(v.x), deg_to_rad(v.z)), EULER_ORDER_YXZ)


## Initial position and velocity of star i (deterministic per seed).
static func initial_star(p: Dictionary, track: PackedVector3Array, i: int, n: int, seed: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed, i))
	var g := 1 if float(i) / n >= 1.0 - fraction2(p) else 0
	var s := disk_scale(p, g)
	var rmin := DISK_RMIN * s
	var rmax := DISK_RMAX * s
	var sc := DISK_SCALE * s
	var u := rng.randf()
	var r := rmin - sc * log(1.0 - u * (1.0 - exp(-(rmax - rmin) / sc)))
	var th := TAU * rng.randf()
	var spin := float(p["spin%d" % (g + 1)])
	var local_p := Vector3(r * cos(th), 0.0, r * sin(th))
	var local_t := Vector3(-sin(th), 0.0, cos(th)) * spin
	var m := 1.0 if g == 0 else float(p.m2)
	var v_circ := sqrt(G * m * r * r / pow(r * r + SOFTENING * SOFTENING, 1.5))
	var cores := core_positions(p, track, 0.0)
	var vels := core_velocities(p, track, 0.0)
	var b := disk_basis(p, g)
	return PackedVector3Array([cores[g] + b * local_p, vels[g] + b * (local_t * v_circ), Vector3(g, 0, 0)])


## Integrates n stars to t_end. Stars are independent, so they are split over worker threads.
static func simulate(p: Dictionary, n := 3000, seed := 7) -> PackedVector3Array:
	p = with_defaults(p)
	var orbit := orbit_track(p)
	var te := t_end(p)
	var steps := int(ceil(te / DT))
	var dt := te / steps
	# Core track at the (half-)steps, shared by all workers.
	var track := PackedVector3Array()
	track.resize(steps * 2)
	for k in steps:
		var c := core_positions(p, orbit, (k + 0.5) * dt)
		track[2 * k] = c[0]
		track[2 * k + 1] = c[1]
	var m1 := G * 1.0
	var m2 := G * float(p.m2)
	var eps2 := SOFTENING * SOFTENING
	var chunks := 8
	var per := int(ceil(float(n) / chunks))
	var parts := []  # one PackedVector3Array per chunk (packed arrays are copied into lambdas)
	parts.resize(chunks)
	var job := func(c: int) -> void:
		var part := PackedVector3Array()
		for i in range(c * per, mini(n, (c + 1) * per)):
			var s := initial_star(p, orbit, i, n, seed)
			var x := s[0]
			var v := s[1]
			# Leapfrog (drift-kick-drift) against the analytic core track.
			for k in steps:
				x += v * (0.5 * dt)
				var d0 := track[2 * k] - x
				var d1 := track[2 * k + 1] - x
				var r0 := d0.length_squared() + eps2
				var r1 := d1.length_squared() + eps2
				v += (d0 * (m1 / (r0 * sqrt(r0))) + d1 * (m2 / (r1 * sqrt(r1)))) * dt
				x += v * (0.5 * dt)
			part.append(x)
		parts[c] = part
	var id := WorkerThreadPool.add_group_task(job, chunks, -1, true, "galaxy_sim")
	WorkerThreadPool.wait_for_group_task_completion(id)
	var out := PackedVector3Array()
	for part in parts:
		out.append_array(part)
	return out


## Smoothed, normalised star density on the sky (MAP_SIZE^2, centred on the centre of mass).
static func density_map(p: Dictionary, stars: PackedVector3Array, size := MAP_SIZE, extent := MAP_EXTENT) -> PackedFloat32Array:
	p = with_defaults(p)
	var vb := view_basis(p)
	var right := vb.x
	var up := vb.y
	var m := PackedFloat32Array()
	m.resize(size * size)
	var scale := size / (2.0 * extent)
	for s in stars:
		var u := (s.dot(right) + extent) * scale
		var v := (extent - s.dot(up)) * scale
		var iu := int(floor(u))
		var iv := int(floor(v))
		if iu < 0 or iv < 0 or iu >= size or iv >= size:
			continue
		m[iv * size + iu] += 1.0
	m = _blur(m, size)
	# Saturate: a cell counts as "lit" once it holds a few stars, so faint tails and bridges
	# count as much as the bright centres (that is what the eye compares, too).
	var lit := SATURATION * stars.size() / 3000.0
	var total := 0.0
	for i in m.size():
		m[i] = 1.0 - exp(-m[i] / lit)
		total += m[i]
	if total > 0.0:
		for i in m.size():
			m[i] /= total
	return m


static func _blur(m: PackedFloat32Array, size: int) -> PackedFloat32Array:
	var k := [0.25, 0.5, 0.25]
	var tmp := PackedFloat32Array()
	tmp.resize(m.size())
	for y in size:
		for x in size:
			var acc := 0.0
			for j in 3:
				acc += m[y * size + clampi(x + j - 1, 0, size - 1)] * k[j]
			tmp[y * size + x] = acc
	var out := PackedFloat32Array()
	out.resize(m.size())
	for y in size:
		for x in size:
			var acc := 0.0
			for j in 3:
				acc += tmp[clampi(y + j - 1, 0, size - 1) * size + x] * k[j]
			out[y * size + x] = acc
	return out


## Pearson correlation of two density maps (1 = identical shape).
static func correlation(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		var da := a[i] - ma
		var db := b[i] - mb
		sab += da * db
		saa += da * da
		sbb += db * db
	if saa <= 0.0 or sbb <= 0.0:
		return 0.0
	return sab / sqrt(saa * sbb)
