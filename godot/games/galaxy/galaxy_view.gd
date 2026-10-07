## 3D view of a galaxy encounter: GPU test stars (galaxy_stars.gdshader) following the core
## track of GalaxyModel, glowing cores, and a camera that swings from a 3D side view into the
## observer's view of the target photo while the collision runs.
class_name GalaxyView
extends Node3D

signal finished

## Simulated time units per second of animation.
const SPEED := 9.0
const FOV := 30.0

var params := {}
var extent := 32.0
var t := 0.0
var playing := false
## > 0: advance by this many seconds per frame regardless of the real frame time (captures).
var fixed_step := 0.0
var _t_end := 0.0
var _track := PackedVector3Array()
var _particles: GPUParticles3D
var _mat: ShaderMaterial
var _quad: QuadMesh
var _cores: Array[Sprite3D] = []
var _cam: Camera3D
var _hold := 0              # frames to keep the stars still after a restart
var _swing := 0.0           # camera: 1 = side view, 0 = observer view


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
	_mat.shader = preload("res://games/galaxy/galaxy_stars.gdshader")
	_mat.set_shader_parameter("G", GalaxyModel.G)
	_mat.set_shader_parameter("softening", GalaxyModel.SOFTENING)
	_mat.set_shader_parameter("disk_rmin", GalaxyModel.DISK_RMIN)
	_mat.set_shader_parameter("disk_rmax", GalaxyModel.DISK_RMAX)
	_mat.set_shader_parameter("disk_len", GalaxyModel.DISK_SCALE)

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
	_particles.amount = int(Settings.quality_3d()[2])
	_particles.lifetime = 100000.0
	_particles.explosiveness = 1.0
	_particles.one_shot = true
	_particles.fixed_fps = 0
	_particles.interpolate = false
	_particles.local_coords = true
	_particles.process_material = _mat
	_particles.draw_pass_1 = _quad
	_particles.visibility_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	_particles.emitting = false
	add_child(_particles)

	var glow_tex := _radial_texture(128, 0.12)
	for i in 2:
		var s := Sprite3D.new()
		s.texture = glow_tex
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = glow_tex
		m.albedo_color = Color(1.0, 0.85, 0.62, 0.45)
		s.material_override = m
		add_child(s)
		_cores.append(s)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 5000
	add_child(_cam)
	_cam.make_current()


## Prepares an encounter (stars placed at t = 0) without starting it.
func setup(p: Dictionary, map_extent: float) -> void:
	params = GalaxyModel.with_defaults(p)
	extent = map_extent
	_track = GalaxyModel.orbit_track(params)
	_t_end = GalaxyModel.t_end(params)
	t = 0.0
	playing = false
	var f2 := GalaxyModel.fraction2(params)
	_mat.set_shader_parameter("n_first", int(_particles.amount * (1.0 - f2)))
	_mat.set_shader_parameter("core_mass", PackedFloat32Array([1.0, float(params.m2)]))
	_mat.set_shader_parameter("disk_scale", PackedFloat32Array([GalaxyModel.disk_scale(params, 0), GalaxyModel.disk_scale(params, 1)]))
	_mat.set_shader_parameter("disk_basis", [GalaxyModel.disk_basis(params, 0), GalaxyModel.disk_basis(params, 1)])
	_mat.set_shader_parameter("disk_spin", PackedFloat32Array([float(params.spin1), float(params.spin2)]))
	_mat.set_shader_parameter("core_vel", PackedVector3Array(GalaxyModel.core_velocities(params, _track, 0.0)))
	_quad.size = Vector2.ONE * extent * 0.0042
	_push(0.0, 0.0)
	_particles.restart()
	_particles.emitting = true
	_hold = 3
	_swing = 1.0
	for i in 2:
		var m := 1.0 if i == 0 else float(params.m2)
		_cores[i].pixel_size = 2.6 * sqrt(m) / 128.0
	_update_camera()


func play() -> void:
	playing = true


## Seconds the whole collision takes on screen.
func duration() -> float:
	return _t_end / SPEED


func _push(t_from: float, t_to: float) -> void:
	var a := GalaxyModel.core_positions(params, _track, t_from)
	var b := GalaxyModel.core_positions(params, _track, t_to)
	_mat.set_shader_parameter("core_from", PackedVector3Array(a))
	_mat.set_shader_parameter("core_to", PackedVector3Array(b))
	_mat.set_shader_parameter("step_dt", t_to - t_from)
	for i in 2:
		_cores[i].position = b[i]


func _process(delta: float) -> void:
	if params.is_empty():
		return
	if _hold > 0:
		_hold -= 1
		_push(0.0, 0.0)
		return
	if not playing:
		_push(t, t)
		return
	# Large frame hitches would make big integration steps: slow the clock instead.
	var step := fixed_step if fixed_step > 0.0 else minf(delta, 1.0 / 30.0)
	var t_new := minf(t + step * SPEED, _t_end)
	_push(t, t_new)
	t = t_new
	_swing = 1.0 - smoothstep(0.15, 0.95, t / _t_end)
	_update_camera()
	if t >= _t_end:
		playing = false
		finished.emit()


## Camera in the observer's frame; while _swing > 0 it is turned sideways and pulled back.
func _update_camera() -> void:
	var vb := GalaxyModel.view_basis(params)
	var dist := extent / tan(deg_to_rad(FOV * 0.5))
	var turn := Basis(vb.y, deg_to_rad(-40.0 * _swing)) * Basis(vb.x, deg_to_rad(-25.0 * _swing))
	var b := turn * vb
	_cam.transform = Transform3D(b, b.z * dist * (1.0 + 0.35 * _swing))


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
