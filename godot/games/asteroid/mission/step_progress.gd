## Progress bar at the top of the mission: the six steps as icons, current one highlighted.
class_name StepProgress
extends HBoxContainer

const ICONS := {"plan": "timer", "dome": "power", "align": "travel_explore", "expose": "brightness_3",
	"blink": "visibility", "measure": "search", "orbit": "public"}

var _items := {}


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	for i in MissionState.STEPS.size():
		var id: String = MissionState.STEPS[i]
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var ic := UiTheme.icon(ICONS[id], 40, UiTheme.TEXT_DIM)
		var l := UiTheme.label("STEP_" + id.to_upper(), UiTheme.SIZE_SMALL, "medium", UiTheme.TEXT_DIM)
		box.add_child(ic)
		box.add_child(l)
		add_child(box)
		_items[id] = [ic, l]
		if i < MissionState.STEPS.size() - 1:
			var sep := UiTheme.label("›", UiTheme.SIZE_BODY, "regular", Color(UiTheme.TEXT_DIM, 0.5))
			sep.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			add_child(sep)


func set_current(step: String) -> void:
	var reached := true
	for id in MissionState.STEPS:
		var col := UiTheme.ACCENT if id == step else (UiTheme.SUCCESS if reached else UiTheme.TEXT_DIM)
		if id == step:
			reached = false
		for n in _items[id]:
			(n as Label).add_theme_color_override("font_color", col)
