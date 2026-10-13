## Dev tool: plays the solar system automatically – one explore round (a wrong tap, then the
## right body for every task, small bodies included), a camera flight, and every mission
## with a good launch – and prints what happened. Catches flow bugs unit tests miss.
##   OST_DATA_DIR=/tmp/ost_flow godot --path godot -s res://tools/solar_flow_check.gd   (needs a GPU window)
extends SceneTree


func _initialize() -> void:
	await process_frame
	var session := root.get_node("Session")
	session.set_difficulty(2)   # pro: the hardest find tasks
	var sg: Control = load("res://games/solar/solar_game.tscn").instantiate()
	sg.skip_intro = true
	root.add_child(sg)
	await process_frame
	sg.start_explore()
	await _frames(5)
	var v = sg.view
	var em = sg._mode
	# Tapping on screen finds what is there.
	v.fly_to("jupiter", 3.0)
	await _seconds(2.2)
	print("focus after flight: ", v.focus, "  pick at Jupiter: ", v.pick(v.screen_pos("jupiter")))
	em._on_tap("venus")
	print("wrong tap: ", em._feedback.text)
	while not em._free:
		var task: Dictionary = em._tasks[em._index]
		var target: String = _solution(task, v)
		print("task %s -> %s" % [task.id, target])
		em._on_tap(target)
		await process_frame
	print("round done: result shown %s, total %d" % [em._result != null and is_instance_valid(em._result), em._total])
	sg.show_menu()
	await process_frame
	sg.queue_free()

	for d in [0, 1, 2]:
		session.set_difficulty(d)
		var g: Control = load("res://games/solar/solar_game.tscn").instantiate()
		g.skip_intro = true
		root.add_child(g)
		await process_frame
		g.start_mission()
		await process_frame
		var mm = g._mode
		if mm.planet == "saturn":
			var best := {"closest": INF}
			var best_i := 0
			for i in mm._windows.size():
				var b := MissionLogic.best_for_window(mm._windows[i])
				if float(b.closest) < float(best.closest):
					best = b
					best_i = i
			mm._select_window(best_i)
			mm._rp = best.rp
			mm._side = best.side
			mm._update_preview()
		else:
			var w: float = HohmannTransfer.next_window(mm.planet, mm._jd0, mm._jd0 + MissionLogic.RANGE_DAYS[mm.diff])
			mm._slider.slider.value = w - mm._jd0
		mm._launch()
		mm._fast = 30.0
		var t0 := Time.get_ticks_msec()
		while not mm.find_children("*", "ResultActions", true, false).size() and Time.get_ticks_msec() - t0 < 30000:
			await process_frame
		print("mission %s: %s | result shown %s" % [mm.planet, mm._feedback.text.replace("\n", " | "),
			mm.find_children("*", "ResultActions", true, false).size() > 0])
		# "Another launch": a new situation (other dates) and everything usable again.
		var jd_before: float = mm._jd0
		var again = mm.find_children("*", "ResultActions", true, false)[0].get_child(0)
		again.pressed.emit()
		await process_frame
		print("  again: start %s -> %s, launch enabled %s | %s" % [MarsTransfer.iso_from_jd(jd_before).left(10),
			MarsTransfer.iso_from_jd(mm._jd0).left(10), not mm._launch_btn.disabled, mm._feedback.text])
		g.queue_free()
		await process_frame
	quit()


func _solution(task: Dictionary, v) -> String:
	for a in task.accept:
		var s := str(a)
		if not s.begins_with("class:"):
			return s
		for k in v.small.rows.size():
			if SmallBodies.class_of(v.small.rows[k]) == s.substr(6):
				return "sb:%d" % k
	return ""


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout
