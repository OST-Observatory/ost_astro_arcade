## Spike: 300k GPU test particles in a two-galaxy encounter + glow.
## The two cores are integrated here (same symplectic Euler + substeps as the shader).
extends Node3D

const PARTICLES := 300000
const G := 1.0
const TIME_SCALE := 8.0
const SUBSTEPS := 4

var core_mass := [1.0, 1.0]
var core_pos := [Vector3.ZERO, Vector3.ZERO]
var core_vel := [Vector3.ZERO, Vector3.ZERO]

var _particles: GPUParticles3D
var _mat: ShaderMaterial
var _cam: Camera3D
var _label: Label
var _t := 0.0


func _ready() -> void:
	_setup_cores(40.0, 8.0)
	_build_environment()
	_build_particles()
	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.far = 500
	add_child(_cam)
	_cam.make_current()

	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(32, 24)
	_label.add_theme_font_size_override("font_size", 32)
	layer.add_child(_label)
	add_child(layer)


func _setup_cores(dist: float, impact: float) -> void:
	var m1: float = core_mass[0]
	var m2: float = core_mass[1]
	var m := m1 + m2
	var rel_p := Vector3(dist, 0, impact)
	var rel_v := Vector3(-sqrt(2.0 * G * m / rel_p.length()), 0, 0)  # parabolic approach
	core_pos = [-rel_p * m2 / m, rel_p * m1 / m]
	core_vel = [-rel_v * m2 / m, rel_v * m1 / m]


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.01)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_particles() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://spikes/galaxy_particles.gdshader")
	_mat.set_shader_parameter("n_first", PARTICLES / 2)
	_mat.set_shader_parameter("G", G)
	_mat.set_shader_parameter("time_scale", TIME_SCALE)
	_mat.set_shader_parameter("substeps", SUBSTEPS)
	_mat.set_shader_parameter("core_mass", PackedFloat32Array(core_mass))
	# Galaxy 0 face-on-ish, galaxy 1 tilted by 60 degrees; both prograde.
	_mat.set_shader_parameter("disk_basis", [
		Basis.from_euler(Vector3(deg_to_rad(15), 0, 0)),
		Basis.from_euler(Vector3(deg_to_rad(60), deg_to_rad(30), 0)),
	])
	_mat.set_shader_parameter("disk_spin", PackedFloat32Array([1.0, 1.0]))
	_push_cores()

	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.25, Color(1, 1, 1, 0.5))
	tex.gradient = grad
	tex.width = 32
	tex.height = 32

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.albedo_texture = tex
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = draw_mat

	_particles = GPUParticles3D.new()
	_particles.amount = PARTICLES
	_particles.lifetime = 100000.0
	_particles.explosiveness = 1.0
	_particles.one_shot = true
	_particles.local_coords = true
	_particles.process_material = _mat
	_particles.draw_pass_1 = quad
	_particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	_particles.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
	add_child(_particles)
	_particles.emitting = true


func _push_cores() -> void:
	_mat.set_shader_parameter("core_pos", PackedVector3Array(core_pos))
	_mat.set_shader_parameter("core_vel", PackedVector3Array(core_vel))


func _process(delta: float) -> void:
	_t += delta
	var dt := delta * TIME_SCALE / SUBSTEPS
	for i in SUBSTEPS:
		var d: Vector3 = core_pos[1] - core_pos[0]
		var r2 := d.length_squared() + 0.25
		var f := d * (G / (r2 * sqrt(r2)))
		core_vel[0] += f * core_mass[1] * dt
		core_vel[1] -= f * core_mass[0] * dt
		core_pos[0] += core_vel[0] * dt
		core_pos[1] += core_vel[1] * dt
	_push_cores()

	var a := 0.3 + _t * 0.05
	_cam.position = Vector3(cos(a) * 45.0, 28.0, sin(a) * 45.0)
	_cam.look_at(Vector3.ZERO)
	_label.text = "%d Sterne auf der GPU  ·  %d fps  ·  t = %.0f" % [PARTICLES, Engine.get_frames_per_second(), _t * TIME_SCALE]
