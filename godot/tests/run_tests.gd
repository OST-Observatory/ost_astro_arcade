## Headless test runner.
##   godot --headless --path godot -s res://tests/run_tests.gd [-- <filter>]
## Runs all `test_*` methods of every res://tests/**/test_*.gd script.
## Exit code = number of failed tests.
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var name_filter: String = args[0] if args.size() > 0 else ""
	var files: PackedStringArray = []
	_collect("res://tests", files)
	files.sort()

	var passed := 0
	var failed := 0
	for path in files:
		var script: GDScript = load(path)
		for m in script.get_script_method_list():
			var method: String = m.name
			if not method.begins_with("test_"):
				continue
			if name_filter != "" and not (path + ":" + method).contains(name_filter):
				continue
			var tc: TestCase = script.new()
			tc._set_current(method)
			if tc.has_method("before_each"):
				tc.call("before_each")
			tc.call(method)
			if tc.has_method("after_each"):
				tc.call("after_each")
			if tc.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in tc.failures:
					printerr("FAIL %s  %s" % [path.get_file(), f])

	print("%d passed, %d failed" % [passed, failed])
	quit(failed)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
