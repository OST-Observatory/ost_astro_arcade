// The Moon as a small sphere on the sky: lit side from the Sun's direction (so the phase
// comes out right by itself), the dark side faintly lit by earthshine.
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);   // world space, unit

varying vec3 v_normal;

void vertex() {
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float lit = smoothstep(-0.03, 0.08, dot(v_normal, sun_dir));
	// A few darker "maria" from the surface direction, just enough to look like the Moon.
	vec3 n = v_normal;
	float maria = smoothstep(0.55, 0.85, 0.5 + 0.5 * sin(n.x * 5.0 + 1.3) * sin(n.y * 4.0 - 0.7) * sin(n.z * 3.0 + 2.1));
	vec3 col = vec3(1.0, 0.98, 0.92) * mix(1.0, 0.72, maria);
	ALBEDO = col * (0.015 + 2.2 * lit);
}
