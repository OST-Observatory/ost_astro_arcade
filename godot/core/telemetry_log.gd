## Anonymous usage log: exactly ONE JSON line per game session (no personal data).
## {"game","start","end","duration_s","reason","difficulty","locale","score","steps":[[name, t_s], ...]}
class_name TelemetryLog
extends RefCounted

var path: String
var _current := {}
var _start_ms := 0


func _init(file_path: String) -> void:
	path = file_path


func is_active() -> bool:
	return not _current.is_empty()


func begin(game_id: String, difficulty := "", locale := "") -> void:
	if is_active():
		end("abandoned")
	_start_ms = Time.get_ticks_msec()
	_current = {
		"game": game_id,
		"start": Time.get_datetime_string_from_system(),
		"difficulty": difficulty,
		"locale": locale,
		"steps": [],
	}


func step(step_name: String) -> void:
	if is_active():
		_current.steps.append([step_name, _elapsed()])


## reason: "completed", "home", "idle", "error", "abandoned"
func end(reason: String, extra := {}) -> Dictionary:
	if not is_active():
		return {}
	var rec := _current
	rec["end"] = Time.get_datetime_string_from_system()
	rec["duration_s"] = _elapsed()
	rec["reason"] = reason
	rec.merge(extra, true)
	_current = {}
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(rec))
		f.close()
	return rec


func _elapsed() -> float:
	return snappedf((Time.get_ticks_msec() - _start_ms) / 1000.0, 0.1)


## Per-game summary for records whose "start" begins with `day` (YYYY-MM-DD).
## Returns {game_id: {"sessions", "completed", "median_s", "total_s"}}.
func summary(day: String) -> Dictionary:
	var per := {}
	if not FileAccess.file_exists(path):
		return per
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty():
			continue
		var rec: Variant = JSON.parse_string(line)
		if not (rec is Dictionary) or not str(rec.get("start", "")).begins_with(day):
			continue
		var g: Dictionary = per.get_or_add(rec.game, {"sessions": 0, "completed": 0, "durations": []})
		g.sessions += 1
		if rec.get("reason") == "completed":
			g.completed += 1
		g.durations.append(float(rec.get("duration_s", 0.0)))
	for gid in per:
		var d: Array = per[gid].durations
		d.sort()
		per[gid]["median_s"] = d[d.size() / 2] if not d.is_empty() else 0.0
		per[gid]["total_s"] = d.reduce(func(a, b): return a + b, 0.0)
		per[gid].erase("durations")
	return per
