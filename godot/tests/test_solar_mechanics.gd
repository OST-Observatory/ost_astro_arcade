extends TestCase


func test_state_round_trip_closed_and_open() -> void:
	var jd := 2461000.5
	for v in [Vector3(0.0, 0.0172, 0.001), Vector3(0.002, 0.03, 0.0)]:   # bound, open
		var r := Vector3(1.0, 0.0, 0.0)
		var el := Kepler.elements_from_state(r, v, jd)
		var back := Kepler.state_position(el, jd)
		assert_true(back.distance_to(r) < 1e-5, "round trip e=%.3f: %s" % [el.e, back])
		# Energy is conserved along the orbit.
		var p1 := Kepler.state_position(el, jd + 40.0)
		var p2 := Kepler.state_position(el, jd + 40.1)
		var vel := (p2 - p1) / 0.1
		var e1: float = v.length_squared() / 2.0 - Kepler.GM_SUN / r.length()
		var e2: float = vel.length_squared() / 2.0 - Kepler.GM_SUN / ((p1 + p2) / 2.0).length()
		assert_almost(e2, e1, absf(e1) * 0.01 + 1e-9, "energy conserved")


func test_outer_planets_present() -> void:
	var jd := 2461000.5
	assert_almost(Kepler.planet_position("uranus", jd).length(), 19.5, 1.0)
	assert_almost(Kepler.planet_position("neptune", jd).length(), 29.9, 0.6)


func test_moon_meeus_example() -> void:
	# Meeus, Astronomical Algorithms, example 47.a: 1992-04-12 0h TD.
	var lbr := Moons.moon_lbr(2448724.5)
	assert_almost(lbr.x, 133.162655, 0.5, "longitude")
	assert_almost(lbr.y, -3.229126, 0.3, "latitude")
	assert_almost(lbr.z, 368409.7, 2000.0, "distance km")


func test_galilean_moons_periods() -> void:
	var jd := 2461000.0
	for m in ["io", "europa", "ganymede", "callisto"]:
		var p := float(Moons.CIRCULAR[m][2])
		var a := Moons.offset(m, jd)
		var b := Moons.offset(m, jd + p)
		assert_true(a.distance_to(b) < 1e-6, "%s back after one period" % m)
	var r := Moons.offset("io", jd).length() * Moons.KM_PER_AU
	assert_almost(r, 421700.0, 5.0)


func test_uranus_lies_on_its_side() -> void:
	# The IAU north pole of Uranus is 82 deg from the ecliptic normal and it spins backwards
	# (negative W rate) – i.e. an axial tilt of about 98 deg.
	var tilt := rad_to_deg(acos(Rotation.pole("uranus").dot(Vector3(0, 0, 1))))
	assert_true(tilt > 75.0 and tilt < 90.0, "Uranus pole from the ecliptic normal: %f" % tilt)
	assert_true(float(Rotation.POLES.uranus[3]) < 0.0, "retrograde spin")
	var earth := rad_to_deg(acos(Rotation.pole("earth").dot(Vector3(0, 0, 1))))
	assert_almost(earth, 23.44, 0.1)


func test_generic_hohmann_matches_mars_version() -> void:
	for jd in [2459060.5, 2461350.5]:
		var a := HohmannTransfer.compute("mars", jd)
		var b := MarsTransfer.compute(jd)
		assert_almost(a.miss_deg, b.miss_deg, 1e-6)
		assert_almost(a.days, b.days, 1e-6)
		assert_true(a.position_at(0.5).distance_to(b.position_at(0.5)) < 1e-6)


func test_jupiter_transfer() -> void:
	var t := HohmannTransfer.compute("jupiter", 2461000.5)
	assert_almost(t.days / 365.25, 2.73, 0.15, "flight time to Jupiter")
	var w1 := HohmannTransfer.next_window("jupiter", 2461000.5, 2461600.5)
	var w2 := HohmannTransfer.next_window("jupiter", w1 + 60.0, w1 + 600.0)
	assert_true(w1 > 0.0 and w2 > 0.0, "windows found")
	assert_almost(w2 - w1, 399.0, 20.0, "synodic period")


func test_inward_transfer_to_venus() -> void:
	var t := HohmannTransfer.compute("venus", 2461000.5)
	assert_false(t.outward)
	assert_almost(t.position_at(0.0).length(), t.r1, 1e-5, "leaves at Earth's distance")
	assert_almost(t.arrival_point().length(), t.r2, 1e-5, "arrives at Venus' orbit")
	assert_almost(t.days, 146.0, 6.0, "about five months")


func test_flyby_physics() -> void:
	var w := HohmannTransfer.next_window("jupiter", 2461000.5, 2461800.5)
	var t := HohmannTransfer.compute("jupiter", w)
	var near := Flyby.compute(t, 2.0, 1.0)
	var far := Flyby.compute(t, 20.0, 1.0)
	assert_almost(near.v_inf_in.length(), near.v_inf_out.length(), 1e-9, "|v_inf| conserved")
	assert_true(near.delta_deg > far.delta_deg, "closer pass turns more")
	assert_almost(near.v_inf_in.length() * Flyby.KM_PER_AU / Flyby.SEC_PER_DAY, 5.6, 1.0, "arrival speed relative to Jupiter (km/s)")
	var e_before := t.arrival_velocity().length_squared() / 2.0
	var vp := Kepler.planet_velocity("jupiter", near.jd_flyby)
	vp.z = 0.0
	for s in [1.0, -1.0]:
		var f := Flyby.compute(t, 3.0, s)
		var e_after: float = (vp + f.v_inf_out).length_squared() / 2.0
		assert_true(e_after > e_before, "side %+d gains energy" % int(s))


func test_saturn_via_jupiter_is_reachable() -> void:
	# The Jupiter windows of 2033–2036 lead to Saturn (conjunction around 2040) within its
	# Hill sphere (0.43 AU) – and so did the Voyager windows of 1976/77.
	for start in [2463900.5, 2442800.5]:   # end of 2033 (-> 2034 window), mid 1976
		var w := HohmannTransfer.next_window("jupiter", start, start + 450.0)
		var t := HohmannTransfer.compute("jupiter", w)
		var best := INF
		for side in [1.0, -1.0]:
			for rp in [1.5, 2.0, 3.0, 4.0, 6.0, 9.0, 12.0]:
				best = minf(best, float(Flyby.compute(t, rp, side).closest_to("saturn", 9.0)[0]))
		assert_true(best < 0.5, "window %s: Saturn missed by %.2f AU" % [MarsTransfer.iso_from_jd(w).left(10), best])
