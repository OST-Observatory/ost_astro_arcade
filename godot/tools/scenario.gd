## Puts the UI into a specific state for screenshots (used with tools/capture.gd).
##   OST_DATA_DIR=/tmp/ost_capture SCENARIO=attract godot --path godot -s res://tools/capture.gd -- res://tools/scenario.tscn captures/attract
## Scenarios: hub, en, es, attract, leaderboard, info, admin, dialog, idle, placeholder, start, keyboard,
## psf, briefing and the asteroid mission steps: plan, align, expose, blink(_loupe/_hint/_wrong), measure, orbit, cert
extends Control

const HUB := "res://hub/hub.tscn"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scenario := OS.get_environment("SCENARIO")
	var diff := OS.get_environment("DIFF")
	if diff != "":
		Session.set_difficulty(Session.DIFFICULTY_NAMES.find(diff) as Session.Difficulty)
	await get_tree().process_frame
	match scenario:
		"en", "es":
			I18n.set_locale(scenario)
			_hub()
		"attract":
			_hub().get_node("AttractMode").start()
		"leaderboard":
			_fake_scores()
			var a: AttractMode = _hub().get_node("AttractMode")
			a.start()
			a._show_slide(a._slides.size() - 1)
		"info":
			_hub().add_child(InfoPanel.new())
		"admin":
			_fake_scores()
			var p := AdminPanel.new()
			_hub().add_child(p)
			p._show_main()
		"dialog":
			_hub()
			Dialog.ask(self, "HOME_CONFIRM",
				[["HOME_STAY", "play_arrow", false, "stay"], ["HOME_LEAVE", "home", true, "leave"]], "home")
		"idle":
			add_child(load(GameRegistry.PLACEHOLDER).instantiate())
			var o := IdleOverlay.new()
			add_child(o)
			o.show_countdown(7.2, 10.0)
		"start":
			add_child(Starfield.new())
			add_child(GameStartScreen.make(GameRegistry.get_entry("asteroid")))
		"keyboard":
			add_child(Starfield.new())
			add_child(GameStartScreen.make(GameRegistry.get_entry("asteroid")))
			var e := NameEntry.new()
			add_child(e)
			for ch in ["S", "T", "E", "R", "N", "SPACE", "A"]:
				e._kb._press(ch)
		"plan", "dome", "dome_open", "align", "expose", "blink", "blink_loupe", "blink_hint", "blink_wrong", "measure", "orbit", "cert", "briefing":
			var g: Control = load("res://games/asteroid/mission/asteroid_mission.tscn").instantiate()
			g.skip_intro = scenario != "briefing"
			g.rng_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
			var step_for := {"blink_loupe": "blink", "blink_hint": "blink", "blink_wrong": "blink", "cert": "__cert", "dome_open": "dome"}
			g.start_at = step_for.get(scenario, scenario) if scenario != "briefing" else ""
			if scenario == "briefing":
				g.skip_intro = false
			add_child(g)
			await get_tree().create_timer(0.6).timeout
			if scenario == "dome_open":
				g._step._open()
			if scenario == "briefing":
				for c in g.get_children():
					if c is GameStartScreen:
						c.start_pressed.emit()
			if scenario.begins_with("blink"):
				var b: BlinkStep = g._step
				var a: Vector2 = b.challenge.asteroid_px[1] / Vector2(AsteroidScenario.IMAGE_SIZE) * b.IMAGE_RECT.size
				print("ASTEROID_VIEW ", b.IMAGE_RECT.position + a, " mag ", snappedf(b.challenge.asteroid_mag, 0.01),
					" interval ", snappedf(b.challenge.interval_min, 0.1), " ", b.challenge.scenario.display_name())
				match scenario:
					"blink_loupe":
						b._paused = true
						b._show_frame(1)
						b._update_loupe(a + Vector2(40, 30))
					"blink_hint":
						b._elapsed = 50.0
					"blink_wrong":
						b._on_tap(Vector2(300, 300))
		"quiz", "quiz_answer", "quiz_result":
			var qg: Control = load("res://games/quiz/quiz_game.tscn").instantiate()
			qg.skip_intro = true
			qg.rng_seed = 11
			add_child(qg)
			await get_tree().create_timer(0.4).timeout
			if scenario == "quiz_answer":
				qg._on_answer((int(qg.logic.current().correct) + 1) % 4)
			elif scenario == "quiz_result":
				for k in QuizLogic.ROUND:
					qg.logic.answer(int(qg.logic.current().correct) if k % 3 != 0 else -1, 8.0)
				qg._layer.queue_free()
				qg._layer = null
				qg._show_result()
		"puzzle", "puzzle_half", "puzzle_done", "puzzle_pick":
			var pg: Control = load("res://games/puzzle/puzzle_game.tscn").instantiate()
			pg.skip_intro = scenario != "puzzle_pick"
			pg.rng_seed = 5
			if scenario == "puzzle_pick":
				pg.set_meta("pick_only", true)
			add_child(pg)
			await get_tree().create_timer(0.5).timeout
			if scenario == "puzzle_pick":
				pg._pick_image()
			elif scenario != "puzzle":
				var n: int = pg._pieces.size() if scenario == "puzzle_done" else pg._pieces.size() / 2
				for k in n:
					var p = pg._pieces[k]
					p.position = p.target
					pg._try_snap(p)
		"comet", "comet_found":
			var cb := CometBonus.new()
			add_child(cb)
			if scenario == "comet_found":
				await get_tree().process_frame
				cb._success()
		"gallery":
			_fake_gallery()
			add_child(GallerySlide.new())
		"solar", "solar_fly", "solar_result":
			var sg: Control = load("res://games/solar/solar_game.tscn").instantiate()
			sg.skip_intro = true
			add_child(sg)
			if scenario != "solar":
				await get_tree().process_frame
				var best := MarsTransfer.best_launch(sg._jd0, sg._jd0 + 800)
				sg._slider.slider.value = best - sg._jd0 + (0.0 if scenario == "solar_result" else 12.0)
				sg._launch()
		"con", "con_half", "con_done", "con_result":
			var cg: Control = load("res://games/constellations/constellation_game.tscn").instantiate()
			cg.skip_intro = true
			cg.rng_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3
			add_child(cg)
			if scenario != "con":
				await get_tree().process_frame
				var rounds := 3 if scenario == "con_result" else 1
				for r in rounds:
					var edges: Array = cg._con.edges
					var n := edges.size() if scenario != "con_half" else edges.size() / 2
					for k in n:
						cg._connect(int(edges[k][0]), int(edges[k][1]))
					if scenario == "con_half":
						cg._connect(int(edges[n][0]), cg._members[0] if cg._members[0] != int(edges[n][0]) else cg._members[1])
						cg._active = int(edges[n][0])
					if scenario == "con_result":
						cg._next_round()
		"galaxy", "galaxy_pick", "galaxy_run", "galaxy_result":
			var gg: Control = load("res://games/galaxy/galaxy_game.tscn").instantiate()
			gg.skip_intro = true
			if scenario != "galaxy_pick":
				gg.target_id = OS.get_environment("GAL") if OS.get_environment("GAL") != "" else "antennae"
			add_child(gg)
			if scenario in ["galaxy_run", "galaxy_result"]:
				await get_tree().process_frame
				await get_tree().process_frame
				gg._view.fixed_step = 1.0 / 30.0
				gg._run()
				if scenario == "galaxy_result":
					await gg._view.finished
					await get_tree().create_timer(2.5).timeout
					gg._finish()
		"galaxy_view":
			var vp := SubViewportContainer.new()
			vp.stretch = true
			vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(vp)
			var sv := SubViewport.new()
			sv.own_world_3d = true
			vp.add_child(sv)
			var gv := GalaxyView.new()
			sv.add_child(gv)
			var t := GalaxyLogic.target(OS.get_environment("GAL") if OS.get_environment("GAL") != "" else "antennae")
			gv.fixed_step = 1.0 / 30.0
			gv.setup(t.params, t.extent)
			gv.play()
		"obs_day", "obs_dusk", "obs_night", "obs_inside", "obs_street":
			var vp := SubViewportContainer.new()
			vp.stretch = true
			vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(vp)
			var sv := SubViewport.new()
			sv.own_world_3d = true
			sv.msaa_3d = Viewport.MSAA_4X
			vp.add_child(sv)
			var obs := ObservatoryScene.new()
			sv.add_child(obs)
			await get_tree().process_frame
			match scenario:
				"obs_day":
					obs.set_night(0.1)
					obs.set_shot("roof")
				"obs_street":
					obs.set_night(0.45)
					obs.set_shot("street")
				"obs_dusk":
					obs.set_night(0.55)
					obs.set_dome_azimuth(160.0)
					obs.set_shutter(0.5)
					obs.set_shot("dome_close")
				"obs_night":
					obs.set_night(1.0)
					obs.set_shutter(1.0)
					obs.point_to(-20.0, 20.0)
					print("TUBE dir ", obs.tube_direction(), " az ", obs.tube_azimuth())
					obs.set_shot("roof")
				"obs_inside":
					obs.set_night(1.0)
					obs.set_shutter(1.0)
					obs.point_to(-20.0, 20.0)
					obs.set_shot("inside")
		"psf":
			# PSF test chart: stars from 3 to 15 mag in a row, through the real CCD display.
			var stars := []
			var mags := [3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 15.0]
			for i in mags.size():
				stars.append([Vector2(110 + (i % 6) * 260, 260 + (i / 6) * 500), mags[i]])
			var frames := CcdFrames.new()
			add_child(frames)
			frames.build(stars, [{"asteroid": Vector2(-50, -50), "asteroid_mag": 30.0, "cosmics": [], "hot": [], "variable": {}, "satellite": []}])
			var view := TextureRect.new()
			view.texture = frames.textures[0]
			view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			view.size = Vector2(1536 * 1.25, 1024 * 1.25)
			var m := ShaderMaterial.new()
			m.shader = preload("res://games/asteroid/ccd/ccd_display.gdshader")
			m.set_shader_parameter("frame", frames.textures[0])
			m.set_shader_parameter("image_size", Vector2(1536, 1024))
			view.material = m
			add_child(view)
			for i in mags.size():
				var l := UiTheme.label("%.0f mag" % mags[i], 28, "medium", UiTheme.SCIENCE)
				l.position = (stars[i][0] + Vector2(-40, 200)) * 1.25
				add_child(l)
		"placeholder":
			Router.current = GameRegistry.get_entry("asteroid")
			add_child(load(GameRegistry.PLACEHOLDER).instantiate())
		_:
			_hub()


func _hub() -> Control:
	var h: Control = load(HUB).instantiate()
	add_child(h)
	for c in h.get_children():
		if c is AttractMode:
			c.name = "AttractMode"
	return h


func _fake_scores() -> void:
	Scores.store.clear_all()
	for e in [["Mutiger Komet 42", 1840], ["Anna", 1720], ["Funkelnde Nova 7", 1500],
			["Kühner Pulsar 13", 1210], ["Leo", 980]]:
		Scores.submit("asteroid", e[0], e[1], 3)


## A few visitor discoveries from the real scenarios (for the gallery slide).
func _fake_gallery() -> void:
	var idx: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/asteroid/index.json")).scenarios
	var store := GalleryStore.new(Settings.data_path("gallery.json"))
	if store.entries.size() >= 12:
		return
	var names := ["Kleiner Komet", "Mutige Eule", "Stern-Fuchs", "Luna", "Team Golm", "Schnelle Wega"]
	for i in 12:
		var sc := AsteroidScenario.load_by_id(str(idx[(i * 7) % idx.size()].id))
		store.add(names[i % names.size()], sc, 1500 + i * 37, 2)

