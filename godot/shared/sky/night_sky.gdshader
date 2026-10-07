// Sky from day through dusk to a starry night: Rayleigh-like gradient with a warm glow
// around the sun near the horizon, then procedural stars (3D cell hashing on the sky
// sphere, so they do not stretch) and a Milky Way band fading in as it gets dark.
shader_type sky;

uniform float night : hint_range(0.0, 1.0) = 0.0;        // 0 day ... 1 full night
uniform float star_scale = 220.0;
uniform float star_brightness = 1.0;
uniform vec3 galactic_pole = vec3(-0.45, 0.62, 0.64);    // band orientation (artistic)
uniform vec4 day_zenith : source_color = vec4(0.22, 0.45, 0.85, 1.0);
uniform vec4 day_horizon : source_color = vec4(0.65, 0.78, 0.95, 1.0);
uniform vec4 dusk_glow : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform vec4 night_zenith : source_color = vec4(0.004, 0.006, 0.02, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.02, 0.03, 0.07, 1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i), n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0)), n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1)), n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1)), n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
	           mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

float stars(vec3 dir, float scale, float density) {
	vec3 g = dir * scale;
	vec3 id = floor(g);
	// Only the 8 cells around the nearest cell corner can contain a star touching this pixel.
	vec3 side = step(0.5, fract(g)) * 2.0 - 1.0;
	float acc = 0.0;
	for (int z = 0; z <= 1; z++)
	for (int y = 0; y <= 1; y++)
	for (int x = 0; x <= 1; x++) {
		vec3 cid = id + vec3(float(x), float(y), float(z)) * side;
		float h = hash13(cid);
		if (h > density) continue;
		vec3 sp = normalize(cid + hash33(cid));
		float d = length(dir - sp) * scale;
		float mag = pow(hash13(cid + 5.7), 4.0);
		acc += mag * (1.0 - smoothstep(0.0, 0.08 + 0.12 * mag, d));
	}
	return acc;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y, -0.2, 1.0);
	vec3 sun = LIGHT0_DIRECTION;
	// Day / dusk gradient.
	vec3 day = mix(day_horizon.rgb, day_zenith.rgb, pow(max(h, 0.0), 0.5));
	float toward_sun = max(dot(normalize(vec3(dir.x, 0.0, dir.z)), normalize(vec3(sun.x, 0.0, sun.z))), 0.0);
	float glow = pow(toward_sun, 3.0) * exp(-max(h, 0.0) * 6.0) * (1.0 - smoothstep(-0.05, 0.35, sun.y));
	vec3 dusk = day * (0.25 + 0.75 * smoothstep(-0.1, 0.25, sun.y)) + dusk_glow.rgb * glow * 1.4;
	vec3 night_col = mix(night_horizon.rgb, night_zenith.rgb, pow(max(h, 0.0), 0.4));
	vec3 col = mix(dusk, night_col, night);
	// Stars and Milky Way.
	if (night > 0.05 && dir.y > -0.05) {
		float s = stars(dir, star_scale, 0.08) + stars(dir, star_scale * 0.45, 0.05) * 1.5;
		float band = exp(-pow(dot(dir, normalize(galactic_pole)) / 0.22, 2.0));
		float mw = band * fbm(dir * 6.0) * (0.6 + 0.4 * fbm(dir * 18.0 + 3.0));
		vec3 night_sky = vec3(0.75, 0.8, 1.0) * s * 3.0 * star_brightness * (1.0 + band)
			+ vec3(0.12, 0.11, 0.13) * mw;
		col += night_sky * smoothstep(0.05, 0.9, night) * smoothstep(-0.05, 0.12, dir.y);
	}
	COLOR = col;
}
