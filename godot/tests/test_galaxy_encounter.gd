extends TestCase

const GAME_STARS := 250   # stars per galaxy analysed in the game (galaxy_game.gd)


func _model(partner: String, approach: String, spin := 1.0) -> EncounterModel:
	var me := GalaxyTemplates.get_target("milkyway")
	var pt := GalaxyTemplates.get_target(partner)
	var m := EncounterModel.new()
	m.setup({"pot": me.reference, "target": me, "spin": spin}, {"pot": pt.reference, "target": pt, "spin": 1.0}, approach)
	return m


func test_centre_of_mass_stays_put() -> void:
	var m := _model("ngc3198", "grazing")
	var m1 := (m.gal[0].pot as GalaxyPotential).total_mass()
	var m2 := (m.gal[1].pot as GalaxyPotential).total_mass()
	for t in [0.0, 40.0, 120.0]:
		var com := (m.center(0, t) * m1 + m.center(1, t) * m2) / (m1 + m2)
		assert_true(com.length() < 1e-3, "centre of mass at t=%d: %s" % [t, com])


func test_pericentre_as_requested() -> void:
	for a in ["grazing", "wide"]:
		var m := _model("ddo154", a)
		var want: float = EncounterModel.APPROACH_Q[a] * m.radius(0)
		assert_almost(m.q_actual, want, 0.15 * want, "%s pericentre" % a)


func test_heavy_partners_merge_light_ones_fly_by() -> void:
	assert_true(_model("milkyway", "grazing").merged(), "twin grazing merges")
	assert_true(_model("ngc3198", "headon").merged(), "spiral head-on merges")
	assert_false(_model("ddo154", "wide").merged(), "dwarf passes by")
	assert_false(_model("milkyway", "wide").merged(), "wide encounter does not merge in time")


func test_features_for_recipes() -> void:
	var ring := _model("ngc3198", "headon")
	ring.run_stars(GAME_STARS)
	var f := FeatureDetector.detect(ring)
	assert_true(f.ring >= 0.0, "head-on with a smaller spiral makes a ring")
	assert_true(f.merger >= 0.0, "and they merge")
	var flyby := _model("ddo154", "wide")
	flyby.run_stars(GAME_STARS)
	f = FeatureDetector.detect(flyby)
	for k in ["bridge", "ring", "merger"]:
		assert_true(f[k] < 0.0, "a distant dwarf fly-by makes no %s" % k)


func test_deterministic() -> void:
	var a := _model("ngc3198", "grazing")
	var b := _model("ngc3198", "grazing")
	a.run_stars(40)
	b.run_stars(40)
	assert_true(a.snapshots[-1].stars == b.snapshots[-1].stars, "same stars, same result")


func test_collide_logic() -> void:
	var fresh := CollideLogic.new_badges({"tails": 30.0, "bridge": -1.0, "ring": 50.0, "merger": -1.0}, ["ring"])
	assert_eq(fresh, ["tails"] as Array[String])
	assert_eq(CollideLogic.recipe_hint(["tails", "merger", "ring", "bridge"]), "")
	assert_eq(CollideLogic.stars(true, 3), 3)
	assert_eq(CollideLogic.stars(false, 0), 1)
	assert_true(CollideLogic.total_points(500, 2, "pro") > CollideLogic.total_points(500, 2, "explorer"))


func test_gallery_saves_only_stable_galaxies() -> void:
	var path := "user://test_galaxy_gallery.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var g := GalaxyGalleryStore.new(path)
	assert_false(g.add("A", "milkyway", {}, 50.0, "explorer"), "unstable is refused")
	assert_true(g.add("B", "milkyway", {"stars": 1.0}, 97.0, "explorer"))
	assert_eq(GalaxyGalleryStore.new(path).entries.size(), 1)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	assert_eq(GalaxyGalleryStore.new(path).entries.size(), 0, "a broken file loads as empty")
	DirAccess.remove_absolute(path)
