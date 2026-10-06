## Leaderboards (autoload `Scores`), stored in <data_dir>/scores.json.
extends Node

signal updated(game_id: String)

var store: ScoreStore


func _ready() -> void:
	store = ScoreStore.new(Settings.data_path("scores.json"))


func submit(game_id: String, player: String, score: int, stars := 0, extra := {}) -> Dictionary:
	var res := store.submit(game_id, player, score, stars, extra)
	updated.emit(game_id)
	return res


func top(game_id: String, n := 10, today_only := false) -> Array:
	return store.top(game_id, n, today_only)
