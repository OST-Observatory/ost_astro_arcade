## The game menu ("hub"): night sky, OST logo, game cards, language choice.
## After a while without input it shows the attract mode; after longer it resets the
## session (name, difficulty, language) for the next visitor.
extends Control

const COLS := 4

var _cards: Array[GameCard] = []
var _logo: TextureRect
var _attract: AttractMode
var _t := 0.0
var _session_reset_done := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())
	_build_header()
	_build_cards()
	_build_footer()
	add_child(AdminGesture.new())
	_attract = AttractMode.new()
	add_child(_attract)
	Kiosk.poke()


func _build_header() -> void:
	_logo = TextureRect.new()
	_logo.texture = preload("res://assets/brand/ost_logo_512.png")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.size = Vector2(250, 250)
	_logo.position = Vector2(110, 60)
	_logo.pivot_offset = _logo.size / 2.0
	add_child(_logo)

	var title := UiTheme.label("HUB_TITLE", UiTheme.SIZE_TITLE, "serif")
	title.position = Vector2(410, 92)
	add_child(title)
	var sub := UiTheme.label("HUB_SUBTITLE", UiTheme.SIZE_BODY + 4, "serif_italic", UiTheme.TEXT_DIM)
	sub.position = Vector2(416, 232)
	add_child(sub)


func _build_cards() -> void:
	# Flow layout so an incomplete last row stays centred.
	var grid := HFlowContainer.new()
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.custom_minimum_size = Vector2(COLS * GameCard.CARD_SIZE.x + (COLS - 1) * 48, 0)
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 48)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 300
	center.offset_bottom = -150
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(grid)
	add_child(center)
	for g in GameRegistry.visible_games():
		var card := GameCard.make(g)
		card.pressed.connect(func(): Router.start_game(g.id))
		grid.add_child(card)
		_cards.append(card)


func _build_footer() -> void:
	var langs := LanguageBar.new()
	langs.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	langs.offset_left = -740
	langs.offset_top = -140
	add_child(langs)

	var info := BigButton.make("HUB_INFO", "info", false, 0)
	info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info.offset_left = 64
	info.offset_top = -140
	info.pressed.connect(func(): add_child(InfoPanel.new()))
	add_child(info)
	var best := BigButton.make("HUB_LEADERBOARD", "trophy", false, 0)
	best.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	best.offset_left = 64 + 240
	best.offset_top = -140
	best.pressed.connect(func(): add_child(LeaderboardOverlay.new()))
	add_child(best)

	var hint := UiTheme.label("HUB_HINT", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -500
	hint.offset_right = 500
	hint.offset_top = -120
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _process(delta: float) -> void:
	_t += delta
	# Gentle "breathing": logo glow and a travelling highlight over the cards.
	_logo.modulate = Color(1, 1, 1, 0.85 + 0.15 * sin(_t * 1.3))
	for i in _cards.size():
		_cards[i].set_glow(0.5 + 0.5 * sin(_t * 1.6 - i * 0.7))

	var attract_after: float = Settings.get_value("kiosk/hub_attract_sec")
	var reset_after: float = Settings.get_value("kiosk/hub_reset_sec")
	if Kiosk.idle_sec >= reset_after and not _session_reset_done:
		_session_reset_done = true
		Session.reset()
	elif Kiosk.idle_sec < 1.0:
		_session_reset_done = false
	if Kiosk.idle_sec >= attract_after and not _attract.active:
		_attract.start()
