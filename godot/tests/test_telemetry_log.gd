extends TestCase

const PATH := "user://test_telemetry.jsonl"


func before_each() -> void:
	DirAccess.remove_absolute(PATH)


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func _lines() -> PackedStringArray:
	return FileAccess.get_file_as_string(PATH).strip_edges().split("\n", false)


func test_one_line_per_session() -> void:
	var tl := TelemetryLog.new(PATH)
	tl.begin("quiz", "researcher", "de")
	tl.step("question_1")
	tl.end("completed", {"score": 120})
	tl.end("home")  # second end must be ignored (old launcher counted twice)
	var lines := _lines()
	assert_eq(lines.size(), 1, "exactly one record")
	var rec: Dictionary = JSON.parse_string(lines[0])
	assert_eq(rec.game, "quiz")
	assert_eq(rec.reason, "completed")
	assert_eq(int(rec.score), 120)
	assert_eq(rec.steps.size(), 1)


func test_begin_while_active_closes_previous() -> void:
	var tl := TelemetryLog.new(PATH)
	tl.begin("quiz")
	tl.begin("puzzle")
	tl.end("idle")
	var lines := _lines()
	assert_eq(lines.size(), 2)
	assert_eq(JSON.parse_string(lines[0]).reason, "abandoned")


func test_summary() -> void:
	var tl := TelemetryLog.new(PATH)
	for r in ["completed", "idle", "completed"]:
		tl.begin("asteroid")
		tl.end(r)
	var s := tl.summary(ScoreStore.today())
	assert_eq(int(s.asteroid.sessions), 3)
	assert_eq(int(s.asteroid.completed), 2)
	assert_true(tl.summary("1999-01-01").is_empty(), "other day is empty")
