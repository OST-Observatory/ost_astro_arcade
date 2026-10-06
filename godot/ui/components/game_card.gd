## Hub tile for one game: coloured glow, big icon, serif title, short description.
class_name GameCard
extends Button

const CARD_SIZE := Vector2(560, 420)

var entry: Dictionary
var _title: Label
var _desc: Label
var _badge: Label
var _glow := 0.0


static func make(game: Dictionary) -> GameCard:
	var c := GameCard.new()
	c.entry = game
	return c


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	flat = true
	focus_mode = Control.FOCUS_NONE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	pivot_offset = CARD_SIZE / 2.0
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())

	var col: Color = entry.color
	var ic := UiTheme.icon(entry.icon, 110, col)
	ic.position = Vector2(40, 36)
	ic.size = Vector2(140, 140)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ic)

	_title = UiTheme.label("", UiTheme.SIZE_H2, "serif_bold")
	_title.position = Vector2(44, 196)
	_title.size = Vector2(CARD_SIZE.x - 88, 76)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_desc = UiTheme.label("", UiTheme.SIZE_BODY, "regular", UiTheme.TEXT_DIM)
	_desc.position = Vector2(44, 272)
	_desc.size = Vector2(CARD_SIZE.x - 88, 110)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc)

	if entry.status == "soon":
		_badge = UiTheme.label("", UiTheme.SIZE_SMALL, "semibold", UiTheme.BG)
		_badge.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.TEXT_DIM, 0.9), UiTheme.TEXT_DIM, 0, 18))
		_badge.position = Vector2(CARD_SIZE.x - 250, 44)
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_badge)
	_refresh_text()

	button_down.connect(func(): create_tween().tween_property(self, "scale", Vector2.ONE * 0.96, 0.08))
	button_up.connect(func(): create_tween().tween_property(self, "scale", Vector2.ONE, 0.12))
	pressed.connect(func(): Audio.play("tap"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	if _title == null:
		return
	_title.text = tr(entry.title)
	_fit_font(_title, UiTheme.SIZE_H2, CARD_SIZE.x - 88)
	_desc.text = tr(entry.desc)
	if _badge:
		_badge.text = tr("HUB_SOON")
		_badge.add_theme_constant_override("line_spacing", 0)
		_badge.add_theme_stylebox_override("normal", _badge_box())


## Shrinks a single-line label until it fits the given width.
static func _fit_font(l: Label, max_size: int, width: float) -> void:
	var f: Font = l.get_theme_font("font")
	var s := max_size
	while s > 24 and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 2
	l.add_theme_font_size_override("font_size", s)


func _badge_box() -> StyleBoxFlat:
	var b := UiTheme.box(Color(UiTheme.TEXT_DIM, 0.85), UiTheme.TEXT_DIM, 0, 18)
	b.content_margin_left = 18
	b.content_margin_right = 18
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b


## Slow breathing glow, phase-shifted per card (set by the hub).
func set_glow(v: float) -> void:
	_glow = v
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, CARD_SIZE)
	var col: Color = entry.color
	var bg := UiTheme.box(UiTheme.SURFACE, Color(col, 0.35 + 0.25 * _glow), 3)
	draw_style_box(bg, r)
	# Soft coloured halo behind the icon.
	for i in 6:
		draw_circle(Vector2(110, 106), 100.0 - i * 13.0, Color(col, 0.035 + 0.02 * _glow))
	draw_line(Vector2(44, 190), Vector2(CARD_SIZE.x - 44, 190), Color(1, 1, 1, 0.08), 2)
