// Fixed points of a MultiMesh as round dots of constant pixel size (Oort cloud, nearby stars,
// Milky Way model). Per instance: position in the instance transform, colour in COLOR,
// size factor in INSTANCE_CUSTOM.x. `alpha` fades the whole set.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float px = 1.5;
uniform float alpha = 1.0;

varying vec4 v_col;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0));
	clip.xy += VERTEX.xy * 2.0 * px * INSTANCE_CUSTOM.x / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
	v_col = COLOR;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = v_col.rgb;
	ALPHA = v_col.a * alpha * clamp(1.0 - d * d, 0.0, 1.0);
}
