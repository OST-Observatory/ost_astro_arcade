## Finds the shapes a collision produced, from the CPU snapshots of an EncounterModel:
##   tails   – a one-sided, coherent stream of stars far from both galaxies
##   bridge  – a continuous band of stars between two separated galaxies
##   ring    – a closed ring of stars with a hollow inside, in a disk's own plane (the shape
##             counts, however it formed: a partner punching through, or tidal arms closing)
##   merger  – the two centres have come together for good
## Each feature returns the time it was seen best (or -1).
class_name FeatureDetector
extends RefCounted

const FEATURES := ["tails", "bridge", "ring", "merger"]
const TAIL_FAR := 0.05          # share of a galaxy's stars far away
const TAIL_COHERENT := 0.55     # of those, share within 3 neighbouring direction bins
const RING_WINDOW := 80.0       # rings show up soon after the closest approach
const RING_MASS := 0.01         # a partner lighter than this cannot shape a disk
const RING_BUMP := 1.9          # density in the ring vs. at the start (smoothed over 3 radii)
const RING_DIP := 0.7           # density inside the ring vs. at the start: hollow
const RING_SECTORS := 6         # of 8 directions around the ring filled: closed
## With thousands of stars (GPU analysis) rings are found by direction instead (_ring_edges).
const MANY_STARS := 2000        # per galaxy
const EDGE_DIRS := 12
const EDGE_BINS := 40
const EDGE_FOUND := 8           # directions with a bright edge
const EDGE_SMOOTH := 6          # neighbouring edge points at similar radii (a closed loop)


static func detect(m: EncounterModel) -> Dictionary:
	var out := {"tails": -1.0, "bridge": -1.0, "ring": -1.0, "merger": -1.0}
	if m.snapshots.is_empty():
		return out
	var r0 := _initial_radii(m)
	var first: Dictionary = m.snapshots[0]
	var best := {"tails": 0.0, "bridge": 0.0, "ring": 0.0}
	for snap in m.snapshots.slice(1):
		var s := _tails(m, snap, r0)
		if s > best.tails:
			best.tails = s
			out.tails = snap.t
		s = _bridge(m, snap, r0)
		if s > best.bridge:
			best.bridge = s
			out.bridge = snap.t
		if snap.stars.size() >= 2 * MANY_STARS:
			s = _ring_edges(snap, m, r0)   # whole run: undisturbed disks show no edges
		else:
			s = _ring(m, snap, first, r0) if snap.t <= m.t_peri + RING_WINDOW else 0.0
		if s > best.ring:
			best.ring = s
			out.ring = snap.t
	if m.merged():
		out.merger = m.t_end
	return out


## 90th-percentile radius of each galaxy's stars at the start.
static func _initial_radii(m: EncounterModel) -> Array:
	var snap: Dictionary = m.snapshots[0]
	var out := []
	for g in 2:
		var d := []
		for i in snap.stars.size():
			if snap.owner[i] == g:
				d.append((snap.stars[i] - snap.c[g]).length())
		d.sort()
		out.append(float(d[int(d.size() * 0.9)]) if not d.is_empty() else 1.0)
	return out


## Score > 0 if galaxy g has a tail: >= 4 % of its stars far from both centres, and >= 50 %
## of those within 3 neighbouring of 12 direction bins (one-sided and coherent).
static func _tails(m: EncounterModel, snap: Dictionary, r0: Array) -> float:
	var best := 0.0
	for g in 2:
		var own: Vector3 = snap.c[g]
		var other: Vector3 = snap.c[1 - g]
		var n := 0
		var far := 0
		var bins := PackedInt32Array()
		bins.resize(12)
		var normal: Vector3 = (m.gal[g].pot as GalaxyPotential).basis.y
		var e1 := normal.cross(Vector3.FORWARD if absf(normal.z) < 0.9 else Vector3.RIGHT).normalized()
		var e2 := normal.cross(e1)
		for i in snap.stars.size():
			if snap.owner[i] != g:
				continue
			n += 1
			var p: Vector3 = snap.stars[i]
			if (p - own).length() > 2.0 * r0[g] and (p - other).length() > 1.5 * r0[1 - g]:
				far += 1
				var d := p - own
				var ang := atan2(d.dot(e2), d.dot(e1))
				bins[int(fposmod(ang, TAU) / TAU * 12.0) % 12] += 1
		if n == 0 or far < TAIL_FAR * n:
			continue
		var top := 0
		for b in 12:
			top = maxi(top, bins[b] + bins[(b + 1) % 12] + bins[(b + 2) % 12])
		if top >= TAIL_COHERENT * far:
			best = maxf(best, float(far) / n)
	return best


## Score > 0 for a bridge: galaxies separated; >= 1 % of all stars in the middle 40 % of the
## line between the centres, close to it, away from both galaxies; all 4 sub-bins filled.
static func _bridge(m: EncounterModel, snap: Dictionary, r0: Array) -> float:
	var c1: Vector3 = snap.c[0]
	var c2: Vector3 = snap.c[1]
	var d := (c2 - c1).length()
	if d <= r0[0] + r0[1]:
		return 0.0
	var axis := (c2 - c1) / d
	var bins := PackedInt32Array([0, 0, 0, 0])
	var count := 0
	for i in snap.stars.size():
		var p: Vector3 = snap.stars[i]
		var s := (p - c1).dot(axis) / d
		if s < 0.3 or s > 0.7:
			continue
		var off := (p - c1 - axis * (s * d)).length()
		if off > 0.2 * d or (p - c1).length() < 0.8 * r0[0] or (p - c2).length() < 0.8 * r0[1]:
			continue
		bins[mini(int((s - 0.3) / 0.1), 3)] += 1
		count += 1
	var n: int = snap.stars.size()
	if count < 0.01 * n:
		return 0.0
	var mean := count / 4.0
	for b in bins:
		if b < 0.15 * mean:
			return 0.0
	return float(count) / n


## Score > 0 for a ring in galaxy g's own plane: the surface density relative to the start,
## smoothed over three neighbouring radii (with a few hundred stars single radii are mostly
## noise), has a bump >= RING_BUMP at 0.3–1.8 r0 with a hollow <= RING_DIP inside, and the
## ring is closed: >= RING_SECTORS of 8 directions carry at least 40 % of the average.
## Calibrated so that an undisturbed disk and wide fly-bys stay below (tools/galaxy_calibrate.gd).
static func _ring(m: EncounterModel, snap: Dictionary, first: Dictionary, r0: Array) -> float:
	var best := 0.0
	for g in 2:
		var host: GalaxyPotential = m.gal[g].pot
		var guest: GalaxyPotential = m.gal[1 - g].pot
		if guest.total_mass() < RING_MASS * host.total_mass():
			continue
		var basis: Basis = host.basis
		var rmax: float = 2.4 * float(r0[g])
		var now := _profile(snap, g, basis, rmax)
		var start := _profile(first, g, basis, rmax)
		var ratio := PackedFloat32Array()
		ratio.resize(24)
		for k in 24:
			var a := 0.0
			var b := 0.0
			for j in range(maxi(k - 1, 0), mini(k + 2, 24)):
				a += float(now[0][j])
				b += float(start[0][j])
			ratio[k] = (a + 1.0) / (b + 1.0)
		var bump := -1
		var bump_ratio := 0.0
		for k in 24:
			var rk: float = (k + 0.5) / 24.0 * rmax
			if rk < 0.3 * r0[g] or rk > 1.8 * r0[g]:
				continue
			if ratio[k] > bump_ratio:
				bump_ratio = ratio[k]
				bump = k
		if bump < 3 or bump_ratio < RING_BUMP:
			continue
		var dip := INF
		for k in range(1, bump - 1):
			dip = minf(dip, ratio[k])
		if dip > RING_DIP:
			continue
		var sectors: PackedInt32Array = now[1]
		var per := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
		var total := 0
		for j in range(bump - 1, mini(bump + 2, 24)):
			for sec in 8:
				per[sec] += sectors[j * 8 + sec]
				total += sectors[j * 8 + sec]
		var filled := 0
		for sec in 8:
			if per[sec] >= 0.4 * total / 8.0:
				filled += 1
		if filled >= RING_SECTORS:
			best = maxf(best, bump_ratio)
	return best


## Ring as the eye sees it, for many stars: in each of EDGE_DIRS directions around a galaxy's
## centre (in its disk plane, out to 4.5 r0) look for a bright edge – a local maximum of the
## smoothed surface density, clearly brighter than further out (x1.6) and than further in
## (x1.25). A ring: edges in >= EDGE_FOUND directions that join up smoothly (neighbours at
## radii within x1.4) – so off-centre and oval rings count too, wound-up arms or a ragged
## disk do not. Undisturbed disks show no such edges (checked at the start of every recipe).
static func _ring_edges(snap: Dictionary, m: EncounterModel, r0: Array) -> float:
	var best := 0.0
	for g in 2:
		var radii := _edge_radii(snap, g, snap.c[g], (m.gal[g].pot as GalaxyPotential).basis, float(r0[g]))
		var found := 0
		var smooth := 0
		for k in EDGE_DIRS:
			var a: float = radii[k]
			var b: float = radii[(k + 1) % EDGE_DIRS]
			if a > 0.0:
				found += 1
			if a > 0.0 and b > 0.0 and maxf(a, b) / minf(a, b) < 1.4:
				smooth += 1
		if found >= EDGE_FOUND and smooth >= EDGE_SMOOTH:
			best = maxf(best, float(found + smooth))
	return best


## Radius of the bright edge per direction (-1: none).
static func _edge_radii(snap: Dictionary, g: int, c: Vector3, basis: Basis, r0: float) -> PackedFloat32Array:
	var rmax := 4.5 * r0
	var cnt := PackedFloat32Array()
	cnt.resize(EDGE_DIRS * EDGE_BINS)
	var inv := basis.transposed()
	var stars: PackedVector3Array = snap.stars
	var owner: PackedByteArray = snap.owner
	for i in stars.size():
		if owner[i] != g:
			continue
		var p: Vector3 = inv * (stars[i] - c)
		if absf(p.y) > 0.6 * r0:
			continue
		var rr := Vector2(p.x, p.z).length()
		if rr >= rmax:
			continue
		var d := int(fposmod(atan2(p.z, p.x), TAU) / TAU * EDGE_DIRS) % EDGE_DIRS
		cnt[d * EDGE_BINS + int(rr / rmax * EDGE_BINS)] += 1.0
	var radii := PackedFloat32Array()
	radii.resize(EDGE_DIRS)
	for d in EDGE_DIRS:
		radii[d] = -1.0
		var sig := PackedFloat32Array()
		var raw := PackedFloat32Array()
		sig.resize(EDGE_BINS)
		raw.resize(EDGE_BINS)
		for k in EDGE_BINS:
			var a := 0.0
			var area := 0.0
			for j in range(maxi(k - 1, 0), mini(k + 2, EDGE_BINS)):
				a += cnt[d * EDGE_BINS + j]
				var r_in := j / float(EDGE_BINS) * rmax
				var r_out := (j + 1) / float(EDGE_BINS) * rmax
				area += r_out * r_out - r_in * r_in
			sig[k] = a / area
			raw[k] = a
		var best := 0.0
		for k in range(4, EDGE_BINS - 3):
			var rk := (k + 0.5) / EDGE_BINS * rmax
			if rk < 0.6 * r0 or raw[k] < 12.0:
				continue
			if sig[k] < sig[k - 1] or sig[k] < sig[k + 1]:
				continue
			var outer := sig[k + 3]
			var inner := INF
			for j in range(maxi(1, k - 7), k - 1):
				inner = minf(inner, sig[j])
			if sig[k] < 1.6 * outer or sig[k] < 1.25 * inner:
				continue
			var score := minf(sig[k] / maxf(outer, 1e-9), 3.0) * minf(sig[k] / maxf(inner, 1e-9), 3.0)
			if score > best:
				best = score
				radii[d] = rk
	return radii


## Star density per ring (24 radial bins) and counts per ring and direction sector (flat,
## 24 x 8), in the disk plane.
static func _profile(snap: Dictionary, g: int, basis: Basis, rmax: float) -> Array:
	var dens := PackedFloat32Array()
	dens.resize(24)
	var sectors := PackedInt32Array()   # 24 radial bins x 8 directions
	sectors.resize(24 * 8)
	var inv := basis.transposed()
	var c: Vector3 = snap.c[g]
	for i in snap.stars.size():
		if snap.owner[i] != g:
			continue
		var p: Vector3 = inv * (snap.stars[i] - c)
		if absf(p.y) > 0.5 * rmax:
			continue
		var rr := Vector2(p.x, p.z).length()
		if rr >= rmax:
			continue
		var k := int(rr / rmax * 24.0)
		dens[k] += 1.0
		var sec := int(fposmod(atan2(p.z, p.x), TAU) / TAU * 8.0) % 8
		sectors[k * 8 + sec] += 1
	for k in 24:
		var r_in := k / 24.0 * rmax
		var r_out := (k + 1) / 24.0 * rmax
		dens[k] = dens[k] / (PI * (r_out * r_out - r_in * r_in)) * (rmax * rmax / 24.0)
	return [dens, sectors]
