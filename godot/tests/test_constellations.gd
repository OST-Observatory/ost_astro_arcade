extends TestCase

const AREA := Vector2(1960, 1250)


func _logic(diff: String) -> ConstellationLogic:
	var l := ConstellationLogic.new()
	l.load_data()
	l.diff = diff
	return l


func test_data_complete() -> void:
	var l := _logic("explorer")
	assert_true(l.stars.size() > 4000, "stars: %d" % l.stars.size())
	for diff in ["explorer", "researcher", "pro"]:
		var n := l.constellations.filter(func(c): return c.level == diff).size()
		assert_true(n >= ConstellationLogic.ROUNDS, "%s has %d constellations" % [diff, n])
	for c in l.constellations:
		assert_true(c.edges.size() >= 4, "%s has lines" % c.id)
		for h in ConstellationLogic.members(c):
			assert_true(l.stars.has(h), "%s: star %d exists" % [c.id, h])
		for k in ["de", "en", "es"]:
			assert_true(str(c.name.get(k, "")) != "", "%s name %s" % [c.id, k])
			assert_true(str(c.fact.get(k, "")) != "", "%s fact %s" % [c.id, k])


func test_whole_figure_visible_at_every_level() -> void:
	for diff in ["explorer", "researcher", "pro"]:
		var l := _logic(diff)
		var rng := RandomNumberGenerator.new()
		for seed in 6:
			rng.seed = seed
			for c in l.constellations:
				var v := l.view_for(c, AREA, rng)
				for h in ConstellationLogic.members(c):
					var s: Array = l.stars[h]
					var p: Variant = ConstellationLogic.project(s[0], s[1], v.ra0, v.dec0)
					assert_true(p != null, "%s/%s star %d in front" % [diff, c.id, h])
					var xy: Vector2 = AREA / 2.0 + (p as Vector2) * float(v.scale)
					assert_true(Rect2(Vector2(30, 30), AREA - Vector2(60, 60)).has_point(xy), "%s/%s star %d on screen: %s" % [diff, c.id, h, xy])


func test_figure_stars_far_enough_apart_to_touch() -> void:
	var l := _logic("explorer")
	var rng := RandomNumberGenerator.new()
	for c in l.constellations:
		var v := l.view_for(c, AREA, rng)
		var pts := []
		for h in ConstellationLogic.members(c):
			var s: Array = l.stars[h]
			pts.append(AREA / 2.0 + (ConstellationLogic.project(s[0], s[1], v.ra0, v.dec0) as Vector2) * float(v.scale))
		var closest := INF
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				closest = minf(closest, (pts[i] as Vector2).distance_to(pts[j]))
		assert_true(closest > 20.0, "%s: closest stars %.0f px" % [c.id, closest])


func test_pick_is_unique_and_on_level() -> void:
	var l := _logic("pro")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var p := l.pick(rng)
	assert_eq(p.size(), ConstellationLogic.ROUNDS)
	var ids := {}
	for c in p:
		assert_eq(c.level, "pro")
		ids[c.id] = true
	assert_eq(ids.size(), ConstellationLogic.ROUNDS)


func test_points_and_stars() -> void:
	var l := _logic("researcher")
	assert_true(l.round_points(10, 0, 30.0) > l.round_points(10, 3, 30.0), "misses cost points")
	assert_true(l.round_points(10, 0, 20.0) > l.round_points(10, 0, 70.0), "speed pays")
	assert_true(l.round_points(5, 40, 300.0) >= 50, "never below the minimum")
	assert_eq(ConstellationLogic.stars_for(30, 2, 120.0), 3)
	assert_eq(ConstellationLogic.stars_for(30, 10, 300.0), 2)
	assert_eq(ConstellationLogic.stars_for(30, 30, 600.0), 1)
	assert_eq(ConstellationLogic.edge_key(5, 3), ConstellationLogic.edge_key(3, 5))
