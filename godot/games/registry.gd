## All games shown in the hub, in display order.
## status: "ready" (playable), "soon" (placeholder scene, hidden unless general/show_upcoming).
## External apps start a separate process (docs/external_apps.md) and are only shown if
## the binary exists on this machine.
class_name GameRegistry
extends RefCounted

const PLACEHOLDER := "res://games/placeholder/placeholder.tscn"

const GAMES := [
	{"id": "asteroid", "title": "GAME_ASTEROID", "desc": "GAME_ASTEROID_DESC", "icon": "search",
		"color": Color("ffb347"), "scene": "res://games/asteroid/mission/asteroid_mission.tscn", "status": "ready"},
	{"id": "quiz", "title": "GAME_QUIZ", "desc": "GAME_QUIZ_DESC", "icon": "quiz",
		"color": Color("4dd0e1"), "scene": "res://games/quiz/quiz_game.tscn", "status": "ready"},
	{"id": "puzzle", "title": "GAME_PUZZLE", "desc": "GAME_PUZZLE_DESC", "icon": "extension",
		"color": Color("ff8a80"), "scene": "", "status": "soon"},
	{"id": "galaxy", "title": "GAME_GALAXY", "desc": "GAME_GALAXY_DESC", "icon": "blur_on",
		"color": Color("b39ddb"), "scene": "", "status": "soon"},
	{"id": "solar", "title": "GAME_SOLAR", "desc": "GAME_SOLAR_DESC", "icon": "public",
		"color": Color("81c784"), "scene": "", "status": "soon"},
	{"id": "constellations", "title": "GAME_CONSTELLATIONS", "desc": "GAME_CONSTELLATIONS_DESC",
		"icon": "stars", "color": Color("90caf9"), "scene": "", "status": "soon"},
	{"id": "nbody", "title": "GAME_NBODY", "desc": "GAME_NBODY_DESC", "icon": "hub",
		"color": Color("f48fb1"), "status": "ready",
		"external": {"path_setting": "external/nbody_path",
			"args": ["--width", "2560", "--height", "1440", "--timeout", "180", "--exit-on-timeout", "--quiet"],
			"root_flag": "--root"}},
]


static func get_entry(game_id: String) -> Dictionary:
	for g in GAMES:
		if g.id == game_id:
			return g
	return {}


static func is_external(entry: Dictionary) -> bool:
	return entry.has("external")


static func external_path(entry: Dictionary) -> String:
	return Settings.get_value(entry.external.path_setting)


## Games the hub should show right now.
static func visible_games() -> Array:
	var show_upcoming: bool = Settings.get_value("general/show_upcoming")
	var out := []
	for g in GAMES:
		if not Settings.is_game_enabled(g.id):
			continue
		if g.status == "soon" and not show_upcoming:
			continue
		if is_external(g) and not FileAccess.file_exists(external_path(g)):
			continue
		out.append(g)
	return out
