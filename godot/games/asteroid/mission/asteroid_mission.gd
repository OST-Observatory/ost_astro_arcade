## The asteroid hunt as a mission of six steps:
## plan the night -> align the telescope -> expose -> blink -> measure -> orbit -> certificate.
## Each step is a MissionStep; this node runs them in order and keeps the progress bar.
extends Control


var mission: MissionState
var skip_intro := false   # screenshots/tests
var rng_seed := 0
var start_at := ""        # screenshots/tests: jump to this step with automatic choices
var _progress: StepProgress
var _step: Control
var _played: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())
	if not skip_intro:
		var start := GameStartScreen.make(Router.current if not Router.current.is_empty() else GameRegistry.get_entry("asteroid"))
		add_child(start)
		await start.start_pressed
		start.queue_free()
		Router.step("start")
		await _briefing()
	_run()


func _briefing() -> void:
	# The observatory in 3D behind the briefing: camera flies up from the street while
	# dusk turns into night.
	var vp := SubViewportContainer.new()
	vp.stretch = true
	vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	vp.add_child(sv)
	var obs := ObservatoryScene.new()
	sv.add_child(obs)
	obs.set_night(0.3)
	obs.fly("street", "roof", 12.0)
	create_tween().tween_method(obs.set_night, 0.3, 0.9, 14.0)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.02, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 40)
	add_child(v)
	var t := UiTheme.label("MISSION_TITLE", UiTheme.SIZE_TITLE, "serif")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var txt := UiTheme.label("MISSION_TEXT", UiTheme.SIZE_H2 - 8, "regular")
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(1800, 0)
	txt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(txt)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 56)
	for i in MissionState.STEPS.size():
		var id: String = MissionState.STEPS[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		var ic := UiTheme.icon(StepProgress.ICONS[id], 96, UiTheme.ACCENT)
		col.add_child(ic)
		var l := UiTheme.label("STEP_" + id.to_upper(), UiTheme.SIZE_BODY, "medium", UiTheme.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		var n := UiTheme.label(str(i + 1), UiTheme.SIZE_SMALL, "bold", UiTheme.TEXT_DIM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		col.add_child(n)
		row.add_child(col)
	v.add_child(row)
	var go := BigButton.make("AST_GO", "play_arrow", true, 520)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(go)
	await go.pressed
	v.queue_free()
	shade.queue_free()
	vp.queue_free()


func _new_mission() -> MissionState:
	var m := MissionState.new()
	if rng_seed != 0:
		m.rng.seed = rng_seed
	else:
		m.rng.randomize()
	Session.ensure_name()
	m.difficulty = Session.difficulty_name()
	m.scenario = AsteroidScenario.pick(m.difficulty, m.rng, _played)
	_played.append(m.scenario.data.id)
	m.obs_index = m.scenario.data.best_index
	m.sky = m.quality_at(m.obs_index)
	m.pointing = m.scenario.position_at(m.obs_index)
	return m


func _run() -> void:
	mission = _new_mission()
	if _progress == null:
		_progress = StepProgress.new()
		_progress.position = Vector2(200, 52)
		add_child(_progress)
	_progress.visible = true
	for id in MissionState.STEPS:
		if start_at != "" and id != start_at:
			_auto_complete(id)
			continue
		start_at = ""
		_progress.set_current(id)
		Router.step(id)
		var step := _make_step(id)
		step.mission = mission
		_step = step
		add_child(step)
		await step.finished
		step.queue_free()
	_progress.visible = false
	var cert := CertificateStep.new()
	cert.mission = mission
	add_child(cert)
	await cert.again
	cert.queue_free()
	_run()


func _make_step(id: String) -> MissionStep:
	match id:
		"plan": return PlanNightStep.new()
		"dome": return DomeStep.new()
		"align": return AlignStep.new()
		"expose": return ExposeStep.new()
		"blink": return BlinkStep.new()
		"measure": return MeasureStep.new()
	return OrbitStep.new()


## For screenshots/tests: fill in a step's result without playing it.
func _auto_complete(id: String) -> void:
	match id:
		"plan":
			mission.points["plan"] = int(MissionState.MAX_POINTS.plan * mission.sky.q)
		"align":
			mission.points["align"] = 240
		"expose":
			mission.challenge = BlinkChallenge.create(mission.scenario, mission.difficulty, mission.rng,
				{"obs_index": mission.obs_index})
			mission.pointing = mission.challenge.center
		"blink":
			mission.blink = {"stars": 3, "revealed": false}
			mission.points["blink"] = int(mission.challenge.score(20.0, 0, 0) * 0.5)
		"measure":
			mission.measure_error_arcsec = 0.9
			mission.points["measure"] = 330
