## Solar system: one 3D scene (SolarView) for two modes, chosen on a menu after the start
## screen:
##   explore – fly through the solar system, tap bodies for info, solve five "find …" tasks
##   mission – explorer: Mars, researcher: Jupiter, pro: Saturn via a Jupiter swing-by
extends Control

const VIEW := Rect2(40, 170, 1700, 1230)
const PANEL := Rect2(1780, 160, 740, 1250)

var skip_intro := false   # screenshots/tests
var diff := "researcher"
var view: SolarView
var _frame: Panel
var _container: SubViewportContainer
var _cam_bar: HBoxContainer
var _title: Label
var _menu: Control
var _mode: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Starfield.new())
	if not skip_intro:
		var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("solar"))
		add_child(start)
		await start.start_pressed
		start.queue_free()
	diff = Session.difficulty_name()
	_build_3d()
	if not skip_intro:
		show_menu()


func _build_3d() -> void:
	_frame = Panel.new()
	_frame.position = VIEW.position - Vector2(6, 6)
	_frame.size = VIEW.size + Vector2(12, 12)
	_frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.6), Color(UiTheme.SCIENCE, 0.45), 3, 10))
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_container = SubViewportContainer.new()
	_container.position = VIEW.position
	_container.size = VIEW.size
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	Settings.apply_3d(vp)
	_container.add_child(vp)
	view = SolarView.new()
	vp.add_child(view)
	view.gestures.area = Rect2(Vector2.ZERO, VIEW.size)

	_title = UiTheme.label("", UiTheme.SIZE_H2, "serif", UiTheme.TEXT)
	_title.position = Vector2(200, 52)
	add_child(_title)
	_cam_bar = HBoxContainer.new()
	_cam_bar.add_theme_constant_override("separation", 10)
	add_child(_cam_bar)
	for b in [["SOL_CAM_TOP", "crop_free", view.view_top], ["SOL_CAM_EDGE", "view_day", view.view_edge],
			["SOL_CAM_SUN", "wb_sunny", func(): view.fly_to("sun", 4.5)],
			["", "add", func(): view.zoom_by(2.0)], ["", "remove", func(): view.zoom_by(0.5)]]:
		var btn := BigButton.make(b[0], b[1], false, 96)
		btn.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		btn.pressed.connect(b[2])
		_cam_bar.add_child(btn)
	_cam_bar.position = VIEW.position + Vector2(20, 20)
	_set_3d_visible(false)


func _set_3d_visible(on: bool) -> void:
	for n in [_frame, _container, _cam_bar, _title]:
		(n as CanvasItem).visible = on
	view.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _unhandled_input(event: InputEvent) -> void:
	if view and _container.visible and view.handle_input(event, VIEW.position):
		get_viewport().set_input_as_handled()


# --- menu ------------------------------------------------------------------------------------

func show_menu() -> void:
	if _mode:
		_mode.queue_free()
		_mode = null
	_set_3d_visible(false)
	Router.step("menu")
	_menu = VBoxContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_menu as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_menu.add_theme_constant_override("separation", 50)
	add_child(_menu)
	var t := UiTheme.label("SOL_MENU_TITLE", UiTheme.SIZE_H2 + 10, "serif")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	_menu.add_child(row)
	var target := MissionLogic.target(diff).to_upper()
	row.add_child(_card("travel_explore", "SOL_MENU_EXPLORE", "SOL_MENU_EXPLORE_DESC", UiTheme.SCIENCE, start_explore))
	row.add_child(_card("rocket_launch", "SOL_M_TITLE_" + target, "SOL_MENU_MISSION_DESC_" + target, UiTheme.ACCENT, start_mission))


func _card(icon: String, title: String, desc: String, col: Color, action: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(900, 560)
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SURFACE, Color(col, 0.6), 3))
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.SURFACE_HI, col, 3))
	b.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.SURFACE_HI, col, 4))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 24)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := UiTheme.icon(icon, 150, col)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	for line in [[title, UiTheme.SIZE_H2 - 6, "serif", UiTheme.TEXT], [desc, UiTheme.SIZE_BODY - 2, "regular", UiTheme.TEXT_DIM]]:
		var l := UiTheme.label(line[0], line[1], line[2], line[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(800, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	b.pressed.connect(func():
		Audio.play("tap")
		action.call())
	return b


func _open_mode(m: Control, title_key: String) -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	if _mode:
		_mode.queue_free()
	_set_3d_visible(true)
	_title.text = tr(title_key)
	_mode = m
	add_child(m)
	m.connect("menu_pressed", show_menu)


func start_explore() -> void:
	_open_mode(ExploreMode.make(view, diff, PANEL, VIEW), "SOL_EXPLORE_TITLE")


func start_mission() -> void:
	_open_mode(MissionMode.make(view, diff, PANEL, VIEW), "SOL_MISSION_TITLE")
