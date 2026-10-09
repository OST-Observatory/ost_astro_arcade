extends TestCase


func test_every_task_target_exists() -> void:
	for t in FindTasks.TASKS:
		assert_true(BodyCatalog.has(t.fly), "%s: fly target %s" % [t.id, t.fly])
		for a in t.accept:
			if str(a).begins_with("class:"):
				assert_true(str(a).substr(6) in SmallBodies.CLASSES, "%s: class %s" % [t.id, a])
			else:
				assert_true(BodyCatalog.has(a), "%s: body %s" % [t.id, a])


func test_task_facts() -> void:
	# The texts claim these facts – check them against the data.
	var jd := 2461000.5
	assert_true(BodyCatalog.radius_km("ganymede") > BodyCatalog.radius_km("mercury"), "Ganymede > Mercury")
	assert_true(BodyCatalog.radius_km("titan") > BodyCatalog.radius_km("mercury"), "Titan > Mercury")
	assert_true(float(BodyCatalog.elements("eris", jd).i) > 40.0, "Eris inclined > 40 deg")
	for d in ["ceres", "pluto", "haumea", "makemake", "sedna"]:
		assert_true(float(BodyCatalog.elements(d, jd).i) < 40.0, "%s below 40 deg" % d)
	assert_true(BodyCatalog.period_days("sedna", jd) / 365.25 > 10000.0, "Sedna > 10,000 years")
	var shortest := ""
	var best := INF
	for c in ["halley", "67p", "halebopp", "encke"]:
		if BodyCatalog.period_days(c, jd) < best:
			best = BodyCatalog.period_days(c, jd)
			shortest = c
	assert_eq(shortest, "encke", "comet with the shortest period")


func test_round_mix() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for diff in ["explorer", "researcher", "pro"]:
		var tasks := FindTasks.pick(diff, rng)
		assert_eq(tasks.size(), FindTasks.ROUND, diff)
		var ids := {}
		for t in tasks:
			ids[t.id] = true
		assert_eq(ids.size(), FindTasks.ROUND, "%s: no task twice" % diff)


func test_accepts_and_points() -> void:
	var trojan: Dictionary = FindTasks.TASKS.filter(func(t): return t.id == "trojan")[0]
	assert_true(FindTasks.accepts(trojan, "sb:12", "TJN"))
	assert_false(FindTasks.accepts(trojan, "sb:12", "MBA"))
	assert_false(FindTasks.accepts(trojan, "jupiter"))
	assert_true(FindTasks.points(5.0, false) > FindTasks.points(40.0, false), "faster = more")
	assert_true(FindTasks.points(5.0, true) < FindTasks.points(5.0, false), "hint costs points")
	assert_eq(FindTasks.stars(FindTasks.ROUND * 500), 3)
	assert_eq(FindTasks.stars(FindTasks.ROUND * 100), 1)


func test_small_body_packing_matches_cpu() -> void:
	# The shader's orbit vectors give the same position as Kepler on the CPU.
	var rows := SmallBodies.load_rows(400)
	assert_true(rows.size() > 300)
	var classes := {}
	for r in rows:
		classes[r[8]] = true
	assert_eq(classes.size(), SmallBodies.CLASSES.size(), "thinning keeps every class")
	var epoch := 2461200.5
	var jd := 2462000.25
	for k in [0, 57, 123, rows.size() - 1]:
		var r: Array = rows[k]
		var pk := SmallBodies.pack(r, epoch)
		var t: Transform3D = pk[0]
		var c: Color = pk[1]
		var m := fposmod(c.g + c.b * (jd - epoch), TAU)
		var ea := Kepler.solve_eccentric_anomaly(m, c.r)
		var gpu := t.basis.x * (cos(ea) - c.r) + t.basis.y * sin(ea)
		var cpu := Kepler.to_godot(SmallBodies.position_of(r, jd))
		assert_true(gpu.distance_to(cpu) < 1e-4 * maxf(1.0, cpu.length()), "row %d: %s vs %s" % [k, gpu, cpu])


func test_moon_and_planet_positions() -> void:
	var jd := 2461000.5
	var d := (BodyCatalog.helio("moon", jd) - BodyCatalog.helio("earth", jd)).length() * Kepler.AU_KM
	assert_true(d > 356000.0 and d < 407000.0, "Moon distance %f km" % d)
	assert_almost(BodyCatalog.helio("ceres", jd).length(), 2.77, 0.25, "Ceres in the belt")
	assert_eq(BodyCatalog.orbit_points("io", jd, 32).size(), 33)
