## Full-screen procedural night sky (see starfield.gdshader).
class_name Starfield
extends ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = preload("res://ui/backgrounds/starfield.gdshader")
	material = m
	resized.connect(func(): m.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0)))


func set_brightness(v: float) -> void:
	(material as ShaderMaterial).set_shader_parameter("brightness", v)
