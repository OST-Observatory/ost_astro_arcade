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


## Whole number with thousands separators: 139.820 (de), 139,820 (en), 139 820 (es).
static func grouped(x: float) -> String:
	var s := str(int(round(absf(x))))
	var sep: String = {"de": ".", "es": " "}.get(_lang(), ",")
	var out := ""
	while s.length() > 3:
		out = sep + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if x < 0.0 else "") + s + out


## A number with about three significant digits (0,0123 / 1,23 / 12,3 / 1.234).
static func sig(x: float) -> String:
	var ax := absf(x)
	if ax >= 1000.0:
		return grouped(x)
	if ax >= 100.0:
		return num(x, 0)
	if ax >= 10.0:
		return num(x, 1)
	if ax >= 1.0:
		return num(x, 2)
	return num(x, maxi(2, 2 - int(floor(log(maxf(ax, 1e-9)) / log(10.0)))))


## Month of an ISO date: 10.2026 (de), 10/2026 (es), 2026-10 (en).
static func month(iso: String) -> String:
	var p := iso.substr(0, 10).split("-")
	match _lang():
		"de": return "%s.%s" % [p[1], p[0]]
		"es": return "%s/%s" % [p[1], p[0]]
	return iso.substr(0, 7)
