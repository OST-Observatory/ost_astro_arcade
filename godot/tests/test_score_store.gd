extends TestCase

const PATH := "user://test_scores.json"
var store: ScoreStore


func before_each() -> void:
	DirAccess.remove_absolute(PATH)
	store = ScoreStore.new(PATH)


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func test_ranking_and_persistence() -> void:
	store.submit("quiz", "A", 100)
	store.submit("quiz", "B", 300)
	var res := store.submit("quiz", "C", 200)
	assert_eq(res.rank_all, 2, "rank of C")
	assert_eq(res.rank_today, 2, "today rank of C")
	var top := store.top("quiz", 2)
	assert_eq(top.size(), 2)
	assert_eq(top[0].name, "B")
	var reloaded := ScoreStore.new(PATH)
	assert_eq(reloaded.top("quiz", 10).size(), 3, "entries persisted")


func test_tie_keeps_earlier_first() -> void:
	store.submit("quiz", "first", 50)
	var res := store.submit("quiz", "second", 50)
	assert_eq(res.rank_all, 2)


func test_remove_and_clear_today() -> void:
	var e: Dictionary = store.submit("puzzle", "X", 10).entry
	store.submit("puzzle", "Y", 20)
	assert_true(store.remove("puzzle", e.id))
	assert_eq(store.top("puzzle").size(), 1)
	store.clear_today()
	assert_eq(store.top("puzzle").size(), 0)


func test_games_are_separate() -> void:
	store.submit("quiz", "A", 1)
	assert_eq(store.top("puzzle").size(), 0)
