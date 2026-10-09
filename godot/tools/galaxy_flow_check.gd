## Dev tool: plays the galaxy collision act automatically (two recipes, badge pop-ups closed,
## then "done") and prints badges and state – catches flow bugs that unit tests miss.
##   godot --path godot -s res://tools/galaxy_flow_check.gd      (needs a GPU window)
extends SceneTree
func _initialize() -> void:
	await process_frame
	var store := GalaxyGalleryStore.new(root.get_node("Settings").data_path("galaxy_gallery.json"))
	if store.entries.is_empty():
		store.add("Test Eule", "milkyway", GalaxyTemplates.reference_knobs(GalaxyTemplates.get_target("milkyway")), 99.0, "explorer")
	var gg: Control = load("res://games/galaxy/galaxy_game.tscn").instantiate()
	gg.skip_intro = true
	root.add_child(gg)
	await process_frame
	gg._target = GalaxyTemplates.get_target("milkyway")
	gg._knobs = GalaxyTemplates.reference_knobs(gg._target)
	gg._unlocked = GalaxyTemplates.COMPONENTS.duplicate()
	gg._match = 99.0
	gg.start_collide()
	print("partners: ", gg._choice_buttons.keys())
	for recipe in [["spiral", "headon"], ["twin", "grazing"], ["dwarf", "wide"]]:
		gg._partner = recipe[0]
		gg._approach = recipe[1]
		gg._view.fixed_step = 0.05
		gg._run_collision()
		var t0 := Time.get_ticks_msec()
		var max_progress := 0.0
		while gg._running and Time.get_ticks_msec() - t0 < 240000:
			if gg._analysis:
				max_progress = maxf(max_progress, gg._analysis.progress())
			await process_frame
			# Close badge popups automatically.
			for c in gg.get_children():
				if c is ColorRect and c.get_child_count() > 0:
					var btns := c.find_children("*", "BigButton", true, false)
					if btns.size() > 0:
						btns[0].emit_signal("pressed")
		print("after %s/%s: running=%s badges=%s progress seen %.2f, start enabled %s | %s" % [recipe[0], recipe[1], gg._running,
			gg._badges, max_progress, not gg._start_btn.disabled, gg._info.text.replace("\n", " | ")])
	gg._finish()
	await process_frame
	print("finished, panels: ", gg.find_children("*", "ResultActions", true, false).size())
	# Remove the test galaxy again from the real gallery.
	var g := GalaxyGalleryStore.new(root.get_node("Settings").data_path("galaxy_gallery.json"))
	var keep := g.entries.filter(func(e): return e.player != "Test Eule")
	g.clear()
	for e in keep:
		g.add(e.player, e.target, e.knobs, float(e.match), "explorer")
	quit()
