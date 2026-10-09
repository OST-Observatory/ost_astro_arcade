extends TestCase


func _touch(g: TouchGestures, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	g.handle(e)


func _drag(g: TouchGestures, idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	g.handle(e)


func test_tap_with_any_touch_index() -> void:
	var g := TouchGestures.new()
	g.clock = 10.0
	var taps := []
	g.tapped.connect(func(p: Vector2): taps.append(p))
	_touch(g, 7, Vector2(100, 100), true)
	g.clock = 10.1
	_touch(g, 7, Vector2(105, 102), false)
	assert_eq(taps.size(), 1, "tap with index 7")


func test_drag_is_not_a_tap() -> void:
	var g := TouchGestures.new()
	g.clock = 1.0
	var taps := []
	var moved := [Vector2.ZERO]
	g.tapped.connect(func(p: Vector2): taps.append(p))
	g.dragged.connect(func(d: Vector2): moved[0] += d)
	_touch(g, 3, Vector2(100, 100), true)
	_drag(g, 3, Vector2(140, 100))
	_drag(g, 3, Vector2(200, 130))
	_touch(g, 3, Vector2(200, 130), false)
	assert_eq(taps.size(), 0, "no tap after dragging")
	assert_true(moved[0].distance_to(Vector2(100, 30)) < 0.01, "whole way reported: %s" % moved[0])


func test_double_tap() -> void:
	var g := TouchGestures.new()
	var doubles := []
	g.double_tapped.connect(func(p: Vector2): doubles.append(p))
	g.clock = 5.0
	_touch(g, 2, Vector2(300, 300), true)
	_touch(g, 2, Vector2(300, 300), false)
	g.clock = 5.3
	_touch(g, 4, Vector2(310, 305), true)
	_touch(g, 4, Vector2(310, 305), false)
	assert_eq(doubles.size(), 1)
	g.clock = 9.0   # much later: a single tap again
	_touch(g, 5, Vector2(310, 305), true)
	_touch(g, 5, Vector2(310, 305), false)
	assert_eq(doubles.size(), 1)


func test_pinch_any_lift_order() -> void:
	var g := TouchGestures.new()
	g.clock = 1.0
	var factor := [1.0]
	var taps := []
	g.pinched.connect(func(f: float, _c: Vector2): factor[0] *= f)
	g.tapped.connect(func(p: Vector2): taps.append(p))
	_touch(g, 3, Vector2(100, 100), true)
	_touch(g, 7, Vector2(200, 100), true)
	_drag(g, 7, Vector2(300, 100))      # distance 100 -> 200
	assert_almost(factor[0], 2.0, 1e-4, "zoom factor")
	_touch(g, 3, Vector2(100, 100), false)   # first finger lifts first
	_drag(g, 7, Vector2(320, 100))
	_touch(g, 7, Vector2(320, 100), false)
	assert_eq(taps.size(), 0, "a pinch is never a tap")
	assert_false(g.active(), "all fingers released")


func test_area_limits_start() -> void:
	var g := TouchGestures.new()
	g.area = Rect2(0, 0, 100, 100)
	assert_false(g.handle(_ev(1, Vector2(150, 50))), "outside the area")
	assert_true(g.handle(_ev(1, Vector2(50, 50))), "inside the area")


func _ev(idx: int, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = true
	return e
