## Dev tool: renders GalaxyModel results for several parameter sets into one PNG grid.
##   GALAXY_SETS=/tmp/sets.json OUT=/tmp/out.png godot --headless --path godot --script res://tools/galaxy_preview.gd
## sets.json: [{"label": "...", "m2": 1, "q": 5, ..., "view": [yaw, pitch, roll]}, ...]
extends SceneTree

var CELL: int = int(OS.get_environment("CELL")) if OS.get_environment("CELL") != "" else 320


func _init() -> void:
	var sets: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GALAXY_SETS")))
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 6000
	var cols := mini(sets.size(), 4)
	var rows := int(ceil(sets.size() / float(cols)))
	var img := Image.create(CELL * cols, CELL * rows, false, Image.FORMAT_RGB8)
	for k in sets.size():
		var p: Dictionary = sets[k]
		if p.has("view"):
			p.view = Vector3(p.view[0], p.view[1], p.view[2])
		var t0 := Time.get_ticks_msec()
		var stars := GalaxyModel.simulate(p, n)
		var dt := Time.get_ticks_msec() - t0
		var m := GalaxyModel.density_map(p, stars, CELL / 2, GalaxyModel.MAP_EXTENT)
		var mx := 0.0
		for v in m:
			mx = maxf(mx, v)
		for y in CELL:
			for x in CELL:
				var v := m[(y / 2) * (CELL / 2) + x / 2] / mx
				img.set_pixel((k % cols) * CELL + x, (k / cols) * CELL + y, Color(v, v, v * 1.1))
		print("%s: %d ms" % [p.get("label", str(k)), dt])
	img.save_png(OS.get_environment("OUT"))
	quit()
