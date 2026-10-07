## Small 3D drawing helpers for space scenes: glowing spheres, polylines (heliocentric AU
## or scene space), dashed lines and billboard labels.
class_name SpaceDraw
extends RefCounted


static func sphere(pos: Vector3, radius: float, col: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = 2.0 * radius
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position = pos
	return mi


## pts: heliocentric AU as a strip, or (pairs = true) scene-space segment pairs from dashed().
static func line(pts: PackedVector3Array, col: Color, energy: float, pairs := false) -> MeshInstance3D:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var v := PackedVector3Array()
	for p in pts:
		v.append(p if pairs else Kepler.to_godot(p))
	arr[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES if pairs else Mesh.PRIMITIVE_LINE_STRIP, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.emission_enabled = true
	m.emission = Color(col, 1.0)
	m.emission_energy_multiplier = energy
	mi.material_override = m
	return mi


## Points for a dashed line in scene space (pairs for PRIMITIVE_LINES).
static func dashed(a: Vector3, b: Vector3, n := 24) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in n:
		if k % 2 == 0:
			out.append(a.lerp(b, float(k) / n))
			out.append(a.lerp(b, float(k + 1) / n))
	return out


static func label(text: String, pos: Vector3, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font = UiTheme.font("medium")
	l.font_size = 36
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.pixel_size = 0.0011
	l.modulate = Color(col, 0.9)
	l.no_depth_test = true
	l.fixed_size = true
	return l
