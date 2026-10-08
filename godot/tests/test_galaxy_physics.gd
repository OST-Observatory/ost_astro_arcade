extends TestCase


func test_hash_matches_shader_reference() -> void:
	# Reference values computed with Python's arbitrary-precision ints (uint32 semantics).
	var ref := {0: [888989596, 3867314330], 1: [4105576733, 1161176604], 7: [1580914852, 397795651],
		123456: [1683614844, 397668785], 199999: [3263354772, 3634909316]}
	for i in ref:
		var s := StarSampler.hash_u(StarSampler.seed_for(i))
		assert_eq(s, ref[i][0], "first hash of %d" % i)
		assert_eq(StarSampler.hash_u(s), ref[i][1], "second hash of %d" % i)


func test_circular_speed_matches_force() -> void:
	var t := GalaxyTemplates.get_target("milkyway")
	var p: GalaxyPotential = t.reference
	p.m_bh = 0.0005
	for r in [0.1, 0.5, 1.0, 3.0, 8.0, 40.0]:
		var a := p.accel_local(Vector3(r, 0, 0))
		assert_almost(sqrt(r * -a.x), p.v_circ(r), 1e-4 * maxf(p.v_circ(r), 1.0), "R = %f" % r)
		assert_almost(a.y, 0.0, 1e-9, "no vertical force in the plane")
	p.m_bh = 0.0


func test_halo_continuous_at_truncation() -> void:
	var p := GalaxyPotential.new()
	p.v_halo = 0.5
	p.r_core = 1.0
	p.r_trunc = 10.0
	assert_almost(p.v_circ(9.9999), p.v_circ(10.0001), 1e-4)
	assert_true(p.mass_within(20.0) >= p.mass_within(10.0), "enclosed mass never shrinks")
	assert_almost(p.halo_density(10.5), 0.0, 1e-12)


func test_rotated_disk_force() -> void:
	var p := GalaxyPotential.new()
	p.m_disk = 1.0
	p.basis = Basis(Vector3.RIGHT, PI / 2)   # disk axis now along world z
	var a := p.accel(Vector3(0, 0, 0.5))      # a point on the axis
	assert_true(a.z < 0.0 and absf(a.x) < 1e-6 and absf(a.y) < 1e-6, "pulled back along the axis: %s" % a)


func test_reference_models_match_the_data() -> void:
	for t in GalaxyTemplates.targets():
		var m := BuildLogic.match_percent(t, t.reference)
		assert_true(m >= 95.0, "%s reference matches %.1f %%" % [t.id, m])


func test_no_halo_never_stable() -> void:
	for t in GalaxyTemplates.targets():
		for diff in ["explorer", "researcher"]:
			var steps: Dictionary = GalaxyTemplates.STEPS[diff]
			var best := 0.0
			for s in steps.stars:
				for g in steps.gas:
					for b in steps.bh:
						best = maxf(best, BuildLogic.match_percent(t, GalaxyTemplates.build(t, {"bh": b, "stars": s, "gas": g, "halo": 0.0})))
			assert_true(best < 90.0, "%s/%s best without halo %.1f %%" % [t.id, diff, best])
		var best_pro := 0.0
		for s in range(0, 26):
			for g in range(0, 26, 2):
				best_pro = maxf(best_pro, BuildLogic.match_percent(t, GalaxyTemplates.build(t, {"stars": s * 0.1, "gas": g * 0.1})))
		assert_true(best_pro < 90.0, "%s pro best without halo %.1f %%" % [t.id, best_pro])


func test_every_level_has_a_solution() -> void:
	for t in GalaxyTemplates.targets():
		for diff in ["explorer", "researcher"]:
			var steps: Dictionary = GalaxyTemplates.STEPS[diff]
			var best := 0.0
			for s in steps.stars:
				for g in steps.gas:
					for h in steps.halo:
						best = maxf(best, BuildLogic.match_percent(t, GalaxyTemplates.build(t, {"stars": s, "gas": g, "halo": h})))
			assert_true(best >= BuildLogic.STABLE[diff], "%s/%s best %.1f %%" % [t.id, diff, best])


func test_black_hole_hardly_matters() -> void:
	for t in GalaxyTemplates.targets():
		var k := GalaxyTemplates.reference_knobs(t)
		var m0 := BuildLogic.match_percent(t, GalaxyTemplates.build(t, k))
		k.bh = 100.0
		var m1 := BuildLogic.match_percent(t, GalaxyTemplates.build(t, k))
		assert_true(absf(m1 - m0) < 1.0, "%s: black hole changes %.2f %%" % [t.id, m1 - m0])


func test_sampler_puts_stars_inside_the_galaxy() -> void:
	var t := GalaxyTemplates.get_target("milkyway")
	var g := GalaxyTemplates.star_setup(t, t.reference, true)
	var kinds := [0, 0, 0]
	for i in 3000:
		var s := StarSampler.sample(i, g)
		kinds[s[2]] += 1
		var p: Vector3 = s[0]
		assert_true(Vector2(p.x, p.z).length() <= float(g.r_max) * 1.001, "star %d inside r_max" % i)
	assert_almost(kinds[0] / 3000.0, float(t.look.f_bulge), 0.03, "bulge fraction")
	assert_almost(kinds[2] / 3000.0, float(t.look.f_gas), 0.03, "gas fraction")
