## Usage statistics (autoload `Telemetry`), one line per session in <data_dir>/telemetry.jsonl.
extends Node

var sessions: TelemetryLog


func _ready() -> void:
	sessions = TelemetryLog.new(Settings.data_path("telemetry.jsonl"))


func game_started(game_id: String) -> void:
	sessions.begin(game_id, Session.difficulty_name(), I18n.locale)


func step(step_name: String) -> void:
	sessions.step(step_name)


func game_ended(reason: String, extra := {}) -> void:
	sessions.end(reason, extra)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if sessions and sessions.is_active():
			sessions.end("abandoned")
