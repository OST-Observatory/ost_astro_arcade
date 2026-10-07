extends TestCase


func test_orbit_reaches_pericentre_at_t_peri() -> void:
	var p := GalaxyModel.with_defaults({"q": 6.0, "e": 1.0, "friction": 0.0})
	var track := GalaxyModel.orbit_track(p)
	var closest := 1e9
	var t_closest := 0.0
	for i in track.size():
		var r := track[i].length()
		if r < closest:
			closest = r
			t_closest = i * GalaxyModel.TRACK_DT
	assert_almost(t_closest, GalaxyModel.T_PERI, 0.2, "closest approach at T_PERI")
	assert_almost(closest, 6.0, 0.05, "closest approach distance = q")


func test_friction_brings_cores_together() -> void:
	var p := GalaxyModel.with_defaults({"q": 5.0, "e": 0.9, "t_after": 80.0})
	var track := GalaxyModel.orbit_track(p)
	assert_true(track[track.size() - 1].length() < 5.0, "cores merge: %f" % track[track.size() - 1].length())


func test_simulation_is_deterministic() -> void:
	var t: Dictionary = GalaxyLogic.TARGETS[0]
	var a := GalaxyModel.simulate(t.params, 400)
	var b := GalaxyModel.simulate(t.params, 400)
	assert_eq(a.size(), 400)
	assert_true(a == b, "same seed, same stars")


func test_true_answer_scores_high_and_start_scores_low() -> void:
	for t in GalaxyLogic.TARGETS:
		var ref := GalaxyLogic.density(t, t.params)
		var again := GalaxyLogic.similarity(t, GalaxyModel.correlation(ref, GalaxyLogic.density(t, t.params, 3000, 99)))
		assert_true(again >= 95, "%s: true answer %d %%" % [t.id, again])
		var st := GalaxyLogic.start_values(t, GalaxyLogic.controls_for(t, "pro"))
		var start := GalaxyLogic.similarity(t, GalaxyModel.correlation(ref, GalaxyLogic.density(t, GalaxyLogic.params_for(t, st))))
		assert_true(start < 85, "%s: start values only %d %%" % [t.id, start])


func test_start_values_are_off_the_answer() -> void:
	for t in GalaxyLogic.TARGETS:
		var controls := GalaxyLogic.controls_for(t, "pro")
		var st := GalaxyLogic.start_values(t, controls)
		for c in controls:
			var spec: Array = GalaxyLogic.CONTROLS[c]
			var off := float(spec[2]) * (1.0 if c.begins_with("spin") else 1.5)
			assert_true(absf(float(st[c]) - float(t.params[c])) >= off, "%s/%s starts off" % [t.id, c])
			assert_true(float(st[c]) >= float(spec[0]) and float(st[c]) <= float(spec[1]), "%s/%s in range" % [t.id, c])


func test_controls_per_difficulty() -> void:
	var t: Dictionary = GalaxyLogic.TARGETS[0]
	assert_eq(GalaxyLogic.controls_for(t, "explorer").size(), 2)
	assert_eq(GalaxyLogic.controls_for(t, "researcher").size(), 3)
	assert_eq(GalaxyLogic.controls_for(t, "pro").size(), 4)


func test_hint_points_to_the_answer() -> void:
	var t := GalaxyLogic.target("antennae")
	var h := GalaxyLogic.hint(t, {"t_after": 20.0, "m2": 1.0, "q": 5.0})
	assert_eq(h, ["t_after", 1])
	h = GalaxyLogic.hint(t, {"t_after": 45.0, "m2": 1.0, "q": 11.0})
	assert_eq(h, ["q", -1])
	assert_eq(GalaxyLogic.hint(t, {"t_after": 45.0, "m2": 1.0, "q": 5.0}), [])


func test_score_and_stars() -> void:
	assert_eq(GalaxyLogic.stars(95), 3)
	assert_eq(GalaxyLogic.stars(80), 2)
	assert_eq(GalaxyLogic.stars(55), 1)
	assert_eq(GalaxyLogic.stars(20), 0)
	assert_true(GalaxyLogic.score(90, 2, "explorer") > GalaxyLogic.score(90, 5, "explorer"), "fewer attempts pay")
	assert_true(GalaxyLogic.score(90, 2, "pro") > GalaxyLogic.score(90, 2, "explorer"), "pro pays more")
	assert_true(GalaxyLogic.score(25, 1, "explorer") < GalaxyLogic.score(60, 5, "explorer"), "quitting early does not pay")
