## Jigsaw geometry without UI (unit tested): grid size per stage, random tabs/blanks on
## every inner edge and the outline polygon of each piece in image pixel coordinates.
## Neighbouring pieces use exactly the same edge points (reversed), so they fit perfectly.
class_name PuzzleLogic
extends RefCounted

const TARGET_PIECES := {"explorer": 12, "researcher": 24, "pro": 48}
const EDGE_SAMPLES := 14   # points on the round head of a tab

var cols := 4
var rows := 3
var image_size := Vector2(2400, 1600)
var cell := Vector2.ZERO
var _h_edges := {}         # Vector2i(c, r) -> Array[Vector2]: edge between row r-1 and r, left->right
var _v_edges := {}         # Vector2i(c, r) -> Array[Vector2]: edge between col c-1 and c, top->bottom


## Grid closest to the target piece count with nearly square pieces.
static func grid_for(pieces: int, aspect: float) -> Vector2i:
	var best := Vector2i(4, 3)
	var best_err := INF
	for r in range(2, 12):
		var c := maxi(2, roundi(float(pieces) / r))
		var piece_aspect := aspect * r / c
		var err := absf(c * r - pieces) / pieces + absf(log(piece_aspect)) * 0.8
		if err < best_err:
			best_err = err
			best = Vector2i(c, r)
	return best


func setup(size: Vector2, difficulty: String, rng: RandomNumberGenerator) -> void:
	image_size = size
	var g := grid_for(TARGET_PIECES.get(difficulty, 24), size.x / size.y)
	cols = g.x
	rows = g.y
	cell = size / Vector2(cols, rows)
	_h_edges.clear()
	_v_edges.clear()
	for r in range(1, rows):
		for c in cols:
			var a := Vector2(c, r) * cell
			_h_edges[Vector2i(c, r)] = _edge(a, a + Vector2(cell.x, 0), Vector2(0, 1), rng)
	for c in range(1, cols):
		for r in rows:
			var a := Vector2(c, r) * cell
			_v_edges[Vector2i(c, r)] = _edge(a, a + Vector2(0, cell.y), Vector2(1, 0), rng)


func piece_count() -> int:
	return cols * rows


## Classic tab: straight, a narrow neck and a round head, mirrored at random to either side.
func _edge(a: Vector2, b: Vector2, normal: Vector2, rng: RandomNumberGenerator) -> Array[Vector2]:
	var length := a.distance_to(b)
	var d := (b - a) / length
	var s := 1.0 if rng.randf() < 0.5 else -1.0
	var shift := rng.randf_range(-0.04, 0.04)
	var head_r := rng.randf_range(0.10, 0.12)
	var cx := 0.5 + shift
	var cy := 0.17
	var prof: Array[Vector2] = [Vector2(0, 0), Vector2(cx - 0.14, 0.0), Vector2(cx - 0.10, 0.035), Vector2(cx - 0.095, 0.085)]
	for k in EDGE_SAMPLES + 1:
		var ang := deg_to_rad(lerpf(205.0, -25.0, float(k) / EDGE_SAMPLES))
		prof.append(Vector2(cx + head_r * cos(ang), cy + head_r * sin(ang)))
	prof.append_array([Vector2(cx + 0.095, 0.085), Vector2(cx + 0.10, 0.035), Vector2(cx + 0.14, 0.0), Vector2(1, 0)])
	var pts: Array[Vector2] = []
	for p in prof:
		pts.append(a + d * p.x * length + normal * p.y * length * s)
	return pts


## Outline of piece (c, r) in image pixels, clockwise starting at the top-left corner.
func polygon(c: int, r: int) -> PackedVector2Array:
	var tl := Vector2(c, r) * cell
	var tr := tl + Vector2(cell.x, 0)
	var br := tl + cell
	var bl := tl + Vector2(0, cell.y)
	var poly := PackedVector2Array()
	poly.append_array(_side(_h_edges.get(Vector2i(c, r), []), tl, tr, false))
	poly.append_array(_side(_v_edges.get(Vector2i(c + 1, r), []), tr, br, false))
	poly.append_array(_side(_h_edges.get(Vector2i(c, r + 1), []), br, bl, true))
	poly.append_array(_side(_v_edges.get(Vector2i(c, r), []), bl, tl, true))
	return poly


## One side without its last point (the next side starts there).
static func _side(edge: Array, a: Vector2, b: Vector2, reverse: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	if edge.is_empty():
		out.append(a)
		return out
	var pts := edge.duplicate()
	if reverse:
		pts.reverse()
	for i in pts.size() - 1:
		out.append(pts[i])
	return out


func cell_origin(c: int, r: int) -> Vector2:
	return Vector2(c, r) * cell


## Points for a finished puzzle: more for more pieces, bonus for speed.
func score(seconds: float) -> int:
	var base := piece_count() * 30
	var par := piece_count() * 6.0
	return base + int(maxf(0.0, par - seconds) * 10.0)


func stars(seconds: float) -> int:
	var par := piece_count() * 6.0
	if seconds <= par:
		return 3
	return 2 if seconds <= par * 2.0 else 1
