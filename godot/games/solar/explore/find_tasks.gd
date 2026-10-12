## "Find …" tasks of the solar-system explorer. Every task names what to look for; it is
## solved by tapping one of the accepted bodies (catalogue ids, or "class:<SBDB class>" for
## asteroids and Kuiper-belt objects). Level 0 = explorer, 1 = researcher, 2 = pro.
## `fly` is where the hint button flies to.
class_name FindTasks
extends RefCounted

const ROUND := 5
const HINT_AFTER := 30.0    # s
const TASKS := [
	{"id": "mars", "level": 0, "accept": ["mars"], "fly": "mars"},
	{"id": "saturn", "level": 0, "accept": ["saturn"], "fly": "saturn"},
	{"id": "jupiter", "level": 0, "accept": ["jupiter"], "fly": "jupiter"},
	{"id": "moon", "level": 0, "accept": ["moon"], "fly": "moon"},
	{"id": "mercury", "level": 0, "accept": ["mercury"], "fly": "mercury"},
	{"id": "earth", "level": 0, "accept": ["earth"], "fly": "earth"},
	{"id": "uranus", "level": 1, "accept": ["uranus"], "fly": "uranus"},
	{"id": "ceres", "level": 1, "accept": ["ceres"], "fly": "ceres"},
	{"id": "halley", "level": 1, "accept": ["halley"], "fly": "halley"},
	{"id": "bigmoon", "level": 1, "accept": ["ganymede", "titan"], "fly": "ganymede"},
	{"id": "neptune", "level": 1, "accept": ["neptune"], "fly": "neptune"},
	{"id": "pluto", "level": 1, "accept": ["pluto"], "fly": "pluto"},
	{"id": "io", "level": 1, "accept": ["io"], "fly": "io"},
	{"id": "proxima", "level": 1, "accept": ["deep:proxima"], "fly": "deep:proxima"},
	{"id": "eris", "level": 2, "accept": ["eris"], "fly": "eris"},
	{"id": "trojan", "level": 2, "accept": ["class:TJN"], "fly": "jupiter"},
	{"id": "neo", "level": 2, "accept": ["class:APO", "class:ATE", "class:AMO"], "fly": "earth"},
	{"id": "sedna", "level": 2, "accept": ["sedna"], "fly": "sedna"},
	{"id": "titan", "level": 2, "accept": ["titan"], "fly": "titan"},
	{"id": "67p", "level": 2, "accept": ["67p"], "fly": "67p"},
	{"id": "kuiper", "level": 2, "accept": ["class:TNO", "pluto", "haumea", "makemake", "eris"], "fly": "pluto"},
	{"id": "encke", "level": 2, "accept": ["encke"], "fly": "encke"},
	{"id": "oort", "level": 2, "accept": ["deep:oort"], "fly": "deep:oort"},
	{"id": "gc", "level": 2, "accept": ["deep:gc"], "fly": "deep:gc"},
]
## How many tasks of each level a round has, per difficulty.
const MIX := {"explorer": [5, 0, 0], "researcher": [2, 3, 0], "pro": [0, 2, 3]}


static func pick(diff: String, rng: RandomNumberGenerator) -> Array:
	var mix: Array = MIX.get(diff, MIX.researcher)
	var out := []
	for level in 3:
		var pool := TASKS.filter(func(t: Dictionary) -> bool: return int(t.level) == level)
		for k in range(pool.size() - 1, 0, -1):   # shuffle with the given rng
			var j := rng.randi_range(0, k)
			var tmp: Variant = pool[k]
			pool[k] = pool[j]
			pool[j] = tmp
		out.append_array(pool.slice(0, int(mix[level])))
	return out


## Is the tapped body (catalogue id, or SBDB class for a small body) a solution?
static func accepts(task: Dictionary, id: String, small_class := "") -> bool:
	if id in task.accept:
		return true
	return small_class != "" and ("class:" + small_class) in task.accept


static func points(seconds: float, hinted: bool) -> int:
	var p := maxi(100, 500 - int(seconds * 8.0))
	return p / 2 if hinted else p


## Stars from the points of a whole round (ROUND tasks).
static func stars(total: int) -> int:
	var avg := float(total) / ROUND
	if avg >= 330.0:
		return 3
	if avg >= 200.0:
		return 2
	return 1


static func score(total: int, diff: String) -> int:
	return int(total * float({"explorer": 1.0, "researcher": 1.5, "pro": 2.5}.get(diff, 1.0)))
