## Two galaxies meet. Their centres move on a track computed once on the CPU: each galaxy
## pulls on the other with the mass inside their separation, and dynamical friction
## (Chandrasekhar) from both dark halos lets close pairs merge. Test stars of both galaxies
## feel both full mass models around the moving centres (restricted three-body method of
## Toomre & Toomre 1972, here with extended halos, which also allows ring galaxies).
## The GPU animates many stars along the same track; a CPU subset is used for the analysis
## (snapshots for the feature detector).
class_name EncounterModel
extends RefCounted

const DT := 0.05             # track step = GPU step (model time units)
const DT_CPU := 0.1          # CPU star integration step
const LN_LAMBDA := 3.0
const DF_SCALE := 0.25
var df_scale := DF_SCALE     # tuning (calibration tool)
const SNAPSHOT_EVERY := 10.0
const T_AFTER := 150.0       # how long to follow the galaxies after the first closest approach
const T_MAX := 220.0
const APPROACH_Q := {"headon": 0.08, "grazing": 0.9, "wide": 2.2}   # pericentre in units of R1

var gal: Array = []          # two dictionaries: {pot, setup, target, n_cpu}
var approach := "grazing"
var track := PackedVector3Array()   # relative position r = x2 - x1 at t = j * DT
var t_end := 0.0
var t_peri := 0.0
var q_actual := 0.0
var mu := [0.5, 0.5]         # mass fractions
var v_rel0 := Vector3.ZERO
var snapshots: Array = []    # [{t, c1, c2, stars: PackedVector3Array, owner: PackedByteArray}]
var _done: Array = []        # stars finished per worker chunk (read by progress())
var _total := 1
var cancelled := false       # set from the main thread: run_stars() stops early, no snapshots


## Orientation of the player's disk and of the partner for an approach type and spin.
static func orientations(approach_type: String) -> Array:
	var player := Basis(Vector3.RIGHT, deg_to_rad(90.0)) if approach_type == "headon" \
		else Basis(Vector3.RIGHT, deg_to_rad(20.0))
	var partner := Basis(Vector3.UP, deg_to_rad(30.0)) * Basis(Vector3.RIGHT, deg_to_rad(45.0))
	return [player, partner]


## g1 = the player's galaxy, g2 = the partner: {pot: GalaxyPotential, target: Dictionary,
## spin: float}. Builds the centre track.
func setup(g1: Dictionary, g2: Dictionary, approach_type: String) -> void:
	approach = approach_type
	var bases := orientations(approach_type)
	gal = []
	for i in 2:
		var g: Dictionary = [g1, g2][i]
		var pot: GalaxyPotential = (g.pot as GalaxyPotential).copy()
		pot.basis = bases[i]
		var setup := GalaxyTemplates.star_setup(g.target, pot, false, float(g.get("spin", 1.0)))
		gal.append({"pot": pot, "target": g.target, "setup": setup})
	var m1: float = (gal[0].pot as GalaxyPotential).total_mass()
	var m2: float = (gal[1].pot as GalaxyPotential).total_mass()
	mu = [m1 / (m1 + m2), m2 / (m1 + m2)]
	_build_track()


func radius(i: int) -> float:
	return float(gal[i].target.r_last)


func center(i: int, t: float) -> Vector3:
	var r := rel_at(t)
	return -r * mu[1] if i == 0 else r * mu[0]


func rel_at(t: float) -> Vector3:
	var f := clampf(t / DT, 0.0, track.size() - 1.001)
	var j := int(f)
	return track[j].lerp(track[j + 1], f - j)


func center_velocity(i: int, t: float) -> Vector3:
	var h := DT
	return (center(i, t + h) - center(i, maxf(t - h, 0.0))) / (h + minf(t, h))


# --- centre track ----------------------------------------------------------------------------

func _rel_accel(r: Vector3, v: Vector3, friction: bool) -> Vector3:
	var p1: GalaxyPotential = gal[0].pot
	var p2: GalaxyPotential = gal[1].pot
	var d := maxf(r.length(), 1e-4)
	var a := -r / d * ((p1.mass_within(d) + p2.mass_within(d)) / (d * d))
	if friction:
		var speed := maxf(v.length(), 1e-4)
		var df := 0.0
		for k in 2:
			var host: GalaxyPotential = [p1, p2][k]
			var guest: GalaxyPotential = [p2, p1][k]
			var rho := host.halo_density(d)
			if rho > 0.0:
				var x := speed / maxf(host.v_halo, 1e-4)
				var fx := _erf(x) - 2.0 * x / sqrt(PI) * exp(-x * x)
				df += guest.total_mass() * rho * fx
		a -= v / (speed * speed * speed) * (4.0 * PI * LN_LAMBDA * df_scale * df)
	return a


static func _erf(x: float) -> float:
	# Abramowitz & Stegun 7.1.26 (|error| < 1.5e-7)
	var t := 1.0 / (1.0 + 0.3275911 * absf(x))
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)
	return y if x >= 0.0 else -y


## Start separation and velocity for a wanted pericentre q; the impact parameter is found by a
## few secant steps on the friction-free orbit.
func _start_state(q: float) -> Array:
	var d0 := 2.0 * (radius(0) + radius(1)) + 6.0
	var p1: GalaxyPotential = gal[0].pot
	var p2: GalaxyPotential = gal[1].pot
	var v0 := 0.95 * sqrt(2.0 * (p1.mass_within(d0) + p2.mass_within(d0)) / d0)
	var b0 := q
	var b1 := q * 2.0 + 0.5
	var f0 := _peri_for(b0, d0, v0) - q
	var f1 := _peri_for(b1, d0, v0) - q
	for i in 8:
		if absf(f1 - f0) < 1e-6:
			break
		var b2 := clampf(b1 - f1 * (b1 - b0) / (f1 - f0), 0.0, d0 * 0.9)
		b0 = b1
		f0 = f1
		b1 = b2
		f1 = _peri_for(b1, d0, v0) - q
		if absf(f1) < 0.02 * maxf(q, 0.2):
			break
	var b := b1
	return [Vector3(b, 0.0, -sqrt(maxf(d0 * d0 - b * b, 0.0))), Vector3(0.0, 0.0, v0)]


func _peri_for(b: float, d0: float, v0: float) -> float:
	var r := Vector3(b, 0.0, -sqrt(maxf(d0 * d0 - b * b, 0.0)))
	var v := Vector3(0.0, 0.0, v0)
	var dmin := INF
	var dt := DT * 4.0
	for i in int(T_MAX / dt):
		r += v * (0.5 * dt)
		v += _rel_accel(r, v, false) * dt
		r += v * (0.5 * dt)
		var d := r.length()
		if d < dmin:
			dmin = d
		elif d > dmin * 1.5 and d > 2.0:
			break
	return dmin


func _build_track() -> void:
	var q: float = float(APPROACH_Q.get(approach, 1.0)) * radius(0)
	var s := _start_state(q)
	var r: Vector3 = s[0]
	var v: Vector3 = s[1]
	v_rel0 = v
	track = PackedVector3Array([r])
	var dmin := INF
	var first_done := false
	t_peri = 0.0
	t_end = T_MAX
	var t := 0.0
	while t < t_end:
		r += v * (0.5 * DT)
		v += _rel_accel(r, v, true) * DT
		r += v * (0.5 * DT)
		t += DT
		track.append(r)
		var d := r.length()
		if not first_done:
			if d < dmin:
				dmin = d
				t_peri = t
			elif d > dmin * 1.2 + 0.5:
				first_done = true   # first passage is over: follow the pair for a while
				t_end = minf(t_peri + T_AFTER, T_MAX)
	q_actual = dmin
	track.append(r)


## Share of the CPU analysis already done (0..1), safe to call from the main thread.
func progress() -> float:
	var s := 0
	for d in _done:
		s += int(d)
	return clampf(float(s) / _total, 0.0, 1.0)


## True if the centres end close together and slow: the galaxies have merged.
func merged() -> bool:
	var r := rel_at(t_end)
	var v := (rel_at(t_end) - rel_at(t_end - 1.0))
	return r.length() < 1.0 and v.length() < 0.2


# --- CPU stars ---------------------------------------------------------------------------------

## Integrates n stars per galaxy to t_end and stores snapshots for the feature detector.
func run_stars(n_per_galaxy := 500, dt := DT_CPU) -> void:
	var init := []          # [pos, vel, owner]
	for g in 2:
		var setup: Dictionary = gal[g].setup
		var pot: GalaxyPotential = gal[g].pot
		var c := center(g, 0.0)
		var cv := center_velocity(g, 0.0)
		for i in n_per_galaxy:
			var s := StarSampler.sample(i + g * 1000003, setup)
			init.append([c + pot.basis * (s[0] as Vector3), cv + pot.basis * (s[1] as Vector3), g])
	var steps := int(ceil(t_end / dt))
	var every := maxi(1, int(round(SNAPSHOT_EVERY / dt)))
	var n := init.size()
	var chunks := 8
	var per := int(ceil(float(n) / chunks))
	var parts := []
	parts.resize(chunks)
	var done := []
	done.resize(chunks)
	done.fill(0)
	_done = done
	_total = maxi(n, 1)
	var p1: GalaxyPotential = gal[0].pot
	var p2: GalaxyPotential = gal[1].pot
	var job := func(ch: int) -> void:
		var out := []   # per star: PackedVector3Array of snapshot positions
		for i in range(ch * per, mini(n, (ch + 1) * per)):
			if cancelled:
				return
			var x: Vector3 = init[i][0]
			var v: Vector3 = init[i][1]
			var snaps := PackedVector3Array([x])
			for k in steps:
				var tm := (k + 0.5) * dt
				x += v * (0.5 * dt)
				v += (p1.accel(x - center(0, tm)) + p2.accel(x - center(1, tm))) * dt
				x += v * (0.5 * dt)
				if (k + 1) % every == 0:
					snaps.append(x)
			out.append(snaps)
			done[ch] += 1   # each chunk writes only its own slot
		parts[ch] = out
	var id := WorkerThreadPool.add_group_task(job, chunks, -1, true, "galaxy_encounter")
	WorkerThreadPool.wait_for_group_task_completion(id)
	if cancelled:
		snapshots = []
		return
	var all := []
	for p in parts:
		all.append_array(p)
	snapshots = []
	var count: int = (all[0] as PackedVector3Array).size()
	var owner := PackedByteArray()
	for i in n:
		owner.append(int(init[i][2]))
	for k in count:
		var tk := minf(k * every * dt, t_end)
		var pos := PackedVector3Array()
		pos.resize(n)
		for i in n:
			pos[i] = (all[i] as PackedVector3Array)[k]
		snapshots.append({"t": tk, "c": [center(0, tk), center(1, tk)], "stars": pos, "owner": owner})


# --- GPU stars -----------------------------------------------------------------------------------

## Like run_stars(), but on the graphics card (encounter_stars.glsl): tens of thousands of
## stars in a fraction of the time. Snapshots hold a subsample (`sub` stars per galaxy, for
## tails, bridges and the merger), and `ring_hist` the counts of all stars per snapshot,
## galaxy, direction and radius in the galaxy's disk plane (for rings, see FeatureDetector).
## Returns false where there is no RenderingDevice (headless, compatibility renderer), then
## run_stars() is the fallback.
const HIST_DIRS := 12
const HIST_BINS := 160
const HIST_REACH := 4.5      # counted out to this many r0
var ring_hist := PackedInt32Array()
var ring_r0 := [1.0, 1.0]
var ring_baseline := [0.0, 0.0]   # ripple coherence each galaxy shows on its own (see baseline())


func run_stars_gpu(n_per_galaxy := 30000, sub := 3000, dt := DT) -> bool:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		return false
	_done = [0]
	_total = 3
	sub = mini(sub, n_per_galaxy)
	var init := PackedFloat32Array()
	init.resize(2 * n_per_galaxy * 8)
	var owner := PackedByteArray()
	for g in 2:
		var setup: Dictionary = gal[g].setup
		var pot: GalaxyPotential = gal[g].pot
		var c := center(g, 0.0)
		var cv := center_velocity(g, 0.0)
		var dists := PackedFloat32Array()
		for i in n_per_galaxy:
			if cancelled:
				rd.free()
				return true
			var s := StarSampler.sample(i + g * 1000003, setup)
			var x := c + pot.basis * (s[0] as Vector3)
			var v := cv + pot.basis * (s[1] as Vector3)
			var o := (g * n_per_galaxy + i) * 8
			init[o] = x.x
			init[o + 1] = x.y
			init[o + 2] = x.z
			init[o + 4] = v.x
			init[o + 5] = v.y
			init[o + 6] = v.z
			if i < sub:
				owner.append(g)
				dists.append((x - c).length())
		dists.sort()
		ring_r0[g] = maxf(float(dists[int(dists.size() * 0.9)]), 0.1)   # as FeatureDetector._initial_radii()
		_done = [g + 1]
	var n := 2 * n_per_galaxy
	var steps := int(ceil(t_end / dt))
	var every := maxi(1, int(round(SNAPSHOT_EVERY / dt)))
	var count := 1 + steps / every
	var params := PackedFloat32Array([float(n), float(steps), dt, float(every)])
	for g in 2:
		params.append_array((gal[g].pot as GalaxyPotential).to_uniforms())
	for g in 2:
		var b: Basis = (gal[g].pot as GalaxyPotential).basis
		params.append_array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z])
	params.append_array([float(n_per_galaxy), float(sub), 0.5 * ring_r0[0], 0.5 * ring_r0[1],
		HIST_REACH * ring_r0[0], HIST_REACH * ring_r0[1]])
	var centers := PackedFloat32Array()
	centers.resize(steps * 8)
	for k in steps:
		var tm := (k + 0.5) * dt
		for g in 2:
			var cp := center(g, tm)
			centers[k * 8 + g * 4] = cp.x
			centers[k * 8 + g * 4 + 1] = cp.y
			centers[k * 8 + g * 4 + 2] = cp.z
	var snap_c := PackedFloat32Array()
	snap_c.resize(count * 8)
	for j in count:
		for g in 2:
			var cp := center(g, j * every * dt)
			snap_c[j * 8 + g * 4] = cp.x
			snap_c[j * 8 + g * 4 + 1] = cp.y
			snap_c[j * 8 + g * 4 + 2] = cp.z
	var hist_n := count * 2 * HIST_DIRS * HIST_BINS
	var shader_file: RDShaderFile = load("res://games/galaxy/physics/encounter_stars.glsl")
	var shader := rd.shader_create_from_spirv(shader_file.get_spirv())
	var bufs := []
	var uniforms := []
	var zeros := PackedByteArray()
	zeros.resize(hist_n * 4)
	var datas: Array = [params.to_byte_array(), centers.to_byte_array(), init.to_byte_array(), PackedByteArray(), zeros,
		snap_c.to_byte_array()]
	for k in datas.size():
		var bytes: PackedByteArray = datas[k]
		var buf := rd.storage_buffer_create(count * 2 * sub * 16 if k == 3 else bytes.size(), bytes)
		bufs.append(buf)
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = k
		u.add_id(buf)
		uniforms.append(u)
	var uset := rd.uniform_set_create(uniforms, shader, 0)
	var pipeline := rd.compute_pipeline_create(shader)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline)
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	rd.compute_list_dispatch(cl, int(ceil(n / 64.0)), 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var out := rd.buffer_get_data(bufs[3]).to_float32_array()
	ring_hist = rd.buffer_get_data(bufs[4]).to_int32_array()
	for r in [pipeline, uset] + bufs + [shader]:
		rd.free_rid(r)
	rd.free()
	snapshots = []
	var m := 2 * sub
	for k in count:
		var tk := minf(k * every * dt, t_end)
		var pos := PackedVector3Array()
		pos.resize(m)
		var base := k * m * 4
		for i in m:
			pos[i] = Vector3(out[base + i * 4], out[base + i * 4 + 1], out[base + i * 4 + 2])
		snapshots.append({"t": tk, "c": [center(0, tk), center(1, tk)], "stars": pos, "owner": owner})
	_done = [3]
	return true


## How much concentric rippling each galaxy shows on its own, without the partner: the same
## stars and steps with the partner made massless (its centre then stays put). A ring from
## the collision has to stand out above this (FeatureDetector._ring_counts).
func baseline(n_per_galaxy := 30000) -> void:
	for g in 2:
		var alone := EncounterModel.new()
		var g1 := {"pot": (gal[0].pot as GalaxyPotential) if g == 0 else GalaxyPotential.new(), "target": gal[0].target,
			"spin": float(gal[0].setup.spin)}
		var g2 := {"pot": (gal[1].pot as GalaxyPotential) if g == 1 else GalaxyPotential.new(), "target": gal[1].target,
			"spin": float(gal[1].setup.spin)}
		alone.setup(g1, g2, approach)
		alone.t_end = t_end
		if cancelled or not alone.run_stars_gpu(n_per_galaxy, 1):
			return
		var best := 0.0
		for j in range(2, alone.snapshots.size()):
			best = maxf(best, FeatureDetector.pair_coherence(alone, j, g))
		ring_baseline[g] = best
