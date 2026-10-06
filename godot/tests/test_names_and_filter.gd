extends TestCase


func test_generated_names_are_well_formed_and_allowed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for loc in ["de", "en", "es"]:
		for i in 300:
			var n := NameGenerator.generate(loc, rng)
			assert_true(n.length() >= 5 and n.length() <= 28, "length of '%s'" % n)
			assert_true(WordFilter.is_allowed(n), "generated name blocked: '%s'" % n)


func test_german_adjective_agrees_with_gender() -> void:
	var rng := RandomNumberGenerator.new()
	for i in 200:
		rng.seed = i
		var n := NameGenerator.generate("de", rng)
		var parts := n.split(" ")
		var adj := parts[0]
		var noun := parts[1]
		for entry in NameGenerator.DE_NOUN:
			if entry[0] == noun:
				var ending: String = NameGenerator.DE_END[entry[1]]
				assert_true(adj.ends_with(ending), "'%s' should end with -%s" % [n, ending])


func test_filter_blocks_variants() -> void:
	for bad in ["Fuck", "f.u.c.k", "FUUUCK", "Sch3isse", "Hitler", "nazi99", "88", "Hurensohn", "Mierda", "puta"]:
		assert_false(WordFilter.is_allowed(bad), "should block '%s'" % bad)


func test_filter_allows_normal_names() -> void:
	for ok in ["Anna", "Kometen-Kater", "Cockpit", "Analyse", "Fukushima", "Computadora", "Schwank",
			"Grapefruit", "Moby", "Sascha", "Hans 1988", "Mongolei", "Conocer"]:
		assert_true(WordFilter.is_allowed(ok), "should allow '%s'" % ok)


func test_filter_allows_astronomy_names() -> void:
	for ok in ["Polaris", "Polarlicht", "Pollux", "Uranus", "Andromeda", "Kassiopeia", "Betelgeuse",
			"Shoemaker-Levy", "Hale-Bopp", "Apophis", "Arrokoth", "Itokawa", "Fomalhaut", "Aldebaran",
			"Kopernikus", "Schwarzschild", "Hertzsprung", "Zwicky", "Tombaugh", "Potsdam", "Golm",
			"Babelsberg", "Kometenjäger", "Sternenstaub", "Supernova Sasha", "Cassini"]:
		assert_true(WordFilter.is_allowed(ok), "should allow '%s'" % ok)
