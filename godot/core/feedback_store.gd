## Feedback from testers, stored on the kiosk: one JSON file per report (kind, text, where in
## the app, version, time) plus a screenshot as JPEG, in <data_dir>/feedback/. Fetched with
## kiosk/fetch_feedback.sh. The oldest reports go when there are more than MAX_REPORTS.
class_name FeedbackStore
extends RefCounted

const MAX_REPORTS := 300
const SHOT_WIDTH := 1280
const KINDS := ["bug", "idea", "other"]

var dir: String


func _init(directory: String) -> void:
	dir = directory


## Saves a report (the screenshot may be null); returns its id.
func save(report: Dictionary, shot: Image) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var id := "%s_%04d" % [stamp, randi() % 10000]
	var r := report.duplicate()
	r["id"] = id
	r["time"] = Time.get_datetime_string_from_system(false, true)
	if shot != null:
		var img := shot.duplicate() as Image
		if img.get_width() > SHOT_WIDTH:
			img.resize(SHOT_WIDTH, int(img.get_height() * float(SHOT_WIDTH) / img.get_width()), Image.INTERPOLATE_BILINEAR)
		if img.save_jpg(dir.path_join(id + ".jpg"), 0.8) == OK:
			r["screenshot"] = id + ".jpg"
	# Written to a temporary file first, so a power cut never leaves half a report.
	var tmp := dir.path_join(id + ".json.tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(r, " "))
	f.close()
	DirAccess.rename_absolute(tmp, dir.path_join(id + ".json"))
	_prune()
	return id


## Report ids, oldest first.
func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


func count() -> int:
	return ids().size()


func load_report(id: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(dir.path_join(id + ".json"))) == OK and json.data is Dictionary:
		return json.data
	return {}


func clear() -> void:
	for id in ids():
		_remove(id)


func _prune() -> void:
	var all := ids()
	for i in maxi(all.size() - MAX_REPORTS, 0):
		_remove(all[i])


func _remove(id: String) -> void:
	for ext in [".json", ".jpg"]:
		if FileAccess.file_exists(dir.path_join(id + ext)):
			DirAccess.remove_absolute(dir.path_join(id + ext))


## Version of the running build: written next to the binary by kiosk/deploy.sh.
static func app_version() -> String:
	var path := OS.get_executable_path().get_base_dir().path_join("VERSION")
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	return "dev"
