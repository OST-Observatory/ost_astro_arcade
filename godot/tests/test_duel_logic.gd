extends TestCase


func _logic() -> DuelLogic:
	var d := DuelLogic.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	d.new_round(rng)
	return d


func test_first_correct_gets_more() -> void:
	var d := _logic()
	var right := int(d.current().correct)
	var a := d.answer(1, right, 15.0)
	var b := d.answer(0, right, 10.0)
	assert_true(a > b and b > 0, "first %d, second %d" % [a, b])
	assert_eq(d.scores[1], a)


func test_wrong_and_double_answers() -> void:
	var d := _logic()
	var right := int(d.current().correct)
	assert_eq(d.answer(0, (right + 1) % 4, 15.0), 0)
	assert_eq(d.answer(0, right, 15.0), 0, "only one answer per question")
	assert_false(d.both_answered())
	d.answer(1, right, 5.0)
	assert_true(d.both_answered())
	d.next()
	assert_false(d.has_answered(0))


func test_round_and_winner() -> void:
	var d := _logic()
	assert_eq(d.questions.size(), DuelLogic.ROUND)
	assert_eq(d.winner(), -1)
	for i in DuelLogic.ROUND:
		d.answer(0, int(d.current().correct), 10.0)
		d.next()
	assert_true(d.is_finished())
	assert_eq(d.winner(), 0)
