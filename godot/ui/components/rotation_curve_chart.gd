## Rotation curve chart: measured speeds with error bars, the player's model as a thick line
## and one thin line per building block (black hole, stars, gas, dark matter), labelled at
## their right end. Axes in kpc and km/s.
class_name RotationCurveChart
extends Control

const PAD := Vector2(110, 30)        # left/bottom margins for the axis labels
const COLORS := {
	"bh": Color("b0b4c0"), "stars": Color("ffcf86"), "gas": Color("6fb7ff"), "halo": Color("c39bff"),
}
const TOTAL_COLOR := Color("ffb347")
const DATA_COLOR := Color("f4f1ea")

var target: Dictionary
var pot: GalaxyPotential
var unlocked: Array = []              # building blocks drawn as thin lines
var _font: Font


func _ready() -> void:
	_font = UiTheme.font("medium")


func set_model(t: Dictionary, p: GalaxyPotential, blocks: Array) -> void:
	target = t
	pot = p
	unlocked = blocks
	queue_redraw()


func _draw() -> void:
	draw_style_box(UiTheme.box(Color(0, 0, 0, 0.45), UiTheme.LINE, 2, 18), Rect2(Vector2.ZERO, size))
	if target.is_empty() or pot == null:
		return
	var kms := GalaxyPotential.KMS
	var kpc := GalaxyPotential.KPC
	var r_max := float(target.r_last) * 1.08
	var v_max := 0.0
	for p in target.points:
		v_max = maxf(v_max, float(p[1]) + float(p[2]))
	v_max *= 1.3
	var area := Rect2(Vector2(PAD.x, 34), size - Vector2(PAD.x + 190, 34 + PAD.y + 40))
	var to_px := func(r: float, v: float) -> Vector2:
		return area.position + Vector2(r / r_max * area.size.x, area.size.y * (1.0 - clampf(v / v_max, 0.0, 1.05)))

	# Axes, grid and labels.
	var fs := 24
	draw_line(area.position + Vector2(0, area.size.y), area.end, UiTheme.TEXT_DIM, 2.0)
	draw_line(area.position, area.position + Vector2(0, area.size.y), UiTheme.TEXT_DIM, 2.0)
	var v_step := _nice_step(v_max * kms / 4.0)
	var v := v_step
	while v < v_max * kms:
		var y: float = (to_px.call(0.0, v / kms) as Vector2).y
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.07), 1.0)
		draw_string(_font, Vector2(8, y + 8), "%d" % int(v), HORIZONTAL_ALIGNMENT_RIGHT, PAD.x - 20, fs, UiTheme.TEXT_DIM)
		v += v_step
	var r_step := _nice_step(r_max * kpc / 5.0)
	var r := r_step
	while r < r_max * kpc:
		var x: float = (to_px.call(r / kpc, 0.0) as Vector2).x
		draw_string(_font, Vector2(x - 40, area.end.y + 30), "%d" % int(r), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, UiTheme.TEXT_DIM)
		r += r_step
	draw_string(_font, Vector2(18, 28), tr("GAL_AXIS_V"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	draw_string(_font, Vector2(area.position.x, size.y - 8), tr("GAL_AXIS_R"), HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, UiTheme.TEXT_DIM)

	# Model lines: components (thin), total (thick).
	var l_bh := PackedVector2Array()
	var l_stars := PackedVector2Array()
	var l_gas := PackedVector2Array()
	var l_halo := PackedVector2Array()
	var total := PackedVector2Array()
	for i in 121:
		var rr := r_max * (i + 0.5) / 121.0
		var v2 := pot.v2_parts(rr)
		l_bh.append(to_px.call(rr, sqrt(maxf(v2.bh, 0.0))))
		l_stars.append(to_px.call(rr, sqrt(maxf(v2.bulge + v2.disk, 0.0))))
		l_gas.append(to_px.call(rr, sqrt(maxf(v2.gas, 0.0))))
		l_halo.append(to_px.call(rr, sqrt(maxf(v2.halo, 0.0))))
		total.append(to_px.call(rr, pot.v_circ(rr)))
	var parts := {"bh": l_bh, "stars": l_stars, "gas": l_gas, "halo": l_halo}
	var labels := []   # [y, block] at the right end of each line
	for k in ["bh", "stars", "gas", "halo"]:
		if not unlocked.has(k):
			continue
		var line: PackedVector2Array = parts[k]
		draw_polyline(line, Color(COLORS[k], 0.85), 3.0, true)
		labels.append([line[line.size() - 1].y, k])
	# Lines that end close together: push their labels apart, but keep them inside the box.
	labels.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var gap := float(fs)
	for i in range(1, labels.size()):
		labels[i][0] = maxf(labels[i][0], labels[i - 1][0] + gap)
	for i in range(labels.size() - 1, -1, -1):
		var lowest := size.y - 20.0 if i == labels.size() - 1 else float(labels[i + 1][0]) - gap
		labels[i][0] = minf(labels[i][0], lowest)
	var label_x := total[total.size() - 1].x + 12.0
	for l in labels:
		draw_string(_font, Vector2(label_x, l[0] + 8), tr("GAL_BLOCK_" + str(l[1]).to_upper()), HORIZONTAL_ALIGNMENT_LEFT, 180, fs - 4, COLORS[l[1]])
	draw_polyline(total, TOTAL_COLOR, 6.0, true)

	# Measurements with error bars.
	for p in target.points:
		var c: Vector2 = to_px.call(float(p[0]), float(p[1]))
		var lo: Vector2 = to_px.call(float(p[0]), float(p[1]) - float(p[2]))
		var hi: Vector2 = to_px.call(float(p[0]), float(p[1]) + float(p[2]))
		draw_line(lo, hi, Color(DATA_COLOR, 0.7), 2.0)
		draw_circle(c, 5.0, DATA_COLOR)


static func _nice_step(x: float) -> float:
	var e := pow(10.0, floor(log(x) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if m * e >= x:
			return m * e
	return 10.0 * e
