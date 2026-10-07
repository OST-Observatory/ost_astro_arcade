extends TestCase


func test_2020_window_matches_perseverance() -> void:
	# Perseverance launched on 2020-07-30 (JD 2459060.5); our window must be within two weeks.
	var best := MarsTransfer.best_launch(2459000.5, 2459200.5)
	assert_true(absf(best - 2459060.5) < 14.0, "2020 window at JD %f" % best)


func test_windows_repeat_about_every_26_months() -> void:
	var w1 := MarsTransfer.next_window(2459000.5, 2459900.5)
	var w2 := MarsTransfer.next_window(w1 + 100.0, w1 + 1000.0)
	assert_true(absf((w2 - w1) - 780.0) < 60.0, "synodic period: %f days" % (w2 - w1))
	assert_true(absf(MarsTransfer.compute(w1).miss_deg) < 2.0, "window really hits")


func test_transfer_geometry() -> void:
	var jd := 2461000.5
	var t := MarsTransfer.compute(jd)
	assert_true(t.days > 230.0 and t.days < 290.0, "flight time %f days" % t.days)
	var earth := Kepler.planet_position("earth", jd)
	assert_true(t.position_at(0.0).distance_to(Vector3(earth.x, earth.y, 0.0)) < 0.001, "starts at Earth")
	assert_almost(t.arrival_point().length(), t.r2, 0.001, "arrives at Mars' orbit")
	assert_almost(MarsTransfer.ideal_phase_deg(), 44.3, 0.5)


func test_days_off_points_to_the_window() -> void:
	var w := MarsTransfer.next_window(2459000.5, 2459900.5)
	assert_almost(MarsTransfer.days_off(w - 20.0), 20.0, 6.0, "20 days early -> launch later")
	assert_almost(MarsTransfer.days_off(w + 15.0), -15.0, 6.0, "15 days late -> launch earlier")


func test_stars_and_score() -> void:
	assert_eq(MarsTransfer.stars(0.5, "explorer"), 3)
	assert_eq(MarsTransfer.stars(0.9, "pro"), 2)
	assert_eq(MarsTransfer.stars(20.0, "explorer"), 0)
	assert_true(MarsTransfer.score(0.5, 1, "pro") > MarsTransfer.score(0.5, 1, "explorer"))
	assert_true(MarsTransfer.score(0.5, 1, "explorer") > MarsTransfer.score(4.0, 1, "explorer"))
