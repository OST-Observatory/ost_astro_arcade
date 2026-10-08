## Confetti rain over the whole screen for a success moment; frees itself when done.
##   Confetti.burst(self)
class_name Confetti
extends Control

const PIECES := 260
const LIFETIME := 6.0
const COLORS := [Color("ffb347"), Color("ffcf86"), Color("4dd0e1"), Color("7ee08a"), Color("ff8a80"),
	Color("b39ddb"), Color("f4f1ea")]

var _p := []        # [pos, vel, angle, spin, flip_speed, size, color]
var _t := 0.0


static func burst(parent: Node) -> Confetti:
	var c := Confetti.new()
	parent.add_child(c)
	return c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	var w := 2560.0
	for i in PIECES:
		var pos := Vector2(randf() * w, -randf() * 900.0 - 20.0)
		var vel := Vector2(randf_range(-80, 80), randf_range(180, 420))
		_p.append([pos, vel, randf() * TAU, randf_range(-4.0, 4.0), randf_range(4.0, 10.0),
			Vector2(randf_range(20, 34), randf_range(11, 18)), COLORS[randi() % COLORS.size()]])


func _process(delta: float) -> void:
	_t += delta
	for p in _p:
		var v: Vector2 = p[1]
		v.x += sin(_t * 2.0 + p[2]) * 60.0 * delta   # flutter
		v.y = minf(v.y + 120.0 * delta, 520.0)
		p[1] = v
		p[0] += v * delta
		p[2] += p[3] * delta
	modulate.a = clampf((LIFETIME - _t) / 1.0, 0.0, 1.0)
	queue_redraw()
	if _t > LIFETIME:
		queue_free()


func _draw() -> void:
	for p in _p:
		var s: Vector2 = p[5]
		# The flip (cos) makes the pieces look like turning paper.
		var flip := absf(cos(_t * p[4] + p[2]))
		draw_set_transform(p[0], p[2], Vector2(1.0, maxf(flip, 0.15)))
		draw_rect(Rect2(-s / 2.0, s), (p[6] as Color).darkened(0.25 * (1.0 - flip)))
	draw_set_transform(Vector2.ZERO)
