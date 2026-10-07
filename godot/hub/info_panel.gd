## "About" overlay: what the OST is, plus image/font credits (CC licences require them).
class_name InfoPanel
extends Control

const CREDITS := [
	"OST-Logo, Fotos & Aufnahmen: OST, Universität Potsdam (Komet 67P: CC BY-NC-SA 3.0)",
	"Quiz-Bilder: siehe Bildnachweis unter jedem Bild",
	"Galaxien: NASA, ESA & Hubble Heritage Team / ACS Science Team (CC BY 4.0)",
	"Sternkarten: d3-celestial, Olaf Frohn (BSD-3), Daten ESA Hipparcos",
	"Asteroiden: JPL Horizons & SBDB (NASA/JPL-Caltech), ESA Gaia DR3 (CC BY-SA 3.0 IGO)",
	"Schriften: Inter (SIL OFL 1.1), CMU Serif (SIL OFL 1.1), Material Icons (Apache 2.0)",
	"Spiel-Engine: Godot Engine (MIT)",
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SCIENCE, 0.4), 3))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(1500, 0)
	v.add_theme_constant_override("separation", 26)
	panel.add_child(v)

	v.add_child(UiTheme.label("INFO_TITLE", UiTheme.SIZE_H2 + 8, "serif"))
	var body := UiTheme.label("INFO_BODY", UiTheme.SIZE_BODY, "regular")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	v.add_child(UiTheme.label("INFO_CREDITS", UiTheme.SIZE_BODY, "semibold", UiTheme.SCIENCE))
	for c in CREDITS:
		var l := UiTheme.label(c, UiTheme.SIZE_SMALL, "regular", UiTheme.TEXT_DIM)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var close := BigButton.make("CLOSE", "close", true, 360)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(queue_free)
	v.add_child(close)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.75))
