## Final screen: certificate with the visitor's name, the real asteroid and facts from
## JPL, points per step, stars and today's rank. Emits `again` or goes home.
class_name CertificateStep
extends MissionStep

signal again

const STEP_ORDER := ["plan", "align", "blink", "measure"]


func _ready() -> void:
	super._ready()
	var sc := mission.scenario
	var total := mission.total_points()
	var stars := mission.stars()
	var rank := Scores.submit("asteroid", Session.player_name, total, stars, {"object": sc.display_name()})
	GalleryStore.new(Settings.data_path("gallery.json")).add(Session.player_name, sc, total, stars)
	Router.complete({"score": total, "stars": stars, "object": sc.data.number, "steps": mission.points,
		"blink": mission.blink, "measure_arcsec": snappedf(mission.measure_error_arcsec, 0.01)})

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 120
	add_child(center)
	var card := PanelContainer.new()
	var box := UiTheme.box(Color(0.06, 0.06, 0.1, 0.96), Color(UiTheme.ACCENT, 0.7), 4, 18)
	box.set_content_margin_all(56)
	card.add_theme_stylebox_override("panel", box)
	center.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 64)
	card.add_child(h)

	# Left: the certificate.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(1250, 0)
	left.add_theme_constant_override("separation", 20)
	h.add_child(left)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 30)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/brand/ost_logo_512.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.custom_minimum_size = Vector2(170, 170)
	head.add_child(logo)
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_child(UiTheme.label("CERT_TITLE", UiTheme.SIZE_TITLE - 10, "serif", UiTheme.ACCENT_HI))
	hv.add_child(UiTheme.label("CERT_SUBTITLE", UiTheme.SIZE_BODY, "serif_italic", UiTheme.TEXT_DIM))
	head.add_child(hv)
	left.add_child(head)
	var text := plain_label(tr("CERT_TEXT") % [Session.player_name, AstroFormat.date(sc.data.night), sc.display_name()],
		UiTheme.SIZE_H2 - 14, "serif", UiTheme.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(1250, 0)
	left.add_child(text)
	for line in _facts():
		var l := plain_label("•  " + line, UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1250, 0)
		left.add_child(l)

	# Right: points.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(620, 0)
	right.add_theme_constant_override("separation", 14)
	h.add_child(right)
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		star_row.add_child(UiTheme.icon("star" if i < stars else "star_border", 110, UiTheme.ACCENT))
	right.add_child(star_row)
	for id in STEP_ORDER:
		var row := HBoxContainer.new()
		var name_l := UiTheme.label("STEP_" + id.to_upper(), UiTheme.SIZE_BODY, "regular", UiTheme.TEXT_DIM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(plain_label(str(int(mission.points.get(id, 0))), UiTheme.SIZE_BODY, "semibold", UiTheme.TEXT))
		right.add_child(row)
	var sep := HSeparator.new()
	right.add_child(sep)
	var total_l := plain_label(tr("AST_SCORE") % total, UiTheme.SIZE_H2 + 6, "bold", UiTheme.ACCENT_HI)
	total_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(total_l)
	var rank_l := plain_label(tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))],
		UiTheme.SIZE_BODY - 2, "medium", UiTheme.TEXT_DIM)
	rank_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rank_l.custom_minimum_size = Vector2(620, 0)
	right.add_child(rank_l)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	right.add_child(spacer)
	var more := BigButton.make("CERT_AGAIN", "refresh", true, 620)
	more.pressed.connect(func(): again.emit())
	right.add_child(more)
	var bonus := BigButton.make("COMET_BUTTON", "auto_awesome", false, 620)
	bonus.pressed.connect(_open_comet)
	right.add_child(bonus)
	right.add_child(Router.restart_button(620))
	var home := BigButton.make("BACK_TO_HUB", "home", false, 620)
	home.pressed.connect(func(): Router.go_home("home"))
	right.add_child(home)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.5)
	Audio.play("success")


## Bonus: find the real comet 67P in the OST's own images.
func _open_comet() -> void:
	var c := CometBonus.new()
	add_child(c)
	c.closed.connect(c.queue_free)


func _facts() -> Array[String]:
	var sc := mission.scenario
	var f: Dictionary = sc.data.facts
	var s := sc.sample_at(mission.obs_index)
	var out: Array[String] = []
	var mkm := float(s.delta_au) * 149.598
	out.append(tr("AST_FACT_DIST") % [AstroFormat.num(mkm, 0), AstroFormat.num(float(s.delta_au) * 8.317, 0)])
	if f.diameter_km != null:
		out.append(tr("AST_FACT_SIZE") % AstroFormat.num(float(f.diameter_km), 0 if f.diameter_km >= 10 else 1))
	var d: Dictionary = f.discovery
	if d.get("who") and d.get("date"):
		out.append(tr("AST_FACT_DISC") % [str(d.date).substr(0, 4), sc.discoverer(), d.get("location") if d.get("location") else "?"])
	out.append(tr("CERT_INSTRUMENT") % [ExposeStep._format_time(mission.exposure_s), Kepler.local_time_hhmm(s.t)])
	return out
