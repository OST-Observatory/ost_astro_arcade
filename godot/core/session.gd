## The current visitor (autoload `Session`): generated name, difficulty, running game.
## Everything is reset when the kiosk falls idle, so the next visitor starts fresh.
extends Node

signal changed

enum Difficulty { EXPLORER, RESEARCHER, PRO }

const DIFFICULTY_NAMES := ["explorer", "researcher", "pro"]

var player_name := ""
var custom_name := false
var difficulty := Difficulty.RESEARCHER
var game_id := ""


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func ensure_name() -> String:
	if player_name == "":
		reroll_name()
	return player_name


func reroll_name() -> void:
	player_name = NameGenerator.generate(I18n.locale)
	custom_name = false
	changed.emit()


func set_custom_name(n: String) -> bool:
	n = n.strip_edges()
	if n.length() < 2 or n.length() > 24 or not WordFilter.is_allowed(n):
		return false
	player_name = n
	custom_name = true
	changed.emit()
	return true


func set_difficulty(d: Difficulty) -> void:
	difficulty = d
	changed.emit()


func reset() -> void:
	player_name = ""
	custom_name = false
	difficulty = Difficulty.RESEARCHER
	game_id = ""
	I18n.reset()
	changed.emit()
