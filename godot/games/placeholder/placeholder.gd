## Shown for games that are still being built: big icon, title, "coming soon" message.
extends Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())
	var entry: Dictionary = Router.current
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 36)
	add_child(v)
	var col: Color = entry.get("color", UiTheme.ACCENT)
	v.add_child(UiTheme.icon(entry.get("icon", "construction"), 240, col))
	var title := UiTheme.label(entry.get("title", ""), UiTheme.SIZE_TITLE, "serif")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var msg := UiTheme.label("PLACEHOLDER_MSG", UiTheme.SIZE_H2, "regular", UiTheme.TEXT_DIM)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg)
	var back := BigButton.make("BACK_TO_HUB", "home", true, 520)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): Router.go_home("home"))
	v.add_child(back)
