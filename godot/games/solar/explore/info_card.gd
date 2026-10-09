## Info card for a tapped body: name, type, a few numbers computed for the current date
## (distance, orbital period, size, mass) and a short text. Small bodies get their class.
class_name InfoCard
extends PanelContainer

signal fly_pressed(id: String)

const SB_GROUP := {"MBA": "BELT", "IMB": "BELT", "OMB": "BELT", "TJN": "TJN", "TNO": "TNO",
	"APO": "NEO", "ATE": "NEO", "AMO": "NEO", "CEN": "CEN"}

var id := ""
var _title: Label
var _type: Label
var _facts: Label
var _text: Label
var _fly: BigButton
var _width := 700.0


static func make(width: float) -> InfoCard:
	var c := InfoCard.new()
	c._width = width
	return c


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE, Color(UiTheme.SCIENCE, 0.4), 2, 22))
	custom_minimum_size = Vector2(_width, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	_title = _plain(UiTheme.SIZE_H2 - 8, "serif", UiTheme.TEXT)
	v.add_child(_title)
	_type = _plain(UiTheme.SIZE_SMALL, "semibold", UiTheme.SCIENCE)
	v.add_child(_type)
	_facts = _plain(UiTheme.SIZE_SMALL - 2, "medium", UiTheme.TEXT)
	v.add_child(_facts)
	_text = _plain(UiTheme.SIZE_SMALL - 2, "regular", UiTheme.TEXT_DIM)
	v.add_child(_text)
	_fly = BigButton.make("SOL_FLY_TO", "near_me", false, int(_width - 60))
	_fly.pressed.connect(func(): fly_pressed.emit(id))
	v.add_child(_fly)
	visible = false


func _plain(font_size: int, kind: String, col: Color) -> Label:
	var l := UiTheme.label("", font_size, kind, col)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_width - 60, 0)
	return l


func show_body(body: String, view: SolarView) -> void:
	id = body
	visible = body != ""
	if body == "":
		return
	var jd := view.jd
	var lines: Array[String] = []
	if body.begins_with("sb:"):
		var row: Array = view.small.rows[int(body.substr(3))]
		var group: String = SB_GROUP.get(SmallBodies.class_of(row), "BELT")
		_title.text = tr("SOL_SB_" + group)
		_type.text = tr("SOL_SB_TYPE")
		var r := SmallBodies.position_of(row, jd).length()
		lines.append(tr("SOL_FACT_SUN_DIST") % [AstroFormat.sig(r), AstroFormat.grouped(r * Kepler.AU_KM / 1e6)])
		lines.append(tr("SOL_FACT_PERIOD_Y") % AstroFormat.sig(Kepler.period_years(float(row[0]))))
		lines.append(tr("SOL_FACT_INCL") % AstroFormat.num(float(row[2]), 1))
		_text.text = tr("SOL_SBD_" + group)
	else:
		_title.text = BodyCatalog.display_name(body)
		_type.text = BodyCatalog.type_text(body)
		var kind := BodyCatalog.kind(body)
		if kind == "moon":
			var par := BodyCatalog.parent(body)
			lines.append(tr("SOL_FACT_ORBITS") % BodyCatalog.display_name(par))
			lines.append(tr("SOL_FACT_PLANET_DIST") % AstroFormat.grouped(Moons.offset(body, jd).length() * Kepler.AU_KM))
			lines.append(tr("SOL_FACT_PERIOD_D") % AstroFormat.sig(BodyCatalog.period_days(body, jd)))
		elif kind != "star":
			var r := BodyCatalog.helio(body, jd).length()
			lines.append(tr("SOL_FACT_SUN_DIST") % [AstroFormat.sig(r), AstroFormat.grouped(r * Kepler.AU_KM / 1e6)])
			var pd := BodyCatalog.period_days(body, jd)
			lines.append(tr("SOL_FACT_PERIOD_D") % AstroFormat.sig(pd) if pd < 1000.0 \
				else tr("SOL_FACT_PERIOD_Y") % AstroFormat.sig(pd / 365.25))
			if kind != "planet":
				lines.append(tr("SOL_FACT_INCL") % AstroFormat.num(float(BodyCatalog.elements(body, jd).i), 1))
		if body != "earth":
			var de := (BodyCatalog.helio(body, jd) - BodyCatalog.helio("earth", jd)).length()
			lines.append(tr("SOL_FACT_EARTH_DIST") % (AstroFormat.sig(de) + " " + tr("SOL_AU_UNIT")) if de > 0.01 \
				else tr("SOL_FACT_EARTH_DIST") % (AstroFormat.grouped(de * Kepler.AU_KM) + " km"))
		lines.append(tr("SOL_FACT_DIAM") % AstroFormat.grouped(BodyCatalog.radius_km(body) * 2.0))
		var m := BodyCatalog.mass_kg(body)
		if m > 0.0:
			lines.append(tr("SOL_FACT_MASS") % AstroFormat.sig(m / BodyCatalog.EARTH_MASS))
		_text.text = BodyCatalog.description(body)
	_facts.text = "\n".join(lines)
	_fly.visible = body != view.focus
