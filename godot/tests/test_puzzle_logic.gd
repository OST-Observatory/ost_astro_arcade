extends TestCase


func _logic(diff := "researcher", size := Vector2(2400, 1600)) -> PuzzleLogic:
	var p := PuzzleLogic.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	p.setup(size, diff, rng)
	return p


func test_grid_close_to_target_and_square_pieces() -> void:
	for diff in ["explorer", "researcher", "pro"]:
		for size in [Vector2(2400, 1600), Vector2(2400, 1340), Vector2(1211, 925)]:
			var p := _logic(diff, size)
			var target: int = PuzzleLogic.TARGET_PIECES[diff]
			assert_true(absi(p.piece_count() - target) <= target / 3, "%s %s: %d pieces" % [diff, size, p.piece_count()])
			var aspect := p.cell.x / p.cell.y
			assert_true(aspect > 0.65 and aspect < 1.5, "piece aspect %f" % aspect)


func test_pieces_tile_the_image() -> void:
	var p := _logic("pro")
	var area := 0.0
	for r in p.rows:
		for c in p.cols:
			var poly := p.polygon(c, r)
			assert_true(poly.size() >= 4)
			area += absf(_signed_area(poly))
	var img := p.image_size.x * p.image_size.y
	assert_almost(area / img, 1.0, 0.001, "pieces cover the image exactly")


func test_pieces_are_simple_polygons() -> void:
	# Self-intersecting outlines cannot be triangulated and would render empty.
	for diff in ["explorer", "pro"]:
		var p := _logic(diff)
		for r in p.rows:
			for c in p.cols:
				var tri := Geometry2D.triangulate_polygon(p.polygon(c, r))
				assert_true(tri.size() >= 3, "%s piece %d,%d cannot be triangulated" % [diff, c, r])


func test_neighbours_share_edges() -> void:
	var p := _logic("researcher")
	# Every vertex of an inner tab must appear in both neighbouring pieces.
	var left := p.polygon(0, 0)
	var right := p.polygon(1, 0)
	var shared := 0
	for v in left:
		for w in right:
			if v.distance_to(w) < 0.01:
				shared += 1
	assert_true(shared >= PuzzleLogic.EDGE_SAMPLES, "shared edge points: %d" % shared)


func test_score_and_stars() -> void:
	var p := _logic("explorer")
	assert_true(p.score(10) > p.score(200))
	assert_eq(p.stars(1), 3)
	assert_eq(p.stars(p.piece_count() * 6.0 * 3.0), 1)


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a / 2.0
