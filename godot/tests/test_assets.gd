extends TestCase


func test_all_icons_exist_in_font() -> void:
	var f: FontFile = load(UiTheme.FONT_DIR + "icons/MaterialIcons-Regular.ttf")
	for icon_name in Icons.MAP:
		assert_true(f.has_char(Icons.MAP[icon_name]), "missing glyph for icon '%s'" % icon_name)


func test_registry_entries_complete() -> void:
	var ids := {}
	for g in GameRegistry.GAMES:
		for key in ["id", "title", "desc", "icon", "color", "status"]:
			assert_true(g.has(key), "%s lacks %s" % [g.get("id", "?"), key])
		assert_true(Icons.MAP.has(g.icon), "unknown icon %s" % g.icon)
		assert_false(ids.has(g.id), "duplicate id %s" % g.id)
		ids[g.id] = true


func test_every_used_translation_key_exists() -> void:
	var csv := FileAccess.open("res://locale/ui.csv", FileAccess.READ)
	var keys := {}
	csv.get_csv_line()
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() == 4:
			keys[row[0]] = true
			for i in range(1, 4):
				assert_true(row[i].strip_edges() != "", "empty translation %s[%d]" % [row[0], i])
	for g in GameRegistry.GAMES:
		assert_true(keys.has(g.title) and keys.has(g.desc), "missing strings for %s" % g.id)
