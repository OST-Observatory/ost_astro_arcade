## Galaxies built by visitors (only stable ones), stored in <data_dir>/galaxy_gallery.json and
## offered as collision partners to later visitors.
class_name GalaxyGalleryStore
extends RefCounted

const MAX_ENTRIES := 200

var path: String
var entries: Array = []


func _init(file_path: String) -> void:
	path = file_path
	if FileAccess.file_exists(path):
		# A damaged file (power cut) just means an empty gallery; JSON.parse() does not log it.
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Array:
			entries = (json.data as Array).filter(func(e): return e is Dictionary and e.has("target") and e.has("knobs"))


## Saves a galaxy if it is stable; returns false otherwise.
func add(player: String, target_id: String, knobs: Dictionary, match: float, diff: String) -> bool:
	if not BuildLogic.is_stable(match, diff):
		return false
	entries.append({"player": player, "target": target_id, "knobs": knobs, "match": snappedf(match, 0.1),
		"ts": Time.get_datetime_string_from_system()})
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(entries))
	f.close()
	DirAccess.rename_absolute(tmp, path)
	return true


func latest(n: int) -> Array:
	return entries.slice(maxi(0, entries.size() - n))


func clear() -> void:
	entries = []
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
