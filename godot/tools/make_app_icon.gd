## Builds the Android launcher icons from the OST logo (white line art) on the night-blue
## of the hub. Run once after the logo changes:
##   godot --headless --path godot -s res://tools/make_app_icon.gd
extends SceneTree

const LOGO := "res://assets/brand/ost_logo_2048.png"
const OUT := "res://assets/brand/"
const BG := Color("0b1430")


func _init() -> void:
	# Classic icon: logo on a full square (the launcher rounds it itself).
	_save(_compose(192, 0.84, BG), "app_icon_192.png")
	# Adaptive icon: background layer plus the logo inside the 66 % safe zone.
	_save(_compose(432, 0.62, Color(0, 0, 0, 0)), "app_icon_fg_432.png")
	_save(_compose(432, 0.0, BG), "app_icon_bg_432.png")
	# Monochrome layer (themed icons on Android 13+): the logo's shape only.
	_save(_compose(432, 0.62, Color(0, 0, 0, 0)), "app_icon_mono_432.png")
	quit()


func _compose(size: int, logo_frac: float, bg: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	if logo_frac > 0.0:
		var logo := Image.load_from_file(ProjectSettings.globalize_path(LOGO))
		logo.convert(Image.FORMAT_RGBA8)
		var s := int(size * logo_frac)
		logo.resize(s, s, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i((size - s) / 2, (size - s) / 2)
		img.blend_rect(logo, Rect2i(Vector2i.ZERO, logo.get_size()), at)
	return img


func _save(img: Image, file_name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUT + file_name))
	print("wrote ", OUT + file_name)
