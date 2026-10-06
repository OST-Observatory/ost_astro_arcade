## Persistent leaderboards per game (JSON file). Used by the `Scores` autoload and tests.
class_name ScoreStore
extends RefCounted

const MAX_PER_GAME := 500

var path: String
var _data := {}  # game_id -> Array[Dictionary]


func _init(file_path: String) -> void:
	path = file_path
	load_file()


func load_file() -> void:
	_data = {}
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_data = parsed


func save_file() -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("ScoreStore: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(_data))
	f.close()
	DirAccess.rename_absolute(tmp, path)


static func today() -> String:
	return Time.get_date_string_from_system()


## Adds an entry and returns {"entry", "rank_today", "rank_all"} (ranks are 1-based).
func submit(game_id: String, player: String, score: int, stars := 0, extra := {}) -> Dictionary:
	var entry := {
		"id": "%d_%d" % [Time.get_unix_time_from_system() * 1000, randi() % 100000],
		"name": player,
		"score": score,
		"stars": stars,
		"day": today(),
		"ts": Time.get_datetime_string_from_system(),
	}
	entry.merge(extra)
	var list: Array = _data.get(game_id, [])
	list.append(entry)
	_sort(list)
	if list.size() > MAX_PER_GAME:
		_trim(list)
	_data[game_id] = list
	save_file()
	return {
		"entry": entry,
		"rank_today": _rank_of(top(game_id, MAX_PER_GAME, true), entry.id),
		"rank_all": _rank_of(list, entry.id),
	}


func top(game_id: String, n := 10, today_only := false) -> Array:
	var out := []
	var day := today()
	for e in _data.get(game_id, []):
		if today_only and e.day != day:
			continue
		out.append(e)
		if out.size() >= n:
			break
	return out


func remove(game_id: String, entry_id: String) -> bool:
	var list: Array = _data.get(game_id, [])
	for i in list.size():
		if list[i].id == entry_id:
			list.remove_at(i)
			save_file()
			return true
	return false


## Clears today's entries of one game, or of all games when game_id is "".
func clear_today(game_id := "") -> void:
	var day := today()
	for gid in _data.keys():
		if game_id == "" or gid == game_id:
			_data[gid] = (_data[gid] as Array).filter(func(e): return e.day != day)
	save_file()


func clear_all() -> void:
	_data = {}
	save_file()


func game_ids() -> Array:
	return _data.keys()


static func _sort(list: Array) -> void:
	# Higher score first; on ties the earlier entry wins.
	list.sort_custom(func(a, b): return a.score > b.score or (a.score == b.score and a.ts < b.ts))


static func _rank_of(list: Array, entry_id: String) -> int:
	for i in list.size():
		if list[i].id == entry_id:
			return i + 1
	return -1


## Keeps the best entries plus everything from today.
static func _trim(list: Array) -> void:
	var day := today()
	var keep := []
	for e in list:
		if keep.size() < MAX_PER_GAME or e.day == day:
			keep.append(e)
	list.assign(keep)
