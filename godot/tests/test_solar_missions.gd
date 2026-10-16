extends TestCase


func test_targets_per_difficulty() -> void:
	assert_eq(MissionLogic.target("explorer"), "mars")
	assert_eq(MissionLogic.target("researcher"), "jupiter")
	assert_eq(MissionLogic.target("pro"), "saturn")


func test_ideal_phase_hits() -> void:
	# Launching when the phase angle equals the ideal one meets the planet.
	for p in ["mars", "jupiter"]:
		var w := HohmannTransfer.next_window(p, 2461000.5, 2461900.5)
		assert_true(w > 0.0, "%s window" % p)
		assert_almost(MissionLogic.phase(p, w), MissionLogic.ideal_phase(p, w), 4.0, p)
	assert_almost(MissionLogic.ideal_phase("jupiter", 2461000.5), 97.0, 8.0)


func test_days_off_points_to_the_window() -> void:
	var w := HohmannTransfer.next_window("jupiter", 2461000.5, 2461600.5)
	assert_almost(MissionLogic.days_off("jupiter", w - 20.0), 20.0, 6.0, "20 days early")
	assert_almost(MissionLogic.days_off("jupiter", w + 15.0), -15.0, 6.0, "15 days late")


func test_saturn_windows_from_today_are_solvable() -> void:
	# From 2026 on there are 3-star windows (Saturn within its Hill sphere), and also
	# windows that cannot reach Saturn at all, so the choice matters.
	var ws := MissionLogic.jupiter_windows(2461322.5)
	assert_true(ws.size() >= 15, "about one window a year: %d" % ws.size())
	var good := 0
	var bad := 0
	for w in ws:
		var b := MissionLogic.best_for_window(w)
		if MissionLogic.flyby_stars(b.closest) == 3:
			good += 1
		elif float(b.closest) > 2.0:
			bad += 1
	assert_true(good >= 2, "3-star windows: %d" % good)
	assert_true(bad >= 3, "hopeless windows: %d" % bad)


func test_scores_order() -> void:
	assert_true(MissionLogic.flyby_score(0.3, 1) > MissionLogic.flyby_score(1.5, 1))
	assert_true(MissionLogic.flyby_score(0.3, 1) > MissionLogic.flyby_score(0.3, 3))
	assert_eq(MissionLogic.flyby_stars(0.3), 3)
	assert_eq(MissionLogic.flyby_stars(0.8), 2)
	assert_eq(MissionLogic.flyby_stars(1.5), 1)
	assert_eq(MissionLogic.flyby_stars(5.0), 0)


func test_encounter_is_the_minimum_around_the_orbit_crossing() -> void:
	# Brute force with a fine step (in 3D, Saturn's orbit is tilted) in the time span around
	# the moment the probe reaches Saturn's distance: for near misses (where stars are won)
	# the same closest approach; for wide misses never less than the true minimum.
	var ws := MissionLogic.jupiter_windows(2461322.5, 12.0)
	var near := 0
	for k in [3, 4, 5, 6, 7, 8, 10]:
		for side in [1.0, -1.0]:
			for rp in [3.0, 6.0, 12.0]:
				var p := MissionLogic.plan_flyby(ws[k], rp, side)
				var f: Flyby = p.flyby
				var lo := maxf(f.jd_flyby, float(p.jd_ref) - Flyby.ENCOUNTER_DAYS)
				var hi := minf(f.jd_flyby + MissionLogic.SATURN_YEARS * 365.25, float(p.jd_ref) + Flyby.ENCOUNTER_DAYS)
				var best := INF
				var jd := lo
				while jd <= hi:
					best = minf(best, f.position(jd).distance_to(Kepler.planet_position("saturn", jd)))
					jd += 0.5
				if float(p.closest) < 1.5:
					near += 1
					assert_almost(float(p.closest), best, 0.01, "window %d side %+d rp %.0f" % [k, int(side), rp])
				else:
					assert_true(float(p.closest) >= best - 0.01, "never below the true minimum")
				assert_true(float(p.jd_closest) >= f.jd_flyby, "never before the swing-by")
				if p.reached:
					var at := f.position(float(p.jd_ref)).length() - Kepler.planet_position("saturn", float(p.jd_ref)).length()
					assert_true(at >= -0.05, "reference at or beyond Saturn's distance: %.2f" % at)
	assert_true(near >= 3, "some near misses checked: %d" % near)


func test_encounter_moves_smoothly() -> void:
	# No jumps when the pass distance changes a little, in any launch window, on both sides.
	# Where the date moves fast (an orbit just touching Saturn's distance) a ten times finer
	# step must give a ten times smaller change, i.e. the change is steep but continuous.
	var ws := MissionLogic.jupiter_windows(2461326.5, 20.0)
	for w in ws:
		for side in [1.0, -1.0]:
			var last := {}
			for k in 290:
				var rp := 1.1 + k * 0.1
				var p := MissionLogic.plan_flyby(w, rp, side)
				if not last.is_empty():
					var tag := "%s %+d rp %.1f" % [MarsTransfer.iso_from_jd(w).left(7), int(side), rp]
					assert_true(absf(float(p.closest) - float(last.closest)) < 0.6, tag + ": distance jumps")
					if absf(float(p.jd_closest) - float(last.jd_closest)) > 60.0:
						var prev := last
						for j in range(1, 11):
							var q := MissionLogic.plan_flyby(w, rp - 0.1 + j * 0.01, side)
							assert_true(absf(float(q.jd_closest) - float(prev.jd_closest)) < 40.0,
								tag + ": date jumps %.0f days" % absf(float(q.jd_closest) - float(prev.jd_closest)))
							prev = q
				last = p


func test_saturn_windows_always_offer_solutions() -> void:
	# From any starting date the eight windows offered contain several that reach Saturn's
	# sphere of influence; the offset shrinks by about 20° per later window (the hint).
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for start in [2461326.5, 2462500.5, 2464100.5, 2465300.5]:
		var ws := MissionLogic.saturn_windows(start, rng)
		assert_eq(ws.size(), 8)
		var good := 0
		for w in ws:
			if MissionLogic.flyby_stars(float(MissionLogic.best_for_window(w).closest)) == 3:
				good += 1
		assert_true(good >= 2, "%s: %d windows with three stars" % [MarsTransfer.iso_from_jd(start).left(10), good])
		var a := MissionLogic.saturn_offset(MissionLogic.plan_flyby(ws[2], 6.0, -1.0))
		var b := MissionLogic.saturn_offset(MissionLogic.plan_flyby(ws[3], 6.0, -1.0))
		assert_almost(a - b, 20.0, 8.0, "offset change per window")
