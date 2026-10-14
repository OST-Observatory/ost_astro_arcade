## Dev tool: checks every hint recipe (CollideLogic.RECIPES) with the analysis the game uses
## – 8000 stars per galaxy on the graphics card – and with the CPU fallback (250 stars).
## The unit tests can only run the CPU part (headless has no graphics card).
##   godot --path godot -s res://tools/galaxy_recipe_check.gd
extends SceneTree


func _initialize() -> void:
	var bad := 0
	for target_id in CollideLogic.RECIPES:
		var me := GalaxyTemplates.get_target(target_id)
		for f in CollideLogic.RECIPES[target_id]:
			var r: Array = CollideLogic.RECIPES[target_id][f]
			var partner := ""
			for p in GalaxyTemplates.PARTNERS:
				if p[0] == r[0]:
					partner = p[1]
			var pt := GalaxyTemplates.get_target(partner)
			var spins := [1.0, -1.0] if int(r[2]) == 0 else [float(r[2])]
			for spin in spins:
				for gpu in [true, false]:
					var m := EncounterModel.new()
					m.setup({"pot": me.reference, "target": me, "spin": spin}, {"pot": pt.reference, "target": pt, "spin": 1.0}, r[1])
					if gpu:
						if not m.run_stars_gpu(8000):
							print("no graphics card")
							quit(1)
							return
					else:
						m.run_stars(250)
					var ok := float(FeatureDetector.detect(m)[f]) >= 0.0
					bad += 0 if ok else 1
					print("%s %-8s %-6s: %s %-7s spin %+d -> %s" % ["ok  " if ok else "FAIL", target_id, f, r[0], r[1], int(spin), "gpu" if gpu else "cpu"])
	print("%d recipes fail" % bad)
	quit(bad)
