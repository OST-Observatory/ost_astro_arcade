// Procedural night sky for 2D screens: three star layers with twinkle, a Milky Way band
// built from fbm noise with dark dust lanes, faint airglow, and slow drift.
// (To be replaced/augmented by a real Hipparcos star map from tools/.)
shader_type canvas_item;

uniform float aspect = 1.7778;  // width / height of the rect
uniform float drift_speed = 0.004;
uniform float brightness = 1.0;
uniform float band_angle = 0.42;
uniform float band_strength = 0.55;
uniform vec4 tint : source_color = vec4(0.62, 0.72, 1.0, 1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
	           mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// One layer of stars on a jittered grid: returns brightness.
float stars(vec2 uv, float cell, float density, float size, float t) {
	vec2 g = uv * cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float acc = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 cid = id + o;
			float h = hash12(cid);
			if (h > density) continue;
			vec2 pos = o + hash22(cid);
			float d = length(f - pos);
			float mag = pow(hash12(cid + 7.3), 3.0);
			float tw = 0.75 + 0.25 * sin(t * (1.0 + 3.0 * hash12(cid + 3.1)) + h * 40.0);
			acc += mag * tw * (1.0 - smoothstep(0.0, size * (0.5 + mag), d));
		}
	}
	return acc;
}

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(aspect, 1.0);
	uv.y = -uv.y;
	uv += vec2(TIME * drift_speed, TIME * drift_speed * 0.3);

	// Milky Way band.
	float ca = cos(band_angle);
	float sa = sin(band_angle);
	vec2 b = vec2(ca * uv.x + sa * uv.y, -sa * uv.x + ca * uv.y);
	float bn = b.y / 0.23;
	float band = exp(-bn * bn);
	float clouds = fbm(b * vec2(2.2, 5.0) + 3.0);
	float dust = smoothstep(0.45, 0.75, fbm(b * vec2(4.0, 9.0) + 11.0));
	float mw = band * clouds * (1.0 - 0.75 * dust * band) * band_strength;

	vec3 col = vec3(0.004, 0.006, 0.018);
	col += vec3(0.010, 0.012, 0.03) * (1.0 - smoothstep(-0.6, 0.7, uv.y));  // airglow near horizon
	col += mw * mix(vec3(0.55, 0.5, 0.45), tint.rgb, 0.4) * 0.35;

	float s = 0.0;
	s += stars(uv, 90.0, 0.55, 0.06, TIME) * 0.6;
	s += stars(uv, 38.0, 0.35, 0.05, TIME * 0.8) * 1.0;
	s += stars(uv + 3.7, 14.0, 0.25, 0.035, TIME * 0.6) * 1.6;
	s *= 1.0 + 1.8 * band;  // more stars along the band
	vec3 star_col = mix(vec3(1.0, 0.85, 0.7), tint.rgb, hash12(floor(uv * 38.0)));
	col += s * star_col;

	COLOR = vec4(col * brightness, 1.0);
}
