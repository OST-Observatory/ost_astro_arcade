extends TestCase


func test_kepler_equation() -> void:
	for e in [0.0, 0.1, 0.5, 0.9]:
		for m in [0.1, 1.0, 3.0, 5.5]:
			var ea := Kepler.solve_eccentric_anomaly(m, e)
			assert_almost(ea - e * sin(ea), m, 1e-9, "e=%s M=%s" % [e, m])


func test_planet_distances_plausible() -> void:
	var jd := Kepler.jd_from_iso("2027-01-15T00:00:00Z")
	var r_earth := Kepler.planet_position("earth", jd).length()
	assert_almost(r_earth, 0.9835, 0.002, "Earth near perihelion in January")
	var r_mars := Kepler.planet_position("mars", jd).length()
	assert_true(r_mars > 1.38 and r_mars < 1.67, "Mars r=%f" % r_mars)
	var r_jup := Kepler.planet_position("jupiter", jd).length()
	assert_true(r_jup > 4.9 and r_jup < 5.5, "Jupiter r=%f" % r_jup)


func test_asteroid_matches_horizons_distance() -> void:
	# Propagating the stored elements must reproduce Horizons' heliocentric distance.
	var idx := AsteroidScenario.load_index()
	for k in mini(idx.size(), 12):
		var sc := AsteroidScenario.load_by_id(idx[k].id)
		var el: Dictionary = sc.data.elements
		for i in [0, sc.track.size() / 2, sc.track.size() - 1]:
			var t: Dictionary = sc.track[i]
			var r := Kepler.asteroid_position(el, Kepler.jd_from_iso(t.t)).length()
			assert_almost(r, float(t.r_au), 0.002, "%s at %s" % [sc.data.id, t.t])


func test_geocentric_distance_matches_horizons() -> void:
	var idx := AsteroidScenario.load_index()
	var sc := AsteroidScenario.load_by_id(idx[0].id)
	var t: Dictionary = sc.track[sc.data.best_index]
	var jd := Kepler.jd_from_iso(t.t)
	var d := (Kepler.asteroid_position(sc.data.elements, jd) - Kepler.planet_position("earth", jd)).length()
	# Earth-Moon barycentre vs. geocentre and light time: allow 0.01 AU.
	assert_almost(d, float(t.delta_au), 0.01, "delta")


func test_moid_earth_mars() -> void:
	var jd := Kepler.J2000
	var e := Kepler.planet_elements("earth", jd)
	var m := Kepler.planet_elements("mars", jd)
	var oe := Kepler.orbit_points(e.a, e.e, e.i, e.node, e.w, 360)
	var om := Kepler.orbit_points(m.a, m.e, m.i, m.node, m.w, 360)
	var d := Kepler.moid(oe, om)
	assert_true(d > 0.3 and d < 0.45, "Earth-Mars MOID %f" % d)


func test_local_time_dst() -> void:
	assert_eq(Kepler.local_time_hhmm("2027-07-01T20:00:00Z"), "22:00", "CEST")
	assert_eq(Kepler.local_time_hhmm("2027-12-01T20:00:00Z"), "21:00", "CET")
	assert_eq(Kepler.local_time_hhmm("2027-03-28T00:30:00Z"), "01:30", "before switch")
	assert_eq(Kepler.local_time_hhmm("2027-03-28T01:30:00Z"), "03:30", "after switch")
