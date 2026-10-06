## Asteroids observed by visitors ("Entdecker-Galerie"), stored in <data_dir>/gallery.json.
## The hub can show them later, e.g. all orbits together in the attract mode.
class_name GalleryStore
extends RefCounted

const MAX_ENTRIES := 300

var path: String
var entries: Array = []


func _init(file_path: String) -> void:
	path = file_path
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			entries = parsed


func add(player: String, sc: AsteroidScenario, points: int, stars: int) -> void:
	var el: Dictionary = sc.data.elements
	entries.append({
		"player": player, "number": sc.data.number, "name": sc.display_name(),
		"night": sc.data.night, "points": points, "stars": stars,
		"ts": Time.get_datetime_string_from_system(),
		"elements": {"a": el.a, "e": el.e, "incl": el.incl, "Omega": el.Omega, "w": el.w,
			"M": el.M, "n": el.n, "datetime_jd": el.datetime_jd},
	})
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(entries))
