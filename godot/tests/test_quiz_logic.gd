extends TestCase


func _logic(diff := "researcher", seed_value := 1) -> QuizLogic:
	var q := QuizLogic.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	q.new_round(diff, rng)
	return q


func test_data_complete() -> void:
	var q := QuizLogic.new()
	q.load_data()
	assert_true(q.all_questions.size() >= 100)
	for item in q.all_questions:
		for lang in ["de", "en", "es"]:
			assert_eq((item.answers[lang] as Array).size(), 4, "%s answers %s" % [item.id, lang])
			assert_true(str(item.explain.get(lang, "")) != "", "%s explanation %s" % [item.id, lang])
		if item.has("image"):
			assert_true(ResourceLoader.exists(item.image), "image %s" % item.image)


func test_round_has_rising_difficulty_and_no_duplicates() -> void:
	for diff in ["explorer", "researcher", "pro"]:
		var q := _logic(diff)
		assert_eq(q.round_questions.size(), QuizLogic.ROUND)
		var ids := {}
		for i in q.round_questions.size():
			ids[q.round_questions[i].id] = true
			assert_eq(int(q.round_questions[i].difficulty), QuizLogic.LADDER[diff][i], "%s position %d" % [diff, i])
		assert_eq(ids.size(), QuizLogic.ROUND, "no duplicates")


func test_scoring_and_streak() -> void:
	var q := _logic("explorer")
	var c: int = int(q.current().correct)
	var p1 := q.answer(c, 10.0)
	assert_eq(p1, 100 + 50, "level 1 + time bonus")
	q.answer(int(q.current().correct), 0.0)
	var p3 := q.answer(int(q.current().correct), 0.0)
	assert_eq(p3, 100 + 25, "streak bonus from the third correct answer")
	var wrong := (int(q.current().correct) + 1) % 4
	assert_eq(q.answer(wrong, 15.0), 0)
	assert_eq(q.streak, 0)
	assert_eq(q.correct, 3)
	assert_eq(q.best_streak, 3)


func test_fifty_fifty_keeps_correct_answer() -> void:
	var q := _logic()
	var rng := RandomNumberGenerator.new()
	var hidden := q.fifty_fifty(rng)
	assert_eq(hidden.size(), 2)
	assert_false(hidden.has(int(q.current().correct)))
	assert_false(q.joker_fifty)


func test_stars() -> void:
	var q := _logic()
	q.correct = 8
	assert_eq(q.stars(), 3)
	q.correct = 5
	assert_eq(q.stars(), 2)
	q.correct = 2
	assert_eq(q.stars(), 1)
