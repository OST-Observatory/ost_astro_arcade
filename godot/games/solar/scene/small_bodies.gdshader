// Asteroids and Kuiper-belt objects: every instance carries its orbit, the vertex shader
// solves Kepler's equation and draws a round dot of constant pixel size.
//   instance basis column 0: P * a (towards perihelion), column 1: Q * a * sqrt(1 - e^2)
//   (scene axes, read from MODEL_MATRIX – the node transform stays identity)
//   INSTANCE_CUSTOM: e, mean anomaly at the epoch (rad), mean motion (rad/day), class index
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float t_days = 0.0;            // days since the common epoch
uniform vec3 origin = vec3(0.0);       // scene position of the Sun is -origin
uniform float px = 1.8;                // dot radius in pixels
uniform vec4 colors[9] : source_color;
uniform float highlight_class = -1.0;  // brighter dots for one class (find tasks)

varying vec4 v_col;

void vertex() {
	vec3 p = MODEL_MATRIX[0].xyz;
	vec3 q = MODEL_MATRIX[1].xyz;
	float e = INSTANCE_CUSTOM.x;
	float m = mod(INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.z * t_days, 6.2831853);
	float ea = e < 0.8 ? m : 3.14159265;
	for (int k = 0; k < 10; k++) {
		ea -= (ea - e * sin(ea) - m) / (1.0 - e * cos(ea));
	}
	vec3 world = p * (cos(ea) - e) + q * sin(ea) - origin;
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	int cls = int(INSTANCE_CUSTOM.w + 0.5);
	bool hi = float(cls) == highlight_class;
	float size = px * (hi ? 1.8 : 1.0);
	clip.xy += VERTEX.xy * 2.0 * size / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
	v_col = colors[cls];
	if (hi) {
		v_col = vec4(v_col.rgb * 2.0, 1.0);
	}
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = v_col.rgb;
	ALPHA = v_col.a * clamp(1.0 - d * d, 0.0, 1.0);
}
