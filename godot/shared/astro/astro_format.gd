## Locale-aware formatting of dates and numbers for the astronomy screens.
class_name AstroFormat
extends RefCounted


static func _lang() -> String:
	return TranslationServer.get_locale().substr(0, 2)


## ISO date "2027-11-10" -> 10.11.2027 (de) / 10/11/2027 (es) / 2027-11-10 (en).
static func date(iso: String) -> String:
	var p := iso.substr(0, 10).split("-")
	match _lang():
		"de": return "%s.%s.%s" % [p[2], p[1], p[0]]
		"es": return "%s/%s/%s" % [p[2], p[1], p[0]]
	return iso.substr(0, 10)


## Number with a decimal comma in German/Spanish.
static func num(x: float, decimals: int) -> String:
	var s := String.num(x, decimals)
	return s.replace(".", ",") if _lang() in ["de", "es"] else s
