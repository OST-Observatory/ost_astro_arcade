extends TestCase

var sc: AsteroidScenario


func before_each() -> void:
	var idx := AsteroidScenario.load_index()
	assert_true(not idx.is_empty(), "scenario index is empty – run tools/asteroid/build_scenarios.py")
	sc = AsteroidScenario.load_by_id(idx[0].id)


func _challenge(diff: String, seed_value := 5) -> BlinkChallenge:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return BlinkChallenge.create(sc, diff, rng)


func test_asteroid_inside_image_in_all_frames() -> void:
	for diff in ["explorer", "researcher", "pro"]:
		for s in 20:
			var c := _challenge(diff, s + 1)
			for p in c.asteroid_px:
				var inside := p.x >= 0 and p.y >= 0 and p.x <= AsteroidScenario.IMAGE_SIZE.x and p.y <= AsteroidScenario.IMAGE_SIZE.y
				assert_true(inside, "%s seed %d: asteroid at %s" % [diff, s, p])


func test_asteroid_moves_between_frames() -> void:
	var c := _challenge("researcher")
	assert_true(c.motion_arcsec() > 2.0, "motion %.1f arcsec" % c.motion_arcsec())
	assert_eq(c.frames.size(), BlinkChallenge.FRAMES)


func test_tap_classification() -> void:
	var c := _challenge("pro")
	assert_eq(c.classify(c.asteroid_px[0], 0), "asteroid", "tap on frame-1 position")
	assert_eq(c.classify(c.asteroid_px[2] + Vector2(5, -5), 2), "asteroid", "tap near frame-3 position")
	var far := c.asteroid_px[1] + Vector2(500, 0)
	assert_true(c.classify(far, 1) != "asteroid", "far away must not count")
	# Distractors are recognised (unless they happen to lie on the asteroid).
	for f in c.cosmic_px.size():
		for p in c.cosmic_px[f]:
			if p.distance_to(c.asteroid_px[0]) > 60 and p.distance_to(c.asteroid_px[2]) > 60:
				assert_eq(c.classify(p, f), "cosmic")
	for h in c.hot_px:
		if h.distance_to(c.asteroid_px[1]) > 60:
			var k := c.classify(h, 0)
			assert_true(k == "hot" or k == "cosmic", "hot pixel classified as %s" % k)


func test_difficulty_rules() -> void:
	assert_true(_challenge("explorer").cosmic_px[0].size() < _challenge("pro").cosmic_px[0].size())
	assert_true(_challenge("explorer").rules.tol > _challenge("pro").rules.tol)
	assert_eq(_challenge("explorer").hot_px.size(), 0)


func test_scoring() -> void:
	var c := _challenge("researcher")
	assert_true(c.score(10, 0, 0) > c.score(60, 0, 0), "faster is better")
	assert_true(c.score(20, 0, 0) > c.score(20, 3, 0), "fewer wrong taps is better")
	assert_true(c.score(20, 0, 0) > c.score(20, 0, 1), "no hints is better")
	assert_true(c.score(999, 50, 2) >= 100, "never below minimum")
	assert_eq(BlinkChallenge.stars_for(0, 0), 3)
	assert_eq(BlinkChallenge.stars_for(3, 1), 2)
	assert_eq(BlinkChallenge.stars_for(9, 2), 1)


func test_normalised_difficulty() -> void:
	# Every eligible scenario ends up with the target brightness and motion of its stage.
	var idx := AsteroidScenario.load_index()
	for diff in ["explorer", "researcher", "pro"]:
		var pool := BlinkChallenge.eligible(idx, diff)
		assert_true(pool.size() >= 3, "%s: only %d eligible scenarios" % [diff, pool.size()])
		var r: Dictionary = BlinkChallenge.RULES[diff]
		for e in pool:
			var c := BlinkChallenge.create(AsteroidScenario.load_by_id(e.id), diff, RandomNumberGenerator.new())
			var ok: bool = c.asteroid_mag >= r.mag - r.brighter - r.jitter - 0.01 and c.asteroid_mag <= r.mag + r.jitter + 0.01
			assert_true(ok, "%s %s brightness %.2f" % [diff, e.id, c.asteroid_mag])
			assert_true(c.depth <= BlinkChallenge.MAX_SHORTEN + 0.001, "exposure shortened too much")
			var px := c.motion_arcsec() / AsteroidScenario.ARCSEC_PER_PX
			assert_almost(px, r.motion_px, r.motion_px * 0.3, "%s %s motion" % [diff, e.id])


func test_crowding_bonus() -> void:
	assert_true(BlinkChallenge.crowding_for(1000) > BlinkChallenge.crowding_for(250))
	assert_almost(BlinkChallenge.crowding_for(250), 1.0, 0.001)
	assert_almost(BlinkChallenge.crowding_for(10), 0.8, 0.001, "lower clamp")
	assert_almost(BlinkChallenge.crowding_for(100000), 2.0, 0.001, "upper clamp")
	var c := _challenge("researcher")
	assert_true(c.visible_stars > 0)
	var sparse := c.score(30, 0, 0)
	c.crowding = 1.8
	assert_true(c.score(30, 0, 0) > sparse, "dense field scores more")


func test_same_seed_same_setup() -> void:
	var a := _challenge("pro", 99)
	var b := _challenge("pro", 99)
	assert_eq(a.asteroid_px, b.asteroid_px)
	assert_eq(a.center, b.center)
