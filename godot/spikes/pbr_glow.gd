## Spike: PBR materials, dusk sky, shadows, AgX tonemapping, glow and volumetric fog.
## A rough stand-in for the OST dome on the roof (no real assets yet).
extends Node3D

var _cam: Camera3D
var _t := 0.0
var _fps_label: Label


func _ready() -> void:
	_build_environment()
	_build_scene()
	_cam = Camera3D.new()
	_cam.fov = 55
	add_child(_cam)
	_cam.make_current()
	_update_camera()

	var layer := CanvasLayer.new()
	_fps_label = Label.new()
	_fps_label.position = Vector2(32, 24)
	_fps_label.add_theme_font_size_override("font_size", 32)
	layer.add_child(_fps_label)
	add_child(layer)


func _process(delta: float) -> void:
	_t += delta
	_update_camera()
	_fps_label.text = "%d fps  ·  %s" % [Engine.get_frames_per_second(), RenderingServer.get_video_adapter_name()]


func _update_camera() -> void:
	var a := 0.6 + _t * 0.08
	_cam.position = Vector3(cos(a) * 11.0, 3.2, sin(a) * 11.0)
	_cam.look_at(Vector3(0, 2.6, 0))


func _build_environment() -> void:
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.5
	sky_mat.mie_coefficient = 0.008
	sky_mat.turbidity = 8.0
	sky_mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.002
	env.volumetric_fog_albedo = Color(0.9, 0.85, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Low sun just above the horizon -> dusk colours.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-8, 150, 0)
	sun.light_color = Color(1.0, 0.72, 0.5)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	add_child(sun)


func _mat(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	return mi


func _build_scene() -> void:
	# Concrete roof with noise variation.
	var roof := _mat(Color(0.42, 0.42, 0.41), 0.0, 0.92)
	var noise := NoiseTexture2D.new()
	noise.noise = FastNoiseLite.new()
	noise.noise.frequency = 0.05
	noise.width = 512
	noise.height = 512
	roof.albedo_texture = noise
	roof.uv1_scale = Vector3(6, 6, 6)
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	_add(plane, roof, Vector3.ZERO)

	# 5 m dome: cylinder base + hemisphere, white paint.
	var paint := _mat(Color(0.93, 0.93, 0.9), 0.0, 0.35)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.4
	var base := CylinderMesh.new()
	base.top_radius = 2.5
	base.bottom_radius = 2.5
	base.height = 2.2
	_add(base, paint, Vector3(0, 1.1, 0))
	var dome := SphereMesh.new()
	dome.radius = 2.55
	dome.height = 2.55
	dome.is_hemisphere = true
	_add(dome, paint, Vector3(0, 2.2, 0))

	# Stand-ins for mount parts: black anodized tube, stainless counterweight.
	var anodized := _mat(Color(0.03, 0.03, 0.035), 0.6, 0.45)
	var steel := _mat(Color(0.78, 0.78, 0.8), 1.0, 0.22)
	var tube := CylinderMesh.new()
	tube.top_radius = 0.38
	tube.bottom_radius = 0.38
	tube.height = 1.4
	_add(tube, anodized, Vector3(4.5, 1.6, -1.5), Vector3(35, 0, 20))
	var weight := CylinderMesh.new()
	weight.top_radius = 0.28
	weight.bottom_radius = 0.28
	weight.height = 0.45
	_add(weight, steel, Vector3(4.0, 0.6, 1.2), Vector3(0, 0, 90))

	# Galvanised railing.
	var zinc := _mat(Color(0.65, 0.66, 0.68), 1.0, 0.5)
	var rail := CylinderMesh.new()
	rail.top_radius = 0.025
	rail.bottom_radius = 0.025
	rail.height = 14
	for h in [0.5, 1.0]:
		_add(rail, zinc, Vector3(-6, h, 0), Vector3(90, 0, 0))

	# Red work lamp (emissive + light) and a green laser beam for glow/fog.
	var red := _mat(Color(1, 0.1, 0.05), 0.0, 0.5)
	red.emission_enabled = true
	red.emission = Color(1, 0.08, 0.03)
	red.emission_energy_multiplier = 6.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.08
	bulb.height = 0.16
	_add(bulb, red, Vector3(2.4, 1.9, 0.6))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1, 0.15, 0.05)
	lamp.light_energy = 2.0
	lamp.omni_range = 4.0
	lamp.position = Vector3(2.6, 1.9, 0.6)
	add_child(lamp)

	var laser := StandardMaterial3D.new()
	laser.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser.albedo_color = Color(0.3, 1.0, 0.4)
	laser.emission_enabled = true
	laser.emission = Color(0.3, 1.0, 0.4)
	laser.emission_energy_multiplier = 8.0
	var beam := CylinderMesh.new()
	beam.top_radius = 0.012
	beam.bottom_radius = 0.012
	beam.height = 30
	_add(beam, laser, Vector3(4.5, 15.5, -1.5), Vector3(0, 0, -12))
