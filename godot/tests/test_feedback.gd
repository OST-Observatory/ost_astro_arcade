extends TestCase

const DIR := "user://test_feedback"


func before_each() -> void:
	FeedbackStore.new(DIR).clear()


func test_saves_report_and_screenshot() -> void:
	var store := FeedbackStore.new(DIR)
	var img := Image.create(2560, 1440, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.3, 0.4))
	var id := store.save({"kind": "bug", "text": "Der Stern springt.", "game": "constellations"}, img)
	assert_true(id != "", "saved")
	assert_eq(store.count(), 1)
	var r := store.load_report(id)
	assert_eq(r.get("kind"), "bug")
	assert_eq(r.get("text"), "Der Stern springt.")
	assert_true(r.has("time"), "time stamped")
	assert_true(FileAccess.file_exists(DIR.path_join(id + ".jpg")), "screenshot written")
	var shot := Image.load_from_file(ProjectSettings.globalize_path(DIR.path_join(id + ".jpg")))
	assert_eq(shot.get_width(), FeedbackStore.SHOT_WIDTH)


func test_without_screenshot_and_clear() -> void:
	var store := FeedbackStore.new(DIR)
	store.save({"kind": "idea", "text": ""}, null)
	store.save({"kind": "other", "text": "x"}, null)
	assert_eq(store.count(), 2)
	store.clear()
	assert_eq(store.count(), 0)
