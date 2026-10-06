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
