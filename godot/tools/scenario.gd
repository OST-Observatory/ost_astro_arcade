## Puts the UI into a specific state for screenshots (used with tools/capture.gd).
##   OST_DATA_DIR=/tmp/ost_capture SCENARIO=attract godot --path godot -s res://tools/capture.gd -- res://tools/scenario.tscn captures/attract
## Scenarios: hub, en, es, attract, leaderboard, info, admin, dialog, idle, placeholder, start, keyboard
extends Control

const HUB := "res://hub/hub.tscn"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scenario := OS.get_environment("SCENARIO")
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
		"blink", "blink_loupe", "blink_hint", "blink_wrong", "blink_found":
			var diff := OS.get_environment("DIFF")
			if diff != "":
				Session.set_difficulty(Session.DIFFICULTY_NAMES.find(diff) as Session.Difficulty)
			var g: Control = load("res://games/asteroid/blink/blink_game.tscn").instantiate()
			g.skip_intro = true
			g.rng_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
			add_child(g)
			await get_tree().create_timer(0.5).timeout
			var a: Vector2 = g.challenge.asteroid_px[1] / Vector2(AsteroidScenario.IMAGE_SIZE) * g.IMAGE_RECT.size
			match scenario:
				"blink_loupe":
					g._paused = true
					g._show_frame(1)
					g._update_loupe(a + Vector2(40, 30))
				"blink_hint":
					g._elapsed = 50.0
				"blink_wrong":
					g._on_tap(Vector2(300, 300))
				"blink_found":
					g._on_tap(a)
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
