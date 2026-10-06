## Renders a scene offscreen at kiosk resolution and saves PNG screenshots.
##   godot --path godot -s res://tools/capture.gd -- <scene.tscn> <out_prefix> [frames=120] [shots=1] [WxH=2560x1440]
## Takes `shots` screenshots spread over `frames` frames and prints the average FPS.
## Needs a real GPU/window (not --headless).
extends SceneTree


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		printerr("usage: -- <scene> <out_prefix> [frames] [shots] [WxH]")
		quit(2)
		return
	var scene_path: String = a[0]
	var out_prefix: String = a[1]
	var frames: int = int(a[2]) if a.size() > 2 else 120
	var shots: int = maxi(1, int(a[3]) if a.size() > 3 else 1)
	var size := Vector2i(2560, 1440)
	if a.size() > 4:
		var wh := a[4].split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")
	vp.own_world_3d = true
	root.add_child(vp)
	# A SubViewport does not inherit the window theme (set by the Router autoload),
	# so wrap the scene in a Control that carries it.
	var holder := Control.new()
	holder.theme = root.theme if root.theme else UiTheme.build()
	holder.size = Vector2(size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(holder)
	var packed: PackedScene = load(scene_path)
	holder.add_child(packed.instantiate())

	DirAccess.make_dir_recursive_absolute(out_prefix.get_base_dir())
	var start_ms := Time.get_ticks_msec()
	var shot := 0
	for f in range(1, frames + 1):
		await process_frame
		if f * shots >= (shot + 1) * frames:
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			var path := "%s_%02d.png" % [out_prefix, shot] if shots > 1 else out_prefix + ".png"
			img.save_png(path)
			print("saved ", path)
			shot += 1
	var secs := (Time.get_ticks_msec() - start_ms) / 1000.0
	print("avg fps: %.1f over %d frames" % [frames / secs, frames])
	quit(0)
