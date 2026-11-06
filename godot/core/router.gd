## Scene flow (autoload `Router`): hub <-> games, transitions, global overlays,
## in-game idle countdown and external apps. Games talk to the kiosk only through
## Router.step(), Router.complete() and Router.go_home().
extends Node

signal game_started(game_id: String)

const HUB_SCENE := "res://hub/hub.tscn"

var current: Dictionary = {}  # registry entry of the running game, {} in the hub
var last_step := ""           # last progress step of the running game (for feedback)
var _busy := false

var _fade: ColorRect
var _home_btn: BigButton
var _feedback_btn: Button
var _idle: IdleOverlay
var _fps: Label
var _overlay_root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var theme := UiTheme.build()
	get_tree().root.theme = theme
	# Controls under a CanvasLayer or in a SubViewport do not inherit the window theme;
	# merged into the default theme, the same look applies everywhere.
	ThemeDB.get_default_theme().merge_with(theme)
	_build_overlays()
	Kiosk.activity.connect(_on_activity)
	Kiosk.external_finished.connect(_on_external_finished)
	# Android's back button: handled in _notification instead of quitting at once.
	get_tree().quit_on_go_back = false
	Settings.changed.connect(func(key):
		if key == "display/show_fps":
			_fps.visible = Settings.get_value(key)
		elif key == "feedback/enabled":
			_feedback_btn.visible = Settings.get_value(key))


func _build_overlays() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_overlay_root = Control.new()
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay_root)

	_home_btn = BigButton.make("", "home")
	_home_btn.custom_minimum_size = Vector2(120, 120)
	_home_btn.position = Vector2(32, 32)
	_home_btn.add_theme_font_size_override("font_size", 64)
	_home_btn.sound = "back"
	_home_btn.visible = false
	_home_btn.pressed.connect(_confirm_home)
	_overlay_root.add_child(_home_btn)

	# Feedback for testers: a slim tab flush with the right edge, low enough to miss the hub's
	# cards and clear of the corners used by the admin gesture. Narrow so that it stays off the
	# games' right-hand panels (they end at x <= 2510). Switched off in the admin menu.
	_feedback_btn = Button.new()
	_feedback_btn.focus_mode = Control.FOCUS_NONE
	_feedback_btn.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_feedback_btn.offset_left = -44
	_feedback_btn.offset_right = 0
	_feedback_btn.offset_top = 200
	_feedback_btn.offset_bottom = 332
	for st in [["normal", UiTheme.SURFACE, UiTheme.LINE], ["hover", UiTheme.SURFACE_HI, Color(UiTheme.ACCENT, 0.6)],
			["pressed", UiTheme.ACCENT, UiTheme.ACCENT_HI]]:
		var sb := UiTheme.box(st[1], st[2])
		sb.set_content_margin_all(0)
		sb.corner_radius_top_right = 0
		sb.corner_radius_bottom_right = 0
		sb.border_width_right = 0
		_feedback_btn.add_theme_stylebox_override(st[0], sb)
	var fb_icon := UiTheme.icon("feedback", 36, UiTheme.TEXT)
	fb_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fb_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fb_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fb_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_btn.add_child(fb_icon)
	_feedback_btn.modulate = Color(1, 1, 1, 0.85)
	_feedback_btn.visible = Settings.get_value("feedback/enabled")
	_feedback_btn.pressed.connect(_open_feedback)
	_overlay_root.add_child(_feedback_btn)

	_idle = IdleOverlay.new()
	_overlay_root.add_child(_idle)

	_fps = UiTheme.label("", UiTheme.SIZE_SMALL, "medium", UiTheme.SCIENCE)
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.offset_left = -240
	_fps.offset_top = 16
	_fps.visible = Settings.get_value("display/show_fps")
	_overlay_root.add_child(_fps)

	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 128
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	fade_layer.add_child(_fade)


func _process(_delta: float) -> void:
	if _fps.visible:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
	if current.is_empty() or Kiosk.external_pid > 0:
		return
	var warn: float = Settings.get_value("kiosk/idle_warning_sec")
	var total: float = Settings.get_value("kiosk/idle_countdown_sec")
	if warn <= 0.0:
		return
	if Kiosk.idle_sec >= warn + total:
		_idle.hide_countdown()
		go_home("idle")
	elif Kiosk.idle_sec >= warn:
		_idle.show_countdown(warn + total - Kiosk.idle_sec, total)


## Back (Android): closes an open dialog, in a game asks like the home button, in the hub quits.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or _busy:
		return
	for c in _overlay_root.get_children():
		if c is Dialog or c is FeedbackPanel:
			_close_dialogs()
			return
	if is_in_game():
		_confirm_home()
	else:
		get_tree().quit()


func _on_activity() -> void:
	if _idle.visible:
		_idle.hide_countdown()


# --- public API for hub and games --------------------------------------------------

func is_in_game() -> bool:
	return not current.is_empty()


func start_game(game_id: String) -> void:
	if _busy or is_in_game():
		return
	var entry := GameRegistry.get_entry(game_id)
	if entry.is_empty():
		return
	Session.game_id = game_id
	Session.ensure_name()
	last_step = ""
	if GameRegistry.is_external(entry):
		_start_external(entry)
		return
	current = entry
	var scene: String = entry.scene if entry.get("scene", "") != "" else GameRegistry.PLACEHOLDER
	await _transition(scene)
	Telemetry.game_started(game_id)
	_home_btn.visible = true
	game_started.emit(game_id)


## Records a progress step of the running game (for the drop-off funnel in telemetry).
func step(step_name: String) -> void:
	last_step = step_name
	Telemetry.step(step_name)


## Called by a game when the visitor finished it. The game shows its own result screen.
func complete(result := {}) -> void:
	Telemetry.game_ended("completed", result)


func go_home(reason := "home") -> void:
	if _busy:
		return
	_close_dialogs()
	Telemetry.game_ended(reason)  # no-op if the game already completed
	current = {}
	last_step = ""
	_home_btn.visible = false
	_idle.hide_countdown()
	if reason == "idle":
		Session.reset()
	await _transition(HUB_SCENE)


## Restarts the running game at its start screen, so the visitor can pick another
## difficulty (or simply start over).
func restart_current() -> void:
	if _busy or not is_in_game():
		return
	var game_id: String = current.id
	Telemetry.game_ended("restart")
	current = {}
	_home_btn.visible = false
	start_game(game_id)


## The "change difficulty" button for result screens (same action as the overlay button).
func restart_button(min_width := 0) -> BigButton:
	var b := BigButton.make("CHANGE_DIFFICULTY", "tune", false, min_width)
	b.pressed.connect(restart_current)
	return b


## The home button asks first: keep playing, start over with another difficulty, or leave.
func _confirm_home() -> void:
	var buttons := [["HOME_STAY", "play_arrow", false, "stay"]]
	if current.get("scene", "") != "":
		buttons.append(["CHANGE_DIFFICULTY", "tune", false, "restart"])
	buttons.append(["HOME_LEAVE", "home", true, "leave"])
	get_tree().paused = true   # timers and simulations stop while the dialog is open
	var choice := await Dialog.ask(_overlay_root, "HOME_CONFIRM", buttons, "home")
	get_tree().paused = false
	if choice == "leave":
		go_home("home")
	elif choice == "restart":
		restart_current()


## Closes open overlay dialogs (e.g. when the idle timeout fires) and resumes the game.
func _close_dialogs() -> void:
	for c in _overlay_root.get_children():
		if c is Dialog or c is FeedbackPanel:
			c.queue_free()
	get_tree().paused = false


## Feedback: the screenshot first (the panel must not be on it), then the panel; the app
## waits while it is open.
func _open_feedback() -> void:
	if _busy or Kiosk.external_pid > 0:
		return
	for c in _overlay_root.get_children():
		if c is FeedbackPanel or c is Dialog:
			return
	_feedback_btn.visible = false
	await RenderingServer.frame_post_draw
	var panel := FeedbackPanel.new()
	panel.shot = get_viewport().get_texture().get_image()
	var was_paused := get_tree().paused
	get_tree().paused = true
	_overlay_root.add_child(panel)
	await panel.closed
	get_tree().paused = was_paused
	_feedback_btn.visible = Settings.get_value("feedback/enabled")


func _transition(scene_path: String) -> void:
	_busy = true
	get_tree().paused = false
	Audio.play("whoosh", "SFX")
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	await create_tween().tween_property(_fade, "modulate:a", 1.0, 0.25).finished
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	await create_tween().tween_property(_fade, "modulate:a", 0.0, 0.35).finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


# --- external apps -------------------------------------------------------------------

func _start_external(entry: Dictionary) -> void:
	var path := GameRegistry.external_path(entry)
	var args := PackedStringArray()
	args.append_array([entry.external.root_flag, path.get_base_dir()])
	args.append_array(entry.external.args)
	var env := {"ASTRO_LANG": I18n.locale, "SDL_VIDEODRIVER": "wayland"}
	_fade.modulate.a = 1.0
	if Kiosk.launch_external(entry.id, path, args, env):
		Telemetry.game_started(entry.id)
	else:
		_fade.modulate.a = 0.0


func _on_external_finished(_app_id: String, timed_out: bool) -> void:
	Telemetry.game_ended("idle" if timed_out else "home")
	create_tween().tween_property(_fade, "modulate:a", 0.0, 0.4)
