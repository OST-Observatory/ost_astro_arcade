## Astro puzzle: pick one of the OST's own images, then assemble real jigsaw pieces on
## the board. Several fingers can drag pieces at once (two kids can puzzle together).
## A faint template helps (stronger for explorers, none for pros). The finished picture
## is followed by an info card about the object.
extends Control

const DATA := "res://assets/data/puzzle/images.json"
const BOARD_AREA := Rect2(1000, 170, 1480, 1120)
const TRAY := Rect2(60, 200, 880, 1100)
const SNAP_PX := 55.0
const GHOST_ALPHA := {"explorer": 0.35, "researcher": 0.14, "pro": 0.0}

var skip_intro := false   # screenshots/tests
var rng_seed := 0
var logic := PuzzleLogic.new()
var _rng := RandomNumberGenerator.new()
var _images: Array = []
var _entry: Dictionary
var _texture: Texture2D
var _board_origin := Vector2.ZERO
var _scale := 1.0
var _table: Node2D
var _pieces: Array[_Piece] = []
var _drags := {}           # touch index -> {"piece", "offset"}
var _placed := 0
var _elapsed := 0.0
var _playing := false
var _ui: Control
var _status: Label
var _timer: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_images = JSON.parse_string(FileAccess.get_file_as_string(DATA)).images
	add_child(Starfield.new())
	if not skip_intro:
		var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("puzzle"))
		add_child(start)
		await start.start_pressed
		start.queue_free()
		await _pick_image()
	else:
		_entry = _images[0]
	_start()


func _clear() -> void:
	for c in get_children():
		if not (c is Starfield):
			c.queue_free()
	_pieces.clear()
	_drags.clear()


# --- image picker ------------------------------------------------------------------------

func _pick_image() -> void:
	_clear()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 40)
	add_child(v)
	var t := UiTheme.label("PUZZLE_PICK", UiTheme.SIZE_H2 + 10, "serif")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 32)
	var center := CenterContainer.new()
	center.add_child(grid)
	v.add_child(center)
	var chosen := [null]
	for e in _images:
		var b := Button.new()
		b.custom_minimum_size = Vector2(440, 380)
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 14
		col.offset_right = -14
		col.offset_top = 14
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var img := TextureRect.new()
		img.texture = load(e.thumb)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.custom_minimum_size = Vector2(412, 270)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(img)
		var name := _plain(_tr_dict(e.name), UiTheme.SIZE_SMALL + 2, "semibold", UiTheme.TEXT)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(name)
		b.pressed.connect(func():
			Audio.play("tap")
			chosen[0] = e)
		grid.add_child(b)
	while chosen[0] == null:
		await get_tree().process_frame
	_entry = chosen[0]
	v.queue_free()


# --- playing -------------------------------------------------------------------------------

func _start() -> void:
	_clear()
	_texture = load(_entry.image)
	var size := Vector2(_texture.get_size())
	logic.setup(size, Session.difficulty_name() if Session else "researcher", _rng)
	_scale = minf(BOARD_AREA.size.x / size.x, BOARD_AREA.size.y / size.y)
	_board_origin = BOARD_AREA.get_center() - size * _scale / 2.0

	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var frame := Panel.new()
	frame.position = _board_origin - Vector2(8, 8)
	frame.size = size * _scale + Vector2(16, 16)
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.7), Color(UiTheme.SCIENCE, 0.5), 3, 8))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(frame)
	var ghost := TextureRect.new()
	ghost.texture = _texture
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.position = _board_origin
	ghost.size = size * _scale
	ghost.modulate = Color(1, 1, 1, GHOST_ALPHA.get(Session.difficulty_name(), 0.14))
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(ghost)

	var title := _plain(_tr_dict(_entry.name), UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
	title.position = Vector2(200, 50)
	_ui.add_child(title)
	_status = _plain("", UiTheme.SIZE_BODY + 4, "semibold", UiTheme.ACCENT_HI)
	_status.position = Vector2(1700, 60)
	_ui.add_child(_status)
	_timer = _plain("", UiTheme.SIZE_BODY + 4, "medium", UiTheme.SCIENCE)
	_timer.position = Vector2(2250, 60)
	_ui.add_child(_timer)

	_table = Node2D.new()
	add_child(_table)
	var slots := _tray_slots(logic.piece_count(), logic.cell * _scale)
	var k := 0
	for r in logic.rows:
		for c in logic.cols:
			var p := _Piece.new()
			p.setup(logic, c, r, _texture, _scale)
			p.target = _board_origin + logic.cell_origin(c, r) * _scale
			p.position = slots[k]
			k += 1
			_table.add_child(p)
			_pieces.append(p)
	_placed = 0
	_elapsed = 0.0
	_playing = true
	_update_status()
	Router.step("play")


## Evenly spread, slightly jittered and shuffled start positions in the tray.
func _tray_slots(n: int, piece: Vector2) -> Array[Vector2]:
	var aspect := TRAY.size.x / TRAY.size.y
	var cols := maxi(1, ceili(sqrt(n * aspect)))
	var rows := ceili(float(n) / cols)
	var step := Vector2((TRAY.size.x - piece.x) / maxf(cols - 1, 1), (TRAY.size.y - piece.y) / maxf(rows - 1, 1))
	var out: Array[Vector2] = []
	for i in n:
		var cell := Vector2(i % cols, i / cols)
		var jitter := Vector2(_rng.randf_range(-0.2, 0.2) * step.x, _rng.randf_range(-0.2, 0.2) * step.y)
		out.append(TRAY.position + cell * step + jitter)
	for i in range(n - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp := out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func _process(delta: float) -> void:
	if _playing:
		_elapsed += delta
		_timer.text = "%d:%02d" % [int(_elapsed) / 60, int(_elapsed) % 60]


func _update_status() -> void:
	_status.text = tr("PUZZLE_PLACED") % [_placed, logic.piece_count()]


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var p := _piece_at(event.position)
			if p:
				_drags[event.index] = {"piece": p, "offset": p.position - event.position}
				_table.move_child(p, -1)
				p.lift(true)
		elif _drags.has(event.index):
			var p: _Piece = _drags[event.index].piece
			_drags.erase(event.index)
			p.lift(false)
			_try_snap(p)
	elif event is InputEventScreenDrag and _drags.has(event.index):
		var d: Dictionary = _drags[event.index]
		(d.piece as _Piece).position = event.position + d.offset


func _piece_at(pos: Vector2) -> _Piece:
	for i in range(_table.get_child_count() - 1, -1, -1):
		var p := _table.get_child(i) as _Piece
		if p and not p.locked and p.contains(pos):
			return p
	return null


func _try_snap(p: _Piece) -> void:
	if p.position.distance_to(p.target) > SNAP_PX:
		Audio.play("tick", "UI", 0.8, -10.0)
		return
	p.position = p.target
	p.lock()
	_table.move_child(p, 0)
	_placed += 1
	Audio.play("tap", "UI", 1.3)
	_update_status()
	if _placed == logic.piece_count():
		_finished()


func _finished() -> void:
	_playing = false
	Router.step("solved")
	Audio.play("success")
	var pts := logic.score(_elapsed)
	var stars := logic.stars(_elapsed)
	var rank := Scores.submit("puzzle", Session.player_name, pts, stars, {"image": _entry.id})
	Router.complete({"score": pts, "stars": stars, "seconds": snappedf(_elapsed, 0.1), "image": _entry.id,
		"pieces": logic.piece_count()})
	await get_tree().create_timer(1.2).timeout
	_show_info(pts, stars, rank)


func _show_info(pts: int, stars: int, rank: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(60, 200)
	panel.custom_minimum_size = Vector2(900, 1080)
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_HI, Color(UiTheme.SUCCESS, 0.6), 3))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)
	v.add_child(UiTheme.label("PUZZLE_DONE", UiTheme.SIZE_H2 + 8, "serif", UiTheme.SUCCESS))
	var name := _plain(_tr_dict(_entry.name), UiTheme.SIZE_H2 - 8, "semibold", UiTheme.ACCENT_HI)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.custom_minimum_size = Vector2(840, 0)
	v.add_child(name)
	var desc := _plain(_tr_dict(_entry.description), UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(840, 0)
	v.add_child(desc)
	v.add_child(_plain(tr("PUZZLE_CREDIT"), UiTheme.SIZE_SMALL - 4, "regular", UiTheme.TEXT_DIM))
	var star_row := HBoxContainer.new()
	for i in 3:
		star_row.add_child(UiTheme.icon("star" if i < stars else "star_border", 90, UiTheme.ACCENT))
	v.add_child(star_row)
	v.add_child(_plain(tr("PUZZLE_RESULT") % [logic.piece_count(), int(_elapsed) / 60, int(_elapsed) % 60], UiTheme.SIZE_BODY, "medium", UiTheme.TEXT))
	v.add_child(_plain(tr("AST_SCORE") % pts + "  ·  " + tr("AST_RANK") % [Session.player_name, int(rank.get("rank_today", 0))],
		UiTheme.SIZE_BODY, "semibold", UiTheme.ACCENT_HI))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var home := BigButton.make("BACK_TO_HUB", "home", false, 380)
	home.pressed.connect(func(): Router.go_home("home"))
	row.add_child(home)
	var again := BigButton.make("PUZZLE_AGAIN", "extension", true, 420)
	again.pressed.connect(func():
		await _pick_image()
		_start())
	row.add_child(again)
	v.add_child(row)


func _tr_dict(d: Dictionary) -> String:
	return str(d.get(I18n.locale, d.get("en", "")))


func _plain(t: String, font_size: int, kind := "regular", color := UiTheme.TEXT) -> Label:
	var l := UiTheme.label(t, font_size, kind, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## One jigsaw piece: textured polygon plus a thin outline.
class _Piece:
	extends Node2D

	var c := 0
	var r := 0
	var target := Vector2.ZERO
	var locked := false
	var _poly: PackedVector2Array
	var _outline: Line2D

	func setup(logic: PuzzleLogic, col: int, row: int, tex: Texture2D, s: float) -> void:
		c = col
		r = row
		var abs_poly := logic.polygon(col, row)
		var origin := logic.cell_origin(col, row)
		_poly = PackedVector2Array()
		for p in abs_poly:
			_poly.append(p - origin)
		scale = Vector2(s, s)
		var poly := Polygon2D.new()
		poly.polygon = _poly
		poly.uv = abs_poly
		poly.texture = tex
		poly.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(poly)
		_outline = Line2D.new()
		var pts := _poly.duplicate()
		pts.append(_poly[0])
		_outline.points = pts
		_outline.width = 2.0 / s
		_outline.default_color = Color(1, 1, 1, 0.45)
		_outline.antialiased = true
		add_child(_outline)

	func contains(global_pos: Vector2) -> bool:
		return Geometry2D.is_point_in_polygon(to_local(global_pos), _poly)

	func lift(on: bool) -> void:
		modulate = Color(1.12, 1.12, 1.12) if on else Color.WHITE
		_outline.default_color = Color(UiTheme.ACCENT, 0.9) if on else Color(1, 1, 1, 0.45)

	func lock() -> void:
		locked = true
		create_tween().tween_property(_outline, "modulate:a", 0.0, 0.6)
