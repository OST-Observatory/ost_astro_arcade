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
	# From 2026 on there are 3-star windows (Saturn within its Hill sphere) – and also
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


func test_closest_approach_is_the_true_minimum() -> void:
	# Brute force with a fine step (and in 3D, Saturn's orbit is tilted) must not find a
	# closer approach than Flyby.closest_to().
	var ws := MissionLogic.jupiter_windows(2461322.5, 12.0)
	for k in [3, 5, 8, 10]:
		for side in [1.0, -1.0]:
			var p := MissionLogic.plan_flyby(ws[k], 6.0, side)
			var f: Flyby = p.flyby
			var best := INF
			var jd := f.jd_flyby
			while jd < f.jd_flyby + MissionLogic.SATURN_YEARS * 365.25:
				best = minf(best, f.position(jd).distance_to(Kepler.planet_position("saturn", jd)))
				jd += 0.5
			assert_almost(float(p.closest), best, 0.01, "window %d side %+d" % [k, int(side)])
