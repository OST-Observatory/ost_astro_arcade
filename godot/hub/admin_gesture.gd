## Hidden admin access: hold the top-left corner for 3 s, then tap the top-right,
## bottom-right and bottom-left corners (clockwise) within 6 s. Opens the PIN pad.
## Does not consume any input, so visitors never notice it.
class_name AdminGesture
extends Control

const CORNER := 180.0
const HOLD_SEC := 3.0
const SEQUENCE_SEC := 6.0

var _hold := -1.0      # >= 0 while the top-left corner is held
var _armed_at := -1.0  # time when the hold completed
var _next := 0         # index into the tap sequence
var _clock := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _corner_of(p: Vector2) -> int:
	var s := size
	if p.x < CORNER and p.y < CORNER: return 0
	if p.x > s.x - CORNER and p.y < CORNER: return 1
	if p.x > s.x - CORNER and p.y > s.y - CORNER: return 2
	if p.x < CORNER and p.y > s.y - CORNER: return 3
	return -1


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	var p: Vector2 = (make_input_local(event) as InputEventScreenTouch).position
	var c := _corner_of(p)
	if event.pressed:
		if c == 0 and _armed_at < 0.0:
			_hold = 0.0
		elif _armed_at >= 0.0:
			var expected: int = [1, 2, 3][_next]
			if c == expected:
				_next += 1
				if _next == 3:
					_reset()
					get_parent().add_child(AdminPanel.new())
			else:
				_reset()
	else:
		_hold = -1.0


func _process(delta: float) -> void:
	_clock += delta
	if _hold >= 0.0:
		_hold += delta
		if _hold >= HOLD_SEC:
			_hold = -1.0
			_armed_at = _clock
			_next = 0
	if _armed_at >= 0.0 and _clock - _armed_at > SEQUENCE_SEC:
		_reset()


func _reset() -> void:
	_hold = -1.0
	_armed_at = -1.0
	_next = 0
