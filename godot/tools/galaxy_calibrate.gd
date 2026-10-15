## Dev tool: runs every collision recipe (partner x approach x spin) for the Milky Way and
## prints closest approach, merger, detected features and timings. Used to tune the friction,
## approach presets and feature thresholds.
##   godot --headless --path godot --script res://tools/galaxy_calibrate.gd
##   GPU=1 godot --path godot --script res://tools/galaxy_calibrate.gd      (50000 stars on the GPU)
extends SceneTree


func _init() -> void:
	var player := GalaxyTemplates.get_target(OS.get_environment("GAL") if OS.get_environment("GAL") != "" else "milkyway")
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 400
	var gpu := OS.get_environment("GPU") != ""   # analysis as in the game (needs a window, not --headless)
	for partner in GalaxyTemplates.PARTNERS:
		var pt := GalaxyTemplates.get_target(partner[1])
		for approach in ["headon", "grazing", "wide"]:
			for spin in [1.0, -1.0]:
				if approach == "headon" and spin < 0:
					continue
				var m := EncounterModel.new()
				var t0 := Time.get_ticks_msec()
				m.setup({"pot": player.reference, "target": player, "spin": spin},
					{"pot": pt.reference, "target": pt, "spin": 1.0}, approach)
				var t1 := Time.get_ticks_msec()
				if gpu:
					m.run_stars_gpu(50000)
					m.baseline(50000)
				else:
					m.run_stars(n)
				var t2 := Time.get_ticks_msec()
				var f := FeatureDetector.detect(m)
				var feats := []
				for k in FeatureDetector.FEATURES:
					if f[k] >= 0.0:
						feats.append("%s@%d" % [k, int(f[k])])
				print("%-6s %-8s spin %+d | q %.2f (want %.2f) t_peri %.0f t_end %.0f merged %s | %s | track %d ms, stars %d ms" % [
					partner[0], approach, int(spin), m.q_actual, EncounterModel.APPROACH_Q[approach] * m.radius(0),
					m.t_peri, m.t_end, m.merged(), ", ".join(feats), t1 - t0, t2 - t1])
	quit()
