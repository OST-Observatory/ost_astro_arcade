## Quiz duel rules (two players at one screen): both answer the same question; the first
## correct answer gets the full points plus a speed bonus, a later correct answer half the
## base points, a wrong answer nothing. Each player answers once per question.
class_name DuelLogic
extends RefCounted

const ROUND := 8

var quiz := QuizLogic.new()
var questions: Array = []
var index := 0
var scores := [0, 0]
var choices := [-1, -1]      # this question
var earned := [0, 0]         # this question
var _first_correct := -1


func new_round(rng: RandomNumberGenerator, avoid: Array = []) -> void:
	quiz.new_round("researcher", rng, avoid)
	questions = quiz.round_questions.slice(0, ROUND)
	index = 0
	scores = [0, 0]
	_reset_question()


func current() -> Dictionary:
	return questions[index]


func is_finished() -> bool:
	return index >= questions.size()


func has_answered(player: int) -> bool:
	return choices[player] >= 0


func both_answered() -> bool:
	return has_answered(0) and has_answered(1)


## Registers a player's answer; returns the points (scored immediately, shown later).
func answer(player: int, choice: int, seconds_left: float) -> int:
	if has_answered(player):
		return 0
	choices[player] = choice
	var q := current()
	var pts := 0
	if choice == int(q.correct):
		var base: int = QuizLogic.LEVEL_POINTS[int(q.difficulty)]
		if _first_correct < 0:
			_first_correct = player
			pts = base + int(maxf(seconds_left, 0.0) * 5.0)
		else:
			pts = base / 2
	earned[player] = pts
	scores[player] += pts
	return pts


func next() -> void:
	index += 1
	_reset_question()


## 0 or 1, or -1 for a draw.
func winner() -> int:
	if scores[0] == scores[1]:
		return -1
	return 0 if scores[0] > scores[1] else 1


func _reset_question() -> void:
	choices = [-1, -1]
	earned = [0, 0]
	_first_correct = -1
