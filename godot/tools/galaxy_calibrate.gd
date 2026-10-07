## Dev tool: measures, per galaxy target, the density-map correlation of random knob settings
## (base) and of the true settings with another star sample (ceil), plus the similarity of
## settings one and two steps off. Paste base/ceil into GalaxyLogic.TARGETS.
##   godot --headless --path godot --script res://tools/galaxy_calibrate.gd
extends SceneTree


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for t in GalaxyLogic.TARGETS:
		var ref := GalaxyLogic.density(t, t.params)
		var ceil_c := GalaxyModel.correlation(ref, GalaxyLogic.density(t, t.params, 3000, 99))
		var sum := 0.0
		var n := 24
		for i in n:
			var knobs := {}
			for c in GalaxyLogic.controls_for(t, "pro"):
				var spec: Array = GalaxyLogic.CONTROLS[c]
				var steps := int((float(spec[1]) - float(spec[0])) / float(spec[2]))
				knobs[c] = float(spec[0]) + float(spec[2]) * rng.randi_range(0, steps)
			sum += GalaxyModel.correlation(ref, GalaxyLogic.density(t, GalaxyLogic.params_for(t, knobs)))
		var base := sum / n
		var tt: Dictionary = t.duplicate()
		tt.base = base
		tt.ceil = ceil_c
		var line := "%s: base %.3f ceil %.3f |" % [t.id, base, ceil_c]
		for c in GalaxyLogic.controls_for(t, "pro"):
			var spec: Array = GalaxyLogic.CONTROLS[c]
			for k in [1, 2]:
				var knobs := {c: clampf(float(t.params[c]) + float(spec[2]) * k * (1 if float(t.params[c]) + float(spec[2]) * k <= float(spec[1]) else -1), float(spec[0]), float(spec[1]))}
				var s := GalaxyLogic.similarity(tt, GalaxyModel.correlation(ref, GalaxyLogic.density(t, GalaxyLogic.params_for(t, knobs))))
				line += " %s±%d: %d%%" % [c, k, s]
		var st := GalaxyLogic.start_values(t, GalaxyLogic.controls_for(t, "pro"))
		line += " | start: %d%%" % GalaxyLogic.similarity(tt, GalaxyModel.correlation(ref, GalaxyLogic.density(t, GalaxyLogic.params_for(t, st))))
		print(line)
	quit()
