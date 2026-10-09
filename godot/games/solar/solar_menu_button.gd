## "Back to the choice" button of the solar-system modes, top right next to the title.
class_name SolarMenuButton
extends RefCounted


static func make(panel: Rect2) -> BigButton:
	var b := BigButton.make("SOL_MENU", "arrow_back", false, 420)
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	b.position = Vector2(panel.end.x - 420, 36)
	return b
