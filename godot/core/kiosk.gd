## Kiosk runtime (autoload `Kiosk`): inactivity tracking, external apps, heartbeat.
## The Router decides what idleness means (attract mode in the hub, countdown in games).
extends Node

signal activity
signal external_finished(app_id: String, timed_out: bool)

const HEARTBEAT_SEC := 10.0
const POLL_SEC := 0.5

var idle_sec := 0.0
var external_pid := -1
var external_app := ""
var _external_elapsed := 0.0
var _poll := 0.0
var _heartbeat := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_write_heartbeat()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag \
			or event is InputEventMouseButton or event is InputEventKey:
		poke()


## Resets the idle timer (also usable by games with long passive animations).
func poke() -> void:
	idle_sec = 0.0
	activity.emit()


func _process(delta: float) -> void:
	idle_sec += delta
	_heartbeat += delta
	if _heartbeat >= HEARTBEAT_SEC:
		_heartbeat = 0.0
		_write_heartbeat()
	if external_pid > 0:
		_external_elapsed += delta
		_poll += delta
		if _poll >= POLL_SEC:
			_poll = 0.0
			_check_external()


## A systemd timer restarts the app if this file is older than ~60 s.
func _write_heartbeat() -> void:
	var f := FileAccess.open(Settings.data_path("heartbeat"), FileAccess.WRITE)
	if f:
		f.store_string(str(int(Time.get_unix_time_from_system())))


## Starts an external app (see docs/external_apps.md). Returns false on failure.
func launch_external(app_id: String, path: String, args: PackedStringArray, env := {}) -> bool:
	for k in env:
		OS.set_environment(k, str(env[k]))
	var pid := OS.create_process(path, args)
	if pid <= 0:
		push_error("Kiosk: could not start %s" % path)
		return false
	external_pid = pid
	external_app = app_id
	_external_elapsed = 0.0
	OS.low_processor_usage_mode = true
	return true


func _check_external() -> void:
	var limit: float = Settings.get_value("kiosk/external_max_sec")
	var timed_out := _external_elapsed > limit
	if timed_out:
		OS.kill(external_pid)
	if timed_out or not OS.is_process_running(external_pid):
		var app := external_app
		external_pid = -1
		external_app = ""
		OS.low_processor_usage_mode = false
		poke()
		external_finished.emit(app, timed_out)
