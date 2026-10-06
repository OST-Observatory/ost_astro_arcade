extends TestCase


func _mission(diff := "researcher") -> MissionState:
	var m := MissionState.new()
	m.rng.seed = 3
	m.difficulty = diff
	m.scenario = AsteroidScenario.pick(diff, m.rng)
	return m


func test_quality_prefers_dark_high_sky() -> void:
	var m := _mission()
	var best := -1.0
	var best_i := 0
	for i in m.scenario.track.size():
		var q := m.quality_at(i)
		assert_true(q.q >= 0.0 and q.q <= 1.0)
		assert_true(q.bg_factor >= 1.0 and q.bg_factor <= 5.0)
		if q.ok and q.q > best:
			best = q.q
			best_i = i
	assert_true(best > 0.0, "a usable time exists")
	var s := m.sample(best_i)
	assert_true(float(s.sun_alt) < -12.0 and float(s.alt) > 25.0)
	# Twilight must never be "ok".
	for i in m.scenario.track.size():
		if float(m.sample(i).sun_alt) > -12.0:
			assert_false(m.quality_at(i).ok)


func test_challenge_uses_mission_choices() -> void:
	var m := _mission()
	var i := float(m.scenario.data.best_index)
	var mid := m.scenario.position_at(i)
	var aim := mid + Vector2(300, -200)
	var c := BlinkChallenge.create(m.scenario, m.difficulty, m.rng, {"obs_index": i, "center": aim, "exposure_offset": 0.75})
	assert_eq(c.center, aim, "pointing taken from the align step")
	var c0 := BlinkChallenge.create(m.scenario, m.difficulty, m.rng, {"obs_index": i, "exposure_offset": 0.0})
	assert_true(c.asteroid_mag > c0.asteroid_mag - 0.4 + 0.75 - 0.5, "short exposure makes it fainter")


func test_totals_and_stars() -> void:
	var m := _mission("pro")
	m.points = {"plan": 300, "align": 200, "blink": 1500, "measure": 400}
	assert_eq(m.total_points(), 2400)
	m.blink = {"stars": 3}
	m.measure_error_arcsec = 0.8
	assert_eq(m.stars(), 3)
	m.measure_error_arcsec = 3.0
	assert_eq(m.stars(), 2)
	assert_almost(m.diff_mult(), 2.5, 0.001)
