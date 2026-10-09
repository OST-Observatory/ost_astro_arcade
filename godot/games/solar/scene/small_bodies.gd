## Asteroids, Trojans, Centaurs and Kuiper-belt objects from assets/data/solar/small_bodies.json
## (JPL SBDB) as one MultiMesh: the orbits are uploaded once, small_bodies.gdshader moves
## the dots. The CPU only computes positions when someone taps (positions()).
class_name SmallBodies
extends MultiMeshInstance3D

const PATH := "res://assets/data/solar/small_bodies.json"
const CLASSES := ["MBA", "IMB", "OMB", "TJN", "TNO", "APO", "ATE", "AMO", "CEN"]
const CLASS_COLORS := [Color(0.8, 0.72, 0.6, 0.3), Color(0.8, 0.72, 0.6, 0.3), Color(0.8, 0.7, 0.58, 0.3),
	Color(0.45, 0.9, 0.5, 0.5), Color(0.45, 0.65, 1.0, 0.6), Color(1.0, 0.45, 0.3, 0.8),
	Color(1.0, 0.45, 0.3, 0.8), Color(1.0, 0.45, 0.3, 0.8), Color(0.8, 0.55, 1.0, 0.7)]

const TYPICAL_A := [2.7, 2.2, 3.2, 5.2, 43.0, 1.6, 0.9, 1.6, 15.0]   # AU, per class

var rows: Array = []          # [a, e, i, node, w, M (deg at epoch), n (deg/day), epoch, class]
var epoch := 2461200.5
var _mat: ShaderMaterial


## Up to max_count rows, thinned evenly within every class (so all classes stay visible).
static func load_rows(max_count: int) -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var all: Array = data.data
	if all.size() <= max_count:
		return all
	var keep := float(max_count) / all.size()
	var out := []
	var acc := {}
	for r in all:
		var c: String = r[8]
		acc[c] = float(acc.get(c, 0.0)) + keep
		if acc[c] >= 1.0:
			acc[c] -= 1.0
			out.append(r)
	return out


## Instance transform and custom data of one orbit (see small_bodies.gdshader).
static func pack(r: Array, common_epoch: float) -> Array:
	var a := float(r[0])
	var e := float(r[1])
	var i := deg_to_rad(float(r[2]))
	var o := deg_to_rad(float(r[3]))
	var w := deg_to_rad(float(r[4]))
	var p := Kepler.to_godot(Kepler._rotate(1.0, 0.0, i, o, w)) * a
	var q := Kepler.to_godot(Kepler._rotate(0.0, 1.0, i, o, w)) * (a * sqrt(1.0 - e * e))
	var m0 := fposmod(deg_to_rad(float(r[5]) + float(r[6]) * (common_epoch - float(r[7]))), TAU)
	var cls := CLASSES.find(r[8])
	return [Transform3D(Basis(p, q, p.cross(q).normalized() * 1e-3), Vector3.ZERO),
		Color(e, m0, deg_to_rad(float(r[6])), float(maxi(cls, 0)))]


## Heliocentric ecliptic position of one row (same maths as the shader).
static func position_of(r: Array, jd: float) -> Vector3:
	return Kepler.position(float(r[0]), float(r[1]), float(r[2]), float(r[3]), float(r[4]),
		float(r[5]) + float(r[6]) * (jd - float(r[7])))


static func class_of(r: Array) -> String:
	return str(r[8])


func setup(max_count: int) -> void:
	rows = load_rows(max_count)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = rows.size()
	for k in rows.size():
		var pk := pack(rows[k], epoch)
		mm.set_instance_transform(k, pk[0])
		mm.set_instance_custom_data(k, pk[1])
	multimesh = mm
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://games/solar/scene/small_bodies.gdshader")
	_mat.set_shader_parameter("colors", PackedColorArray(CLASS_COLORS))
	material_override = _mat
	custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## px_per_au: screen scale near the camera's focus. A class whose belt would be only a few
## pixels wide on screen fades out (thousands of dots on one spot would glare), and so do
## all a bit when seen edge-on (edge_on 0..1).
func update(jd: float, origin_scene: Vector3, px_per_au: float, edge_on := 0.0) -> void:
	_mat.set_shader_parameter("t_days", jd - epoch)
	_mat.set_shader_parameter("origin", origin_scene)
	var cols := PackedColorArray()
	for k in CLASSES.size():
		var c: Color = CLASS_COLORS[k]
		c.a *= smoothstep(40.0, 160.0, float(TYPICAL_A[k]) * px_per_au) * (1.0 - 0.6 * edge_on)
		cols.append(c)
	_mat.set_shader_parameter("colors", cols)


func highlight(cls: String) -> void:
	_mat.set_shader_parameter("highlight_class", float(CLASSES.find(cls)) if cls != "" else -1.0)


## All heliocentric positions at a date (for tapping).
func positions(jd: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(rows.size())
	for k in rows.size():
		out[k] = position_of(rows[k], jd)
	return out
