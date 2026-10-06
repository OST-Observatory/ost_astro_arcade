## Result card after the asteroid was found: which real object it was, facts from
## JPL (class, distance, size, discovery), score, stars and leaderboard rank.
class_name BlinkResult
extends Control

signal again

const CLASS_KEYS := {
	"MBA": "AST_CLASS_MBA", "IMB": "AST_CLASS_MBA", "OMB": "AST_CLASS_MBA",
	"MCA": "AST_CLASS_MCA", "AMO": "AST_CLASS_NEO", "APO": "AST_CLASS_NEO",
	"ATE": "AST_CLASS_NEO", "IEO": "AST_CLASS_NEO", "TJN": "AST_CLASS_TJN",
}

var _ch: BlinkChallenge
var _points: int
var _stars: int
var _rank: Dictionary
var _secs: float


func setup(ch: BlinkChallenge, points: int, stars: int, rank: Dictionary, secs: float) -> void:
	_ch = ch
	_points = points
	_stars = stars
	_rank = rank
	_secs = secs


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SUCCESS, 0.6), 3))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(1600, 0)
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 28)
	head.add_child(UiTheme.icon("search", 110, UiTheme.SUCCESS))
	var hv := VBoxContainer.new()
	hv.add_child(UiTheme.label("AST_FOUND", UiTheme.SIZE_TITLE - 16, "serif", UiTheme.SUCCESS))
	hv.add_child(_text(tr("AST_FOUND_TEXT") % [_ch.scenario.display_name(), _ch.motion_arcsec()],
		UiTheme.SIZE_H2 - 12, "medium", UiTheme.TEXT))
	head.add_child(hv)
	v.add_child(head)

	var f: Dictionary = _ch.scenario.data.facts
	var s: Dictionary = _ch.scenario.sample_at(_ch.start_index + 2.0)
	var facts: Array[String] = []
	if CLASS_KEYS.has(f.class_code):
		facts.append(tr(CLASS_KEYS[f.class_code]))
	var mkm := float(s.delta_au) * 149.598
	facts.append(tr("AST_FACT_DIST") % [_fmt(mkm, 0), _fmt(float(s.delta_au) * 8.317, 0)])
	if f.diameter_km != null:
		facts.append(tr("AST_FACT_SIZE") % _fmt(float(f.diameter_km), 0 if f.diameter_km >= 10 else 1))
	var d: Dictionary = f.discovery
	if d.get("who") and d.get("date"):
		facts.append(tr("AST_FACT_DISC") % [str(d.date).substr(0, 4), _ch.scenario.discoverer(), d.get("location", "") if d.get("location") else "?"])
	facts.append(tr("AST_FACT_NIGHT") % [_date(_ch.scenario.data.night), _fmt(float(_ch.scenario.data.v_best), 1)])
	for line in facts:
		var l := _text("•  " + line, UiTheme.SIZE_BODY, "regular", UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)

	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 26)
	for i in 3:
		score_row.add_child(UiTheme.icon("star" if i < _stars else "star_border", 96, UiTheme.ACCENT))
	score_row.add_child(_text(tr("AST_SCORE") % _points, UiTheme.SIZE_H2 + 8, "bold", UiTheme.ACCENT_HI))
	v.add_child(score_row)
	var rank_line := _text(tr("AST_RANK") % [Session.player_name, int(_rank.get("rank_today", 0))],
		UiTheme.SIZE_BODY, "medium", UiTheme.TEXT_DIM)
	rank_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rank_line)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	var home := BigButton.make("BACK_TO_HUB", "home", false, 420)
	home.pressed.connect(func(): Router.go_home("home"))
	row.add_child(home)
	var more := BigButton.make("AST_AGAIN", "refresh", true, 520)
	more.pressed.connect(func(): again.emit())
	row.add_child(more)
	v.add_child(row)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0.02, 0.6))


func _text(t: String, size: int, kind: String, color: Color) -> Label:
	var l := UiTheme.label(t, size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


## ISO date -> local style (10.11.2027 / 2027-11-10 / 10/11/2027).
static func _date(iso: String) -> String:
	var p := iso.split("-")
	match TranslationServer.get_locale().substr(0, 2):
		"de": return "%s.%s.%s" % [p[2], p[1], p[0]]
		"es": return "%s/%s/%s" % [p[2], p[1], p[0]]
	return iso


static func _fmt(x: float, decimals: int) -> String:
	var s := String.num(x, decimals)
	if TranslationServer.get_locale().begins_with("de") or TranslationServer.get_locale().begins_with("es"):
		s = s.replace(".", ",")
	return s
