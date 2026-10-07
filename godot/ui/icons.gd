## Material Icons (classic font) code points used in the UI.
## tests/test_icons.gd checks that every glyph exists in the shipped font.
class_name Icons
extends RefCounted

const MAP := {
	"rocket_launch": 0xeb9b,
	"lightbulb": 0xe0f0,
	"arrow_forward": 0xe5c8,
	"add": 0xe145,
	"remove": 0xe15b,
	"rotate_left": 0xe419,
	"rotate_right": 0xe41a,
	"home": 0xe88a,
	"close": 0xe5cd,
	"check": 0xe5ca,
	"refresh": 0xe5d5,
	"volume_up": 0xe050,
	"volume_off": 0xe04f,
	"settings": 0xe8b8,
	"info": 0xe88e,
	"arrow_back": 0xe5c4,
	"casino": 0xeb40,
	"backspace": 0xe14a,
	"keyboard": 0xe312,
	"trophy": 0xea23,
	"star": 0xe838,
	"star_border": 0xe83a,
	"touch_app": 0xe913,
	"language": 0xe894,
	"lock": 0xe897,
	"power": 0xe8ac,
	"delete": 0xe872,
	"timer": 0xe425,
	"public": 0xe80b,
	"quiz": 0xf04c,
	"stars": 0xe8d0,
	"hub": 0xe9f4,
	"search": 0xe8b6,
	"extension": 0xe87b,
	"travel_explore": 0xe2db,
	"construction": 0xea3c,
	"blur_on": 0xe3a5,
	"brightness_3": 0xe3a8,
	"bar_chart": 0xe26b,
	"visibility": 0xe8f4,
	"person": 0xe7fd,
	"edit": 0xe3c9,
	"play_arrow": 0xe037,
}


static func get_char(icon_name: String) -> String:
	return String.chr(MAP.get(icon_name, 0xe88e))
