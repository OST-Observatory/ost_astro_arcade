## Attract mode: when nobody uses the kiosk, cycle through inviting slides
## (call to action, game spotlights, today's best players). Any touch ends it.
class_name AttractMode
extends Control

const SLIDE_SEC := 7.0

var active := false
var _slides: Array[Control] = []
var _index := 0
var _t := 0.0
var _hand: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	Kiosk.activity.connect(stop)


func start() -> void:
	active = true
	visible = true
	_build_slides()
	_index = 0
	_t = 0.0
	_show_slide(0)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 1.2)


func stop() -> void:
	if not active:
		return
	active = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): visible = false)


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	if _hand:
		_hand.scale = Vector2.ONE * (1.0 + 0.12 * sin(_t * 4.0))
	if _t >= SLIDE_SEC:
		_t = 0.0
		_index = (_index + 1) % _slides.size()
		_show_slide(_index)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.02, 0.9))


func _show_slide(i: int) -> void:
	for s in _slides.size():
		var slide := _slides[s]
		if s == i:
			slide.visible = true
			slide.modulate.a = 0.0
			create_tween().tween_property(slide, "modulate:a", 1.0, 0.8)
		else:
			slide.visible = false


func _build_slides() -> void:
	for s in _slides:
		s.queue_free()
	_slides.clear()
	_hand = null

	# 1) Call to action with the logo.
	var cta := _slide()
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/brand/ost_logo_512.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(420, 420)
	cta.add_child(logo)
	cta.add_child(_centered("ATTRACT_TITLE", UiTheme.SIZE_TITLE, "serif"))
	cta.add_child(_centered("ATTRACT_TOUCH", UiTheme.SIZE_H2, "semibold", UiTheme.ACCENT))
	_hand = UiTheme.icon("touch_app", 140, UiTheme.ACCENT)
	_hand.custom_minimum_size = Vector2(160, 160)
	_hand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hand.pivot_offset = Vector2(80, 80)
	cta.add_child(_hand)

	# 2) One spotlight per playable game.
	for g in GameRegistry.visible_games():
		if g.status != "ready":
			continue
		var sl := _slide()
		sl.add_child(UiTheme.icon(g.icon, 220, g.color))
		sl.add_child(_centered(g.title, UiTheme.SIZE_TITLE, "serif"))
		sl.add_child(_centered(g.desc, UiTheme.SIZE_H2, "regular", UiTheme.TEXT_DIM))

	# 3) Today's best players (only games that have entries today).
	for g in GameRegistry.GAMES:
		var best := Scores.top(g.id, 5, true)
		if best.is_empty():
			continue
		var sl := _slide()
		sl.add_child(UiTheme.icon("trophy", 160, UiTheme.ACCENT))
		var head := _centered("ATTRACT_BEST_TODAY", UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
		head.text = tr("ATTRACT_BEST_TODAY") % tr(g.title)
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		sl.add_child(head)
		for i in best.size():
			var row := _centered("", UiTheme.SIZE_H2, "medium", UiTheme.ACCENT_HI if i == 0 else UiTheme.TEXT)
			row.text = "%d.  %s   %d" % [i + 1, best[i].name, best[i].score]
			row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			sl.add_child(row)



func _slide() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 30)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.visible = false
	add_child(v)
	_slides.append(v)
	return v


func _centered(key: String, font_size: int, kind: String, color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(key, font_size, kind, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
