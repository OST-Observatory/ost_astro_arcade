## Quiz rules without UI (unit tested): picks 10 questions of rising difficulty for the
## chosen stage, scores answers (difficulty, speed, streak) and tracks jokers.
class_name QuizLogic
extends RefCounted

const DATA := "res://assets/data/quiz/questions.json"
const ROUND := 10
const TIME_PER_QUESTION := 20.0
const EXTRA_TIME := 15.0
## Question difficulty (1 layperson, 2 amateur, 3 astronomer) per position in the round.
const LADDER := {
	"explorer": [1, 1, 1, 1, 1, 1, 2, 2, 2, 2],
	"researcher": [1, 1, 1, 2, 2, 2, 2, 2, 3, 3],
	"pro": [1, 2, 2, 2, 2, 3, 3, 3, 3, 3],
}
const LEVEL_POINTS := {1: 100, 2: 150, 3: 250}

var all_questions: Array = []
var categories := {}
var round_questions: Array = []
var index := 0
var points := 0
var correct := 0
var streak := 0
var best_streak := 0
var joker_fifty := true
var joker_time := true


func load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	all_questions = parsed.questions
	categories = parsed.categories


## Draws a fresh round; `avoid` are question ids already seen in this session.
func new_round(difficulty: String, rng: RandomNumberGenerator, avoid: Array = []) -> void:
	if all_questions.is_empty():
		load_data()
	round_questions.clear()
	var used := {}
	for level in LADDER.get(difficulty, LADDER.researcher):
		var pool := all_questions.filter(func(q): return q.difficulty == level and not used.has(q.id))
		var fresh := pool.filter(func(q): return not avoid.has(q.id))
		if not fresh.is_empty():
			pool = fresh
		if pool.is_empty():
			pool = all_questions.filter(func(q): return not used.has(q.id))
		var q: Dictionary = pool[rng.randi() % pool.size()]
		used[q.id] = true
		round_questions.append(q)
	index = 0
	points = 0
	correct = 0
	streak = 0
	best_streak = 0
	joker_fifty = true
	joker_time = true


func current() -> Dictionary:
	return round_questions[index]


func is_finished() -> bool:
	return index >= round_questions.size()


## Registers an answer (-1 = time ran out). Returns the points earned.
func answer(choice: int, seconds_left: float) -> int:
	var q := current()
	var earned := 0
	if choice == int(q.correct):
		correct += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		earned = LEVEL_POINTS[int(q.difficulty)] + int(maxf(seconds_left, 0.0) * 5.0)
		if streak >= 3:
			earned += 25 * (streak - 2)
	else:
		streak = 0
	points += earned
	index += 1
	return earned


## 50:50 joker: two wrong answer indices to hide.
func fifty_fifty(rng: RandomNumberGenerator) -> Array:
	joker_fifty = false
	var wrong := [0, 1, 2, 3].filter(func(i): return i != int(current().correct))
	wrong.shuffle()
	return [wrong[0], wrong[1]] if rng == null else _pick_two(wrong, rng)


static func _pick_two(arr: Array, rng: RandomNumberGenerator) -> Array:
	var a: Array = arr.duplicate()
	var first: int = a.pop_at(rng.randi() % a.size())
	var second: int = a.pop_at(rng.randi() % a.size())
	return [first, second]


func stars() -> int:
	if correct >= 8:
		return 3
	return 2 if correct >= 5 else 1


static func text(q: Dictionary, field: String, locale: String) -> Variant:
	var d: Dictionary = q[field]
	return d.get(locale, d.get("en", d.values()[0] if not d.is_empty() else ""))
