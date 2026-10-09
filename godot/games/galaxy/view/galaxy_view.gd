## 3D view of the galaxy builder: GPU stars (galaxy_stars.gdshader) in two modes.
##   build:     one galaxy, stars start with the measured speeds, gravity is the player's mass
##              model; loops over LOOP_T so the effect of each change is seen again and again.
##   collide:   two galaxies along the centre track of an EncounterModel.
## Time advances in fixed steps of EncounterModel.DT (up to MAX_STEPS per frame), like the CPU.
class_name GalaxyView
extends Node3D

signal finished

const DT := EncounterModel.DT
const MAX_STEPS := 24
const LOOP_T := 129.0          # 1 billion years
const BUILD_SPEED := 5.0       # time units per second (calm, so the eye can follow)
const COLLIDE_SPEED := 14.0

var fixed_step := 0.0          # > 0: seconds per frame regardless of the real frame time (captures)
var t := 0.0
var playing := false
var mode := "build"
var model: EncounterModel
var _t_end := LOOP_T
var _acc := 0.0
var _hold := 0
var _particles: GPUParticles3D
var _mat: ShaderMaterial
var _quad: QuadMesh
var _cores: Array[Sprite3D] = []
var _cam: Camera3D
var _cam_dist := 30.0
var _cam_angle := 0.6
var _radius := 8.0
var _centers := PackedVector3Array()


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.008)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://games/galaxy/view/galaxy_stars.gdshader")
	_mat.set_shader_parameter("dt", DT)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.albedo_texture = _radial_texture(32, 0.25)
	_quad = QuadMesh.new()
	_quad.material = draw_mat

	_particles = GPUParticles3D.new()
	_particles.amount = int(Settings.quality_3d().stars)
	_particles.lifetime = 100000.0
	_particles.explosiveness = 1.0
	_particles.one_shot = true
	_particles.fixed_fps = 0
	_particles.interpolate = false
	_particles.local_coords = true
	_particles.process_material = _mat
	_particles.draw_pass_1 = _quad
	_particles.visibility_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	_particles.emitting = false
	add_child(_particles)

	var glow := _radial_texture(128, 0.12)
	for i in 2:
		var s := Sprite3D.new()
		s.texture = glow
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = glow
		m.albedo_color = Color(1.0, 0.85, 0.62, 0.45)
		s.material_override = m
		s.visible = false
		add_child(s)
		_cores.append(s)

	_cam = Camera3D.new()
	_cam.fov = 40
	_cam.far = 5000
	add_child(_cam)
	_cam.make_current()
	_centers.resize(2 * MAX_STEPS)


# --- set-up ------------------------------------------------------------------------------------

## Act 1: the player's galaxy (target look and measured speeds) in the player's potential.
func show_build(target: Dictionary, pot: GalaxyPotential) -> void:
	mode = "build"
	model = null
	_radius = float(target.r_last)
	var setup := GalaxyTemplates.star_setup(target, pot, true)
	_apply_galaxies([{"pot": pot, "setup": setup, "target": target}], [Vector3.ZERO], [Vector3.ZERO])
	_t_end = LOOP_T
	_cam_dist = _radius * 2.6
	_restart()


## Act 1: a knob changed – new gravity, same stars, run the loop again.
func set_potential(pot: GalaxyPotential) -> void:
	var u := PackedFloat32Array(pot.to_uniforms())
	u.append_array(GalaxyPotential.new().to_uniforms())
	_mat.set_shader_parameter("pot", u)
	_restart()


## Act 2: two galaxies of an EncounterModel (setup() must have been called).
func show_encounter(m: EncounterModel) -> void:
	mode = "collide"
	model = m
	_radius = maxf(m.radius(0), m.radius(1))
	_apply_galaxies(m.gal, [m.center(0, 0.0), m.center(1, 0.0)], [m.center_velocity(0, 0.0), m.center_velocity(1, 0.0)])
	_t_end = m.t_end
	_cam_dist = _frame_dist(m.rel_at(0.0).length())
	_restart()


func play() -> void:
	playing = true


func stop() -> void:
	playing = false


func _apply_galaxies(gals: Array, c0: Array, v0: Array) -> void:
	var n := _particles.amount
	var pot := PackedFloat32Array()
	var vtab := PackedFloat32Array()
	var bases := []
	var keys := ["f_bulge", "f_gas", "r_max", "a_bulge", "r_disk", "r_gas", "spin"]
	var per := {}
	for k in keys:
		per[k] = PackedFloat32Array()
	var vr := PackedFloat32Array()
	for g in 2:
		var has := g < gals.size()
		var gp: GalaxyPotential = gals[g].pot if has else GalaxyPotential.new()
		pot.append_array(gp.to_uniforms())
		bases.append(gp.basis)
		var setup: Dictionary = gals[g].setup if has else gals[0].setup
		vtab.append_array(setup.vtab)
		vr.append(float(setup.vtab_rmax))
		for k in keys:
			var arr: PackedFloat32Array = per[k]   # packed arrays are values: write back
			arr.append(float(setup[k]))
			per[k] = arr
	# Share of the particles: brighter (more massive) galaxies get more, but small ones stay visible.
	var n_first := n
	if gals.size() > 1:
		var b0 := sqrt(_baryons(gals[0].pot))
		var b1 := sqrt(_baryons(gals[1].pot))
		n_first = int(n * clampf(b0 / (b0 + b1), 0.5, 0.88))
	_mat.set_shader_parameter("n_first", n_first)
	_mat.set_shader_parameter("pot", pot)
	_mat.set_shader_parameter("basis", bases)
	_mat.set_shader_parameter("vtab", vtab)
	_mat.set_shader_parameter("vtab_rmax", vr)
	for k in keys:
		_mat.set_shader_parameter(k, per[k])
	_mat.set_shader_parameter("start_center", PackedVector3Array([c0[0], c0[1] if c0.size() > 1 else Vector3(1e4, 0, 0)]))
	_mat.set_shader_parameter("start_vel", PackedVector3Array([v0[0], v0[1] if v0.size() > 1 else Vector3.ZERO]))
	var look0: Dictionary = gals[0].target.look
	_mat.set_shader_parameter("color_core0", look0.core)
	_mat.set_shader_parameter("color_edge0", look0.edge)
	var look1: Dictionary = gals[gals.size() - 1].target.look
	_mat.set_shader_parameter("color_core1", look1.core)
	_mat.set_shader_parameter("color_edge1", look1.edge)
	for g in 2:
		var has := g < gals.size()
		_cores[g].visible = has
		if has:
			var gp: GalaxyPotential = gals[g].pot
			_cores[g].pixel_size = maxf(gp.a_bulge * 2.5, float(gals[g].target.r_last) * 0.12) / 128.0


## Camera distance that keeps both galaxies (separation d) in the picture.
func _frame_dist(d: float) -> float:
	var half := d * 0.5 + _radius * 1.1
	return clampf(half / tan(deg_to_rad(_cam.fov * 0.5)) * 1.15, _radius * 2.6, 600.0)


static func _baryons(p: GalaxyPotential) -> float:
	return maxf(p.m_bulge + p.m_disk + p.m_gas, 1e-6)


func _restart() -> void:
	t = 0.0
	_acc = 0.0
	_particles.restart()
	_particles.emitting = true
	_hold = 3
	_push(0)
	_update_scene()


# --- time ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _hold > 0:
		_hold -= 1
		_push(0)
		return
	if not playing:
		_push(0)
		_update_scene()
		return
	var step_time := fixed_step if fixed_step > 0.0 else minf(delta, 1.0 / 20.0)
	_acc += step_time * _speed()
	var n := mini(int(_acc / DT), MAX_STEPS)
	_acc -= n * DT
	_acc = minf(_acc, DT * MAX_STEPS)
	if t + n * DT > _t_end:
		n = maxi(0, int((_t_end - t) / DT))
	_push(n)
	t += n * DT
	_update_scene()
	if t >= _t_end - DT * 0.5:
		if mode == "build":
			_restart()
		else:
			playing = false
			finished.emit()


func _speed() -> float:
	if mode == "build":
		return BUILD_SPEED
	# Faster while the galaxies are still far apart.
	var d := model.rel_at(t).length()
	var far := d / (model.radius(0) + model.radius(1))
	return COLLIDE_SPEED * clampf(far, 1.0, 2.0)


func _push(n: int) -> void:
	for k in MAX_STEPS:
		var tm := t + (k + 0.5) * DT
		for g in 2:
			_centers[2 * k + g] = model.center(g, tm) if model else (Vector3.ZERO if g == 0 else Vector3(1e4, 0, 0))
	_mat.set_shader_parameter("centers", _centers)
	_mat.set_shader_parameter("steps", n)


func _update_scene() -> void:
	for g in 2:
		if _cores[g].visible:
			_cores[g].position = model.center(g, t) if model else Vector3.ZERO
	_cam_angle += 0.0025 if playing else 0.0005
	var target_dist := _cam_dist
	if model:
		target_dist = _frame_dist(model.rel_at(t).length())
	_cam_dist = lerpf(_cam_dist, target_dist, 0.03)
	var elev := deg_to_rad(38.0)
	_cam.position = Vector3(cos(_cam_angle) * cos(elev), sin(elev), sin(_cam_angle) * cos(elev)) * _cam_dist
	_cam.look_at(Vector3.ZERO)
	# Stars keep about the same size on screen however far the camera is.
	_quad.size = Vector2.ONE * _cam_dist * 0.0024


static func _radial_texture(size: int, mid: float) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(mid, Color(1, 1, 1, 0.45))
	tex.gradient = grad
	tex.width = size
	tex.height = size
	return tex
