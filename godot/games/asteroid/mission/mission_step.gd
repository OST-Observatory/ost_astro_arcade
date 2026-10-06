## Base class of one mission step: full-screen Control that emits `finished` when done.
## The common layout is a title, a one-sentence task and the step content below.
class_name MissionStep
extends Control

signal finished

var mission: MissionState


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Big serif step title + task sentence at the top left (below the progress bar).
func add_header(title_key: String, task_key: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(180, 150)
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiTheme.label(title_key, UiTheme.SIZE_H2 + 8, "serif"))
	var task := UiTheme.label(task_key, UiTheme.SIZE_BODY + 2, "regular", UiTheme.TEXT_DIM)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.custom_minimum_size = Vector2(1720, 0)
	v.add_child(task)
	add_child(v)
	return v


func plain_label(text: String, size: int, kind := "regular", color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(text, size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


func done() -> void:
	finished.emit()
