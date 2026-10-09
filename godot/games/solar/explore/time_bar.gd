## Time controls under the 3D view: date, speed buttons (backwards, pause, 1 day / 1 month /
## 1 year per second) and "today". Limited to 1850–2150, where the planet formulas hold.
class_name TimeBar
extends PanelContainer

const SPEEDS := [["fast_rewind", -30.0], ["pause", 0.0], ["play_arrow", 1.0], ["fast_forward", 30.0], ["skip_next", 365.0]]

var view: SolarView
var today := 0.0
var _date: Label
var _speed: Label
var _buttons: Array[BigButton] = []


static func make(v: SolarView, jd_today: float) -> TimeBar:
	var t := TimeBar.new()
	t.view = v
	t.today = jd_today
	return t


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.SURFACE, 0.8), UiTheme.LINE, 2, 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(430, 0)
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	_date = UiTheme.label("", UiTheme.SIZE_BODY + 2, "semibold", UiTheme.TEXT)
	_date.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_date)
	_speed = UiTheme.label("", UiTheme.SIZE_SMALL - 4, "medium", UiTheme.SCIENCE)
	_speed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_speed)
	for s in SPEEDS:
		var b := BigButton.make("", s[0], false, 100)
		var r: float = s[1]
		b.pressed.connect(func(): view.rate = r)
		row.add_child(b)
		_buttons.append(b)
	var now := BigButton.make("SOL_TODAY", "today", false)
	now.pressed.connect(func():
		view.jd = today
		view.rate = minf(view.rate, 1.0))
	row.add_child(now)


func _process(_delta: float) -> void:
	_date.text = AstroFormat.date(MarsTransfer.iso_from_jd(view.jd))
	_speed.text = tr("SOL_SPEED_%d" % int(view.rate)) if int(view.rate) in [-30, 0, 1, 30, 365] else ""
	for k in _buttons.size():
		var on: bool = float(SPEEDS[k][1]) == view.rate
		_buttons[k].modulate = Color(UiTheme.ACCENT_HI) if on else Color.WHITE
