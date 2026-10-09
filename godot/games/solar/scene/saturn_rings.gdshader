// Saturn's rings on a flat square in the equator plane: the radial profile from
// assets/solar/saturn_rings.png (u = 0 at 74,500 km, u = 1 at 140,500 km = edge of the square).
// Lit from the Sun on both faces, dimmer on the unlit face.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, shadows_disabled, specular_disabled;

uniform sampler2D profile : source_color, filter_linear, repeat_disable;
const float R_IN = 74500.0 / 140500.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r < R_IN || r > 1.0) {
		discard;
	}
	vec4 c = texture(profile, vec2((r - R_IN) / (1.0 - R_IN), 0.5));
	ALBEDO = c.rgb;
	ALPHA = c.a;
	BACKLIGHT = c.rgb * 0.35;
}
