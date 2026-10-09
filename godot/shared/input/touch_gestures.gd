## Raw touch gestures for 3D views: one finger drags (rotate), two fingers pinch (zoom),
## a short touch without movement is a tap, two taps close together a double tap.
## Touches are kept by index in a dictionary – X11 numbers touches on and on, so index 0
## must never be assumed. Mouse input arrives here too (emulate_touch_from_mouse).
## Feed events with handle(); positions are in the caller's coordinates, `area` limits where
## a gesture may start.
class_name TouchGestures
extends RefCounted

signal tapped(pos: Vector2)
signal double_tapped(pos: Vector2)
signal dragged(delta: Vector2)
signal pinched(factor: float, center: Vector2)   # factor > 1: fingers apart (zoom in)

const TAP_MOVE := 24.0       # px a tap may wander
const TAP_TIME := 0.4        # s
const DOUBLE_TIME := 0.45    # s between two taps
const DOUBLE_DIST := 60.0    # px between two taps

var area := Rect2(-1e9, -1e9, 2e9, 2e9)
var clock := -1.0            # >= 0: fixed time in seconds (tests); otherwise the real clock
var _touches := {}           # index -> position
var _down_pos := Vector2.ZERO
var _down_time := 0.0
var _moved := false
var _last_tap_time := -100.0
var _last_tap_pos := Vector2.ZERO


func _now() -> float:
	return clock if clock >= 0.0 else Time.get_ticks_msec() / 1000.0


func active() -> bool:
	return not _touches.is_empty()


## Returns true if the event belonged to a gesture of this area.
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var idx: int = event.index
		if event.pressed:
			if _touches.is_empty() and not area.has_point(event.position):
				return false
			_touches[idx] = event.position
			if _touches.size() == 1:
				_moved = false
				_down_pos = event.position
				_down_time = _now()
			else:
				_moved = true   # a second finger: never a tap
			return true
		if not _touches.has(idx):
			return false
		_touches.erase(idx)
		if _touches.is_empty() and not _moved and _now() - _down_time <= TAP_TIME:
			var pos: Vector2 = event.position
			if _now() - _last_tap_time <= DOUBLE_TIME and pos.distance_to(_last_tap_pos) <= DOUBLE_DIST:
				_last_tap_time = -100.0
				double_tapped.emit(pos)
			else:
				_last_tap_time = _now()
				_last_tap_pos = pos
				tapped.emit(pos)
		return true
	if event is InputEventScreenDrag:
		var idx: int = event.index
		if not _touches.has(idx):
			return false
		var old: Vector2 = _touches[idx]
		if _touches.size() == 1:
			_touches[idx] = event.position
			if not _moved and event.position.distance_to(_down_pos) > TAP_MOVE:
				_moved = true
				dragged.emit(event.position - _down_pos)   # the way so far, nothing is lost
			elif _moved:
				dragged.emit(event.position - old)
			return true
		# Two (or more) fingers: the first two by index pinch.
		var keys := _touches.keys()
		keys.sort()
		var a: int = keys[0]
		var b: int = keys[1]
		if idx != a and idx != b:
			return true
		var other: Vector2 = _touches[b if idx == a else a]
		var d_old := old.distance_to(other)
		_touches[idx] = event.position
		var d_new: Vector2 = event.position - other
		if d_old > 1.0 and d_new.length() > 1.0:
			pinched.emit(d_new.length() / d_old, (event.position + other) / 2.0)
		return true
	return false
