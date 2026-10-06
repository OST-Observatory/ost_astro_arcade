## Scene flow (autoload `Router`): hub <-> games, transitions, global overlays,
## in-game idle countdown and external apps. Games talk to the kiosk only through
## Router.step(), Router.complete() and Router.go_home().
extends Node

signal game_started(game_id: String)

const HUB_SCENE := "res://hub/hub.tscn"

var current: Dictionary = {}  # registry entry of the running game, {} in the hub
var _busy := false

var _fade: ColorRect
var _home_btn: BigButton
var _idle: IdleOverlay
var _fps: Label
var _overlay_root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.theme = UiTheme.build()
	_build_overlays()
	Kiosk.activity.connect(_on_activity)
	Kiosk.external_finished.connect(_on_external_finished)
	Settings.changed.connect(func(key): if key == "display/show_fps": _fps.visible = Settings.get_value(key))


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
	if Kiosk.idle_sec >= warn + total:
		_idle.hide_countdown()
		go_home("idle")
	elif Kiosk.idle_sec >= warn:
		_idle.show_countdown(warn + total - Kiosk.idle_sec, total)


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
	Telemetry.step(step_name)


## Called by a game when the visitor finished it. The game shows its own result screen.
func complete(result := {}) -> void:
	Telemetry.game_ended("completed", result)


func go_home(reason := "home") -> void:
	if _busy:
		return
	Telemetry.game_ended(reason)  # no-op if the game already completed
	current = {}
	_home_btn.visible = false
	_idle.hide_countdown()
	if reason == "idle":
		Session.reset()
	await _transition(HUB_SCENE)


func _confirm_home() -> void:
	var choice := await Dialog.ask(_overlay_root, "HOME_CONFIRM",
		[["HOME_STAY", "play_arrow", false, "stay"], ["HOME_LEAVE", "home", true, "leave"]], "home")
	if choice == "leave":
		go_home("home")


func _transition(scene_path: String) -> void:
	_busy = true
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
